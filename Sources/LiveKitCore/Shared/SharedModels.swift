//
//  SharedModels.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 5/16/23.
//

import Foundation
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

// We'd need to be able to retain ownership of the rtc object ...
// If we were to use a struct, we'd dealloc the rtc object right away, won't we?
public class MediaTrack: @unchecked Sendable {
	var rtcMediaStreamTrack: RTCMediaStreamTrack
	
	public enum TrackType: Sendable {
		case audio
		case video
		case unknown
	}
	
	public let trackId: String
	public let trackType: TrackType
	
	@MainActor
	public var isEnabled: Bool {
		get {
			rtcMediaStreamTrack.isEnabled
		}
		set {
			rtcMediaStreamTrack.isEnabled = newValue
		}
	}
	
	init(_ rtcMediaStreamTrack: RTCMediaStreamTrack) {
		self.rtcMediaStreamTrack = rtcMediaStreamTrack
		self.trackId = rtcMediaStreamTrack.trackId
		self.trackType = TrackType(rtcMediaStreamTrack.kind)
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

public struct LiveKitStream: Sendable {
	public let pId: String //participant ID
	public let tId: String //track ID
	public let streamId: String
	
	public let videoTracks: [MediaTrack]
	public let audioTracks: [MediaTrack]
//	public let dataTracks: [MediaTrack] //not supported(yet)
	
	init(_ rtcMediaStream: RTCMediaStream) {
		self.streamId = rtcMediaStream.streamId
		
		//PA_dQDLmN3aFt92|TR_VCcdbkczVxyutm
		if let separatorIndex = streamId.firstIndex(of: "|") {
			self.pId = String(streamId[streamId.startIndex..<separatorIndex])
			self.tId = String(streamId[streamId.index(after: separatorIndex)..<streamId.endIndex])
		} else {
			self.pId = ""
			self.tId = ""
		}
		
		self.videoTracks = rtcMediaStream.videoTracks.map { MediaTrack($0) }
		self.audioTracks = rtcMediaStream.audioTracks.map { MediaTrack($0) }
	}
}

extension LiveKitStream: Equatable {
	static public func ==(lhs: LiveKitStream, rhs: LiveKitStream) -> Bool {
		lhs.streamId == rhs.streamId
	}
}

extension LiveKitStream: Hashable {
	public func hash(into hasher: inout Hasher) {
		hasher.combine(streamId)
	}
}

extension LiveKitStream: Identifiable {
	public var id: String { streamId }
}

//MARK: - Track

//public struct LiveKitVideoTrack: Sendable {
//	
//	let rtcVideoTrack: RTCVideoTrack
//	
//	public var trackId: String { rtcVideoTrack.trackId }
//	
//	init(rtcVideoTrack: RTCVideoTrack) {
//		self.rtcVideoTrack = rtcVideoTrack
//	}
//	
//	func add(renderer: RTCVideoRenderer) {
//		self.rtcVideoTrack.add(renderer)
//	}
//}
//
//extension LiveKitVideoTrack: Equatable {
//	
//	public static func ==(lhs: Self, rhs: Self) -> Bool {
//		lhs.rtcVideoTrack.trackId == rhs.rtcVideoTrack.trackId
//	}
//}
//
//extension LiveKitVideoTrack: Hashable {
//	
//	public func hash(into hasher: inout Hasher) {
//		hasher.combine(rtcVideoTrack.trackId)
//	}
//}

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
	public var joinedSince: Date
	public var canPublish: Bool
	public var canSubscribe: Bool
	public var canPublishData: Bool
	public var region: String
	
	init(participantInfo: Livekit_ParticipantInfo) {
		self.id = participantInfo.sid
		self.name = participantInfo.identity
		self.state = State(participantInfoState: participantInfo.state)
		self.joinedSince = Date(timeIntervalSince1970: TimeInterval(participantInfo.joinedAt))
		self.canPublish = participantInfo.permission.canPublish
		self.canSubscribe = participantInfo.permission.canSubscribe
		self.canPublishData = participantInfo.permission.canPublishData
		self.region = participantInfo.region
	}
	
	mutating func update(with participantInfo: Livekit_ParticipantInfo) {
		self.id = participantInfo.sid
		self.name = participantInfo.identity
		self.state = State(participantInfoState: participantInfo.state)
		self.joinedSince = Date(timeIntervalSince1970: TimeInterval(participantInfo.joinedAt))
		self.canPublish = participantInfo.permission.canPublish
		self.canSubscribe = participantInfo.permission.canSubscribe
		self.canPublishData = participantInfo.permission.canPublishData
		self.region = participantInfo.region
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
	case speaker(LiveKitActiveSpeaker)
	case unknown
	
	init(_ liveKitDataPacket: Livekit_DataPacket) {
		switch liveKitDataPacket.value {
		case .user(let userPacket):
			self = .user(LiveKitUserData(userPacket))
			
		case .speaker(let speakerData):
			self = .speaker(LiveKitActiveSpeaker(speakerData))
			
		default:
			self = .unknown
		}
	}
}

public struct LiveKitUserData: Sendable {
	
	public let data: Data
	public let originID: String
	public let destinationIDs: [String]
	
	public init(data: Data, originID: String, destinationIDs: [String]) {
		self.data = data
		self.originID = originID
		self.destinationIDs = destinationIDs
	}
	
	init(_ livekitUserPacket: Livekit_UserPacket) {
		self.init(data: livekitUserPacket.payload, originID: livekitUserPacket.participantSid, destinationIDs: livekitUserPacket.destinationSids)
	}
	
	func makeUserPacket() -> Livekit_UserPacket {
		let userPacket = Livekit_UserPacket.with {
			$0.destinationSids = destinationIDs
			$0.payload = data
			$0.participantSid = originID
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

public struct Speaker: Sendable {
	
	public let id: String
	public let active: Bool
	public let level: Float
	
	static func make(from speakerChanged: Livekit_SpeakersChanged) -> [Speaker] {
		speakerChanged.speakers.map { Speaker($0) }
	}
	
	static func make(from activeSpeakerUpdate: Livekit_ActiveSpeakerUpdate) -> [Speaker] {
		activeSpeakerUpdate.speakers.map { Speaker($0) }
	}
	
	init(_ livekit_SpeakerInfo: Livekit_SpeakerInfo) {
		self.id = livekit_SpeakerInfo.sid
		self.active = livekit_SpeakerInfo.active
		self.level = livekit_SpeakerInfo.level
	}
}

extension Speaker: Equatable {
	public static func ==(lhs: Speaker, rhs: Speaker) -> Bool {
		lhs.id == rhs.id
	}
}

extension Speaker: Hashable {
	public func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}
}

public struct LiveKitSpeaker {
	
	public let speakers: [Speaker]
	
	init(_ speakerChanged: Livekit_SpeakersChanged) {
		self.speakers = speakerChanged.speakers.map { Speaker($0) }
	}
}

public struct LiveKitActiveSpeaker: Sendable {
	
	let speakers: [Speaker]
	
	init(_ activeSpeakerUpdate: Livekit_ActiveSpeakerUpdate) {
		self.speakers = activeSpeakerUpdate.speakers.map { Speaker($0) }
	}
}


//MARK: - Track published / unpublished

public struct LiveKitTrack: Sendable {
	public let trackSid: String
	public let trackInfo: Info?
	
	init(_ published: Livekit_TrackPublishedResponse) {
		self.trackSid = published.track.sid
		self.trackInfo = Info(published.track)
	}
	
	init(_ unpublished: Livekit_TrackUnpublishedResponse) {
		self.trackSid = unpublished.trackSid
		self.trackInfo = nil
	}
	
	public struct Info: Sendable {
		
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
		
		init(_ info: Livekit_TrackInfo) {
			self.sid = info.sid
			self.type = Kind(info.type)
			self.name = info.name
			self.muted = info.muted
			self.width = info.width
			self.height = info.height
			self.simulcast = info.simulcast
			self.disableDtx = info.disableDtx
			self.source = Source(info.source)
			self.layers = info.layers.map { VideoLayer($0) }
			self.mimeType = info.mimeType
			self.mid = info.mid
			self.codecs = info.codecs.map { CodecInfo($0) }
			self.stereo = info.stereo
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
