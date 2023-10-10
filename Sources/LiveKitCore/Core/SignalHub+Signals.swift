//
//  SignalHub+Signals.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 5/5/23.
//

import Foundation
import OSLog
@_implementationOnly import WebRTC

extension SignalHub {
	@discardableResult
	func handle(responseMessage: Livekit_SignalResponse.OneOf_Message) async throws -> Bool {
		// create a shared channel for incoming messages, this is especially relevant for webrtc negotiation
		// related messaging.
		
		// handling (some cases of) response messages that arrive via livekit socket
		switch responseMessage {
		/// sent when participants in the room has changed
		case .update(let participantUpdate):
			Logger.log(oslog: signalHubLog, message: "participant update: \(participantUpdate)")
			
			let groupedParticipants = Dictionary(grouping: participantUpdate.participants) { $0.state }
			
			for (status, participants) in groupedParticipants {
				switch status {
				case .active:
					// merge all active participants (with or without tracks) into our dictionary of remote participants
					participants.mergingGrouped(by: \.id, into: &remoteParticipants) { LiveKitParticipant($0) }
					
				default:
					// remove all partipants that were updated to non-active state from our dictionary of remote participants
					for participant in participants {
						remoteParticipants.removeValue(forKey: participant.sid)
					}
				}
			}
			return true
			
		case .trackPublished(let update) where update.track.type == .audio :
			audioTracks[update.cid] = LiveKitTrackInfo(update)
			return true
			
		case .trackPublished(let update) where update.track.type == .video :
			videoTracks[update.cid] = LiveKitTrackInfo(update)
			return true
			
		case .trackPublished(let update) where update.track.type == .data :
			dataTracks[update.cid] = LiveKitTrackInfo(update)
			return true
			
		case .trackUnpublished(let update):
			audioTracks.removeValue(forKey: update.trackSid)
			videoTracks.removeValue(forKey: update.trackSid)
			dataTracks.removeValue(forKey: update.trackSid)
			return true
			
		case .leave(let request):
			Logger.log(oslog: signalHubLog, message: "leave request: \(request)")
			//TODO: reconnect?
			return true
			
		case .refreshToken(let token):
			Logger.log(oslog: signalHubLog, message: "refreshToken update: \(token)")
			return true
			
		case .connectionQuality(let update):
			Logger.log(oslog: signalHubLog, message: "connection quality update: \(update)")
			connectionQuality = update.livekitQualities
			return true
			
		case .subscribedQualityUpdate(let update):
			Logger.log(oslog: signalHubLog, message: "subscribed quality update: \(update)")
			return true
			
		case .pong(_):
			Logger.log(oslog: signalHubLog, message: "messages: pong")
			return true
			
		case .streamStateUpdate(let update):
			Logger.log(oslog: signalHubLog, message: "stream state update: \(update)")
			
			let streamStateInfos = update.streamStates
			for streamStateInfo in streamStateInfos {
				//TODO:
			}
			
			return true
			
		case .subscriptionPermissionUpdate(let update):
			Logger.log(oslog: signalHubLog, message: "subscriptionPermission update: \(update)")
			return true
			
		case .speakersChanged(let update):
			Logger.log(oslog: signalHubLog, message: "speakersChanged update: \(update)")
			return true
			
		case .roomUpdate(let update):
			Logger.log(oslog: signalHubLog, message: "roomUpdate update: \(update)")
			// TODO: participants and max participants can be found here
			return true
			
		default:
			//forwarding message down to peer connection(s) for handling
			let publishingPeerConnection = peerConnectionFactory.publishingPeerConnection
			let handled = try await publishingPeerConnection.handleIncomingResponseMessage(responseMessage, signalHub: self)
			if handled == false {
				let subscribingPeerConnection = peerConnectionFactory.subscribingPeerConnection
				return try await subscribingPeerConnection.handleIncomingResponseMessage(responseMessage, signalHub: self)
			}
			return handled
		}
	}
}
