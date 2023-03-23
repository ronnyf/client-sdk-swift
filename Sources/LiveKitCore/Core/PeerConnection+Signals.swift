//
//  PeerConnection+Signals.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 10/3/23.
//

import Foundation
import Combine
@_implementationOnly import WebRTC

extension PeerConnection {	
	// called from session (in task group), injecting the signalhub property so we can collect the signals as needed
	func handlePeerConnectionSignals(with signalHub: SignalHub) async throws {
		for await rtcSignal in signals.values {
			try Task.checkCancellation()
			
			switch rtcSignal {
			case .didGenerate(let iceCandidate):
				// signal from RTCPeerConnection ... send over to LiveKit right away
				let request = try Livekit_SignalRequest(iceCandidate, target: peerConnectionIsPublisher ? .publisher : .subscriber)
				try signalHub.enqueue(request: request)
				
			case .didAddMediaStream(let mediaStream):
				let liveKitStream = LiveKitStream(mediaStream)
				Logger.log(oslog: coordinator.peerConnectionLog, message: "adding media stream: \(liveKitStream)")
				signalHub.mediaStreams.append(liveKitStream)
				
			case .didRemoveMediaStream(let mediaStream):
				Logger.log(oslog: coordinator.peerConnectionLog, message: "removing media stream: \(mediaStream)")
				if let index = signalHub.mediaStreams.firstIndex(where: { $0.streamId == mediaStream.streamId }) {
					signalHub.mediaStreams.remove(at: index)
				}
				
			case .didAddMediaStreams(let mediaStreams, let receiver):
				Logger.log(oslog: coordinator.peerConnectionLog, message: "added media streams: \(mediaStreams) with \(receiver)")
				signalHub.mediaStreams = mediaStreams.map { LiveKitStream($0) }
				
			case .dataChannelDidReceiveMessage(let buffer):
				let dataPacket = try Livekit_DataPacket(contiguousBytes: buffer.data)
				signalHub.incomingDataPackets.send(dataPacket)
				
			case .shouldNegotiate where peerConnectionIsPublisher == true:
				continue
				
			default:
				continue
			}
		}
	}
	
	func handleIncomingResponseMessage(_ message: Livekit_SignalResponse.OneOf_Message, signalHub: SignalHub) async throws -> Bool {
		switch message {
			// this arrives first, and we update the peer connection and everything, suspending
			// the incomming messages channel (back-pressure) until the peer connections are configured
		case .join(let joinResponse):
			try await configure(with: joinResponse)
			try await configureDataChannels()
			
			if joinResponse.subscriberPrimary == false {
				offeringMachine(signalHub: signalHub)
			}
			return peerConnectionIsPublisher == false
			
		case .trickle(let response) where response.target == .publisher && peerConnectionIsPublisher == true:
			try await addIceCandidate(response.candidateInit)
			return true
			
		case .trickle(let response) where response.target == .subscriber && peerConnectionIsPublisher == false:
			try await addIceCandidate(response.candidateInit)
			return true
			
		case .answer(let answer) where peerConnectionIsPublisher == true:
			Logger.log(oslog: coordinator.peerConnectionLog, message: "\(self.description) received answer: \(answer)")
			try await setRemoteDescription(answer)
			return true
			
			// offers that come in via websocket are for the subscribing pc only
		case .offer(let offer) where peerConnectionIsPublisher == false:
			Logger.log(oslog: coordinator.peerConnectionLog, message: "\(self.description) received offer: \(offer)")
			try await setRemoteDescription(offer)
			let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
			let answer = try await answer(for: constraints)
			let sdp = try await setLocalDescription(answer)
			let signalRequest = Livekit_SignalRequest(answer: sdp)
			try signalHub.enqueue(request: signalRequest)
			//waiting for trickle now ... on our way to 'connected'
			return true
			
		default:
			Logger.log(oslog: coordinator.peerConnectionLog, message: "\(self.description) unhandled message: \(message)")
			return false
		}
	}
}
