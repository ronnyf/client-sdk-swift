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
	let audioDevice: AudioDevice
	
	init(
		rtcConfiguration: RTCConfiguration = .liveKitDefault(),
		rtcMediaConstraints: RTCMediaConstraints = .defaultPCConstraints,
		audioDevice: AudioDevice = AudioDevice()
	) {
		dispatchPrecondition(condition: .onQueue(.main))
		
		self.audioDevice = audioDevice
		
		let rtcPeerConnectionFactory: RTCPeerConnectionFactory = {
			RTCInitializeSSL()
			
			let fieldTrials = [kRTCFieldTrialUseNWPathMonitor: kRTCFieldTrialEnabledValue]
			RTCInitFieldTrialDictionary(fieldTrials)
			
			let encoderFactory = DefaultVideoEncoderFactory()
			let decoderFactory = DefaultVideoDecoderFactory()
			let pcf = RTCPeerConnectionFactory(encoderFactory: encoderFactory,
											   decoderFactory: decoderFactory,
											   audioDevice: audioDevice.rtc)
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
		audioDevice.teardown()
		
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
