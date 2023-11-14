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
		_ = try await peerConnectionFactory.publishingPeerConnection.rtcPeerConnectionStatePublisher.firstValue(timeout: timeout) { $0 == .connected }
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

	func createAudioTransmitter(audioPublication: Publication, enabled: Bool = false) async throws -> AudioTransmitter? {
		try await peerConnectionFactory.publishingPeerConnection.audioTransmitter(audioPublication: audioPublication, enabled: enabled)
	}
	
	func createVideoTransmitter(videoPublication: Publication, enabled: Bool = false) async throws -> VideoTransmitter? {
		try await peerConnectionFactory.publishingPeerConnection.videoTransmitter(videoPublication: videoPublication, enabled: enabled)
	}
}
