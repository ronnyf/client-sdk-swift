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
	
	func negotiate(signalHub: SignalHub) async throws -> RTCSignalingState {
		guard peerConnectionIsPublisher == true, offerInProgress() == false else { return coordinator.signalingState }
		update(offerInProgress: true)
		defer {
			update(offerInProgress: false)
		}
		
		let offerTask = startOfferTask(signalHub: signalHub)
		return try await offerTask.value
	}
	
	private func startOfferTask(signalHub: SignalHub) -> Task<RTCSignalingState, Error> {
		
		Task {
			Logger.plog(oslog: coordinator.peerConnectionLog, publicMessage: "\(self.description) offering machine >>> start")
			defer {
				Logger.plog(oslog: coordinator.peerConnectionLog, publicMessage: "\(self.description) offering machine <<< end")
			}
			
			let signalingStates = signalingState.stream()
			
			var firstOfferSent = false
			
			for await signalingState in signalingStates {
				try Task.checkCancellation()
				
				let localDescription = rtcPeerConnection?.localDescription
				let remoteDescription = rtcPeerConnection?.remoteDescription
				
				switch (signalingState, localDescription, remoteDescription) {
				case (.stable, _, _) where firstOfferSent == false:
					// fire off an offer, TODO: define other states where we allow this too...
					let sdp = try await sendInitialOffer() // expecting .haveLocalOffer
					let request = Livekit_SignalRequest(offer: sdp)
					try signalHub.enqueue(request: request)
					firstOfferSent = true
					continue
					
				case (.haveLocalOffer, _, _):
					// wait for remote answer
					Logger.plog(level: .debug, oslog: coordinator.peerConnectionLog, publicMessage: "\(self.description) with signaling state \(signalingState.debugDescription) is waiting for an answer")
					// trickle requests should be coming in
					continue
					
				case (.stable, .some(_), .some(_)) where firstOfferSent == true:
					// we should have local and remote description(s)
					// let's wait for trickle to conclude ?
					// or not
					// once pcs reaches .connecting, .connected should be next (if everything goes well)
					return signalingState
					
				default:
					Logger.plog(level: .debug, oslog: coordinator.peerConnectionLog, publicMessage: "\(self.description) received an unhandled (yet) signalingState: \(signalingState.debugDescription)")
					continue
				}
				
				return signalingState
			}
			// if we land here then something is wrong, let's bubble this up...
			throw Errors.makeOffer
		}
	}
	
	func offeringMachine(signalHub: SignalHub) {
		
		guard peerConnectionIsPublisher == true, offerInProgress() == false else { return }
		update(offerInProgress: true)
		defer {
			update(offerInProgress: false)
		}
		
		_offerTask?.cancel()
		update(offerTask: startOfferTask(signalHub: signalHub))
	}
	
	func sendInitialOffer() async throws -> Livekit_SessionDescription {
		
		let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
		let offer = try await offerDescription(with: constraints)
		
		Logger.plog(oslog: coordinator.peerConnectionLog, publicMessage: "\(self.description) sending initial offer: \(offer)")
		
		let sdp = try await update(localDescription: offer)
		precondition(coordinator.signalingState == .haveLocalOffer)
		return sdp
	}
}
