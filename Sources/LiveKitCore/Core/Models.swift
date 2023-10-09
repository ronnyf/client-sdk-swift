//
//  Models.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 4/24/23.
//

import Combine
import OSLog
import AVFoundation
@_implementationOnly import WebRTC

//MARK: - WebRTC Types

extension RTCIceServer {
	
	convenience init(_ livekit_ICEServer: Livekit_ICEServer) {
		self.init(
			urlStrings: livekit_ICEServer.urls,
			username: livekit_ICEServer.username.nilIfEmpty,
			credential: livekit_ICEServer.credential.nilIfEmpty
		)
	}
}

extension String {
	
	fileprivate var nilIfEmpty: Self? {
		isEmpty == false ? self : nil
	}
}

extension RTCRtpEncodingParameters {
	
	convenience init(rid: String? = nil, encoding: MediaEncoding? = nil, scaleDownBy: Double? = nil, active: Bool = true) {
		self.init()
		
		self.isActive = isActive
		self.rid = rid
		
		if let scaleDownBy = scaleDownBy {
			self.scaleResolutionDownBy = NSNumber(value: scaleDownBy)
		}
		
		if let encoding = encoding {
			self.maxBitrateBps = NSNumber(value: encoding.maxBitrate)
			
			// VideoEncoding specific
			if let videoEncoding = encoding as? VideoEncoding {
				self.maxFramerate = NSNumber(value: videoEncoding.maxFps)
			}
		}
	}
}

extension RTCDataChannelConfiguration {
	static func createDataChannelConfiguration(ordered: Bool = true, maxRetransmits: Int32 = -1) -> RTCDataChannelConfiguration {
		
		let result = RTCDataChannelConfiguration()
		result.isOrdered = ordered
		result.maxRetransmits = maxRetransmits
		return result
	}
}

extension RTCRtpTransceiverInit {
	convenience init<E: MediaEncoding>(encoding: E?) {
		self.init()
		self.direction = .sendOnly
		self.sendEncodings = [Engine.createRtpEncodingParameters(encoding: encoding)]
	}
	
	convenience init(encodingParameters: [RTCRtpEncodingParameters]) {
		self.init()
		self.direction = .sendOnly
		self.sendEncodings = encodingParameters
	}
}

extension RTCRtpEncodingParameters {

	var __description: String {
		"RTCRtpEncodingParameters(rid: \(rid ?? "nil"), "
			+ "active: \(isActive), "
			+ "scaleResolutionDownBy: \(String(describing: scaleResolutionDownBy)), "
			+ "minBitrateBps: \(minBitrateBps == nil ? "nil" : String(describing: minBitrateBps)), "
			+ "maxBitrateBps: \(maxBitrateBps == nil ? "nil" : String(describing: maxBitrateBps)), "
			+ "maxFramerate: \(maxFramerate == nil ? "nil" : String(describing: maxFramerate)))"
	}
}

extension RTCDataChannelState {

	var _description: String {
		switch self {
		case .connecting: return ".connecting"
		case .open: return ".open"
		case .closing: return ".closing"
		case .closed: return ".closed"
		@unknown default: return ".unknown"
		}
	}
}

extension RTCDataChannelConfiguration {
	
	static func make(ordered: Bool = true, maxRetransmits: Int32 = -1) -> RTCDataChannelConfiguration {
		let configuration = RTCDataChannelConfiguration()
		configuration.isOrdered = ordered
		configuration.maxRetransmits = maxRetransmits
		return configuration
	}
}

extension RTCSessionDescription {
	convenience init(_ liveKit_SessionDescription: Livekit_SessionDescription) {
		let type = RTCSessionDescription.type(for: liveKit_SessionDescription.type)
		self.init(type: type, sdp: liveKit_SessionDescription.sdp)
	}
}

extension RTCIceCandidate {
	convenience init(_ iceCandidate: IceCandidate) {
		self.init(sdp: iceCandidate.sdp, sdpMLineIndex: iceCandidate.sdpMLineIndex, sdpMid: iceCandidate.sdpMid)
	}
}

extension RTCDataChannel {
	func withDelegate(_ delegate: RTCDataChannelDelegate) -> Self {
		self.delegate = delegate
		return self
	}
}

extension RTCPeerConnectionState {
	var debugDescription: String {
		switch self {
		case .new:
			return "New"
			
		case .connecting:
			return "Connecting"
			
		case .connected:
			return "Connected"
			
		case .disconnected:
			return "Disconnected"
			
		case .failed:
			return "Failed"
			
		case .closed:
			return "Closed"
			
		@unknown default:
			return "Unknown"
		}
	}
}

extension RTCSignalingState {
	var debugDescription: String {
		switch self {
		case .stable:
			return "Stable"
			
		case .haveLocalOffer:
			return "Have Local Offer"
			
		case .haveLocalPrAnswer:
			return "Have Local Pr Answer"
			
		case .haveRemoteOffer:
			return "Have Remote Offer"
			
		case .haveRemotePrAnswer:
			return "Have Remote Pr Answer"
			
		case .closed:
			return "Closed"
			
		@unknown default:
			return "Unknown"
		}
	}
}

extension RTCIceConnectionState {
	var debugDescription: String {
		switch self {
		case .new:
			return "New"
			
		case .checking:
			return "Checking"
			
		case .connected:
			return "Connected"
			
		case .completed:
			return "Completed"
			
		case .failed:
			return "Failed"
			
		case .disconnected:
			return "Disconnected"
			
		case .closed:
			return "Closed"
			
		case .count:
			return "Count"
			
		@unknown default:
			return "Unknown"
		}
	}
}

extension RTCIceGatheringState {
	var debugDescription: String {
		switch self {
			
		case .new:
			return "New"
			
		case .gathering:
			return "Gathering"
			
		case .complete:
			return "Complete"
			
		@unknown default:
			return "Unknown"
		}
	}
}

extension RTCPeerConnectionState: @unchecked Sendable {}
extension RTCSessionDescription: @unchecked Sendable {}
extension RTCMediaConstraints: @unchecked Sendable {}
extension RTCVideoFrame: @unchecked Sendable {}
extension RTCMediaStream: @unchecked Sendable {}
extension RTCMediaStreamTrack: @unchecked Sendable {}
//extension RTCRtpTransceiver: @unchecked Sendable {} // not sure if I'd go this far (yet)

extension RTCPeerConnection {
	func removeSender(trackId: String) {
		let senders = self.senders.filter {
			guard let track = $0.track else { return false }
			return track.trackId == trackId
		}
		for sender in senders {
			self.removeTrack(sender)
		}
	}
}

//MARK: - LiveKit Types

extension Livekit_ICEServer {
	
	var rtcIceServer:  RTCIceServer {
		
		let rtcUsername = !username.isEmpty ? username : nil
		let rtcCredential = !credential.isEmpty ? credential : nil
		return RTCIceServer(urlStrings: urls, username: rtcUsername, credential: rtcCredential)
	}
}

extension Livekit_SignalResponse.OneOf_Message {
	
	enum Errors: Error {
		case emptyMessage
		case invalid
	}
	
	init(message: URLSessionWebSocketTask.Message) throws {
		
		var responseMessage: Livekit_SignalResponse.OneOf_Message?
		switch message {
		case .data(let bytes):
			responseMessage = try Livekit_SignalResponse(contiguousBytes: bytes).message
			
		case .string(let stringValue):
			responseMessage = try Livekit_SignalResponse(jsonString: stringValue).message
			
		@unknown default:
			print("unknown SignalResponseType")
			throw Errors.invalid
		}
		
		guard let responseMessage else { throw Errors.emptyMessage }
		self = responseMessage
	}
}

extension Livekit_SignalResponse: CustomStringConvertible {
	var description: String {
		"Livekit_SignalResponse:\(String(describing: message))"
	}
}

extension Livekit_SignalRequest {
	
	static var leaveRequest: Self {
		Livekit_SignalRequest.with {
			$0.leave = Livekit_LeaveRequest.with {
				$0.canReconnect = false
				$0.reason = .clientInitiated
			}
		}
	}
	
	static var pingRequest: Self {
		Livekit_SignalRequest.with {
			$0.ping = Int64(Date().timeIntervalSince1970)
		}
	}
	
	init(offer sdp: RTCSessionDescription) {
		self.init(offer: Livekit_SessionDescription(sdp))
	}
	
	init(offer sdp: Livekit_SessionDescription) {
		offer = sdp
	}
	
	init(answer sdp: RTCSessionDescription) {
		self.init(answer: Livekit_SessionDescription(sdp))
	}
	
	init(answer sdp: Livekit_SessionDescription) {
		answer = sdp
	}
	
	init(_ iceCandidate: IceCandidate, target: Livekit_SignalTarget) throws {
		self.trickle = try Livekit_TrickleRequest.with {
			$0.target = target
			$0.candidateInit = try iceCandidate.toJsonString()
		}
	}
	
	static func makeTrickleRequest(candidate: RTCIceCandidate, target: Livekit_SignalTarget) throws -> Self {
		try Livekit_SignalRequest.with {
			$0.trickle = try Livekit_TrickleRequest.with {
				$0.target = target
				$0.candidateInit = try IceCandidate(candidate).toJsonString()
			}
		}
	}
}

extension Livekit_SessionDescription {
	init(_ sd: RTCSessionDescription) {
		self.sdp = sd.sdp
		self.type = RTCSessionDescription.string(for: sd.type)
	}

	init?(_ sd: RTCSessionDescription?) {
		guard let sd else { return nil }
		self.init(sd)
	}
}

extension IceCandidate {
	init(_ rtcIceCandidate: RTCIceCandidate) {
		self.sdp = rtcIceCandidate.sdp
		self.sdpMLineIndex = rtcIceCandidate.sdpMLineIndex
		self.sdpMid = rtcIceCandidate.sdpMid
	}
}

extension Livekit_VideoQuality {
	var rid: String {
		switch self {
			
		case .high:
			return "f"
			
		case .medium:
			return "h"
			
		case .low:
			return "q"
			
		default:
			return ""
		}
	}
}

extension Livekit_TrackPermission {
	init(_ trackPermission: LiveKitTrack.Permission) {
		self.participantSid = trackPermission.participantSid
		self.allTracks = trackPermission.allAllowed
		self.trackSids = trackPermission.allowedTrackSids
		self.participantIdentity = trackPermission.participantIdentity
	}
}

extension Livekit_ConnectionQualityUpdate {
	var livekitQualities: [String: LiveKitConnectionQuality] {
		updates.grouped(by: \.participantId) {
			LiveKitConnectionQuality(participantId: $0.participantSid, quality: LiveKitQuality($0.quality), score: $0.score)
		}
	}
}
