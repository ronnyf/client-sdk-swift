//
//  LiveKitCompatibility.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 1/8/24.
//

import Foundation
import OSLog

@_implementationOnly import WebRTC

#if LKCORE

typealias LKRTCVideoCodecInfo = RTCVideoCodecInfo
typealias LKRTCDefaultVideoEncoderFactory = RTCDefaultVideoEncoderFactory
typealias LKRTCDefaultVideoDecoderFactory = RTCDefaultVideoDecoderFactory
typealias LKRTCH264ProfileLevelId = RTCH264ProfileLevelId
typealias LKRTCVideoEncoderFactory = RTCVideoEncoderFactory
typealias LKRTCPeerConnection = RTCPeerConnection
typealias LKRTCPeerConnectionFactory = RTCPeerConnectionFactory
typealias LKRTCConfiguration = RTCConfiguration
typealias LKRTCVideoSource = RTCVideoSource
typealias LKRTCVideoTrack = RTCVideoTrack
typealias LKRTCMediaConstraints = RTCMediaConstraints
typealias LKRTCAudioSource = RTCAudioSource
typealias LKRTCAudioTrack = RTCAudioTrack
typealias LKRTCDataChannelConfiguration = RTCDataChannelConfiguration
typealias LKRTCDataBuffer = RTCDataBuffer
typealias LKRTCIceCandidate = RTCIceCandidate
typealias LKRTCSessionDescription = RTCSessionDescription
typealias LKRTCVideoCapturer = RTCVideoCapturer
typealias LKRTCRtpEncodingParameters = RTCRtpEncodingParameters
typealias LKRTCIceServer = RTCIceServer

#if !LKCORE_WEBRTC

typealias LKRTCVideoEncoderFactorySimulcast = RTCVideoEncoderFactorySimulcast
typealias LKRTCDefaultAudioProcessingModule = RTCDefaultAudioProcessingModule
typealias LKRTCAudioDeviceModule = RTCAudioDeviceModule

#else

public class IceServer: NSObject {
	
	public let urls: [String]
	public let username: String
	public let credential: String
	
	public init(urls: [String], username: String, credential: String) {
		self.urls = urls
		self.username = username
		self.credential = credential
		super.init()
	}
}

typealias LKRTCVideoEncoderFactorySimulcast = RTCDefaultVideoEncoderFactory
extension RTCDefaultVideoEncoderFactory {
	convenience init(primary: RTCVideoEncoderFactory, fallback: RTCVideoEncoderFactory) {
		self.init()
	}
}
struct RTCFakeAudioDeviceModule {}
struct RTCFakeAudioProcessingModule {}

typealias LKRTCDefaultAudioProcessingModule = RTCFakeAudioProcessingModule
extension RTCPeerConnectionFactory {
	struct Capabilities {}
	
	convenience init(bypassVoiceProcessing: Bool, encoderFactory: RTCVideoEncoderFactory, decoderFactory: RTCVideoDecoderFactory, audioProcessingModule: RTCFakeAudioProcessingModule) {
		self.init(encoderFactory: encoderFactory, decoderFactory: decoderFactory)
	}
	var audioDeviceModule: RTCFakeAudioDeviceModule { RTCFakeAudioDeviceModule() }
	func rtpSenderCapabilities(for mediaType: RTCRtpMediaType) -> Capabilities {
		Capabilities()
	}
}

typealias LKRTCAudioDeviceModule = RTCFakeAudioDeviceModule
extension DispatchQueue {
	struct liveKitWebRTC {
		static func sync<T>(perform: () throws -> T) rethrows -> T { try perform() }
	}
}
extension RTCRtpEncodingParameters {
	var scalabilityMode: String? {
		get {
			return nil
		}
		set {
			
		}
	}
}

#endif

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

#endif // LKCORE
