/*
 * Copyright 2022 LiveKit
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import Foundation
#if LIVEKIT_STATIC_WEBRTC
@_implementationOnly import WebRTC
#endif

#if LKCORE

/// The open source platform for real-time communication.
///
/// See [LiveKit's Online Docs](https://docs.livekit.io/) for more information.
///
/// Comments are written in [DocC](https://developer.apple.com/documentation/docc) compatible format.
/// With Xcode 13 and above you can build documentation right into your Xcode documentation viewer by chosing
/// **Product** >  **Build Documentation** from Xcode's menu.
///
/// Download the [Multiplatform SwiftUI Example](https://github.com/livekit/multiplatform-swiftui-example)
/// to try out the features.
@objc
public class LiveKit: NSObject {
	
	@objc(sdkVersion)
	public static let version = "1.1.2"
}

extension DispatchQueue {
	struct webRTC {
		static func sync<Value>(value: () -> Value) -> Value {
			return value()
		}
		
		static func sync<Value>(value: () throws -> Value) rethrows -> Value {
			return try value()
		}
	}
}

public class Promise<T> {}

#if LIVEKIT_STATIC_WEBRTC

extension RTCVideoCodecInfo {
	
	static var h264BaselineLevel5CodecInfo: RTCVideoCodecInfo = {
		// this should never happen
		guard let profileLevelId = RTCH264ProfileLevelId(profile: .constrainedBaseline, level: .level5) else {
			fatalError("failed to generate profileLevelId")
		}
		// create a new H264 codec with new profileLevelId
		return RTCVideoCodecInfo(
			name: kRTCH264CodecName,
			parameters: ["profile-level-id": profileLevelId.hexString,
						 "level-asymmetry-allowed": "1",
						 "packetization-mode": "1"]
		)
	}()
}

extension RTCRtpEncodingParameters {
	static func createRtpEncodingParameters(rid: String? = nil,
											encoding: MediaEncoding? = nil,
											scaleDownBy: Double? = nil,
											active: Bool = true) -> RTCRtpEncodingParameters {
		
		let result = RTCRtpEncodingParameters()
		
		result.isActive = active
		result.rid = rid
		
		if let scaleDownBy {
			result.scaleResolutionDownBy = scaleDownBy as NSNumber
		}
		
		if let encoding {
			result.maxBitrateBps = encoding.maxBitrate as NSNumber
			
			// VideoEncoding specific
			if let videoEncoding = encoding as? VideoEncoding {
				result.maxFramerate = videoEncoding.maxFps as NSNumber
			}
		}
		
		return result
	}
}

private extension Array where Element: RTCVideoCodecInfo {
	
	func rewriteCodecsIfNeeded() -> [RTCVideoCodecInfo] {
		// rewrite H264's profileLevelId to 42e032
		let codecs = map { $0.name == kRTCVideoCodecH264Name ? RTCVideoCodecInfo.h264BaselineLevel5CodecInfo : $0 }
		// logger.log("supportedCodecs: \(codecs.map({ "\($0.name) - \($0.parameters)" }).joined(separator: ", "))", type: Engine.self)
		return codecs
	}
}

class VideoEncoderFactory: RTCDefaultVideoEncoderFactory {
	
	override func supportedCodecs() -> [RTCVideoCodecInfo] {
		super.supportedCodecs().rewriteCodecsIfNeeded()
	}
	
#if DEBUG
	deinit {
		print("DEBUG: deinit \(self)")
	}
#endif
}

class VideoDecoderFactory: RTCDefaultVideoDecoderFactory {
	
	override func supportedCodecs() -> [RTCVideoCodecInfo] {
		super.supportedCodecs().rewriteCodecsIfNeeded()
	}
	
#if DEBUG
	deinit {
		print("DEBUG: deinit \(self)")
	}
#endif
}

typealias RTCAudioBuffer = LKRTCAudioBuffer
typealias RTCAudioCustomProcessingDelegate = LKRTCAudioCustomProcessingDelegate
typealias RTCAudioDevice = LKRTCAudioDevice
typealias RTCAudioDeviceDelegate = LKRTCAudioDeviceDelegate
typealias RTCAudioDeviceModule = LKRTCAudioDeviceModule
typealias RTCAudioProcessingConfig = LKRTCAudioProcessingConfig
typealias RTCAudioProcessingModule = LKRTCAudioProcessingModule
typealias RTCAudioRenderer = LKRTCAudioRenderer
typealias RTCAudioSession = LKRTCAudioSession
typealias RTCAudioSessionConfiguration = LKRTCAudioSessionConfiguration
typealias RTCAudioSource = LKRTCAudioSource
typealias RTCAudioTrack = LKRTCAudioTrack
typealias RTCCVPixelBuffer = LKRTCCVPixelBuffer
typealias RTCCallbackLogger = LKRTCCallbackLogger
typealias RTCCameraPreviewView = LKRTCCameraPreviewView
typealias RTCCameraVideoCapturer = LKRTCCameraVideoCapturer
typealias RTCCertificate = LKRTCCertificate
typealias RTCCodecSpecificInfo = LKRTCCodecSpecificInfo
typealias RTCCodecSpecificInfoH264 = LKRTCCodecSpecificInfoH264
typealias RTCConfiguration = LKRTCConfiguration
typealias RTCCryptoOptions = LKRTCCryptoOptions
typealias RTCDataChannel = LKRTCDataChannel
typealias RTCDataBuffer = LKRTCDataBuffer
typealias RTCDataChannelDelegate = LKRTCDataChannelDelegate
typealias RTCDataChannelConfiguration = LKRTCDataChannelConfiguration
typealias RTCDefaultAudioProcessingModule = LKRTCDefaultAudioProcessingModule
typealias RTCDefaultVideoDecoderFactory = LKRTCDefaultVideoDecoderFactory
typealias RTCDefaultVideoEncoderFactory = LKRTCDefaultVideoEncoderFactory
typealias RTCDispatcher = LKRTCDispatcher
typealias RTCDtmfSender = LKRTCDtmfSender
typealias RTCEAGLVideoView = LKRTCEAGLVideoView
typealias RTCEncodedImage = LKRTCEncodedImage
typealias RTCFileLogger = LKRTCFileLogger
typealias RTCFileVideoCapturer = LKRTCFileVideoCapturer
typealias RTCFrameCryptor = LKRTCFrameCryptor
typealias RTCFrameCryptorKeyProvider = LKRTCFrameCryptorKeyProvider
typealias RTCH264ProfileLevelId = LKRTCH264ProfileLevelId
typealias RTCI420Buffer = LKRTCI420Buffer
typealias RTCIODevice = LKRTCIODevice
typealias RTCIceCandidate = LKRTCIceCandidate
typealias RTCIceCandidateErrorEvent = LKRTCIceCandidateErrorEvent
typealias RTCIceServer = LKRTCIceServer
typealias RTCLegacyStatsReport = LKRTCLegacyStatsReport
typealias RTCMTLVideoView = LKRTCMTLVideoView
typealias RTCMediaConstraints = LKRTCMediaConstraints
typealias RTCMediaSource = LKRTCMediaSource
typealias RTCMediaStream = LKRTCMediaStream
typealias RTCMediaStreamTrack = LKRTCMediaStreamTrack
typealias RTCMetricsSampleInfo = LKRTCMetricsSampleInfo
typealias RTCMutableI420Buffer = LKRTCMutableI420Buffer
typealias RTCMutableYUVPlanarBuffer = LKRTCMutableYUVPlanarBuffer
typealias RTCNetworkMonitor = LKRTCNetworkMonitor
typealias RTCPeerConnection = LKRTCPeerConnection
typealias RTCPeerConnectionDelegate = LKRTCPeerConnectionDelegate
typealias RTCPeerConnectionFactory = LKRTCPeerConnectionFactory
typealias RTCPeerConnectionFactoryOptions = LKRTCPeerConnectionFactoryOptions
typealias RTCRtcpParameters = LKRTCRtcpParameters
typealias RTCRtpCapabilities = LKRTCRtpCapabilities
typealias RTCRtpCodecCapability = LKRTCRtpCodecCapability
typealias RTCRtpCodecParameters = LKRTCRtpCodecParameters
typealias RTCRtpEncodingParameters = LKRTCRtpEncodingParameters
typealias RTCRtpHeaderExtension = LKRTCRtpHeaderExtension
typealias RTCRtpParameters = LKRTCRtpParameters
typealias RTCRtpReceiver = LKRTCRtpReceiver
typealias RTCRtpSender = LKRTCRtpSender
typealias RTCRtpTransceiver = LKRTCRtpTransceiver
typealias RTCRtpTransceiverInit = LKRTCRtpTransceiverInit
typealias RTCSSLCertificateVerifier = LKRTCSSLCertificateVerifier
typealias RTCSessionDescription = LKRTCSessionDescription
typealias RTCStatisticsReport = LKRTCStatisticsReport
typealias RTCVideoCapturer = LKRTCVideoCapturer
typealias RTCVideoCodecInfo = LKRTCVideoCodecInfo
typealias RTCVideoDecoder = LKRTCVideoDecoder
typealias RTCVideoDecoderAV1 = LKRTCVideoDecoderAV1
typealias RTCVideoDecoderFactory = LKRTCVideoDecoderFactory
typealias RTCVideoDecoderFactoryH264 = LKRTCVideoDecoderFactoryH264
typealias RTCVideoDecoderH264 = LKRTCVideoDecoderH264
typealias RTCVideoDecoderVP8 = LKRTCVideoDecoderVP8
typealias RTCVideoDecoderVP9 = LKRTCVideoDecoderVP9
typealias RTCVideoEncoder = LKRTCVideoEncoder
typealias RTCVideoEncoderAV1 = LKRTCVideoEncoderAV1
typealias RTCVideoEncoderFactory = LKRTCVideoEncoderFactory
typealias RTCVideoEncoderFactoryH264 = LKRTCVideoEncoderFactoryH264
typealias RTCVideoEncoderFactorySimulcast = LKRTCVideoEncoderFactorySimulcast
typealias RTCVideoEncoderH264 = LKRTCVideoEncoderH264
typealias RTCVideoEncoderQpThresholds = LKRTCVideoEncoderQpThresholds
typealias RTCVideoEncoderSettings = LKRTCVideoEncoderSettings
typealias RTCVideoEncoderSimulcast = LKRTCVideoEncoderSimulcast
typealias RTCVideoEncoderVP8 = LKRTCVideoEncoderVP8
typealias RTCVideoEncoderVP9 = LKRTCVideoEncoderVP9
typealias RTCVideoFrame = LKRTCVideoFrame
typealias RTCVideoFrameBuffer = LKRTCVideoFrameBuffer
typealias RTCVideoRenderer = LKRTCVideoRenderer
typealias RTCVideoSource = LKRTCVideoSource
typealias RTCVideoTrack = LKRTCVideoTrack
typealias RTCVideoViewDelegate = LKRTCVideoViewDelegate
typealias RTCVideoViewShading = LKRTCVideoViewShading
typealias RTCYUVHelper = LKRTCYUVHelper
typealias RTCYUVPlanarBuffer = LKRTCYUVPlanarBuffer

#endif
#endif
