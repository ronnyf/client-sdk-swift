//
//  DimensionsProvider.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 5/16/23.
//

import Foundation

@_implementationOnly import WebRTC

extension CMVideoDimensions {
	
	static let encodeSafeSize = 16
	
	var isEncodeSafe: Bool {
		width >= Self.encodeSafeSize && height >= Self.encodeSafeSize
	}
}
