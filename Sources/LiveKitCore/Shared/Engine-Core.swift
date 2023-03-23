//
//  Engine-Core.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 5/16/23.
//

import Foundation
@_implementationOnly import WebRTC

#if LKCORE

struct Engine {
	static func _createSessionDescription(type: RTCSdpType, sdp: String) -> RTCSessionDescription {
		RTCSessionDescription(type: type, sdp: sdp)
	}
	
	static func _createRtpEncodingParameters(rid: String? = nil,
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
	
	static func createVideoTrack(source: RTCVideoSource, trackId: String = UUID().uuidString) -> RTCVideoTrack {
		peerConnectionFactory.videoTrack(with: source, trackId: trackId)
	}
}

#endif
