/*
 * Copyright 2022 LiveKit
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import Combine
import CoreMedia
import OSLog
@_implementationOnly import WebRTC

/// This is something like a room - but not really - it's more like a meta-room
@available(iOS 15.0, macOS 12.0, *)
open class LiveKitSession: @unchecked Sendable {
	
	public enum Errors: Error {
		case pingTimeout
		case connect
		case url
	}
	
	// TODO: rename?
	@Publishing public var liveKitConnectionState: MessageChannelConnectionState = .disconnected
	
	public let id: String
	public let signalHub: SignalHub
	let sessionLog = OSLog(subsystem: "LiveKitSession", category: "LiveKitCore")
	
	public init(
		id: String = UUID().uuidString,
		signalHub: SignalHub = SignalHub()
	) {
		self.id = id
		self.signalHub = signalHub
	}
	
#if DEBUG
	deinit {
		print("DEBUG: deinit <Session id: \(id)>")
	}
#endif
	
	func connect<P: Publisher>(_ connectionStatePublisher: P) where P.Output == MessageChannelConnectionState, P.Failure == Never {
		connectionStatePublisher.assign(to: &_liveKitConnectionState)
	}
	
	public var localParticipantPublisher: some Publisher<LiveKitParticipant, Never> {
		signalHub.$localParticipant.publisher.compactMap{ $0 }
	}
	
	public var remoteParticipants: some Publisher<[String: LiveKitParticipant], Never> {
		signalHub.$remoteParticipants.publisher
	}
	
	public var mediaStreams: some Publisher<[String: LiveKitStream], Never> {
		signalHub.$mediaStreams.publisher
	}
	
	public var dataTracks: AnyPublisher<Dictionary<String, LiveKitTrackInfo>, Never> {
		signalHub.$dataTracks.publisher.eraseToAnyPublisher()
	}
	
	public var audioTracks: AnyPublisher<[String: LiveKitTrackInfo], Never> {
		signalHub.$audioTracks.publisher.eraseToAnyPublisher()
	}
	
	public var videoTracks: AnyPublisher<[String: LiveKitTrackInfo], Never> {
		signalHub.$videoTracks.publisher.eraseToAnyPublisher()
	}
	
	//sorry for the type ... once Swift can do something like `any AsyncSequence<Data>` this wouldn't be necessary
	private func dataPackets() -> any AsyncSequence {
		fatalError()
	}
	
	public var incomingPacketData: AnyPublisher<LiveKitPacketData, Never> {
		signalHub.incomingDataPackets.map { LiveKitPacketData($0) }.eraseToAnyPublisher()
	}
	
	public func activeSpeakers() -> AnyPublisher<LiveKitSpeaker, Never> {
		signalHub.incomingDataPackets.map { LiveKitSpeaker($0.speaker) }.eraseToAnyPublisher()
	}
	
	public func userData() -> some Publisher<LiveKitUserData, Never> {
		signalHub.incomingDataPackets.map { LiveKitUserData($0.user) }
	}
	
	public func statsStream() -> AsyncStream<Any> {
		AsyncStream<Any> { continuation in
			fatalError()
		}
	}
	
	//MARK: - stats
	func enableStatsPublisher(_ enable: Bool) throws {
		//        let statsTask = Task(priority: .utility) { [weak self] in
		//            while true {
		//                guard let self else { return }
		//                let newStats = try await self.trackStats(peerConnection: peerConnection, current: self.statisticsSubject.value)
		//                try Task.checkCancellation()
		//                self.statisticsSubject.send(newStats)
		//                if #available(iOS 16.0, macOS 13.0, *) {
		//                    try await Task.sleep(until: .now + .seconds(1), tolerance: .milliseconds(500), clock: .continuous)
		//                } else {
		//                    try await Task.sleep(nanoseconds: 1_000_000_000)
		//                }
		//            }
		//        }
	}
	
	//MARK: - data packet sending
	
	public func sendUserData(_ userData: LiveKitUserData) {
		signalHub.outgoingDataPackets.send(userData.makeDataPacket())
	}
	
	//TODO: this kind of out-lives the disconnect ... got to look into this (later)
	private func handlePingPong() async throws {
		//        let connectedStates = await signalHub.connectedStatePublisher.values
		//        for await connectedState in connectedStates {
		//
		//            print("DEBUG: start ping/pong")
		//            while connectedState.isConnected == true {
		//
		//                let pingTimeout = connectedState.pingTimeout
		//                let pingInterval = connectedState.pingInterval
		//
		//                await signalHub.outgoingRequestsChannel.send(.pingRequest)
		//                try await withThrowingTaskGroup(of: Void.self) { group in
		//                    //send ping
		//                    group.addTask {
		//                        for await pong in self.signalHub.pongMessagesChannel {
		//                            print("DEBUG: got pong: \(pong)")
		//                            break
		//                        }
		//                    }
		//
		//                    //Timeout waiting for a pong response
		//                    try await group.timeout(Double(pingTimeout))
		//                } //task group
		//
		//                if #available(iOS 16.0, macOS 13.0, *) {
		//                    try await Task.sleep(for: .seconds(pingInterval))
		//                } else {
		//                    try await Task.sleep(nanoseconds: UInt64(pingInterval) * 1_000_000_000)
		//                }
		//            }
		//        }
	}
	
	// MARK: - audio
	public func stopAudioDelivery() {
		signalHub.peerConnectionFactory.audioDevice.stopAudioDelivery()
	}
	
	public func muteAudio(_ muted: Bool, trackId: String) throws {
		try signalHub.enqueue(request: Livekit_SignalRequest(trackId: trackId, muted: muted))
	}
}

extension URLSessionConfiguration {
	public class var liveKitDefault: URLSessionConfiguration {
		let config = URLSessionConfiguration.default
		// explicitly set timeout intervals
		config.timeoutIntervalForRequest = TimeInterval(60)
		config.timeoutIntervalForResource = TimeInterval(604_800)
		//        log("URLSessionConfiguration.timeoutIntervalForRequest: \(config.timeoutIntervalForRequest)")
		//        log("URLSessionConfiguration.timeoutIntervalForResource: \(config.timeoutIntervalForResource)")
		return config
	}
}
