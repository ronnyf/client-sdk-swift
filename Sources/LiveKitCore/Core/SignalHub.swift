//
//  SignalHub.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 3/30/23.
//

import Foundation
import Combine
import OSLog
import AsyncAlgorithms
@_implementationOnly import WebRTC

public enum SignalHubError: Error {
	case noSignalClient
	case noMessageChannel
	case noJoinResponse
	case noAddTrackResponse
	case noAnswer
	case unhandled
	case negotiationFailed
}

// should this be an actor instead ? so the PeerConnection types can be classes instead of actors?
@available(iOS 15.0, macOS 12.0, *)
open class SignalHub: @unchecked Sendable {
	
	//MARK: - WebSocket messages, in/out
	//using this channel specifically for pong messages
	let outgoingDataRequestsChannel = AsyncChannel<Data>()
	let outgoingDataRequests = PassthroughSubject<Data, Never>()
	
	//MARK: - publishers
	//	let pongMessagesChannel = AsyncChannel<Int64>() // << Switch
	
	//MARK: - State Publishers
	@Publishing var joinResponse: Livekit_JoinResponse? = nil
	@Publishing public var localParticipant: LiveKitParticipant? = nil
	@Publishing public var remoteParticipants: [String: LiveKitParticipant] = [:]
	
	//published tracks ... used for addTrackRequest <> Response during publishing
	@Publishing var audioTracks: [String: LiveKitTrackInfo] = [:]
	@Publishing var videoTracks: [String: LiveKitTrackInfo] = [:]
	@Publishing var dataTracks: [String: LiveKitTrackInfo] = [:]
	
	@Publishing public var connectionQuality: [String: LiveKitConnectionQuality] = [:]
	@Publishing public var mediaStreams: [String: LiveKitStream] = [:]
	@Publishing public var receivers: [String: Receiver] = [:]
	
	@Publishing public var audioTransmitter: AudioTransmitter? = nil
	
	//MARK: - tokens
	let tokenUpdatesSubject = PassthroughSubject<String, Never>()
	
	//MARK: - quality updates
	//TODO
	@Publishing var subscriptionQualityUpdates: Livekit_SubscribedQualityUpdate? = nil
	
	//MARK: - speaker updates
	//TODO
	@Publishing var speakerChangedUpdates: Livekit_SpeakersChanged? = nil
	
	//MARK: - data channels
	let incomingDataPackets = PassthroughSubject<Livekit_DataPacket, Never>()
	let outgoingDataPackets = PassthroughSubject<Livekit_DataPacket, Never>()
	
	let signalHubLog = OSLog(subsystem: "SignalHub", category: "LiveKitCore")
	
	//MARK: - init/deinit
	
	let peerConnectionFactory: PeerConnectionFactory
	init(peerConnectionFactory: PeerConnectionFactory) {
		self.peerConnectionFactory = peerConnectionFactory
	}
	
	convenience public init() {
		self.init(peerConnectionFactory: PeerConnectionFactory())
	}
	
	deinit {
#if DEBUG
		Logger.log(oslog: signalHubLog, message: "deinit <SignalHub>")
#endif
	}
	
	func teardown() async throws {
		//0: housekeeping
		outgoingDataRequestsChannel.finish()
		outgoingDataRequests.send(completion: .finished)
		
		joinResponse = nil
		_joinResponse.finish()
		localParticipant = nil
		_localParticipant.finish()
		remoteParticipants.removeAll()
		_remoteParticipants.finish()
		
		audioTracks.removeAll()
		_audioTracks.finish()
		videoTracks.removeAll()
		_videoTracks.finish()
		dataTracks.removeAll()
		_dataTracks.finish()
		
		_connectionQuality.finish()
		
		mediaStreams.removeAll()
		_mediaStreams.finish()
		receivers.removeAll()
		_receivers.finish()
		
		tokenUpdatesSubject.send(completion: .finished)
		subscriptionQualityUpdates = nil
		_subscriptionQualityUpdates.finish()
		speakerChangedUpdates = nil
		_speakerChangedUpdates.finish()
		
		incomingDataPackets.send(completion: .finished)
		outgoingDataPackets.send(completion: .finished)
		
		peerConnectionFactory.teardown()
		
		Logger.log(oslog: signalHubLog, message: "signalHub did teardown")
	}
	
	public func tokenUpdates() -> AnyPublisher<String, Never> {
		tokenUpdatesSubject.eraseToAnyPublisher()
	}
	
	func enqueue(request: Livekit_SignalRequest) throws {
		do {
			let data = try request.serializedData()
			outgoingDataRequests.send(data)
			//			Logger.log(oslog: signalHubLog, message: "enqueue request: \(String(describing: request.message))")
		} catch {
			Logger.log(level: .error, oslog: signalHubLog, message: "MessageChannel: enqueue ERROR: \(error)")
		}
	}
}
