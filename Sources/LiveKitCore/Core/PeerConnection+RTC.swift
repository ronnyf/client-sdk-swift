//
//  PeerConnection+RTC.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 9/22/23.
//

import Foundation
import Combine
@_implementationOnly import WebRTC

extension RTCPeerConnection {
	func candidateInit(_ value: String) -> some Publisher<Void, Error> {
		Future { promise in
			do {
				let candidate = try RTCIceCandidate(fromJsonString: value)
				assert(self.remoteDescription != nil)
				self.add(candidate) { error in
					if let error {
						promise(.failure(error))
					} else {
						promise(.success(()))
					}
				}
			} catch {
				promise(.failure(error))
			}
		}
	}
	
	func localDescription(_ rtcSdp: RTCSessionDescription) -> some Publisher<Livekit_SessionDescription, Error> {
		Future { promise in
			self.setLocalDescription(rtcSdp) { error in
				if let error {
					promise(.failure(error))
				} else {
					promise(.success(Livekit_SessionDescription(rtcSdp)))
				}
			}
		}
	}	
	
	func localDescription(_ liveKit_Sdp: Livekit_SessionDescription) -> some Publisher<Livekit_SessionDescription, Error> {
		Future { promise in
			let rtcSdp = RTCSessionDescription(liveKit_Sdp)
			self.setLocalDescription(rtcSdp) { error in
				if let error {
					promise(.failure(error))
				} else {
					promise(.success(liveKit_Sdp))
				}
			}
		}
	}	
	
	func remoteDescription(_ rtcSdp: RTCSessionDescription) -> some Publisher<Livekit_SessionDescription, Error> {
		Future { promise in
			self.setRemoteDescription(rtcSdp) { error in
				if let error {
					promise(.failure(error))
				} else {
					promise(.success(Livekit_SessionDescription(rtcSdp)))
				}
			}
		}
	}
	
	func remoteDescription(_ liveKit_Sdp: Livekit_SessionDescription) -> some Publisher<Livekit_SessionDescription, Error> {
		Future { promise in
			let rtcSdp = RTCSessionDescription(liveKit_Sdp)
			self.setRemoteDescription(rtcSdp) { error in
				if let error {
					promise(.failure(error))
				} else {
					promise(.success(liveKit_Sdp))
				}
			}
		}
	}	
	
	func iceCandidate(_ candidate: IceCandidate) -> some Publisher<Void, Error> {
		Future { promise in
			let rtcCandidate = RTCIceCandidate(candidate)
			self.add(rtcCandidate) { error in
				if let error {
					promise(.failure(error))
				} else {
					promise(.success(()))
				}
			}
		}
	}
	
	func transceiver(with track: RTCMediaStreamTrack, transceiverInit: RTCRtpTransceiverInit) -> some Publisher<RTCRtpTransceiver, Error> {
		Future { promise in
			if let transceiver = self.addTransceiver(with: track, init: transceiverInit) {
				promise(.success(transceiver))
			} else {
				promise(.failure(PeerConnection.Errors.createTransceiver))
			}
		}
	}
	
	func offerDescription(with constraints: RTCMediaConstraints) -> some Publisher<RTCSessionDescription, Error> {
		Future { promise in
			self.offer(for: constraints) { sd, error in
				if let error {
					promise(.failure(error))
				} else {
					if let sd {
						promise(.success(sd))
					} else {
						promise(.failure(NoValueError()))
					}
				}
			}
		}
	}
	
	func answerDescription(with constraints: RTCMediaConstraints) -> some Publisher<RTCSessionDescription, Error> {
		Future { promise in
			self.answer(for: constraints) { sd, error in
				if let error {
					promise(.failure(error))
				} else {
					if let sd {
						promise(.success(sd))
					} else {
						promise(.failure(NoValueError()))
					}
				}
			}
		}
	}
}

extension CheckedContinuation {
	func complete(value: T, subscriberCompletion: Subscribers.Completion<E>) {
		switch subscriberCompletion {
		case .finished:
			resume(returning: value)
		case .failure(let error):
			resume(throwing: error)
		}
	}
}

extension PeerConnection {
	//MARK: - peer connection accessors
	
	func add(_ candidateInit: String) async throws {
		try await self._withPublisher(coordinator.rtcPeerConnection) {
			$0.candidateInit(candidateInit)
		}
	}
	
	func _withPublisher<Input, Output, Failure>(_ publisher: some Publisher<Input, Never>, transform: @escaping (@Sendable (Input) -> some Publisher<Output, Failure>)) async throws -> Output {
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Output, Error>) in
			let subscriptions = CurrentValueSubject<Set<AnyCancellable>, Never>([])
			publisher
				.flatMap(transform)
				.first()
				.sink { completion in
					switch completion {
					case .finished:
						break
						
					case .failure(let error):
						continuation.resume(throwing: error)
					}
					subscriptions.send(completion: .finished)
				} receiveValue: {
					continuation.resume(returning: $0)
				}
				.store(in: &subscriptions.value)
		}
	}
	
	@discardableResult
	func setLocalDescription(_ sdp: Livekit_SessionDescription) async throws -> Livekit_SessionDescription {
		let result = try await _withPublisher(coordinator.rtcPeerConnection) { rtcPeerConnection in
			rtcPeerConnection.localDescription(sdp)
		}
		update(localDescription: result)
		return result
	}
	
	func setLocalDescription(_ rtcSdp: RTCSessionDescription) async throws -> Livekit_SessionDescription {
		let result = try await _withPublisher(coordinator.rtcPeerConnection) { rtcPeerConnection in
			rtcPeerConnection.localDescription(rtcSdp)
		}
		update(localDescription: result)
		return result
	}
	
	@discardableResult
	func setRemoteDescription(_ sdp: Livekit_SessionDescription) async throws -> Livekit_SessionDescription {
		let result = try await _withPublisher(coordinator.rtcPeerConnection) { rtcPeerConnection in
			rtcPeerConnection.remoteDescription(sdp)
		}
		update(remoteDescription: result)
		let pendingCandidates = pendingIceCandidates()
		if pendingCandidates.count > 0 {
			try await withThrowingTaskGroup(of: Void.self) { group in
				for pendingCandidate in pendingCandidates {
					group.addTask {
						try await self.add(pendingCandidate)
					}
				}
				
				try await group.waitForAll()
			}
			update(pendingCandidates: [])
		}
		
		return result
	}
	
	func offer(for constraints: RTCMediaConstraints) async throws -> RTCSessionDescription {
		return try await _withPublisher(coordinator.rtcPeerConnection) { rtcPeerConnection in
			rtcPeerConnection.offerDescription(with: constraints)
		}
	}
	
	func answer(for constraints: RTCMediaConstraints) async throws -> RTCSessionDescription {
		return try await _withPublisher(coordinator.rtcPeerConnection) { rtcPeerConnection in
			rtcPeerConnection.answerDescription(with: constraints)
		}
	}
	
	func addTransceiver(with track: RTCMediaStreamTrack, transceiverInit: RTCRtpTransceiverInit) async throws -> RTCRtpTransceiver {
		return try await _withPublisher(coordinator.rtcPeerConnection) { rtcPeerConnection in
			rtcPeerConnection.transceiver(with: track, transceiverInit: transceiverInit)
		}
	}
}
