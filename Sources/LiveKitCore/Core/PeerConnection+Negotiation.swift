//
//  PeerConnection+Negotiation.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 10/3/23.
//

import Foundation
import Combine
import AsyncAlgorithms
@_implementationOnly import WebRTC

extension PeerConnection {
	// TODO: really make sure this runs outside of our messageChannel, rtcSignals, etc sequences;
	// 1: we run this on a child task that gets cleaned up after completion
	// 2: we could also provide another parent task (messageChannelTask)
	func offeringMachine(signalHub: SignalHub) {
		guard peerConnectionIsPublisher == true, offerInProgress() == false else { return }
		update(offerInProgress: true)
		defer {
			update(offerInProgress: false)
		}
		
		Logger.log(oslog: coordinator.peerConnectionLog, message: "\(self.description) offering machine >>> start")
		
		let offerTask = Task {
			let signalingStates = signalingState.stream()
			
			//clear the local description, we're going to set a new one anyways...
			var firstOfferSent = false
			
			for await signalingState in signalingStates {
				try Task.checkCancellation()
				
				let localDescription = rtcPeerConnection?.localDescription
				let remoteDescription = rtcPeerConnection?.remoteDescription
				
				switch (signalingState, localDescription, remoteDescription) {
				case (.stable, _, _) where firstOfferSent == false:
					// fire off an offer, TODO: define other states where we allow this too...
					let sdp = try await sendInitialOffer() //expecting .haveLocalOffer
					let request = Livekit_SignalRequest(offer: sdp)
					try signalHub.enqueue(request: request)
					firstOfferSent = true
					continue
					
				case (.haveLocalOffer, _, _):
					// wait for remote answer
					Logger.log(oslog: coordinator.peerConnectionLog, message: "\(self.description) is waiting for an answer")
					// trickle requests should be coming in
					continue
					
				case (.stable, .some(_), .some(_)) where firstOfferSent == true:
					// we should have local and remote description(s)
					// let's wait for trickle to conclude ?
					// or not
					// once pcs reaches .connecting, .connected should be next (if everything goes well)
					break
					
				default:
					Logger.log(oslog: coordinator.peerConnectionLog, message: "\(self.description) received an unhandled (yet) signalingState: \(signalingState.debugDescription)")
					continue
				}
				
				break
			}
			Logger.log(oslog: coordinator.peerConnectionLog, message: "\(self.description) offering machine <<< end")
		}
		update(offerTask: offerTask)
	}
	
	func sendInitialOffer() async throws -> Livekit_SessionDescription {
		Logger.log(oslog: coordinator.peerConnectionLog, message: "\(self.description) sending initial offer")
		let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
		let offer = try await offerDescription(with: constraints)
		let sdp = try await update(localDescription: offer)
		return sdp
	}
}
