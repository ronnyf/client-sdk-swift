//
//  SignalHub+LiveKit.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 5/5/23.
//

import Foundation
import CoreMedia
import Combine
import OSLog
@_implementationOnly import WebRTC

extension SignalHub {
	
	// MARK: - livekit signals
	
	func sendMuteTrack(trackSid: String, muted: Bool) throws {
		guard trackSid.isEmpty == false else {
			Logger.plog(level: .error, oslog: signalHubLog, publicMessage: "attempting to mute a track without sid, this will not work! Please file a bug.")
			return
		}
		let request = Livekit_SignalRequest.with {
			$0.mute = Livekit_MuteTrackRequest.with {
				$0.sid = trackSid
				$0.muted = muted
			}
		}
		
		try enqueue(request: request)
	}
	
	func makeTrackStatsRequest(trackSids: [String], enabled: Bool, dimensions: CMVideoDimensions, quality: VideoQuality, fps: UInt32) throws -> Livekit_SignalRequest {
		Livekit_SignalRequest.with {
			$0.trackSetting = Livekit_UpdateTrackSettings.with {
				$0.trackSids = trackSids
				$0.disabled = enabled == false
				$0.width = UInt32(dimensions.width)
				$0.height = UInt32(dimensions.height)
				$0.quality = quality.toPBType()
				$0.fps = fps
			}
		}
	}
	
	func sendTrackStats(trackSids: [String], enabled: Bool, dimensions: CMVideoDimensions, quality: VideoQuality, fps: UInt32) throws {
		let request = try makeTrackStatsRequest(trackSids: trackSids, enabled: enabled, dimensions: dimensions, quality: quality, fps: fps)
		try enqueue(request: request)
	}
	
	func makeMuteTrackRequest(trackId: String, muted: Bool) -> Livekit_SignalRequest {
		Livekit_SignalRequest.with {
			$0.mute = Livekit_MuteTrackRequest.with {
				$0.sid = trackId
				$0.muted = muted
			}
		}
	}
	
	// MARK: - add track request
	
	func makeAddTrackRequest(publication: Publication) -> Livekit_AddTrackRequest {
		Livekit_AddTrackRequest.with {
			$0.cid = publication.cid
			$0.name = publication.name.rawValue
			$0.type = publication.type
			$0.source = publication.source
			switch publication.type {
			case .video:
				$0.width = UInt32(publication.dimensions.width)
				$0.height = UInt32(publication.dimensions.height)
				$0.layers = publication.layers
			default:
				break
			}
		}
	}
	
	func sendAddTrackRequest(_ request: Livekit_AddTrackRequest, timeout: TimeInterval = SignalHub.defaultTimeOut) async throws -> LiveKitTrackInfo {
		let signalRequest = Livekit_SignalRequest.with {
			$0.addTrack = request
		}
		try enqueue(request: signalRequest)
		
		Logger.plog(level: .debug, oslog: signalHubLog, publicMessage: "waiting for track published response for: \(request)")
		
		let trackPublisher: AnyPublisher<LiveKitTrackInfo, Never>
		
		switch request.type {
		case .video:
			trackPublisher = $videoTracks.publisher.compactMap { $0[request.cid] }.eraseToAnyPublisher()
		case .audio:
			trackPublisher = $audioTracks.publisher.compactMap { $0[request.cid] }.eraseToAnyPublisher()
		case .data:
			trackPublisher = $dataTracks.publisher.compactMap { $0[request.cid] }.eraseToAnyPublisher()
			
		case .UNRECOGNIZED(_):
			trackPublisher = Empty<LiveKitTrackInfo, Never>().eraseToAnyPublisher()
		}
		
		do {
			let response = try await trackPublisher.firstValue(timeout: timeout)
			Logger.plog(level: .debug, oslog: signalHubLog, publicMessage: "received track published response: \(response)")
			return response
		} catch {
			//TODO: sometimes this fails ... I want to find out why this happens sometimes ... 
			Logger.plog(level: .error, oslog: signalHubLog, publicMessage: "failed receive add track response: \(error)")
			throw error
		}
	}
	
	func makeSubscriptionPermissionRequest(allParticipants: Bool, trackPermissions: [Livekit_TrackPermission]) -> Livekit_SignalRequest {
		Livekit_SignalRequest.with {
			$0.subscriptionPermission = Livekit_SubscriptionPermission.with {
				$0.allParticipants = allParticipants
				$0.trackPermissions = trackPermissions.map({ $0 })
			}
		}
	}
	
	func sendUpdateSubscriptionPermission(allParticipants: Bool = true, trackPermissions: [Livekit_TrackPermission] = []) throws {
		let request = makeSubscriptionPermissionRequest(allParticipants: allParticipants, trackPermissions: trackPermissions)
		try enqueue(request: request)
	}
	
	// MARK: - room permissions
	
	func makeSubscriptionPermissionsRequest(allowAll: Bool, trackPermissions: [LiveKitTrackInfo.Permission] = []) -> Livekit_SignalRequest {
		Livekit_SignalRequest.with {
			$0.subscriptionPermission = Livekit_SubscriptionPermission.with {
				$0.allParticipants = allowAll
				$0.trackPermissions = trackPermissions.map { Livekit_TrackPermission($0) }
			}
		}
	}
	
	func sendUpdateSubscriptionPermissions(allowAll: Bool, trackPermissions: [LiveKitTrackInfo.Permission] = []) throws {
		let request = makeSubscriptionPermissionsRequest(allowAll: allowAll, trackPermissions: trackPermissions)
		try enqueue(request: request)
	}
	
	func sendLeaveRequest() throws {
		Logger.plog(level: .debug, oslog: signalHubLog, publicMessage: "sending leave request")
		let request = Livekit_SignalRequest.with {
			$0.leave = Livekit_LeaveRequest.with {
				$0.reason = .clientInitiated
			}
		}
		try enqueue(request: request)
	}
}
