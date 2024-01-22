//
//  VideoCoding-Core.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 1/8/24.
//

import Foundation
import OSLog
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
	
	fileprivate static let log = OSLog(subsystem: "VideoDecoderFactory", category: "LiveKitCore")
	
	func createDecoder(_ info: RTCVideoCodecInfo) -> RTCVideoDecoder? {
		
		switch info.name {
		case kRTCVideoCodecH264Name:
			#if LKCORE_PASSTHROUGH_DECODER
			return PassthroughVideoDecoder()
			#else
			return RTCVideoDecoderH264()
			#endif
			
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
		let levels: [RTCH264Level] =  [.level3, .level3_2, .level4, .level4_2, .level5, .level5_2]
		let codecs: [RTCH264Profile: [RTCH264Level]] = [
			.constrainedHigh: levels,
			.constrainedBaseline: levels,
		]
		
		let profileLevelIdKey = "profile-level-id"
		let h264Params = [profileLevelIdKey: "", "level-asymmetry-allowed": "1", "packetization-mode": "1"]
		
		let codecInfo: [RTCVideoCodecInfo] = codecs.reduce(into: [RTCVideoCodecInfo]()) { infos, element in
			let profile = element.key
			let levels = element.value
			let info = levels.compactMap { level -> RTCVideoCodecInfo? in
				#if LKCORE_USE_EBAY_WEBRTC
				let profileLevelId = RTCH264ProfileLevelId(profile: profile, level: level)
				#else
				guard let profileLevelId = RTCH264ProfileLevelId(profile: profile, level: level) else { return nil }
				#endif
				var levelParams = h264Params
				levelParams[profileLevelIdKey] = profileLevelId.hexString
				return RTCVideoCodecInfo(name: kRTCVideoCodecH264Name, parameters: levelParams)
			}
			infos.append(contentsOf: info)
		}
		
		Logger.plog(level: .debug, oslog: DefaultVideoDecoderFactory.log, publicMessage: "supported video codecs: \(codecInfo.map { $0.internalDescription })")
		return codecInfo
	}
}

extension RTCVideoCodecInfo {
	var internalDescription: String {
		return "\(super.description): \(self.name) -> \(self.parameters)"
	}
}
