//
//  SignalHub+RTC.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 5/5/23.
//

import Foundation
import Combine
import OSLog
@_implementationOnly import WebRTC
import AsyncAlgorithms

extension SignalHub {
	// publisherPeerConnection negotiation
	
	func negotiate() async {
		let peerConnection = peerConnectionFactory.publishingPeerConnection
		await peerConnection.offeringMachine(signalHub: self)
	}
	
	func waitForConnectedState(_ timeout: TimeInterval = 10) async throws {
		let peerConnection = peerConnectionFactory.publishingPeerConnection
		_ = try await peerConnection.connectionState.firstValue(timeout: timeout) { $0 == .connected }
	}
	
	//MARK: - handling of incoming/outgoing messages/requests
	
	func removeTrack(_ trackId: String) async throws {
		// accessing RTCPeerConnection via CurrentSubject > receive(on: WebRTC-Q (serial), that should make it pretty much sendable...
		try await peerConnectionFactory.publishingPeerConnection.withPeerConnection {
			let senders = $0.transceivers
				.map { transceiver in
					transceiver.sender
				}
				.filter { $0.senderId == trackId }
			for sender in senders {
				$0.removeTrack(sender)
			}
		}
	}
	
	func removeTransceiver(_ transceiver: RTCRtpTransceiver) async throws {
		guard let trackId = transceiver.sender.track?.trackId else { return }
		try await peerConnectionFactory.publishingPeerConnection.withPeerConnection {
			$0.removeSender(trackId: trackId)
		}
	}
	
	//MARK: - transceiver updates (subscriber only)
	func updateQuality(_ update: Livekit_SubscribedQualityUpdate, transceiver: RTCRtpTransceiver) {
		//		let sender = transceiver.sender
		//		guard mode == .publisher, sender.track?.trackId == update.trackSid else {
		//			return
		//		}
		//
		//		let parameters = sender.parameters
		//		let encodings = parameters.encodings
		//
		//		for quality in update.subscribedQualities {
		//			let rid = quality.quality.rid
		//			guard rid.isEmpty == false else { continue }
		//			guard let encoding = encodings.first(where: { $0.rid == rid }) else { continue }
		//			encoding.isActive = quality.enabled
		//		}
		//
		//		// Non simulcast streams don't have rids, handle here.
		//		if let firstEncoding = encodings.first, encodings.count == 1,
		//		   let firstQuality = update.subscribedQualities.first {
		//			firstEncoding.isActive = firstQuality.enabled
		//		}
		//
		//		sender.parameters = parameters
		//		//as per LocalParticipant.swift:~337
	}
}

extension SignalHub {
	func createVideoTransceiver(videoPublication: Publication) async throws -> PeerConnectionFactory.VideoPublishItems {
		try await peerConnectionFactory.videoTransceiver(videoPublication: videoPublication, enabled: true)
	}

	func createAudioTransceiver(audioPublication: Publication, enabled: Bool = false) async throws -> PeerConnectionFactory.AudioPublishItems {
		try await peerConnectionFactory.audioTransceiver(audioPublication: audioPublication, enabled: enabled)
	}
	
	func setMediaTrack(_ track: RTCMediaStreamTrack, enabled: Bool) async {
		let queue = await peerConnectionFactory.publishingPeerConnection.webRTCQueue
		await withCheckedContinuation { continuation in
			queue.sync {
				track.isEnabled = enabled
			}
			continuation.resume(returning: ())
		}
	}
}
