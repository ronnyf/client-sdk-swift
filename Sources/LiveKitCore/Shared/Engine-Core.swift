//
//  Engine-Core.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 5/16/23.
//

import Foundation

@_implementationOnly import WebRTC

struct Engine {
	static func createSessionDescription(type: RTCSdpType, sdp: String) -> RTCSessionDescription {
		RTCSessionDescription(type: type, sdp: sdp)
	}
	
	static func createRtpEncodingParameters(rid: String? = nil,
											encoding: MediaEncoding? = nil,
											scaleDownBy: Double? = nil,
											active: Bool = true,
											scalabilityMode: ScalabilityMode? = nil) -> RTCRtpEncodingParameters {
		
		let result = RTCRtpEncodingParameters(rid: rid, encoding: encoding, scaleDownBy: scaleDownBy, active: active)
		
		#if LKCORE_USE_LIVEKIT_WEBRTC
		if let scalabilityMode {
			result.scalabilityMode = scalabilityMode.rawStringValue
		}
		#endif
		return result
	}
}
