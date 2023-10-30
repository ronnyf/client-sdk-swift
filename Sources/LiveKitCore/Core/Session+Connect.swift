//
//  Session+Connect.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 9/29/23.
//

import Foundation
import AsyncAlgorithms
import Combine

extension LiveKitSession {
	public func connect(
		urlString: String,
		token: String,
		urlSessionConfiguration: URLSessionConfiguration = .liveKitDefault
	) async throws {
		guard let url = Utils.buildUrl(urlString, token, adaptiveStream: true) else {
			throw Errors.url
		}
		
		//just to make sure
		dispatchPrecondition(condition: .notOnQueue(.main))
		
		let messageChannel = MessageChannel(urlSessionConfiguration: urlSessionConfiguration)
		connect(messageChannel.connectionState)
		
		let outgoingData = signalHub.outgoingDataRequests.stream()
		
		// the following we'd like to run in parallel as much as possible ...
		try await withThrowingTaskGroup(of: Void.self) { messageChannelGroup in
			messageChannelGroup.addTask {
				// long running task to (re) connect to the livekit backend/websocket endpoint
				try await messageChannel.connect(urlRequest: URLRequest(url: url), outgoingDataStream: outgoingData)
			}
			
			// RTC signals from RTCPeerConnection(s)
			// normally there'd only be one but the livekit server implements an alternative approach,
			// where there's always two, a master and an appr... erm a publisher and a subscriber
			let publishingPeerConnection = signalHub.peerConnectionFactory.publishingPeerConnection
			let subscribingPeerConnection = signalHub.peerConnectionFactory.subscribingPeerConnection
			
			for peerConnection in [publishingPeerConnection, subscribingPeerConnection] {
				messageChannelGroup.addTask { [signalHub] in
					try await peerConnection.handlePeerConnectionSignals(with: signalHub)
				}
			}
			
			let messages = messageChannel.bufferedMessages.compactMap {
				try? Livekit_SignalResponse.OneOf_Message(message: $0)
			}
			
			messageChannelGroup.addTask { [signalHub] in
				// setup incoming (from livekit) signals sequence
				for try await message in messages  {
					Logger.plog(oslog: messageChannel.coordinator.messageChannelLog, publicMessage: "incoming message: \(message)")
					try await signalHub.handle(responseMessage: message)
				}
			}
			
			let outgoingDataPackets = signalHub.outgoingDataPackets.stream()
			messageChannelGroup.addTask { [signalHub] in
				for await dataPacket in outgoingDataPackets {
					try? await publishingPeerConnection.negotiate {
						let newState = $0 == .new
						return (newState, signalHub)
					}
					Logger.plog(oslog: messageChannel.coordinator.messageChannelLog, publicMessage: "outgoing data packet: \(dataPacket)")
					try? await publishingPeerConnection.send(dataPacket: dataPacket, preferred: .lossy)
				}
			}
			
			try await messageChannelGroup.cancelOnFirstCompletion()
		}
		Logger.plog(oslog: sessionLog, publicMessage: "session is disconnecting")
		try await signalHub.teardown()
	}
}
