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
		for await rtcSignal in signals.stream() {
			try Task.checkCancellation()
			
			switch rtcSignal {
			case .didGenerate(let iceCandidate):
				// signal from RTCPeerConnection ... send over to LiveKit right away
				let request = try Livekit_SignalRequest(iceCandidate, target: peerConnectionIsPublisher ? .publisher : .subscriber)
				try signalHub.enqueue(request: request)
				
			case .didAddMediaStream(let mediaStream):
				let liveKitStream = LiveKitStream(mediaStream)
				signalHub.mediaStreams[liveKitStream.participantId] = liveKitStream
				Logger.log(oslog: coordinator.peerConnectionLog, message: "\(self.description) did add media stream: \(liveKitStream)")
				
			case .didRemoveMediaStream(let mediaStream):
				Logger.log(oslog: coordinator.peerConnectionLog, message: "\(self.description) is removing a media stream: \(mediaStream)")
				let key = String(mediaStream.participantId)
				signalHub.mediaStreams.removeValue(forKey: key)
				
			case .didAddMediaStreams(let mediaStreams, let receiver):
				Logger.log(oslog: coordinator.peerConnectionLog, message: "\(self.description) did add media streams: \(mediaStreams) with \(receiver)")
				mediaStreams.grouped(by: \.participantId) { LiveKitStream($0) }.forEach { key, value in
					signalHub.mediaStreams[key] = value
				}
				if let publicReceiver = Receiver(receiver: receiver) {
					signalHub.receivers[receiver.receiverId] = publicReceiver
				} else {
					Logger.log(oslog: coordinator.peerConnectionLog, message: "no tracks in receiver \(receiver)")
				}
				
			case .didStartReceivingOn(let transceiver):
				Logger.log(oslog: coordinator.peerConnectionLog, message: "\(self.description) did start receiving on: \(transceiver)")
				if let _ = signalHub.receivers[transceiver.receiver.receiverId] {
					// we have that receiver already, why change anything?
				} else {
					if let publicReceiver = Receiver(receiver: transceiver.receiver) {
						signalHub.receivers[transceiver.receiver.receiverId] = publicReceiver
					} else {
						Logger.log(oslog: coordinator.peerConnectionLog, message: "no tracks in receiver \(transceiver.receiver)")
					}
				}
				
			case .didRemoveRtpReceiver(let receiver):
				Logger.log(oslog: coordinator.peerConnectionLog, message: "\(self.description) did remove: \(receiver)")
				signalHub.receivers.removeValue(forKey: receiver.receiverId)
				continue
				
			case .dataChannelDidReceiveMessage(let buffer):
				let dataPacket = try Livekit_DataPacket(contiguousBytes: buffer.data)
				signalHub.incomingDataPackets.send(dataPacket)
				
			case .shouldNegotiate where peerConnectionIsPublisher == true:
				continue
				
			default:
				continue
			}
		}
		
		Logger.log(oslog: coordinator.peerConnectionLog, message: "handlePeerConnectionSignals() task ended")
	}
	
	func handleIncomingResponseMessage(_ message: Livekit_SignalResponse.OneOf_Message, signalHub: SignalHub) async throws -> Bool {
		switch message {
			// this arrives first, and we update the peer connection and everything, suspending
			// the incomming messages channel (back-pressure) until the peer connections are configured
		case .join(let joinResponse) where peerConnectionIsPublisher == true:
			signalHub.joinResponse = joinResponse // TODO: shall we remove this one?
			
			try await configure(with: joinResponse)
			try await configureDataChannels()
			
			if joinResponse.subscriberPrimary == false {
				offeringMachine(signalHub: signalHub)
			}
			
			signalHub.localParticipant = LiveKitParticipant(joinResponse.participant)
			// ---v this should use same grouping as in SignalHub+Signals.swift:~line:23, though we map first
			signalHub.remoteParticipants = joinResponse.otherParticipants.grouped(by: \.id) { LiveKitParticipant($0) }
			return false // we want the subscribing peer connection to call configure() as well...
			
		case .join(let joinResponse) where peerConnectionIsPublisher == false:
			try await configure(with: joinResponse)
			return true
			
		case .trickle(let response) where response.target == .publisher && peerConnectionIsPublisher == true:
			try await add(candidateInit: response.candidateInit)
			return true
			
		case .trickle(let response) where response.target == .subscriber && peerConnectionIsPublisher == false:
			try await add(candidateInit: response.candidateInit)
			return true
			
		case .answer(let answer) where peerConnectionIsPublisher == true:
//			Logger.log(oslog: coordinator.peerConnectionLog, message: "\(self.description) received answer: \(answer)")
			try await update(remoteDescription: answer)
			return true
			
			// offers that come in via websocket are for the subscribing pc only
		case .offer(let offer) where peerConnectionIsPublisher == false:
//			Logger.log(oslog: coordinator.peerConnectionLog, message: "\(self.description) received offer: \(offer)")
			
			try await update(remoteDescription: offer)
			let answer = try await answerDescription()
			let sdp = try await update(localDescription: answer)
			let signalRequest = Livekit_SignalRequest(answer: sdp)
			try signalHub.enqueue(request: signalRequest)
			// waiting for trickle now ... on our way to 'connected'
			
			// find media streams
			if let joinResponse = signalHub.joinResponse {
				let found = try await findMediaStreams(joinResponse: joinResponse)
				print("DEBUG: \(found)")
			}
			return true
			
		default:
//			Logger.log(oslog: coordinator.peerConnectionLog, message: "\(self.description) unhandled message: \(message)")
			return false
		}
	}
}
