//
//  SignalHub+VideoPublishing.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 4/22/23.
//

import Foundation
@_implementationOnly import WebRTC

struct Publication: Sendable {
	
	enum TrackName: String {
		case video = "camera"
		case audio = "microphone"
	}
	
	let cid: String = UUID().uuidString
	var sid: String?
	let name: TrackName
	let type: Livekit_TrackType
	let source: Livekit_TrackSource
	let dimensions: CMVideoDimensions
	let videoPublishOptions: VideoPublishOptions?
	let audioPublishOptions: AudioPublishOptions?
	let audioCaptureOptions: AudioCaptureOptions?
	
	var encodings: [RTCRtpEncodingParameters] {
		switch type {
		case .audio:
			let encoding = audioPublishOptions?.encoding ?? AudioEncoding.presetSpeech
			return [Engine.createRtpEncodingParameters(encoding: encoding)]
			
		case .video:
			return Utils.computeEncodings(
				dimensions: dimensions,
				publishOptions: videoPublishOptions,
				isScreenShare: source == .screenShare
			)
			
		default:
			return []
		}
	}
	
	var layers: [Livekit_VideoLayer] {
		guard type == .video else { return [] }
		return dimensions.videoLayers(for: encodings)
	}
	
	static func videoPublication(dimensions: CMVideoDimensions, options: VideoPublishOptions? = nil) -> Publication {
		Publication(
			name: .video,
			type: .video,
			source: .camera,
			dimensions: dimensions,
			videoPublishOptions: options,
			audioPublishOptions: nil,
			audioCaptureOptions: nil
		)
	}
	
	static func audioPublication(captureOptions: AudioCaptureOptions? = nil, publishOptions: AudioPublishOptions = AudioPublishOptions()) -> Publication {
		Publication(
			name: .audio,
			type: .audio,
			source: .microphone,
			dimensions: CMVideoDimensions(width: 0, height: 0),
			videoPublishOptions: nil,
			audioPublishOptions: publishOptions,
			audioCaptureOptions: captureOptions
		)
	}
}

extension VideoPublishOptions: @unchecked Sendable {}
extension AudioPublishOptions: @unchecked Sendable {}
extension AudioCaptureOptions: @unchecked Sendable {}
