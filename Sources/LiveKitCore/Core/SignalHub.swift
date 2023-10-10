//
//  SignalHub.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 3/30/23.
//

import Foundation
import Combine
import OSLog
@_implementationOnly import WebRTC
import AsyncAlgorithms

public enum SignalHubError: Error {
	case noSignalClient
	case noMessageChannel
	case noJoinResponse
	case noAddTrackResponse
	case noAnswer
	case unhandled
	case negotiationFailed
}

// should this be an actor instead ? so the PeerConnection types can be classes instead of actors?
@available(iOS 15.0, macOS 12.0, *)
open class SignalHub: @unchecked Sendable {
	
	enum LiveKitUpdates {
		case localParticipants(Livekit_ParticipantInfo)
		case participantUpdate(Livekit_ParticipantUpdate)
		case trackPublished(Livekit_TrackPublishedResponse)
		case trackUnpublished(Livekit_TrackUnpublishedResponse)
		case token(String)
		case connectionQuality(Livekit_ConnectionQualityUpdate)
		case subscriptionQuality(Livekit_SubscribedQualityUpdate)
		case activeSpeaker(Livekit_ActiveSpeakerUpdate)
		case speakerChanged(Livekit_SpeakersChanged)
		case room(Livekit_RoomUpdate)
		case join(Livekit_JoinResponse)
	}
	
	//MARK: - WebSocket messages, in/out
	//using this channel specifically for pong messages
	let outgoingDataRequestsChannel = AsyncChannel<Data>()
	let outgoingDataRequests = PassthroughSubject<Data, Never>()
	
	//MARK: - publishers
	//	let pongMessagesChannel = AsyncChannel<Int64>() // << Switch
	
	//MARK: - State Publishers
	//OK
	@Publishing var joinResponse: Livekit_JoinResponse? = nil
	@Publishing public var localParticipant: LiveKitParticipant? = nil
	@Publishing public var remoteParticipants: [String: LiveKitParticipant] = [:]
	
	//OK
	//published tracks ... used for addTrackRequest <> Response during publishing
	@Publishing var audioTracks: [String: LiveKitTrack] = [:]
	@Publishing var videoTracks: [String: LiveKitTrack] = [:]
	@Publishing var dataTracks: [String: LiveKitTrack] = [:]
	
	//OK
	@Publishing public var connectionQuality: [String: LiveKitConnectionQuality] = [:]
	@Publishing public var mediaStreams: [LiveKitStream] = []
	
	//MARK: - tokens
	let tokenUpdatesSubject = PassthroughSubject<String, Never>()
	
	//MARK: - quality updates
	//TODO
	@Publishing var subscriptionQualityUpdates: Livekit_SubscribedQualityUpdate? = nil
	
	//MARK: - speaker updates
	//TODO
	@Publishing var speakerChangedUpdates: Livekit_SpeakersChanged? = nil
	
	//MARK: - data channels
	let incomingDataPackets = PassthroughSubject<Livekit_DataPacket, Never>()
	let outgoingDataPackets = PassthroughSubject<Livekit_DataPacket, Never>()
	
	let signalHubLog = OSLog(subsystem: "SignalHub", category: "LiveKitCore")
	
	//MARK: - init/deinit
	
	let peerConnectionFactory: PeerConnectionFactory
	init(peerConnectionFactory: PeerConnectionFactory) {
		self.peerConnectionFactory = peerConnectionFactory
	}
	
	convenience public init() {
		self.init(peerConnectionFactory: PeerConnectionFactory())
	}
	
	deinit {
#if DEBUG
		Logger.log(oslog: signalHubLog, message: "deinit <SignalHub>")
#endif
	}
	
	func teardown() async throws {
		//0: housekeeping
		incomingDataPackets.send(completion: .finished)
		outgoingDataPackets.send(completion: .finished)
		outgoingDataRequestsChannel.finish()
		outgoingDataRequests.send(completion: .finished)
		
		//1: other subjects/publishers
		_speakerChangedUpdates.finish()
		_subscriptionQualityUpdates.finish()
		tokenUpdatesSubject.send(completion: .finished)
		
		_joinResponse.finish()
		
		_dataTracks.finish()
		_audioTracks.finish()
		_videoTracks.finish()
		_mediaStreams.finish()
		_localParticipant.finish()
		_remoteParticipants.finish()
		
		await withTaskGroup(of: Void.self) { group in
			for pc in [peerConnectionFactory.publishingPeerConnection, peerConnectionFactory.subscribingPeerConnection] {
				group.addTask {
					await pc.teardown()
				}
			}
			
			await group.waitForAll()
		}
		
		Logger.log(oslog: signalHubLog, message: "signalHub did teardown")
	}
	
	public func tokenUpdates() -> AnyPublisher<String, Never> {
		tokenUpdatesSubject.eraseToAnyPublisher()
	}
	
	func enqueue(request: Livekit_SignalRequest) throws {
		do {
			let data = try request.serializedData()
			outgoingDataRequests.send(data)
			Logger.log(oslog: signalHubLog, message: "enqueue request: \(String(describing: request.message))")
		} catch {
			Logger.log(level: .error, oslog: signalHubLog, message: "MessageChannel: enqueue ERROR: \(error)")
		}
	}
}
