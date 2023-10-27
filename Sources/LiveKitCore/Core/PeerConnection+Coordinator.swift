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
		@Publishing var peerConnectionState: RTCPeerConnectionState? = nil
		@Publishing var signalingState: RTCSignalingState? = nil
		@Publishing var iceConnectionState: RTCIceConnectionState? = nil
		@Publishing var iceGatheringState: RTCIceGatheringState? = nil
		
		@Publishing var rtcDataChannelReliable: RTCDataChannel? = nil
		@Publishing var rtcDataChannelLossy: RTCDataChannel? = nil
		
		let _rtcSignals = PassthroughSubject<PeerConnection.RTCSignal, Never>()
		var rtcSignals: some Publisher<PeerConnection.RTCSignal, Never> {
			_rtcSignals
		}
		
		let peerConnectionLog = OSLog(subsystem: "PeerConnection", category: "LiveKitCore")
		
		deinit {
#if DEBUG
			Logger.plog(oslog: peerConnectionLog, publicMessage: "coordinator deinit")
#endif
		}
		
		func teardown() {
			_peerConnectionState.finish()
			_signalingState.finish()
			_iceConnectionState.finish()
			
			_iceGatheringState.finish()
			_rtcDataChannelReliable.finish()
			_rtcDataChannelLossy.finish()
			_rtcSignals.send(completion: .finished)
			
			Logger.plog(oslog: peerConnectionLog, publicMessage: "coordinator did teardown")
		}
	}
}

//MARK: - RTCPeerConnectionDelegate

extension PeerConnection.Coordinator {
	
	func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
		peerConnectionState = newState
		Logger.plog(oslog: peerConnectionLog, publicMessage: "connection state: \(newState.debugDescription)")
	}
	
	func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
		signalingState = stateChanged
		Logger.plog(oslog: peerConnectionLog, publicMessage: "signalingState: \(stateChanged.debugDescription)")
	}
	
	func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
		let iceCandidate = IceCandidate(candidate)
		_rtcSignals.send(.didGenerate(iceCandidate))
		Logger.plog(oslog: peerConnectionLog, publicMessage: "didGenerate iceCandidate: \(String(describing: candidate))")
	}
	
	func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
		//Room.swift:710
		//participant.addSubscribedMediaTrack(rtcTrack: track, sid: trackSid)
		_rtcSignals.send(.didAddMediaStreams(mediaStreams, rtpReceiver))
		Logger.plog(oslog: peerConnectionLog, publicMessage: "didAdd: rtpReceiver: \(rtpReceiver), streams: \(mediaStreams)")
	}
	
	func peerConnection(_ peerConnection: RTCPeerConnection, didRemove rtpReceiver: RTCRtpReceiver) {
		_rtcSignals.send(.didRemoveRtpReceiver(rtpReceiver))
		Logger.plog(oslog: peerConnectionLog, publicMessage: "didRemove: rtpReceiver: \(rtpReceiver)")
	}
	
	func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {
		_rtcSignals.send(.didStartReceivingOn(transceiver))
		Logger.plog(oslog: peerConnectionLog, publicMessage: "did start receiving on: \(transceiver)")
	}
	
	func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
		//Engine.swift: 745
		//store reliable/lossy channels in DataChannelPair (and potentially subscribe to their delegate updates)
		let label = PeerConnection.DataChannelLabel(rawValue: dataChannel.label)
		switch label {
		case .reliable:
			dataChannel.delegate = self
			self.rtcDataChannelReliable = dataChannel
			
		case .lossy:
			dataChannel.delegate = self
			self.rtcDataChannelLossy = dataChannel
			
		case .undefined(let value):
			Logger.plog(level: .error, oslog: peerConnectionLog, publicMessage: "data channel opened with undefined label: \(value)")
		}
		Logger.plog(oslog: peerConnectionLog, publicMessage: "did open data channel: \(dataChannel.label)")
	}
	
	//MARK: - not implemented in livekit ios sdk
	
	func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
		_rtcSignals.send(.didAddMediaStream(stream))
		Logger.plog(oslog: peerConnectionLog, publicMessage: ">>> did add stream: \(stream.streamId)")
	}
	
	func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
		_rtcSignals.send(.didRemoveMediaStream(stream))
		Logger.plog(oslog: peerConnectionLog, publicMessage: "<<< did remove stream: \(stream.streamId)")
	}
	
	/** Called when negotiation is needed, for example ICE has restarted. */
	func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
		//TODO: remove this? LiveKit doesn't use it :shrug:
		_rtcSignals.send(.shouldNegotiate)
		Logger.plog(oslog: peerConnectionLog, publicMessage: "should negotiate")
	}
	
	func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
		iceConnectionState = newState
		Logger.plog(oslog: peerConnectionLog, publicMessage: "ice connection state: \(newState.debugDescription)")
	}
	
	func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
		iceGatheringState = newState
		Logger.plog(oslog: peerConnectionLog, publicMessage: "ice gathering state: \(newState.debugDescription)")
	}
	
	func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
		_rtcSignals.send(.didRemoveIceCandidates(candidates))
		Logger.plog(oslog: peerConnectionLog, publicMessage: "did remove candidates: \(candidates.map { IceCandidate($0) })")
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
