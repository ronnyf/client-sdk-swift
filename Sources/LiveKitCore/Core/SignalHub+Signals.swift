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
		case .update(let update):
			Logger.log(oslog: signalHubLog, message: "participant update: \(update)")
			// duplicates will be eliminated here ------v (which should be ok)
			update.participants.grouping(by: \.id, into: &remoteParticipants) { LiveKitParticipant($0) }
			// if this statement ------^ needs to change, then please adjust PeerConnection+Signals.swift:~line:68
			return true
			
		case .trackPublished(let update) where update.track.type == .audio :
			audioTracks[update.cid] = LiveKitTrack(update)
			return true
			
		case .trackPublished(let update) where update.track.type == .video :
			videoTracks[update.cid] = LiveKitTrack(update)
			return true
			
		case .trackPublished(let update) where update.track.type == .data :
			dataTracks[update.cid] = LiveKitTrack(update)
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
			return true
			
		case .subscribedQualityUpdate(let update):
			Logger.log(oslog: signalHubLog, message: "subscribed quality update: \(update)")
			return true
			
		case .pong(_):
			Logger.log(oslog: signalHubLog, message: "messages: pong")
			return true
			
		case .streamStateUpdate(let update):
			Logger.log(oslog: signalHubLog, message: "stream state update: \(update)")
			return true
			
		case .subscriptionPermissionUpdate(let update):
			Logger.log(oslog: signalHubLog, message: "subscriptionPermission update: \(update)")
			return true
			
		case .speakersChanged(let update):
			Logger.log(oslog: signalHubLog, message: "speakersChanged update: \(update)")
			return true
			
		case .roomUpdate(let update):
			Logger.log(oslog: signalHubLog, message: "roomUpdate update: \(update)")
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
