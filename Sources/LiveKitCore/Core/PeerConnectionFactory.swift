//
//  PeerConnectionFactory.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 9/7/23.
//

import Combine
import OSLog
import AsyncAlgorithms
@_implementationOnly import WebRTC

actor PeerConnectionFactory {
	let queue = DispatchQueue(label: "PeerConnectionFactory")
	let publishingPeerConnection: PeerConnection
	let subscribingPeerConnection: PeerConnection
	let rtcPeerConnectionFactory: CurrentValueSubject<RTCPeerConnectionFactory, Never>
	
	private let subscriptions = CurrentValueSubject<Set<AnyCancellable>, Never>([])
	fileprivate let peerConnectionFactoryLog = OSLog(subsystem: "PeerConnectionFactory", category: "LiveKitCore")
	
	init(
		configuration: RTCConfiguration = .liveKitDefault,
		constraints: RTCMediaConstraints = .defaultPCConstraints,
		encoderFactory: RTCVideoEncoderFactory = VideoEncoderFactory(),
		decoderFactory: RTCVideoDecoderFactory = VideoDecoderFactory()
	) {
		Logger.log(oslog: peerConnectionFactoryLog, message: "initializing SSL")
		let factory = queue.sync {
			RTCInitializeSSL()
			
			let fieldTrials = [kRTCFieldTrialUseNWPathMonitor: kRTCFieldTrialEnabledValue]
			RTCInitFieldTrialDictionary(fieldTrials)
			
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
		}
		
		rtcPeerConnectionFactory = CurrentValueSubject(factory)
		let pub = rtcPeerConnectionFactory.receive(on: queue)
		
		// This should be safe to do so, we're handing a reference around, still without being sendable, this would warn
		publishingPeerConnection = PeerConnection(rtcConfiguration: configuration, rtcMediaConstraints: constraints, isPublisher: true, factory: pub)
		subscribingPeerConnection = PeerConnection(rtcConfiguration: configuration, rtcMediaConstraints: constraints, isPublisher: false, factory: pub)
	}
	
	deinit {
		#if DEBUG
		Logger.log(oslog: peerConnectionFactoryLog, message: "deinit")
		#endif
		Logger.log(oslog: peerConnectionFactoryLog, message: "cleanup SSL")
		queue.async {
			RTCCleanupSSL()
		}
	}
	
	func withRTCPeerConnectionFactory<Result>(perform: @escaping (RTCPeerConnectionFactory) throws -> Result) async throws -> Result {
		try await withCheckedThrowingContinuation { continuation in
			rtcPeerConnectionFactory
				.receive(on: queue)
				.first()
				.sink {
					do {
						let result = try perform($0)
						continuation.resume(returning: result)
					} catch {
						continuation.resume(throwing: error)
					}
				}
				.store(in: &subscriptions.value)
		}
	}
	
	func send(
		publisher: some Publisher<PeerConnection, Never>,
		data: Data,
		channel: PeerConnection.DataChannelLabel = .lossy
	) async throws {
		let peerConnection = try await publisher.firstValue(timeout: 1)
		try await peerConnection.send(data, preferred: channel)
	}

	func teardown() {
		Logger.log(oslog: peerConnectionFactoryLog, message: "teardown")
		rtcPeerConnectionFactory.send(completion: .finished)
	}
	
	func videoTrack(source: RTCVideoSource, trackId: String) async -> RTCVideoTrack {
		await withCheckedContinuation { continuation in
			rtcPeerConnectionFactory
				.receive(on: queue)
				.map { $0.videoTrack(with: source, trackId: trackId) }
				.first()
				.sink {
					continuation.resume(returning: $0)
				}
				.store(in: &subscriptions.value)
		}
	}
	
	struct VideoPublishItems {
		var transceiver: RTCRtpTransceiver?
		let track: RTCVideoTrack
		let source: RTCVideoSource
	}

	struct AudioPublishItems {
		var transceiver: RTCRtpTransceiver?
		let track: RTCAudioTrack
		let source: RTCAudioSource
	}
	
	func audioTransceiver(audioPublication: Publication, enabled: Bool = false) async throws -> AudioPublishItems {
		try await withCheckedThrowingContinuation { continuation in
			rtcPeerConnectionFactory
				.receive(on: queue)
				.map {
					let options = audioPublication.audioCaptureOptions ?? AudioCaptureOptions()
					let constraints: [String: String] = [
						"googEchoCancellation": options.echoCancellation.toString(),
						"googAutoGainControl": options.autoGainControl.toString(),
						"googNoiseSuppression": options.noiseSuppression.toString(),
						"googTypingNoiseDetection": options.typingNoiseDetection.toString(),
						"googHighpassFilter": options.highpassFilter.toString(),
						"googNoiseSuppression2": options.experimentalNoiseSuppression.toString(),
						"googAutoGainControl2": options.experimentalAutoGainControl.toString()
					]
					
					let audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: constraints)
					let source = $0.audioSource(with: audioConstraints)
					let audioTrack = $0.audioTrack(with: source, trackId: audioPublication.cid)
					audioTrack.isEnabled = true
					
					return (audioTrack, source)
				}.flatMap { (track: RTCAudioTrack, source: RTCAudioSource) in
					self.publishingPeerConnection
						.rtcPeerConnection
						.map {
							let transceiverInit = RTCRtpTransceiverInit(encodingParameters: audioPublication.encodings)
							let transceiver = $0.addTransceiver(with: track, init: transceiverInit)
							return AudioPublishItems(transceiver: transceiver, track: track, source: source)
						}
				}
				.first()
				.sink(receiveCompletion: { completion in
					switch completion {
					case .finished:
						break
						
					case .failure(let failure):
						continuation.resume(throwing: failure)
					}
				}, receiveValue: { value in
					continuation.resume(returning: value)
				})
				.store(in: &subscriptions.value)
		}
	}
	
	func videoTransceiver(videoPublication: Publication, enabled: Bool = false) async throws -> VideoPublishItems {
		try await withCheckedThrowingContinuation { continuation in
			rtcPeerConnectionFactory
				.receive(on: queue)
				.map {
					let videoSource = $0.videoSource()
					let track = $0.videoTrack(with: videoSource, trackId: videoPublication.cid)
					track.isEnabled = enabled

					return (track, videoSource)
				}
				.flatMap { (track: RTCVideoTrack, source: RTCVideoSource) in
					self.publishingPeerConnection
						.rtcPeerConnection
						.map {
							let transceiverInit = RTCRtpTransceiverInit(encodingParameters: videoPublication.encodings)
							let transceiver = $0.addTransceiver(with: track, init: transceiverInit)
							#if DEBUG
							assert(transceiver != nil)
							assert(transceiver!.sender.track!.isEqual(track))
							#endif
							return VideoPublishItems(transceiver: transceiver, track: track, source: source)
						}
				}
				.first()
				.sink(receiveCompletion: { completion in
					switch completion {
					case .finished:
						break
						
					case .failure(let failure):
						continuation.resume(throwing: failure)
					}
				}, receiveValue: { value in
					continuation.resume(returning: value)
				})
				.store(in: &subscriptions.value)
		}
	}
}
