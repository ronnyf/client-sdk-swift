//
//  SharedModels.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 5/16/23.
//

import Foundation
import Combine
import SwiftUI
#if os(iOS)
import UIKit
#endif
@_implementationOnly import WebRTC

//MARK: - Connected State

public enum LiveKitState: Sendable {
	case new
	case connecting
	case connected
	case disconnected
	case failed
	case closed
	
	init(_ rtcPeerConnectionState: RTCPeerConnectionState) {
		switch rtcPeerConnectionState {
		case .new:
			self = .new
			
		case .connecting:
			self = .connecting
			
		case .connected:
			self = .connected
			
		case .disconnected:
			self = .disconnected
			
		case .failed:
			self = .failed
			
		case .closed:
			self = .closed
			
		@unknown default:
			self = .closed
		}
	}
}

//MARK: - Stream

public struct MediaTrack: Sendable {
	public enum TrackType: Sendable {
		case audio
		case video
		case unknown
	}
	
	public let trackId: String
	public let trackType: TrackType
	
	public init(trackId: String, trackType: TrackType) {
		self.trackId = trackId
		self.trackType = trackType
	}
	
	init(_ rtcMediaStreamTrack: RTCMediaStreamTrack) {
		self.init(trackId: rtcMediaStreamTrack.trackId, trackType: TrackType(rtcMediaStreamTrack.kind))
	}
}

extension MediaTrack.TrackType {
	init(_ rtcMediaStreamTrackKind: String) {
		if rtcMediaStreamTrackKind == kRTCMediaStreamTrackKindAudio {
			self = .audio
		} else if rtcMediaStreamTrackKind == kRTCMediaStreamTrackKindVideo {
			self = .video
		} else {
			self = .unknown
		}
	}
}

extension MediaTrack: Identifiable {
	public var id: String { trackId }
}

extension MediaTrack: Equatable {
	public static func ==(lhs: MediaTrack, rhs: MediaTrack) -> Bool {
		lhs.trackId == rhs.trackId
	}
}

public struct LiveKitStream: Sendable {
	
	public enum State: Sendable {
		case active
		case paused
		
		init?(_ livekit_StreamState: Livekit_StreamState) {
			switch livekit_StreamState {
			case .active:
				self = .active
				
			case .paused:
				self = .paused
				
			default:
				return nil
			}
		}
	}
	
	public let participantId: String //participant ID
	
	public var videoTracks: [MediaTrack]
	public var audioTracks: [MediaTrack]
	//	public let dataTracks: [LiveKitTrackInfo.LiveKitTrack] //not supported(yet)
	
	public init<S: Sequence>(participantId: String, videoTracks: S, audioTracks: S) where S.Element == MediaTrack {
		self.participantId = participantId
		self.videoTracks = Array(videoTracks)
		self.audioTracks = Array(audioTracks)
	}
	
	init(_ rtcMediaStream: RTCMediaStream) {	
		self.init(
			// e.g.: PA_dQDLmN3aFt92 (omitting '|TR_VCcdbkczVxyutm')
			participantId: String(rtcMediaStream.participantId),
			videoTracks: rtcMediaStream.videoTracks.map { MediaTrack($0) },
			audioTracks: rtcMediaStream.audioTracks.map { MediaTrack($0) }
		)
	}
	
	mutating func update(with rtcMediaStream: RTCMediaStream) {
		if rtcMediaStream.videoTracks.isEmpty == false {
			videoTracks = rtcMediaStream.videoTracks.map { MediaTrack($0) }
		}
		
		if rtcMediaStream.audioTracks.isEmpty == false {
			audioTracks = rtcMediaStream.audioTracks.map { MediaTrack($0) }
			
		}
	}
}

extension LiveKitStream: Equatable {
	static public func ==(lhs: LiveKitStream, rhs: LiveKitStream) -> Bool {
		lhs.participantId == rhs.participantId
	}
}

extension LiveKitStream: Hashable {
	public func hash(into hasher: inout Hasher) {
		hasher.combine(participantId)
	}
}

extension LiveKitStream: Identifiable {
	public var id: String { participantId }
}

//MARK: - Participant

public struct LiveKitParticipant: Sendable {
	
	public enum State: Sendable {
		case joined
		case joining
		case active
		case disconnected
		case invalid
	}
	
	public var id: String
	public var name: String
	public var state: State
	public var joinedAt: Int64
	public var joinedSince: Date {
		Date(timeIntervalSince1970: TimeInterval(joinedAt))
	}
	public var canPublish: Bool
	public var canSubscribe: Bool
	public var canPublishData: Bool
	public var region: String
	public var tracks: [LiveKitTrackInfo.LiveKitTrack]
	
	public static var nobody: LiveKitParticipant {
		LiveKitParticipant(
			id: "",
			name: "",
			state: .disconnected,
			joinedAt: 0,
			canPublish: false,
			canSubscribe: false,
			canPublishData: false,
			region: "",
			tracks: []
		)
	}
	
	public init(
		id: String,
		name: String,
		state: State,
		joinedAt: Int64,
		canPublish: Bool,
		canSubscribe: Bool,
		canPublishData: Bool,
		region: String,
		tracks: [LiveKitTrackInfo.LiveKitTrack]
	) {
		self.id = id
		self.name = name
		self.state = state
		self.joinedAt = joinedAt
		self.canPublish = canPublish
		self.canSubscribe = canSubscribe
		self.canPublishData = canPublishData
		self.region = region
		self.tracks = tracks
	}
	
	init(_ participantInfo: Livekit_ParticipantInfo) {
		self.id = participantInfo.sid
		self.name = participantInfo.name
		self.state = State(participantInfoState: participantInfo.state)
		self.joinedAt = participantInfo.joinedAt
		self.canPublish = participantInfo.permission.canPublish
		self.canSubscribe = participantInfo.permission.canSubscribe
		self.canPublishData = participantInfo.permission.canPublishData
		self.region = participantInfo.region
		self.tracks = participantInfo.tracks.map { LiveKitTrackInfo.LiveKitTrack($0) }
	}
}

extension LiveKitParticipant.State {
	
	init(participantInfoState: Livekit_ParticipantInfo.State) {
		switch participantInfoState {
		case .joining:
			self = .joining
			
		case .joined:
			self = .joined
			
		case .active:
			self = .active
			
		case .disconnected:
			self = .disconnected
			
		default:
			self = .invalid
		}
	}
}

extension LiveKitParticipant: Equatable {
	
	public static func ==(lhs: Self, rhs: Self) -> Bool {
		lhs.id == rhs.id
	}
}

extension LiveKitParticipant: Hashable {
	
	public func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}
}

extension LiveKitParticipant: Comparable {
	
	public static func < (lhs: LiveKitParticipant, rhs: LiveKitParticipant) -> Bool {
		lhs.joinedSince < rhs.joinedSince
	}
}

extension LiveKitParticipant: Identifiable {}

//MARK: - quality

public struct LiveKitConnectionQuality: Sendable {
	public let participantId: String
	public let quality: LiveKitQuality
	public let score: Float
	
	public init(participantId: String, quality: LiveKitQuality, score: Float) {
		self.participantId = participantId
		self.quality = quality
		self.score = score
	}
}

extension LiveKitConnectionQuality: Identifiable {
	public var id: String { participantId }
}

public enum LiveKitQuality : Sendable{
	case poor
	case good
	case excellent
	case value(Int)
}

extension LiveKitQuality: CustomStringConvertible {
	public var description: String {
		switch self {
		case .poor:
			return "QUALITY_POOR"
		case .good:
			return "QUALITY_GOOD"
		case .excellent:
			return "QUALITY_EXCELLENT"
		case .value(let value):
			return "\(value)"
		}
	}
}

extension LiveKitQuality {
	init(_ livekit_ConnectionQuality: Livekit_ConnectionQuality) {
		switch livekit_ConnectionQuality {
		case .poor:
			self = .poor
			
		case .good:
			self = .good
			
		case .excellent:
			self = .excellent
			
		case .UNRECOGNIZED(let value):
			self = .value(value)
		}
	}
}


//MARK: - subscription quality update

public struct LiveKitSubscriptionQualityUpdate {
	
	public let trackId: String
	public let qualities: [Quality]
	public let codecs: [Codec]
	
	init(_ subscribedQualityUpdate: Livekit_SubscribedQualityUpdate) {
		self.trackId = subscribedQualityUpdate.trackSid
		self.qualities = subscribedQualityUpdate.subscribedQualities.map { Quality($0) }
		self.codecs = subscribedQualityUpdate.subscribedCodecs.map { Codec($0) }
	}
	
	public struct Codec {
		
		public let name: String
		public let qualities: [Quality]
		
		init(_ subscribedCodec: Livekit_SubscribedCodec) {
			self.name = subscribedCodec.codec
			self.qualities = subscribedCodec.qualities.map { Quality($0) }
		}
	}
	
	public struct Quality {
		
		public let enabled: Bool
		public let videoQuality: VideoQuality
		
		init(_ subscribedQuality: Livekit_SubscribedQuality) {
			self.enabled = subscribedQuality.enabled
			self.videoQuality = VideoQuality(subscribedQuality.quality)
		}
		
		public enum VideoQuality {
			case low
			case medium
			case high
			case off
			
			init(_ videoQuality: Livekit_VideoQuality) {
				switch videoQuality {
				case .low:
					self = .low
				case .medium:
					self = .medium
				case .high:
					self = .high
				case .off:
					self = .off
					
				case .UNRECOGNIZED(_):
					self = .off
				}
			}
		}
	}
}

//MARK: - User Packets

public enum LiveKitPacketData: Sendable {
	case user(LiveKitUserData)
	case speaker(LiveKitSpeaker)
	case unknown
	
	init(_ liveKitDataPacket: Livekit_DataPacket) {
		switch liveKitDataPacket.value {
		case .user(let userPacket):
			self = .user(LiveKitUserData(userPacket))
			
		case .speaker(let speakerData):
			self = .speaker(LiveKitSpeaker(speakerData))
			
		default:
			self = .unknown
		}
	}
}

public struct LiveKitUserData: Sendable {
	/// participant ID of user that sent the message
	public let participantSid: String
	
	public let participantIdentity: String
	
	/// user defined payload
	public let payload: Data
	
	/// the ID of the participants who will receive the message (sent to all by default)
	public let destinationSids: [String]
	
	/// identities of participants who will receive the message (sent to all by default)
	public let destinationIdentities: [String]
	
	/// topic under which the message was published
	public let topic: String
	
	public init(
		payload: Data,
		participantSid: String,
		participantIdentity: String,
		destinationSids: [String] = [],
		destinationIdentities: [String] = [],
		topic: String = ""
	) {
		self.payload = payload
		self.participantSid = participantSid
		self.participantIdentity = participantIdentity
		self.destinationSids = destinationSids
		self.destinationIdentities = destinationIdentities
		self.topic = topic
	}
	
	init(_ livekitUserPacket: Livekit_UserPacket) {
		self.init(
			payload: livekitUserPacket.payload,
			participantSid: livekitUserPacket.participantSid,
			participantIdentity: livekitUserPacket.participantIdentity,
			destinationSids: livekitUserPacket.destinationSids,
			destinationIdentities: livekitUserPacket.destinationIdentities,
			topic: livekitUserPacket.topic
		)
	}
	
	func makeUserPacket() -> Livekit_UserPacket {
		let userPacket = Livekit_UserPacket.with {
			$0.payload = payload
			$0.participantSid = participantSid
			$0.participantIdentity = participantIdentity
			$0.destinationSids = destinationSids
			$0.destinationIdentities = destinationIdentities
			$0.topic = topic
		}
		return userPacket
	}
	
	func makeDataPacket(label: PeerConnection.DataChannelLabel = .reliable) -> Livekit_DataPacket {
		let dataPacket = Livekit_DataPacket.with {
			$0.user = makeUserPacket()
			$0.kind = Livekit_DataPacket.Kind(label)
		}
		return dataPacket
	}
}

//MARK: - Speaker

public struct SpeakingParticipant: Sendable {
	
	public let id: String
	public let active: Bool
	public let level: Float
	
	static func make(from speakerChanged: Livekit_SpeakersChanged) -> [SpeakingParticipant] {
		speakerChanged.speakers.map { SpeakingParticipant($0) }
	}
	
	static func make(from activeSpeakerUpdate: Livekit_ActiveSpeakerUpdate) -> [SpeakingParticipant] {
		activeSpeakerUpdate.speakers.map { SpeakingParticipant($0) }
	}
	
	init(_ livekit_SpeakerInfo: Livekit_SpeakerInfo) {
		self.id = livekit_SpeakerInfo.sid
		self.active = livekit_SpeakerInfo.active
		self.level = livekit_SpeakerInfo.level
	}
}

extension SpeakingParticipant: Equatable {
	public static func ==(lhs: SpeakingParticipant, rhs: SpeakingParticipant) -> Bool {
		lhs.id == rhs.id
	}
}

extension SpeakingParticipant: Hashable {
	public func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}
}

extension SpeakingParticipant: Identifiable {}

public struct LiveKitSpeaker: Sendable {
	
	public let speakers: [SpeakingParticipant]
	
	init(_ speakerChanged: Livekit_SpeakersChanged) {
		self.speakers = speakerChanged.speakers.map { SpeakingParticipant($0) }
	}
	
	init(_ activeSpeakerUpdate: Livekit_ActiveSpeakerUpdate) {
		self.speakers = activeSpeakerUpdate.speakers.map { SpeakingParticipant($0) }
	}
	
	init<S: Sequence>(_ speakers: S) where S.Element == SpeakingParticipant {
		self.speakers = Array(speakers)
	}
}

//MARK: - Track published / unpublished

public struct LiveKitTrackInfo: Sendable {
	public let trackSid: String
	public let track: LiveKitTrack?
	
	init(_ published: Livekit_TrackPublishedResponse) {
		self.trackSid = published.track.sid
		self.track = LiveKitTrack(published.track)
	}
	
	init(_ unpublished: Livekit_TrackUnpublishedResponse) {
		self.trackSid = unpublished.trackSid
		self.track = nil
	}
	
	public struct LiveKitTrack: Sendable {
		
		public let sid: String
		public let type: Kind
		public let name: String
		public let muted: Bool
		public let width: UInt32
		public let height: UInt32
		public let simulcast: Bool
		public let disableDtx: Bool
		public let source: Source
		public let layers: [VideoLayer]
		public let mimeType: String
		public let mid: String
		public let codecs: [CodecInfo]
		public let stereo: Bool
		
		public init(sid: String, type: Kind, name: String, muted: Bool, width: UInt32, height: UInt32, simulcast: Bool, disableDtx: Bool, source: Source, layers: [VideoLayer], mimeType: String, mid: String, codecs: [CodecInfo], stereo: Bool) {
			self.sid = sid
			self.type = type
			self.name = name
			self.muted = muted
			self.width = width
			self.height = height
			self.simulcast = simulcast
			self.disableDtx = disableDtx
			self.source = source
			self.layers = layers
			self.mimeType = mimeType
			self.mid = mid
			self.codecs = codecs
			self.stereo = stereo
		}
		
		init(_ info: Livekit_TrackInfo) {
			self.init(sid: info.sid, type: Kind(info.type), name: info.name, muted: info.muted, width: info.width, height: info.height, simulcast: info.simulcast, disableDtx: info.disableDtx, source: Source(info.source), layers: info.layers.map { VideoLayer($0) }, mimeType: info.mimeType, mid: info.mid, codecs: info.codecs.map { CodecInfo($0) }, stereo: info.stereo)
		}
	}
	
	public enum Kind: Sendable {
		case audio
		case video
		case data
		case unknown
		
		init(_ trackType: Livekit_TrackType) {
			switch trackType {
			case .audio:
				self = .audio
			case .video:
				self = .video
			case .data:
				self = .data
			case .UNRECOGNIZED(_):
				self = .unknown
			}
		}
	}
	
	public enum Source: Sendable {
		case unknown // = 0
		case camera // = 1
		case microphone // = 2
		case screenShare // = 3
		case screenShareAudio // = 4
		
		init(_ source: Livekit_TrackSource) {
			switch source {
			case .unknown:
				self = .unknown
			case .camera:
				self = .camera
			case .microphone:
				self = .microphone
			case .screenShare:
				self = .screenShare
			case .screenShareAudio:
				self = .screenShareAudio
			case .UNRECOGNIZED(_):
				self = .unknown
			}
		}
	}
	
	public struct VideoLayer: Sendable {
		
		let quality: VideoQuality
		let width: UInt32
		let height: UInt32
		let bitrate: UInt32
		let ssrc: UInt32
		
		init(_ layer: Livekit_VideoLayer) {
			self.quality = VideoQuality(layer.quality)
			self.width = layer.width
			self.height = layer.height
			self.bitrate = layer.bitrate
			self.ssrc = layer.ssrc
		}
	}
	
	public enum	VideoQuality: Sendable {
		case low // = 0
		case medium // = 1
		case high // = 2
		case off // = 3
		case custom(Int)
		
		init(_ quality: Livekit_VideoQuality) {
			switch quality {
			case .low:
				self = .low
			case .medium:
				self = .medium
			case .high:
				self = .high
			case .off:
				self = .off
			case .UNRECOGNIZED(let value):
				self = .custom(value)
			}
		}
	}
	
	public struct CodecInfo: Sendable {
		
		let mimeType: String
		let mid: String
		let cid: String
		let layers: [VideoLayer]
		
		init(_ info: Livekit_SimulcastCodecInfo) {
			self.mimeType = info.mimeType
			self.mid = info.mid
			self.cid = info.cid
			self.layers = info.layers.map { VideoLayer($0) }
		}
	}
	
	public struct Permission: Sendable {
		
		let participantSid: String
		let allAllowed: Bool
		let allowedTrackSids: [String]
		let participantIdentity: String
		
		init(_ trackPermission: Livekit_TrackPermission) {
			self.participantSid = trackPermission.participantSid
			self.allAllowed = trackPermission.allTracks
			self.allowedTrackSids = trackPermission.trackSids
			self.participantIdentity = trackPermission.participantIdentity
		}
	}
}

extension LiveKitParticipant {
	public var videoTracks: [LiveKitTrackInfo.LiveKitTrack] {
		tracks.filter { $0.type == .video }
	}
	
	public var audioTracks: [LiveKitTrackInfo.LiveKitTrack] {
		tracks.filter { $0.type == .audio }
	}
	
	public var mutedAudioTracks: [LiveKitTrackInfo.LiveKitTrack] {
		audioTracks.filter { $0.muted == true }
	}
}

extension LiveKitTrackInfo.LiveKitTrack: Identifiable {
	public var id: String { sid }
}

@MainActor
public final class Receiver: @unchecked Sendable, Identifiable {
	
	public let mediaStreamTrack: MediaStreamTrack
	public let id: String
	
	let receiver: RTCRtpReceiver
	
	nonisolated init?(receiver: RTCRtpReceiver) {
		guard let track = receiver.track else { return nil }
		self.id = receiver.receiverId
		self.receiver = receiver
		self.mediaStreamTrack = MediaStreamTrack(rtcMediaStreamTrack: track)
	}
}

extension Receiver: Equatable {
	public static func == (lhs: Receiver, rhs: Receiver) -> Bool {
		lhs.id == rhs.id
	}
}

@MainActor
public final class MediaStreamTrack: @unchecked Sendable {
	
	let rtcMediaStreamTrack: RTCMediaStreamTrack
	
	nonisolated init(rtcMediaStreamTrack: RTCMediaStreamTrack) {
		self.rtcMediaStreamTrack = rtcMediaStreamTrack
	}
	
	public var enable: Bool {
		get {
			rtcMediaStreamTrack.isEnabled
		}
		set {
			rtcMediaStreamTrack.isEnabled = newValue
		}
	}
	
	var asAudioTrack: RTCAudioTrack? {
		return rtcMediaStreamTrack as? RTCAudioTrack
	}
	
	var asVideoTrack: RTCVideoTrack? {
		return rtcMediaStreamTrack as? RTCVideoTrack
	}
}
