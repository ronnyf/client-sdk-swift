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
		Logger.plog(oslog: sessionLog, publicMessage: "publishVideo: >>>")
		defer {
			Logger.plog(oslog: sessionLog, publicMessage: "publishVideo: <<<")
		}
		
		let videoPublication = Publication.videoPublication(dimensions: videoDimensions)
		let audioPublication = Publication.audioPublication()
		
		let addVideoTrackRequest = signalHub.makeAddTrackRequest(publication: videoPublication)
		let addAudioTrackRequest = signalHub.makeAddTrackRequest(publication: audioPublication)

		// wait for transceivers to be created and track requests to be sent
		async let videoTransmitterTask = signalHub.createVideoTransmitter(videoPublication: videoPublication, enabled: true)
		async let audioTransmitterTask = signalHub.createAudioTransmitter(audioPublication: audioPublication, enabled: audioEnabled)
		async let videoTrackInfoResult = signalHub.sendAddTrackRequest(addVideoTrackRequest)
		async let audioTrackInfoResult = signalHub.sendAddTrackRequest(addAudioTrackRequest)
		
		let (audioTrackInfo, videoTrackInfo, videoTransmitter, audioTransmitter) = try await (audioTrackInfoResult, videoTrackInfoResult, videoTransmitterTask, audioTransmitterTask)
		
		Logger.plog(oslog: sessionLog, publicMessage: "got audio transmitter: \(String(describing: audioTransmitter))")
		Logger.plog(oslog: sessionLog, publicMessage: "got video transmitter: \(String(describing: videoTransmitter))")
		
		signalHub.audioTransmitter = audioTransmitter
		signalHub.videoTransmitter = videoTransmitter
		
		audioTransmitter?.trackInfo = audioTrackInfo
		videoTransmitter?.trackInfo = videoTrackInfo
		
		try await signalHub.negotiateAndWait(signalingState: .stable)
		Logger.plog(level: .debug, oslog: sessionLog, publicMessage: "got .stable signaling state after negotiation")
		
		try await signalHub.waitForConnectedState()
		Logger.plog(level: .debug, oslog: sessionLog, publicMessage: "got .connected connection state after negotiation")
		
		let videoTrackSids = [videoTrackInfo.trackSid]
		try signalHub.sendTrackStats(
			trackSids: videoTrackSids,
			enabled: true,
			dimensions: videoPublication.dimensions,
			quality: .high, fps: 30
		)
		
		try signalHub.sendMuteTrack(trackSid: audioTrackInfo.trackSid, muted: audioEnabled == false)
		
		let videoOrientationPublisher = videoRotation.map { RTCVideoRotation($0) }
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
				guard let videoSource = videoTransmitter?.source as? RTCVideoSource else { return }
				for await videoFrame in videoFrames {
				let videoCapturer = RTCVideoCapturer(delegate: videoSource)
					videoSource.capturer(videoCapturer, didCapture: videoFrame)
					try Task.checkCancellation()
				}
			}
			
			let _ = try? await group.next()
			group.cancelAll()
		}
		
		[videoTrackInfo, audioTrackInfo].forEach {
			try? signalHub.sendMuteTrack(trackSid: $0.trackSid, muted: true)
		}
				
		if let videoTransmitter {
			videoTransmitter.enabled = false
			try await signalHub.removeTrack(videoTransmitter.trackId)
		}
		
		if let audioTransmitter {
			audioTransmitter.enabled = false
			try await signalHub.removeTrack(audioTransmitter.trackId)
		}
		
		//publisher should negotiate and tell the other side that we remove the track(s)
		await signalHub.negotiate()
		signalHub.audioTransmitter = nil
		signalHub.videoTransmitter = nil
	}
}
