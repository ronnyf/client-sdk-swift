//
//  Session+Publish.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 9/29/23.
//

import Foundation
import Combine
import CoreMedia
import AVFoundation
@_implementationOnly import WebRTC

extension LiveKitSession {
	
	public func startMediaStream(_ videoSource: some Publisher<CMSampleBuffer, Never>, videoDimensions: CMVideoDimensions, videoRotation: some Publisher<CGFloat, Never>, audioEnabled: Bool = true) async throws {
		Logger.log(oslog: sessionLog, message: "publishVideo: >>>")
		
		let videoPublication = Publication.videoPublication(dimensions: videoDimensions)
		let audioPublication = Publication.audioPublication()
		
		//wait for transceiver to be created...
		async let videoPublishingResult = signalHub.createVideoTransceiver(videoPublication: videoPublication)
		async let audioPublishingResult = signalHub.createAudioTransceiver(audioPublication: audioPublication, enabled: audioEnabled)
		
		let addVideoTrackRequest = signalHub.makeAddTrackRequest(publication: videoPublication)
		let addAudioTrackRequest = signalHub.makeAddTrackRequest(publication: audioPublication)
		
		//TODO: let's think about how to make those not just fake sendable but actually sendable
		async let videoTrackInfoResult = signalHub.sendAddTrackRequest(addVideoTrackRequest)
		async let audioTrackInfoResult = signalHub.sendAddTrackRequest(addAudioTrackRequest)
		
		let (videoPublishing, audioPublishing, audioTrackInfo, videoTrackInfo) = try await (videoPublishingResult, audioPublishingResult, audioTrackInfoResult, videoTrackInfoResult)
		
		await signalHub.negotiate()
		let connectionState = signalHub.peerConnectionFactory.publishingPeerConnection.connectionState
		_ = try await connectionState.firstValue(timeout: 15, condition: { $0 == .connected })
		
		let videoTrackSids = [videoTrackInfo.trackSid]
		try signalHub.sendTrackStats(
			trackSids: videoTrackSids,
			enabled: true,
			dimensions: videoPublication.dimensions,
			quality: .high, fps: 30
		)
		
		try signalHub.sendMuteTrack(trackSid: audioTrackInfo.trackSid, muted: audioEnabled == false)
		
		let videoOrientationPublisher = videoRotation.removeDuplicates().map { RTCVideoRotation($0) }
		let videoFrames = Publishers.CombineLatest(videoSource, videoOrientationPublisher).compactMap { sampleBuffer, rotation -> RTCVideoFrame? in
			guard let imageBuffer = sampleBuffer.imageBuffer else { return nil }
			
			let seconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
			let timeStampNs = Int64(seconds * Float64(NSEC_PER_SEC))
			
			let pixelBuffer = RTCCVPixelBuffer(pixelBuffer: imageBuffer)
			//TODO: check rotation parameter here
			let frame = RTCVideoFrame(buffer: pixelBuffer, rotation: rotation ?? ._0, timeStampNs: timeStampNs)
			
			let sourceDimensions = CMVideoDimensions(width: Int32(CVPixelBufferGetWidth(imageBuffer)), height: Int32(CVPixelBufferGetHeight(imageBuffer)))
			guard sourceDimensions.isEncodeSafe else { return nil }
			return frame
		}.stream()
		
		await withThrowingTaskGroup(of: Void.self) { group in
			group.addTask {
				let videoSource = videoPublishing.source
				let videoCapturer = RTCVideoCapturer(delegate: videoSource)
				for await videoFrame in videoFrames {
					videoSource.capturer(videoCapturer, didCapture: videoFrame)
					try Task.checkCancellation()
				}
			}
			
			let _ = try? await group.next()
			group.cancelAll()
		}
		
		try signalHub.sendMuteTrack(trackSid: videoTrackInfo.trackSid, muted: true)
		try signalHub.sendMuteTrack(trackSid: audioTrackInfo.trackSid, muted: true)
		
		signalHub.setMediaTrack(videoPublishing.track, enabled: false)
		signalHub.setMediaTrack(audioPublishing.track, enabled: false)
		
		try await signalHub.removeTrack(videoPublishing.track.trackId)
		try await signalHub.removeTrack(audioPublishing.track.trackId)
					
		//publisher should negotiate and tell the other side that we remove the track(s)
		await signalHub.negotiate()
	}
}
