//
//  VideoCoding-Core.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 1/8/24.
//

import Foundation

@_implementationOnly import WebRTC

class DefaultVideoEncoderFactory: NSObject, RTCVideoEncoderFactory {
	func createEncoder(_ info: RTCVideoCodecInfo) -> RTCVideoEncoder? {
		switch info.name {
		case kRTCVideoCodecH264Name:
			return RTCVideoEncoderH264(codecInfo: info)
		case kRTCVideoCodecVp8Name:
			return RTCVideoEncoderVP8.vp8Encoder()
		case kRTCVideoCodecVp9Name:
			return RTCVideoEncoderVP9.vp9Encoder()
			
		#if RTC_USE_LIBAOM_AV1_ENCODER
		case kRTCVideoCodecAv1Name:
			return RTCVideoEncoderAV1.av1Encoder()
		#endif
			
		default:
			return nil
		}
	}
	
	func supportedCodecs() -> [RTCVideoCodecInfo] {
		RTCVideoCodecInfo.defaultSupportedCodecInfo
	}
}

class DefaultVideoDecoderFactory: NSObject, RTCVideoDecoderFactory {
	func createDecoder(_ info: RTCVideoCodecInfo) -> RTCVideoDecoder? {
		switch info.name {
		case kRTCVideoCodecH264Name:
			return RTCVideoDecoderH264()
		case kRTCVideoCodecVp8Name:
			return RTCVideoDecoderVP8.vp8Decoder()
		case kRTCVideoCodecVp9Name:
			return RTCVideoDecoderVP9.vp9Decoder()
			
#if RTC_USE_LIBAOM_AV1_ENCODER
		case kRTCVideoCodecAv1Name:
			return RTCVideoDecoderAV1.av1Decoder()
#endif
			
		default:
			return nil
		}
	}
	
	func supportedCodecs() -> [RTCVideoCodecInfo] {
		RTCVideoCodecInfo.defaultSupportedCodecInfo
	}
}

extension RTCVideoCodecInfo {
	static var defaultSupportedCodecInfo: [RTCVideoCodecInfo] {
		#if LKCORE_USE_ALTERNATIVE_WEBRTC || LKCORE_USE_LIVEKIT_WEBRTC
		guard let profileLevelId = RTCH264ProfileLevelId(profile: .constrainedBaseline, level: .level5) else { return [] }
		#else
		let profileLevelId = RTCH264ProfileLevelId(profile: .constrainedBaseline, level: .level5)
		#endif
		let baselineCodecInfo = RTCVideoCodecInfo(name: kRTCVideoCodecH264Name,
												  parameters: ["profile-level-id": profileLevelId.hexString,
															   "level-asymmetry-allowed": "1",
															   "packetization-mode": "1"])
		
		let maxCodecInfo = RTCVideoCodecInfo(
			name: kRTCVideoCodecH264Name,
			parameters: [
				"profile-level-id": kRTCMaxSupportedH264ProfileLevelConstrainedBaseline,
				"level-asymmetry-allowed": "1",
				"packetization-mode": "1"
			]
		)
		
		return [baselineCodecInfo, maxCodecInfo]
	}
}
