//
//  PeerConnection+Coordinator.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 10/3/23.
//

import Foundation
import Combine
import OSLog
@_implementationOnly import WebRTC

extension PeerConnection {
	
	final class Coordinator: NSObject, RTCPeerConnectionDelegate, @unchecked Sendable {
		@Publishing var peerConnection: RTCPeerConnection? = nil
		var rtcPeerConnection: some Publisher<RTCPeerConnection, Never> {
			$peerConnection.publisher.compactMap { $0 }.receive(on: webRTCQueue)
		}
		
		@Publishing var peerConnectionState: RTCPeerConnectionState? = nil
		@Publishing var signalingState: RTCSignalingState? = nil
		@Publishing var iceConnectionState: RTCIceConnectionState? = nil
		@Publishing var iceGatheringState: RTCIceGatheringState? = nil
		
		@Publishing var rtcDataChannelReliable: RTCDataChannel? = nil
		@Publishing var rtcDataChannelLossy: RTCDataChannel? = nil
		
		let _rtcSignals = PassthroughSubject<PeerConnection.RTCSignal, Never>()
		var rtcSignals: some Publisher<PeerConnection.RTCSignal, Never> {
			_rtcSignals.eraseToAnyPublisher()
		}
		
		let webRTCQueue: DispatchQueue
		let cancellables = CurrentValueSubject<Set<AnyCancellable>, Never>([])
		
		let peerConnectionLog = OSLog(subsystem: "PeerConnection", category: "LiveKitCore")
		
		init(queue: DispatchQueue = DispatchQueue(label: "PeerConnection")) {
			self.webRTCQueue = queue
			super.init()
		}
		
		deinit {
#if DEBUG
			Logger.log(oslog: peerConnectionLog, message: "coordinator deinit")
#endif
		}
		
		func configure(
			_ configuration: RTCConfiguration,
			constraints: RTCMediaConstraints,
			peerConnectionIsPublisher: Bool,
			factory: AnyPublisher<RTCPeerConnectionFactory, Never>
		) {
			Logger.log(oslog: peerConnectionLog, message: "coordinator configure, as publisher: \(peerConnectionIsPublisher)")
			factory
				.tryMap { peerConnectionFactory in
					guard let pc = peerConnectionFactory.peerConnection(with: configuration, constraints: constraints, delegate: self) else {
						throw PeerConnection.Errors.noPeerConnection
					}
					
					self.peerConnectionState = pc.connectionState
					self.signalingState = pc.signalingState
					self.iceConnectionState = pc.iceConnectionState
					self.iceGatheringState = pc.iceGatheringState
					
					return pc
				}
			// TODO: at this point we don't know that there was an error - maybe this needs some more drastic informing ?
				.first()
				.replaceError(with: nil)
				.assign(to: \.value, on: _peerConnection.subject)
				.store(in: &cancellables.value)
		}
		
		func teardown() {
			cancellables.send(completion: .finished)
			
			if let rtcPc = peerConnection {
				rtcPc.close()
				rtcPc.delegate = nil
			}
			
			_peerConnection.finish()
			_peerConnectionState.finish()
			_signalingState.finish()
			_iceConnectionState.finish()
			
			_iceGatheringState.finish()
			_rtcDataChannelReliable.finish()
			_rtcDataChannelLossy.finish()
			_rtcSignals.send(completion: .finished)
			
			Logger.log(oslog: peerConnectionLog, message: "coordinator did teardown")
		}
	}
}

//MARK: - RTCPeerConnectionDelegate

extension PeerConnection.Coordinator {
	
	func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
		peerConnectionState = newState
		Logger.log(oslog: peerConnectionLog, message: "connection state: \(newState.debugDescription)")
	}
	
	func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
		signalingState = stateChanged
		Logger.log(oslog: peerConnectionLog, message: "signalingState: \(stateChanged.debugDescription)")
	}
	
	func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
		let iceCandidate = IceCandidate(candidate)
		_rtcSignals.send(.didGenerate(iceCandidate))
		Logger.log(oslog: peerConnectionLog, message: "didGenerate iceCandidate: \(String(describing: candidate))")
	}
	
	func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
		//Room.swift:710
		//participant.addSubscribedMediaTrack(rtcTrack: track, sid: trackSid)
		_rtcSignals.send(.didAddMediaStreams(mediaStreams, rtpReceiver))
		Logger.log(oslog: peerConnectionLog, message: "didAdd: rtpReceiver: \(rtpReceiver), streams: \(mediaStreams)")
	}
	
	func peerConnection(_ peerConnection: RTCPeerConnection, didRemove rtpReceiver: RTCRtpReceiver) {
		_rtcSignals.send(.didRemoveRtpReceiver(rtpReceiver))
		Logger.log(oslog: peerConnectionLog, message: "didRemove: rtpReceiver: \(rtpReceiver)")
	}
	
	func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {
		_rtcSignals.send(.didStartReceivingOn(transceiver))
		Logger.log(oslog: peerConnectionLog, message: "did start receiving on: \(transceiver)")
	}
	
	func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
		webRTCQueue.sync { [peerConnectionLog] in
			//Engine.swift: 745
			//store reliable/lossy channels in DataChannelPair (and potentially subscribe to their delegate updates)
			let label = PeerConnection.DataChannelLabel(rawValue: dataChannel.label)
			switch label {
			case .reliable:
				dataChannel.delegate = self
				rtcDataChannelReliable = dataChannel
				
			case .lossy:
				dataChannel.delegate = self
				rtcDataChannelLossy = dataChannel
				
			case .undefined(let value):
				Logger.log(level: .error, oslog: peerConnectionLog, message: "data channel opened with undefined label: \(value)")
			}
		}
		Logger.log(oslog: peerConnectionLog, message: "did open data channel: \(dataChannel.label)")
	}
	
	//MARK: - not implemented in livekit ios sdk
	
	func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
		_rtcSignals.send(.didAddMediaStream(stream))
		Logger.log(oslog: peerConnectionLog, message: "did add stream: \(stream.streamId)")
	}
	
	func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
		_rtcSignals.send(.didRemoveMediaStream(stream))
		Logger.log(oslog: peerConnectionLog, message: "did remove stream: \(stream.streamId)")
	}
	
	/** Called when negotiation is needed, for example ICE has restarted. */
	func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
		//TODO: remove this? LiveKit doesn't use it :shrug:
		_rtcSignals.send(.shouldNegotiate)
		Logger.log(oslog: peerConnectionLog, message: "should negotiate")
	}
	
	func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
		iceConnectionState = newState
		Logger.log(oslog: peerConnectionLog, message: "ice connection state: \(newState.debugDescription)")
	}
	
	func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
		iceGatheringState = newState
		Logger.log(oslog: peerConnectionLog, message: "ice gathering state: \(newState.debugDescription)")
	}
	
	func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
		_rtcSignals.send(.didRemoveIceCandidates(candidates))
		Logger.log(oslog: peerConnectionLog, message: "did remove candidates: \(candidates.map { IceCandidate($0) })")
	}
}

extension PeerConnection.Coordinator: RTCDataChannelDelegate {
	
	func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
		let label = PeerConnection.DataChannelLabel(rawValue: dataChannel.label)
		_rtcSignals.send(.dataChannelDidChangeState(label, dataChannel.readyState))
	}
	
	func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
		_rtcSignals.send(.dataChannelDidReceiveMessage(buffer))
	}
	
	func dataChannel(_ dataChannel: RTCDataChannel, didChangeBufferedAmount amount: UInt64) {
		let label = PeerConnection.DataChannelLabel(rawValue: dataChannel.label)
		_rtcSignals.send(.dataChannelDidChangeBufferedAmount(label, amount))
	}
}
