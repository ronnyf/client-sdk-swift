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
	let joinResponse = _Publishing<Livekit_JoinResponse, Never>()
	let localParticipants = _Publishing<Livekit_ParticipantInfo, Never>()
	var connectedState: AnyPublisher<LiveKitState, Never> {
		peerConnectionFactory.publishingPeerConnection.connectionState.map {
			LiveKitState($0)
		}.eraseToAnyPublisher()
	}
	
	//OK
	let updatedParticipantsSubject = PassthroughSubject<[Livekit_ParticipantInfo], Never>()
	var updatedParticipantsPublisher: AnyPublisher<[Livekit_ParticipantInfo], Never> {
		updatedParticipantsSubject.filter { $0.isEmpty == false }.eraseToAnyPublisher()
	}
	
	//OK
	//published tracks ... used for addTrackRequest <> Response during publishing
	let audioTracks = CurrentValueSubject<[String: LiveKitTrack], Never>([:])
	let videoTracks = CurrentValueSubject<[String: LiveKitTrack], Never>([:])
	let dataTracks = CurrentValueSubject<[String: LiveKitTrack], Never>([:])
	
	@Publishing public var mediaStreams: [LiveKitStream] = []
	
	//MARK: - tokens
	let tokenUpdatesSubject = PassthroughSubject<String, Never>()
	
	//MARK: - quality updates
	//TODO
	let subscriptionQualityUpdates = _Publishing<Livekit_SubscribedQualityUpdate, Never>()
	
	//MARK: - speaker updates
	//TODO
	let speakerChangedUpdates = _Publishing<Livekit_SpeakersChanged, Never>()
	
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
		
		//1: other subjects/publishers
		speakerChangedUpdates.finish()
		subscriptionQualityUpdates.finish()
		tokenUpdatesSubject.send(completion: .finished)
		
		joinResponse.finish()
		localParticipants.finish()
		
		dataTracks.send(completion: .finished)
		audioTracks.send(completion: .finished)
		videoTracks.send(completion: .finished)
		
		_mediaStreams.finish()
		outgoingDataRequestsChannel.finish()
		outgoingDataRequests.send(completion: .finished)

		localParticipants.finish()
		
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
	
	func handleParticipantsUpdate(_ update: Livekit_ParticipantUpdate) {
		var allParticipants = update.participants
		
		if let currentLocalParticipant = localParticipants.value {
			
			// This is so not efficient ... if only we had Sets instead of arrays *sigh*
			if let currentLocalParticipantIndex = allParticipants.firstIndex(where: { $0.sid == currentLocalParticipant.sid }) {
				let updatedLocalParticipant = allParticipants.remove(at: currentLocalParticipantIndex)
				localParticipants.update(updatedLocalParticipant)
			}
		}
		
		updatedParticipantsSubject.send(allParticipants)
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
