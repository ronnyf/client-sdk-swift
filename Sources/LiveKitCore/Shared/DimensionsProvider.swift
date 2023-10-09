//
//  DimensionsProvider.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 5/16/23.
//

import Foundation
import CoreMedia
@_implementationOnly import WebRTC

extension CMVideoDimensions {
	func videoLayers(for encodings: [RTCRtpEncodingParameters]) -> [Livekit_VideoLayer] {
		encodings.filter { $0.isActive }.map { encoding in
			let scaleDownBy = Double(exactly: encoding.scaleResolutionDownBy ?? 1) ?? 1
			assert(scaleDownBy != 0)
			return Livekit_VideoLayer.with {
				$0.width = UInt32((Double(self.width) / scaleDownBy).rounded(.up))
				$0.height = UInt32((Double(self.height) / scaleDownBy).rounded(.up))
				$0.quality = Livekit_VideoQuality.from(rid: encoding.rid)
				$0.bitrate = encoding.maxBitrateBps?.uint32Value ?? 0
			}
		}
	}
	
	static let encodeSafeSize = 16
	
	var isEncodeSafe: Bool {
		width >= Self.encodeSafeSize && height >= Self.encodeSafeSize
	}
}

extension Utils {
	static func computeEncodings(dimensions: CMVideoDimensions, publishOptions: VideoPublishOptions?, isScreenShare: Bool = false) -> [RTCRtpEncodingParameters] {
		let dims = Dimensions(width: dimensions.width, height: dimensions.height)
		return Self.computeEncodings(dimensions: dims, publishOptions: publishOptions, isScreenShare: isScreenShare)
	}
}
