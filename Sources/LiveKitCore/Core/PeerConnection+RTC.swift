//
//  PeerConnection+RTC.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 9/22/23.
//

import Foundation
import Combine
@_implementationOnly import WebRTC

extension PeerConnection {
	func removeTrack(trackId: String) throws {
		dispatchPrecondition(condition: .onQueue(dispatchQueue))
		guard let rtcPeerConnection else { throw Errors.noPeerConnection }
		
		rtcPeerConnection.transceivers.map { transceiver in
			transceiver.sender
		}.filter {
			$0.senderId == trackId
		}
		.forEach { sender in
			rtcPeerConnection.removeTrack(sender)
		}
	}
	
	func removeTransceiver(_ transceiver: RTCRtpTransceiver) throws {
		dispatchPrecondition(condition: .onQueue(dispatchQueue))
		guard let rtcPeerConnection else { throw Errors.noPeerConnection }
		
		try rtcPeerConnection.senders
			.compactMap{ sender in
				sender.track?.trackId
			}
			.forEach {
				try removeTrack(trackId: $0)
			}
	}
	
	func candidateInit(_ value: String) async throws {
		dispatchPrecondition(condition: .onQueue(dispatchQueue))
		guard let rtcPeerConnection else { throw Errors.noPeerConnection }
		
		let candidate = try RTCIceCandidate(fromJsonString: value)
		assert(rtcPeerConnection.remoteDescription != nil)
		try await rtcPeerConnection.add(candidate)  // looks dangerous ... but shouldn't be since this actor has a serial executor defined
	}
	
	func update(localDescription rtcSdp: RTCSessionDescription) async throws -> Livekit_SessionDescription {
		dispatchPrecondition(condition: .onQueue(dispatchQueue))
		guard let rtcPeerConnection else { throw Errors.noPeerConnection }
		
		try await rtcPeerConnection.setLocalDescription(rtcSdp)
		return Livekit_SessionDescription(rtcSdp)
	}
	
	func update(localDescription lkSdp: Livekit_SessionDescription) async throws -> Livekit_SessionDescription {
		dispatchPrecondition(condition: .onQueue(dispatchQueue))
		return try await update(localDescription: RTCSessionDescription(lkSdp))
	}
	
	func update(remoteDescription rtcSdp: RTCSessionDescription) async throws -> Livekit_SessionDescription {
		dispatchPrecondition(condition: .onQueue(dispatchQueue))
		guard let rtcPeerConnection else { throw Errors.noPeerConnection }
		
		try await rtcPeerConnection.setRemoteDescription(rtcSdp)
		
		let pendingCandidates = pendingIceCandidates()
		if pendingCandidates.count > 0 {
			try await withThrowingTaskGroup(of: Void.self) { group in
				for pendingCandidate in pendingCandidates {
					group.addTask {
						try await self.add(candidateInit: pendingCandidate)
					}
				}
				try await group.waitForAll()
			}
			update(pendingCandidates: [])
		}
		
		return Livekit_SessionDescription(rtcSdp)
	}
	
	@discardableResult
	func update(remoteDescription lkSdp: Livekit_SessionDescription) async throws -> Livekit_SessionDescription {
		dispatchPrecondition(condition: .onQueue(dispatchQueue))
		return try await update(remoteDescription: RTCSessionDescription(lkSdp))
	}
	
	func add(candidateInit: String) async throws {
		//		Logger.log(oslog: coordinator.peerConnectionLog, message: "\(self.description) will add ice candidate \(candidateInit)")
		dispatchPrecondition(condition: .onQueue(dispatchQueue))
		guard let rtcPeerConnection else { throw Errors.noPeerConnection }
		
		guard let _ = rtcPeerConnection.remoteDescription else {
			update(pendingCandidate: candidateInit)
			return
		}
		
		try await add(iceCandidate: RTCIceCandidate(fromJsonString: candidateInit))
	}
	
	func add(iceCandidate candidate: IceCandidate) async throws {
		try await add(iceCandidate: RTCIceCandidate(candidate))
	}
	
	func add(iceCandidate candidate: RTCIceCandidate) async throws {
		dispatchPrecondition(condition: .onQueue(dispatchQueue))
		guard let rtcPeerConnection else { throw Errors.noPeerConnection }
		
		assert(rtcPeerConnection.remoteDescription != nil)
		try await rtcPeerConnection.add(candidate)
	}
	
	func transceiver(with track: RTCMediaStreamTrack, transceiverInit: RTCRtpTransceiverInit) async throws -> RTCRtpTransceiver {
		dispatchPrecondition(condition: .onQueue(dispatchQueue))
		guard let rtcPeerConnection else { throw Errors.noPeerConnection }
		
		guard let transceiver = rtcPeerConnection.addTransceiver(with: track, init: transceiverInit) else {
			throw Errors.createTransceiver
		}
		return transceiver
	}
	
	func offerDescription(with constraints: RTCMediaConstraints) async throws -> RTCSessionDescription {
		dispatchPrecondition(condition: .onQueue(dispatchQueue))
		guard let rtcPeerConnection else { throw Errors.noPeerConnection }
		
		return try await rtcPeerConnection.offer(for: constraints)
	}
	
	func answerDescription(with constraints: RTCMediaConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)) async throws -> RTCSessionDescription {
		dispatchPrecondition(condition: .onQueue(dispatchQueue))
		guard let rtcPeerConnection else { throw Errors.noPeerConnection }
		
		return try await rtcPeerConnection.answer(for: constraints)
	}
	
	//MARK: - utilities
	
	func findMediaStreams(joinResponse: Livekit_JoinResponse) async throws -> [LiveKitStream] {
		dispatchPrecondition(condition: .onQueue(dispatchQueue))
		guard peerConnectionIsPublisher == false else { return [] }
		guard let rtcPeerConnection else { throw Errors.noPeerConnection }
		
		let mediaTracks = rtcPeerConnection.transceivers
			.compactMap { $0.receiver.track }
			.grouped(by: \RTCMediaStreamTrack.trackId)
		
		guard mediaTracks.count > 0 else { return [] }
		
		return joinResponse.otherParticipants.map {
			
			// streamId ------v
			// PA_dQDLmN3aFt92|TR_VCcdbkczVxyutm
			// participantId-^ ^---------trackId
			
			let participantId = $0.sid
			
			let allTracks = $0.tracks.lazy
			let videoTracks = allTracks.filter { $0.type == .video }
			let audioTracks = allTracks.filter { $0.type == .audio }
			
			let foundVideoTracks = videoTracks.compactMap { videoTrack -> MediaTrack? in
				guard let mediaStreamTrack = mediaTracks[videoTrack.sid] else { return nil }
				return MediaTrack(mediaStreamTrack)
			}
			
			let foundAudioTracks = audioTracks.compactMap { audioTrack -> MediaTrack? in
				guard let mediaStreamTrack = mediaTracks[audioTrack.sid] else { return nil }
				return MediaTrack(mediaStreamTrack)
			}
			
			return LiveKitStream(
				participantId: participantId,
				videoTracks: foundVideoTracks,
				audioTracks: foundAudioTracks
			)
		}
	}
}
