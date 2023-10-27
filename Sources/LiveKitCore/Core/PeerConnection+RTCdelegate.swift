//
//  TransportService+RTCdelegate.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 5/8/23.
//

import Foundation
import Combine
import OSLog
@_implementationOnly @preconcurrency import WebRTC

extension PeerConnection {
	enum RTCSignal: Sendable {
		case connectionState(RTCPeerConnectionState)
		case signalingState(RTCSignalingState)
		case didGenerate(IceCandidate)
		case didAddMediaStreams([RTCMediaStream], RTCRtpReceiver)
		case didRemoveRtpReceiver(RTCRtpReceiver)
		case didOpenDataChannel(RTCDataChannel)
		case didAddMediaStream(RTCMediaStream)
		case didRemoveMediaStream(RTCMediaStream)
		case shouldNegotiate
		case didChangeIceConnectionState(RTCIceConnectionState)
		case didChangeIceGatheringState(RTCIceGatheringState)
		case didRemoveIceCandidates([RTCIceCandidate])
		case didStartReceivingOn(RTCRtpTransceiver)
		case test //TODO: remove
		case dataChannelDidChangeState(DataChannelLabel, RTCDataChannelState)
		case dataChannelDidReceiveMessage(RTCDataBuffer)
		case dataChannelDidChangeBufferedAmount(DataChannelLabel, UInt64)
	}
	
	enum DataChannelLabel {
		static let _reliable = "_reliable"
		static let _lossy = "_lossy"
		case reliable
		case lossy
		case undefined(String)
	}
}

extension PeerConnection.RTCSignal: CustomStringConvertible {
	var description: String {
		switch self {
		case .connectionState(let state):
			return "ConnectionState: \(state)"
			
		case .signalingState(let state):
			return "SignalingState: \(state)"
			
		case .shouldNegotiate:
			return "Should Negotiate"
			
		case .didGenerate(let value):
			return "did generate: \(value)"
			
		case .didAddMediaStreams(let value1, let value2):
			return "did add media streams: \(value1) receiver: \(value2)"
			
		case .didRemoveRtpReceiver(let value):
			return "did remove rtp receiver: \(value)"
			
		case .didOpenDataChannel(let value):
			return "did open data channel: \(value)"
			
		default:
			return "some RTC signal: ... "
		}
	}
}

extension PeerConnection.DataChannelLabel: RawRepresentable {
	var rawValue: String {
		switch self {
		case .lossy:
			return Self._lossy
			
		case .reliable:
			return Self._reliable
			
		case .undefined(let value):
			return "?\(value)"
		}
	}
	
	init(rawValue: String) {
		switch rawValue {
		case PeerConnection.DataChannelLabel._reliable:
			self = .reliable
			
		case PeerConnection.DataChannelLabel._lossy:
			self = .lossy
			
		default:
			self = .undefined(rawValue)
		}
	}
	
	var dataPacketKind: Livekit_DataPacket.Kind {
		switch self {
		case .reliable:
			return .reliable
			
		case .lossy:
			return .lossy
			
		default:
			return .UNRECOGNIZED(0)
		}
	}
}

extension Livekit_DataPacket.Kind {
	init(_ label: PeerConnection.DataChannelLabel) {
		switch label {
		case .reliable:
			self = .reliable
			
		case .lossy:
			self = .lossy
			
		default:
			self = .UNRECOGNIZED(0)
		}
	}
}

extension Livekit_UserPacket {
	func makeDataPacket(kind: Livekit_DataPacket.Kind = .reliable) -> Livekit_DataPacket {
		Livekit_DataPacket.with {
			$0.kind = kind
			$0.user = self
		}
	}
}
