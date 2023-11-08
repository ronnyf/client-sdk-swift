//
//  PeerConnection.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 5/19/23.
//

import Foundation
import Combine
import OSLog
import AsyncAlgorithms
@_implementationOnly import WebRTC

// WebRTC's C++ types often times work with mutexes and locks to syncronize access
// to shared mutable state. This feels like it could be an issue when trying to solve
// this with Swift concurrency. So here we go. Serial Executors.
actor PeerConnection {
	enum Errors: Error {
		case disconnected
		case createPeerConnection
		case noPeerConnection
		case noPeerConnectionFactory
		case timeoutError
		case createTransceiver
		case removeTransceiver
		case removeTrack
		case createOffer
		case createAnswer
		case makeOffer
		case noDataChannel
		case incomingResponseMessages
		case findMediaStreams
	}
	
	let dispatchQueue: DispatchQueue
	nonisolated var unownedExecutor: UnownedSerialExecutor { dispatchQueue.asUnownedSerialExecutor() }
	
	nonisolated var signalingState: some Publisher<RTCSignalingState, Never> {
		coordinator.$signalingState.publisher.compactMap { $0 }
	}
	
	nonisolated public var connectionState: PeerConnectionState {
		PeerConnectionState(coordinator.peerConnectionState)
	}
	
	nonisolated public var connectionStatePublisher: some Publisher<PeerConnectionState, Never> {
		rtcPeerConnectionStatePublisher.map { PeerConnectionState($0) }
	}
	
	nonisolated var rtcPeerConnectionStatePublisher: some Publisher<RTCPeerConnectionState, Never> {
		coordinator.$peerConnectionState.publisher
	}
	
	nonisolated var iceConnectionStatePublisher: some Publisher<RTCIceConnectionState, Never> {
		coordinator.$iceConnectionState.publisher
	}
	
	nonisolated var signals: some Publisher<PeerConnection.RTCSignal, Never> {
		coordinator.rtcSignals
	}
	
	nonisolated var signalsPlus: some Publisher<(PeerConnection.RTCSignal, Bool), Never> {
		coordinator.rtcSignals.combineLatest(Just(peerConnectionIsPublisher))
	}
	
	//MARK: - local/remote descriptions
	@Publishing var rtcPeerConnection: RTCPeerConnection? = nil
	
	private(set) var _pendingCandidates = [String]()
	private(set) var _offerInProgress: Bool = false
	private(set) var _offerTask: Task<Void, Error>?
	
	let peerConnectionIsPublisher: Bool
	let coordinator: PeerConnection.Coordinator
	let factory: () -> RTCPeerConnectionFactory
	let configuration: () -> RTCConfiguration
	let mediaConstraints: () -> RTCMediaConstraints
	
	init(
		dispatchQueue: DispatchQueue = DispatchQueue(label: "PeerConnection"),
		coordinator: PeerConnection.Coordinator = Coordinator(),
		isPublisher: Bool,
		factory: @autoclosure @escaping () -> RTCPeerConnectionFactory,
		configuration: @autoclosure @escaping () -> RTCConfiguration,
		mediaConstraints: @autoclosure @escaping () -> RTCMediaConstraints
	) {
		self.dispatchQueue = dispatchQueue
		self.coordinator = coordinator
		self.peerConnectionIsPublisher = isPublisher
		self.factory = factory
		self.configuration = configuration
		self.mediaConstraints = mediaConstraints
	}
	
	func configure(with joinResponse: Livekit_JoinResponse) async throws {
		dispatchPrecondition(condition: .onQueue(dispatchQueue))
		
		let rtcConfiguration = RTCConfiguration(copy: configuration())
		if rtcConfiguration.iceServers.isEmpty {
			// Set iceServers provided by the server
			rtcConfiguration.iceServers = joinResponse.iceServers.map { RTCIceServer($0) }
		}
		
		if joinResponse.clientConfiguration.forceRelay == .enabled {
			rtcConfiguration.iceTransportPolicy = .relay
		}
		
		Logger.plog(oslog: coordinator.peerConnectionLog, publicMessage: "coordinator configure, as publisher: \(peerConnectionIsPublisher)")
		
		guard let rtcPeerConnection = factory().peerConnection(with: configuration(), constraints: mediaConstraints(), delegate: coordinator) else { throw Errors.createPeerConnection }
		coordinator.peerConnectionState = rtcPeerConnection.connectionState
		coordinator.signalingState = rtcPeerConnection.signalingState
		coordinator.iceConnectionState = rtcPeerConnection.iceConnectionState
		coordinator.iceGatheringState = rtcPeerConnection.iceGatheringState
		self.rtcPeerConnection = rtcPeerConnection
	}
	
	func configureDataChannels() async throws {
		guard peerConnectionIsPublisher == true, let rtcPeerConnection else { return }
		
		let reliable = rtcPeerConnection.dataChannel(
			forLabel: PeerConnection.DataChannelLabel.reliable.rawValue,
			configuration: RTCDataChannelConfiguration.createDataChannelConfiguration(maxRetransmits: -1)
		)
		reliable?.delegate = coordinator
		coordinator.rtcDataChannelReliable = reliable
		
		let lossy = rtcPeerConnection.dataChannel(
			forLabel: PeerConnection.DataChannelLabel.lossy.rawValue,
			configuration: RTCDataChannelConfiguration.createDataChannelConfiguration(maxRetransmits: 0)
		)
		lossy?.delegate = coordinator
		coordinator.rtcDataChannelLossy = lossy
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
	
	func audioTrack(audioPublication: Publication, enabled: Bool = false) -> (RTCAudioTrack, RTCAudioSource) {
		dispatchPrecondition(condition: .onQueue(dispatchQueue))
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
		let source = factory().audioSource(with: audioConstraints)
		let audioTrack = factory().audioTrack(with: source, trackId: audioPublication.cid)
		audioTrack.isEnabled = true
		return (audioTrack, source)
	}
	
	func audioTransceiver(audioPublication: Publication, enabled: Bool = false) async throws -> AudioPublishItems {
		dispatchPrecondition(condition: .onQueue(dispatchQueue))
		
		guard let rtcPeerConnection = rtcPeerConnection else { throw PeerConnection.Errors.noPeerConnection }
		
		let (rtcAudioTrack, rtcAudioSource) = audioTrack(audioPublication: audioPublication, enabled: enabled)
		
		let transceiverInit = RTCRtpTransceiverInit(encodingParameters: audioPublication.encodings)
		let transceiver = rtcPeerConnection.addTransceiver(with: rtcAudioTrack, init: transceiverInit)
		return AudioPublishItems(transceiver: transceiver, track: rtcAudioTrack, source: rtcAudioSource)
	}
	
	func videoTransceiver(videoPublication: Publication, enabled: Bool = true) async throws -> VideoPublishItems {
		dispatchPrecondition(condition: .onQueue(dispatchQueue))
		
		guard let rtcPeerConnection = rtcPeerConnection else { throw PeerConnection.Errors.noPeerConnection }
		
		let transceiverInit = RTCRtpTransceiverInit(encodingParameters: videoPublication.encodings)
		
		let rtcVideoSource = factory().videoSource()
		let rtcVideoTrack = factory().videoTrack(with: rtcVideoSource, trackId: videoPublication.cid)
		rtcVideoTrack.isEnabled = enabled
		
		let transceiver = rtcPeerConnection.addTransceiver(with: rtcVideoTrack, init: transceiverInit)
		assert(transceiver != nil)
		return VideoPublishItems(transceiver: transceiver, track: rtcVideoTrack, source: rtcVideoSource)
	}
	
	func offerInProgress() -> Bool {
		_offerInProgress
	}
	
	func update(offerTask: Task<Void, Error>) {
		_offerTask = offerTask
	}
	
	func update(offerInProgress value: Bool) {
		_offerInProgress = value
	}
	
	func pendingIceCandidates() -> [String] {
		_pendingCandidates
	}
	
	func update(pendingCandidates: [String]) {
		_pendingCandidates = pendingCandidates
	}
	
	func update(pendingCandidate: String) {
		_pendingCandidates.append(pendingCandidate)
	}
	
	func teardown() async {
		Logger.plog(oslog: coordinator.peerConnectionLog, publicMessage: "\(self.description) teardown")
		
		_offerTask?.cancel()
		_offerTask = nil

		coordinator.teardown()
		closeDataChannels()
		if let rtcPeerConnection {
			rtcPeerConnection.close()
		}
	}
	
	// MARK: - retrieve receiver(s) from peer connection
}

extension PeerConnection {
	
	func negotiate(condition: @Sendable (PeerConnectionState) -> (Bool, SignalHub)) async throws {
		let (shouldNegotiate, signalHub) = condition(connectionState)
		if shouldNegotiate == true {
			offeringMachine(signalHub: signalHub)
			let _ = try await rtcPeerConnectionStatePublisher.map { PeerConnectionState($0) }.firstValue(timeout: 15, condition: { $0 == .connected})
		}
	}
	
	func closeDataChannels() {
		coordinator.rtcDataChannelLossy?.close()
		coordinator.rtcDataChannelReliable?.close()
	}
}

//MARK: - TODO: review those functions below ... ----v

/// Data-Channel communication
extension PeerConnection {
	func send(speaker: Livekit_ActiveSpeakerUpdate, label: DataChannelLabel = .reliable) throws {
		let packet = Livekit_DataPacket.with {
			$0.kind = label.dataPacketKind
			$0.speaker = speaker
		}
		try send(dataPacket: packet, preferred: label)
	}
	
	func send(user: Livekit_UserPacket, label: DataChannelLabel = .reliable) throws {
		let packet = Livekit_DataPacket.with {
			$0.kind = label.dataPacketKind
			$0.user = user
		}
		try send(dataPacket: packet, preferred: label)
	}
	
	func send(dataPacket: Livekit_DataPacket, preferred label: DataChannelLabel) throws {
		let serializedData = try dataPacket.serializedData()
		try send(serializedData, preferred: label)
	}
	
	func send(_ data: Data, preferred label: DataChannelLabel = .lossy) throws {
		let buffer = RTCDataBuffer(data: data, isBinary: true)
		precondition(coordinator.peerConnectionState == .connected)
		switch label {
		case .lossy:
			let channel = coordinator.rtcDataChannelLossy ?? coordinator.rtcDataChannelReliable
			channel?.sendData(buffer)
		case .reliable:
			let channel = coordinator.rtcDataChannelReliable ?? coordinator.rtcDataChannelLossy
			channel?.sendData(buffer)
		case .undefined:
			throw Errors.noDataChannel
		}
	}
}

extension PeerConnection: CustomStringConvertible {
	nonisolated var description: String {
		"<PeerConnection \(peerConnectionIsPublisher ? "Publishing" : "Subscribing")>"
	}
}

public enum PeerConnectionState: Sendable {
	case new
	case connecting
	case connected
	case disconnected
	case failed
	case closed
	case down
	
	init(_ rtcPeerConnectionState: RTCPeerConnectionState) {
		switch rtcPeerConnectionState {
		case .new:
			self = .new
		case .connecting:
			self = .connecting
		case .connected:
			self = .connected
		case .disconnected:
			self = .disconnected
		case .failed:
			self = .failed
		case .closed:
			self = .closed
			
		@unknown default:
			self = .down
		}
	}
}
