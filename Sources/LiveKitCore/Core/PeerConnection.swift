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

actor PeerConnection {
	enum Errors: Error {
		case disconnected
		case noPeerConnection
		case timeoutError
		case createTransceiver
		case removeTransceiver
		case removeTrack
		case createOffer
		case createAnswer
		case makeOffer
		case noDataChannel
		case incomingResponseMessages
	}
	
	nonisolated var rtcPeerConnection: some Publisher<RTCPeerConnection, Never> {
		coordinator.rtcPeerConnection
	}
	
	nonisolated var signalingState: some Publisher<RTCSignalingState, Never> {
		coordinator.signalingState.publisher
	}
	
	nonisolated var connectionState: some Publisher<RTCPeerConnectionState, Never> {
		coordinator.peerConnectionState.publisher
	}
	
	nonisolated var iceConnectionState: some Publisher<RTCIceConnectionState, Never> {
		coordinator.iceConnectionState.publisher
	}
	
	nonisolated var signals: some Publisher<PeerConnection.RTCSignal, Never> {
		coordinator.rtcSignals
	}
	
	nonisolated var signalsPlus: some Publisher<(PeerConnection.RTCSignal, Bool), Never> {
		coordinator.rtcSignals.combineLatest(Just(peerConnectionIsPublisher))
	}
	
	//MARK: - local/remote descriptions
	
	//	@Publishing var remoteSessionDescription: Livekit_SessionDescription? = nil
	let remoteSessionDescription = _Publishing<Livekit_SessionDescription, Never>()
	let localSessionDescription = _Publishing<Livekit_SessionDescription, Never>()
	private var remoteDescription: Livekit_SessionDescription?
	private var localDescription: Livekit_SessionDescription?
	
	private var subscriptions = CurrentValueSubject<Set<AnyCancellable>, Never>([])
	
	private var _pendingCandidates = [String]()
	private var _offerInProgress: Bool = false
	private var _offerTask: Task<Void, Error>?
	
	let peerConnectionIsPublisher: Bool
	let rtcConfiguration: RTCConfiguration
	let rtcMediaConstraints: RTCMediaConstraints
	let coordinator: PeerConnection.Coordinator
	
	nonisolated let factoryPublisher: AnyPublisher<RTCPeerConnectionFactory, Never>
	
	init(
		coordinator: PeerConnection.Coordinator = Coordinator(),
		rtcConfiguration: RTCConfiguration,
		rtcMediaConstraints: RTCMediaConstraints,
		isPublisher: Bool,
		factory: some Publisher<RTCPeerConnectionFactory, Never>
	) {
		self.coordinator = coordinator
		self.rtcConfiguration = RTCConfiguration(copy: rtcConfiguration)
		self.rtcMediaConstraints = rtcMediaConstraints
		self.peerConnectionIsPublisher = isPublisher
		self.factoryPublisher = factory.eraseToAnyPublisher()
	}
	
	func configure(with joinResponse: Livekit_JoinResponse) async throws {
		let rtcConfiguration = RTCConfiguration(copy: self.rtcConfiguration)
		if rtcConfiguration.iceServers.isEmpty {
			// Set iceServers provided by the server
			rtcConfiguration.iceServers = joinResponse.iceServers.map { RTCIceServer($0) }
		}
		
		if joinResponse.clientConfiguration.forceRelay == .enabled {
			rtcConfiguration.iceTransportPolicy = .relay
		}
		
		coordinator.configure(
			rtcConfiguration,
			constraints: rtcMediaConstraints,
			peerConnectionIsPublisher: peerConnectionIsPublisher,
			factory: factoryPublisher
		)
	}
	
	func configureDataChannels() async throws {
		guard peerConnectionIsPublisher == true else { return }
		
		_ = try await withPeerConnection { [coordinator] rtcPeerConnection in
			let reliableChannel = rtcPeerConnection.dataChannel(
				forLabel: PeerConnection.DataChannelLabel.reliable.rawValue,
				configuration: RTCDataChannelConfiguration.createDataChannelConfiguration(maxRetransmits: -1)
			)
			coordinator.rtcDataChannelReliable = reliableChannel
			
			let lossyChannel = rtcPeerConnection.dataChannel(
				forLabel: PeerConnection.DataChannelLabel.lossy.rawValue,
				configuration: RTCDataChannelConfiguration.createDataChannelConfiguration(maxRetransmits: 0)
			)
			coordinator.rtcDataChannelLossy = lossyChannel
		}
	}
	
	@discardableResult
	func withPeerConnection<Result>(perform: @escaping (@Sendable(RTCPeerConnection) throws -> Result)) async throws -> Result {
		return try await withCheckedThrowingContinuation { continuation in
			rtcPeerConnection
				.first()
				.sink(receiveCompletion: { completion in
					switch completion {
					case .finished:
						break // continuations can fire only once... so we bail here since we already resumed
						
					case .failure(let failure):
						continuation.resume(throwing: failure)
					}
				}, receiveValue: {
					do {
						let result = try perform($0)
						continuation.resume(returning: result)
					} catch {
						continuation.resume(throwing: error)
					}
				})
				.store(in: &subscriptions.value)
		}
	}
	
	@discardableResult
	func _withPeerConnection<P: Publisher, Result>(
		transform: @escaping (RTCPeerConnection) -> P,
		perform: @escaping (P.Output) throws -> Result
	) async throws -> Result {
		return try await withCheckedThrowingContinuation { continuation in
			rtcPeerConnection
				.first()
				.flatMap {
					transform($0).mapError{ $0 as Error }
				}
				.sink(receiveCompletion: { completion in
					switch completion {
					case .finished:
						break
						
					case .failure(let error):
						continuation.resume(throwing: error)
					}
				}, receiveValue: { input in
					do {
						let result = try perform(input)
						continuation.resume(returning: result)
					} catch {
						continuation.resume(throwing: error)
					}
				})
				.store(in: &subscriptions.value)
		}
	}
	
	//MARK: - rtc peer connection
	
	//WebRTC's c++ types often times work with mutexes and locks to syncronize access
	//to shared mutable state. This feels like it could be an issue when trying to solve
	//this with Swift concurrency. So here we go.
	var webRTCQueue: DispatchQueue {
		coordinator.webRTCQueue
	}
	
	func addIceCandidate(_ candidateInit: String) async throws {
		Logger.log(oslog: coordinator.peerConnectionLog, message: "\(self.description) will add ice candidate \(candidateInit)")
		
		guard let _ = remoteDescription else {
			_pendingCandidates.append(candidateInit)
			return
		}
		
		try await add(candidateInit)
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
	
	func update(remoteDescription: Livekit_SessionDescription?) {
		self.remoteDescription = remoteDescription
		self.remoteSessionDescription.update(remoteDescription)
	}
	
	func update(localDescription: Livekit_SessionDescription?) {
		self.localDescription = localDescription
		self.localSessionDescription.update(localDescription)
	}
	
	nonisolated func withMediaTrack<T>(trackId: String, type: T.Type, perform: @escaping @Sendable (T) -> Void) {
		coordinator.rtcPeerConnection
			.flatMap {
				$0.receivers.publisher
			}
			.filter {
				$0.receiverId == trackId
			}
			.first()
			.compactMap({ $0.track as? T })
			.print("DEBUG: withMediaTrack")
			.sink { track in
				perform(track)
			}
			.store(in: &coordinator.cancellables.value)
	}
	
	nonisolated func renderMediaStream<Renderer: RTCVideoRenderer>(streamId: String, into renderer: Renderer) throws {
		coordinator.rtcPeerConnection
			.flatMap {
				$0.receivers.publisher
			}
			.filter {
				$0.receiverId == streamId
			}
			.first()
			.compactMap {
				$0.track as? RTCVideoTrack
			}
			.receive(on: DispatchQueue.main)
			.print("DEBUG: renderMediaStream")
			.sink { track in
				track.add(renderer)
				print("DEBUG: did add renderer: \(renderer) to track: \(track) with id: \(track.trackId), enabled: \(track.isEnabled)")
			}
			.store(in: &coordinator.cancellables.value)
	}
	
	func teardown() async {
		Logger.log(oslog: coordinator.peerConnectionLog, message: "\(self.description) teardown")
		
		_offerTask?.cancel()
		_offerTask = nil
		
		remoteSessionDescription.finish()
		localSessionDescription.finish()
		subscriptions.send(completion: .finished)
		
		coordinator.teardown()
	}
}

extension PeerConnection {
	//FIXME: call this from somewhere?
	//TODO: fixme?
	func closeDataChannels() {
		fatalError()
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
		switch label {
		case .lossy:
			fatalError()
//			lossyChannel.value?.sendData(buffer)
			
		case .reliable:
			fatalError()
//			reliableChannel.value?.sendData(buffer)
			
		case .undefined:
			throw Errors.noDataChannel
		}
	}
}

struct BufferedQueue<Element> {
	let channel: AsyncChannel<Element>
	let bufferedSequence: AsyncBufferSequence<AsyncChannel<Element>>
	
	init(channel: AsyncChannel<Element> = AsyncChannel(), policy: AsyncBufferSequencePolicy) {
		self.channel = channel
		self.bufferedSequence = AsyncBufferSequence(base: channel, policy: policy)
	}
	
	func send(_ element: Element) async {
		await channel.send(element)
	}
	
	func send(_ element: Element) {
		Task { 
			await channel.send(element)
		}
	}
	
	func values() -> AsyncBufferSequence<AsyncChannel<Element>> {
		bufferedSequence
	}
}

extension PeerConnection: CustomStringConvertible {
	nonisolated var description: String {
		"<PeerConnection \(peerConnectionIsPublisher ? "Publishing" : "Subscribing")>"
	}
}
