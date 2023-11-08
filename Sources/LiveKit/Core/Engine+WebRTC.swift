/*
 * Copyright 2023 LiveKit
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
@_implementationOnly import WebRTC
import Promises

private extension Array where Element: RTCVideoCodecInfo {

    func rewriteCodecsIfNeeded() -> [RTCVideoCodecInfo] {
        // rewrite H264's profileLevelId to 42e032
        let codecs = map { $0.name == kRTCVideoCodecH264Name ? Engine.h264BaselineLevel5CodecInfo : $0 }
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

#if LIVEKIT_STATIC_WEBRTC

class VideoEncoderFactorySimulcast: RTCVideoEncoderFactorySimulcast {

    override func supportedCodecs() -> [RTCVideoCodecInfo] {
        super.supportedCodecs().rewriteCodecsIfNeeded()
    }
}

#endif

internal extension Engine {

	#if LIVEKIT_STATIC_WEBRTC
    static var bypassVoiceProcessing: Bool = false
	#endif

    static let h264BaselineLevel5CodecInfo: RTCVideoCodecInfo = {
		#if LIVEKIT_STATIC_WEBRTC
        // this should never happen
        guard let profileLevelId = RTCH264ProfileLevelId(profile: .constrainedBaseline, level: .level5) else {
            logger.log("failed to generate profileLevelId", .error, type: Engine.self)
            fatalError("failed to generate profileLevelId")
        }
		#else
		let profileLevelId = RTCH264ProfileLevelId(profile: .constrainedBaseline, level: .level5)
		#endif
        // create a new H264 codec with new profileLevelId
        return RTCVideoCodecInfo(name: kRTCH264CodecName,
                                 parameters: ["profile-level-id": profileLevelId.hexString,
                                              "level-asymmetry-allowed": "1",
                                              "packetization-mode": "1"])
    }()

    // global properties are already lazy

    static private let encoderFactory: RTCVideoEncoderFactory = {
        let encoderFactory = VideoEncoderFactory()
        #if LIVEKIT_STATIC_WEBRTC
        return VideoEncoderFactorySimulcast(primary: encoderFactory,
                                            fallback: encoderFactory)

        #else
        return encoderFactory
        #endif
    }()

    static private let decoderFactory = VideoDecoderFactory()
	
	#if LIVEKIT_STATIC_WEBRTC
	static let audioProcessingModule: RTCDefaultAudioProcessingModule = {
		RTCDefaultAudioProcessingModule()
	}()
	#endif

    static let peerConnectionFactory: RTCPeerConnectionFactory = {

        logger.log("Initializing SSL...", type: Engine.self)

        RTCInitializeSSL()

        logger.log("Initializing Field trials...", type: Engine.self)

        let fieldTrials = [kRTCFieldTrialUseNWPathMonitor: kRTCFieldTrialEnabledValue]
        RTCInitFieldTrialDictionary(fieldTrials)

        logger.log("Initializing PeerConnectionFactory...", type: Engine.self)

        #if LIVEKIT_STATIC_WEBRTC
        return RTCPeerConnectionFactory(bypassVoiceProcessing: bypassVoiceProcessing,
                                        encoderFactory: encoderFactory,
										decoderFactory: decoderFactory,
										audioProcessingModule: audioProcessingModule)
        #else
        return RTCPeerConnectionFactory(encoderFactory: encoderFactory,
                                        decoderFactory: decoderFactory)
        #endif
    }()

    // forbid direct access
	#if LIVEKIT_STATIC_WEBRTC
    static var audioDeviceModule: RTCAudioDeviceModule {
        peerConnectionFactory.audioDeviceModule
    }
	#endif

    static func createPeerConnection(_ configuration: RTCConfiguration,
                                     constraints: RTCMediaConstraints) -> RTCPeerConnection? {
        DispatchQueue.webRTC.sync { peerConnectionFactory.peerConnection(with: configuration,
                                                                         constraints: constraints,
                                                                         delegate: nil) }
    }

    static func createVideoSource(forScreenShare: Bool) -> RTCVideoSource {
        #if LIVEKIT_STATIC_WEBRTC
        DispatchQueue.webRTC.sync { peerConnectionFactory.videoSource(forScreenCast: forScreenShare) }
        #else
        DispatchQueue.webRTC.sync { peerConnectionFactory.videoSource() }
        #endif
    }

    static func createVideoTrack(source: RTCVideoSource) -> RTCVideoTrack {
        DispatchQueue.webRTC.sync { peerConnectionFactory.videoTrack(with: source,
                                                                     trackId: UUID().uuidString) }
    }

    static func createAudioSource(_ constraints: RTCMediaConstraints?) -> RTCAudioSource {
        DispatchQueue.webRTC.sync { peerConnectionFactory.audioSource(with: constraints) }
    }

    static func createAudioTrack(source: RTCAudioSource) -> RTCAudioTrack {
        DispatchQueue.webRTC.sync { peerConnectionFactory.audioTrack(with: source,
                                                                     trackId: UUID().uuidString) }
    }

    static func createDataChannelConfiguration(ordered: Bool = true,
                                               maxRetransmits: Int32 = -1) -> RTCDataChannelConfiguration {
        let result = DispatchQueue.webRTC.sync { RTCDataChannelConfiguration() }
        result.isOrdered = ordered
        result.maxRetransmits = maxRetransmits
        return result
    }

    static func createDataBuffer(data: Data) -> RTCDataBuffer {
        DispatchQueue.webRTC.sync { RTCDataBuffer(data: data, isBinary: true) }
    }

    static func createIceCandidate(fromJsonString: String) throws -> RTCIceCandidate {
        try DispatchQueue.webRTC.sync { try RTCIceCandidate(fromJsonString: fromJsonString) }
    }

    static func createSessionDescription(type: RTCSdpType, sdp: String) -> RTCSessionDescription {
        DispatchQueue.webRTC.sync { RTCSessionDescription(type: type, sdp: sdp) }
    }

    static func createVideoCapturer() -> RTCVideoCapturer {
        DispatchQueue.webRTC.sync { RTCVideoCapturer() }
    }

    static func createRtpEncodingParameters(rid: String? = nil,
                                            encoding: MediaEncoding? = nil,
                                            scaleDownBy: Double? = nil,
                                            active: Bool = true) -> RTCRtpEncodingParameters {

        let result = RTCRtpEncodingParameters()

        result.isActive = active
        result.rid = rid

        if let scaleDownBy = scaleDownBy {
            result.scaleResolutionDownBy = NSNumber(value: scaleDownBy)
        }

        if let encoding = encoding {
            result.maxBitrateBps = NSNumber(value: encoding.maxBitrate)

            // VideoEncoding specific
            if let videoEncoding = encoding as? VideoEncoding {
                result.maxFramerate = NSNumber(value: videoEncoding.maxFps)
            }
        }

        return result
    }
}
