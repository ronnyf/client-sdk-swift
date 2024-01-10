//
//  LiveKitCompatibility.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 1/8/24.
//

import Foundation
import OSLog

@_implementationOnly import WebRTC

#if LKCORE_USE_LIVEKIT_WEBRTC
typealias RTCAudioTrack = LKRTCAudioTrack
typealias RTCAudioDevice = LKRTCAudioDevice
typealias RTCAudioDeviceDelegate = LKRTCAudioDeviceDelegate
typealias RTCAudioSource = LKRTCAudioSource
typealias RTCConfiguration = LKRTCConfiguration
typealias RTCCVPixelBuffer = LKRTCCVPixelBuffer
typealias RTCDataBuffer = LKRTCDataBuffer
typealias RTCDataChannel = LKRTCDataChannel
typealias RTCDataChannelConfiguration = LKRTCDataChannelConfiguration
typealias RTCDataChannelDelegate = LKRTCDataChannelDelegate
typealias RTCH264ProfileLevelId = LKRTCH264ProfileLevelId
typealias RTCIceServer = LKRTCIceServer
typealias RTCIceCandidate = LKRTCIceCandidate
typealias RTCMediaConstraints = LKRTCMediaConstraints
typealias RTCMediaSource = LKRTCMediaSource
typealias RTCMediaStream = LKRTCMediaStream
typealias RTCMediaStreamTrack = LKRTCMediaStreamTrack
typealias RTCMTLVideoView = LKRTCMTLVideoView
typealias RTCPeerConnection = LKRTCPeerConnection
typealias RTCPeerConnectionDelegate = LKRTCPeerConnectionDelegate
typealias RTCPeerConnectionFactory = LKRTCPeerConnectionFactory
typealias RTCRtpEncodingParameters = LKRTCRtpEncodingParameters
typealias RTCRtpReceiver = LKRTCRtpReceiver
typealias RTCRtpSender = LKRTCRtpSender
typealias RTCRtpTransceiver = LKRTCRtpTransceiver
typealias RTCRtpTransceiverInit = LKRTCRtpTransceiverInit
typealias RTCSessionDescription = LKRTCSessionDescription
typealias RTCVideoCapturer = LKRTCVideoCapturer
typealias RTCVideoCodecInfo = LKRTCVideoCodecInfo
typealias RTCVideoEncoder = LKRTCVideoEncoder
typealias RTCVideoEncoderFactory = LKRTCVideoEncoderFactory
typealias RTCVideoEncoderH264 = LKRTCVideoEncoderH264
typealias RTCVideoEncoderVP8 = LKRTCVideoEncoderVP8
typealias RTCVideoEncoderVP9 = LKRTCVideoEncoderVP9
typealias RTCVideoDecoder = LKRTCVideoDecoder
typealias RTCVideoDecoderFactory = LKRTCVideoDecoderFactory
typealias RTCVideoDecoderH264 = LKRTCVideoDecoderH264
typealias RTCVideoDecoderVP8 = LKRTCVideoDecoderVP8
typealias RTCVideoDecoderVP9 = LKRTCVideoDecoderVP9
typealias RTCVideoFrame = LKRTCVideoFrame
typealias RTCVideoSource = LKRTCVideoSource
typealias RTCVideoTrack = LKRTCVideoTrack
#else
typealias LKRTCConfiguration = RTCConfiguration
typealias LKRTCIceServer = RTCIceServer
typealias LKRTCIceCandidate = RTCIceCandidate
typealias LKRTCMediaConstraints = RTCMediaConstraints
typealias LKRTCRtpEncodingParameters = RTCRtpEncodingParameters
typealias LKRTCSessionDescription = RTCSessionDescription
#endif
extension DispatchQueue {
	struct liveKitWebRTC {
		static func sync<Value>(value: () -> Value) -> Value {
			return value()
		}
		
		static func sync<Value>(value: () throws -> Value) rethrows -> Value {
			return try value()
		}
	}
}

enum logger {}

extension logger {
	static let liveKitLog = OSLog(subsystem: "default", category: "LiveKit")
	static func log(
		_ message: String,
		_ level: OSLogType = .debug,
		file: StaticString = #fileID,
		type type_: Any.Type? = nil,
		function: String = #function,
		line: UInt = #line
	) {
		Logger.log(
			level: level,
			oslog: Self.liveKitLog,
			line: line,
			file: file,
			message: "\(message), type: \(String(describing: type_))"
		)
	}
}

#if !LKCORE_USE_LIVEKIT_WEBRTC

extension LKRTCRtpEncodingParameters {
	var scalabilityMode: String? {
		get {
			return nil
		}
		set {
			
		}
	}
}

#endif
