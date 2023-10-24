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

extension SignalHub {
	// publisherPeerConnection negotiation
	
	func negotiate() async {
		await peerConnectionFactory.publishingPeerConnection.offeringMachine(signalHub: self)
	}
	
	func waitForConnectedState(_ timeout: TimeInterval = 10) async throws {
		_ = try await peerConnectionFactory.publishingPeerConnection.rtcPeerConnectionState.firstValue(timeout: timeout) { $0 == .connected }
	}
	
	//MARK: - handling of incoming/outgoing messages/requests
	
	func removeTrack(_ trackId: String) async throws {
		try await peerConnectionFactory.publishingPeerConnection.removeTrack(trackId: trackId)
	}
	
	func removeTransceiver(_ transceiver: RTCRtpTransceiver) async throws {
		try await peerConnectionFactory.publishingPeerConnection.removeTransceiver(transceiver)
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
	
	func createVideoTransceiver(videoPublication: Publication) async throws -> PeerConnection.VideoPublishItems {
		try await peerConnectionFactory.publishingPeerConnection.videoTransceiver(videoPublication: videoPublication, enabled: true)
	}

	func createAudioTransceiver(audioPublication: Publication, enabled: Bool = false) async throws -> PeerConnection.AudioPublishItems {
		try await peerConnectionFactory.publishingPeerConnection.audioTransceiver(audioPublication: audioPublication, enabled: enabled)
	}
	
	func setMediaTrack(_ track: RTCMediaStreamTrack, enabled: Bool) {
		peerConnectionFactory.publishingPeerConnection.dispatchQueue.async {
			track.isEnabled = enabled
		}
	}
}
