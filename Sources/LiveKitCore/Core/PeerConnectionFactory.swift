//
//  PeerConnectionFactory.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 9/7/23.
//

import Foundation
@_implementationOnly import WebRTC

class PeerConnectionFactory: @unchecked Sendable {
	let publishingPeerConnection: PeerConnection
	let subscribingPeerConnection: PeerConnection
	
	init(rtcConfiguration: RTCConfiguration = .liveKitDefault, rtcMediaConstraints: RTCMediaConstraints = .defaultPCConstraints) {
		dispatchPrecondition(condition: .onQueue(.main))
		
		let rtcPeerConnectionFactory: RTCPeerConnectionFactory = {
			RTCInitializeSSL()
			
			let fieldTrials = [kRTCFieldTrialUseNWPathMonitor: kRTCFieldTrialEnabledValue]
			RTCInitFieldTrialDictionary(fieldTrials)
			
			let encoderFactory = VideoEncoderFactory()
			let decoderFactory = VideoDecoderFactory()
			
#if LK_USE_CUSTOM_WEBRTC_BUILD
			let audioProcessingModule = RTCDefaultAudioProcessingModule()
			let pcf = RTCPeerConnectionFactory(bypassVoiceProcessing: false,
											   encoderFactory: encoderFactory,
											   decoderFactory: decoderFactory,
											   audioProcessingModule: audioProcessingModule)
#else
			let pcf = RTCPeerConnectionFactory(encoderFactory: encoderFactory,
											   decoderFactory: decoderFactory)
#endif
			return pcf
		}()
		
		publishingPeerConnection = PeerConnection(
			isPublisher: true,
			factory: rtcPeerConnectionFactory,
			configuration: rtcConfiguration,
			mediaConstraints: rtcMediaConstraints
		)
		
		subscribingPeerConnection = PeerConnection(
			isPublisher: false,
			factory: rtcPeerConnectionFactory,
			configuration: rtcConfiguration,
			mediaConstraints: rtcMediaConstraints
		)
	}
	
	func teardown() {
		RTCCleanupSSL()
		Task {
			await withTaskGroup(of: Void.self) { group in
				for pc in [publishingPeerConnection, subscribingPeerConnection] {
					group.addTask {
						await pc.teardown()
					}
				}
				await group.waitForAll()
			}
		}
	}
	
#if DEBUG
	deinit {
		print("DEBUG: deinit <PeerConnectionFactory>")
	}
#endif
}
