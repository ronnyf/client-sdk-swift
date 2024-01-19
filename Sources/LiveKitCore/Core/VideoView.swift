//
//  VideoView.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 9/5/23.
//

import AVKit
import Combine
import CoreMedia
@preconcurrency import OSLog
import SwiftUI
@_implementationOnly import WebRTC

// This View is part of the LiveKitCore module because it needs to have knowledge of WebRTC...
public struct LiveKitVideoView: View {
	
	let mediaTrack: MediaStreamTrack
	@State private var isVisible: Bool = false
	@Binding private var videoGravity: AVLayerVideoGravity
	
	public init(videoGravity: Binding<AVLayerVideoGravity>, mediatrack: @autoclosure () -> MediaStreamTrack) {
		_videoGravity = videoGravity
		self.mediaTrack = mediatrack()
	}
	
	public var body: some View {
		RemoteVideoView(isVisible: $isVisible, videoGravity: $videoGravity, mediaTrack: mediaTrack.rtcMediaStreamTrack)
			.onAppear {
				isVisible = true
			}
			.onDisappear {
				isVisible = false
			}
			.onChange(of: isVisible) { newValue in
				UIApplication.shared.isIdleTimerDisabled = newValue
			}
	}
}

#if os(iOS)
@MainActor
class RemoteVideoRenderView: UIView {
	
	static let log = OSLog(subsystem: "VideoRenderer", category: "LiveKitCore")
	
	class override var layerClass: AnyClass {
		AVSampleBufferDisplayLayer.self
	}
	
	var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer {
		guard let sampleBufferLayer = layer as? AVSampleBufferDisplayLayer else {
			fatalError("Expected `AVSampleBufferDisplayLayer` type for layer. Check the RemoteVideoRenderView.layerClass implementation.")
		}
		return sampleBufferLayer
	}
	
	lazy var videoRenderer: VideoRenderer = {
		VideoRenderer(sampleBufferDisplayLayer: sampleBufferDisplayLayer)
	}()
	
	override func layoutSubviews() {
		super.layoutSubviews()
		Logger.plog(level: .debug, oslog: RemoteVideoRenderView.log, publicMessage: "layout subviews: \(self)")
	}
	
	class VideoRenderer: NSObject, RTCVideoRenderer {
		
		weak var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer?
		
		init(sampleBufferDisplayLayer: AVSampleBufferDisplayLayer) {
			sampleBufferDisplayLayer.preventsDisplaySleepDuringVideoPlayback = true
			self.sampleBufferDisplayLayer = sampleBufferDisplayLayer
			super.init()
			Logger.plog(level: .debug, oslog: RemoteVideoRenderView.log, publicMessage: "init: \(self)")
		}
		
		deinit {
			Logger.plog(level: .debug, oslog: RemoteVideoRenderView.log, publicMessage: "deinit: \(self)")
		}
		
		func setSize(_ size: CGSize) {
			Logger.plog(oslog: RemoteVideoRenderView.log, publicMessage: "setSize: \(size)")
		}
		
		func renderFrame(_ frame: RTCVideoFrame?) {
			guard let frame else { return }
			let sampleBuffer: CMSampleBuffer?
			
			if let pb = frame.buffer as? RTCCVPixelBuffer {
				sampleBuffer = makeSampleBuffer(from: pb.pixelBuffer, timestamp: frame.timeStampNs)
			} else if let frameBuffer = frame.buffer as? VideoFrameBuffer {
				sampleBuffer = frameBuffer.sampleBuffer
			} else {
				Logger.plog(level: .error, oslog: RemoteVideoRenderView.log, publicMessage: "frameBuffer type \(type(of: frame.buffer)) is unsupported!")
				return
			}
			
			guard let sampleBuffer else {
				Logger.plog(level: .error, oslog: RemoteVideoRenderView.log, publicMessage: "samplebuffer is nil! please file a bug.")
				return
			}
			
#if swift(>=5.9)
			if #available(iOS 17.0, *) {
				sampleBufferDisplayLayer?.sampleBufferRenderer.enqueue(sampleBuffer)
			} else {
				DispatchQueue.main.async {
					self.sampleBufferDisplayLayer?.enqueue(sampleBuffer)
				}
			}
#endif
		}
		private func makeSampleBuffer(from pixelBuffer: CVPixelBuffer, timestamp: Int64) -> CMSampleBuffer? {
			// Get the video format description
			var formatDescription: CMFormatDescription?
			CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
														 imageBuffer: pixelBuffer,
														 formatDescriptionOut: &formatDescription)
			
			// Create the sample timing
			var sampleTiming = CMSampleTimingInfo(duration: CMTime.invalid,
												  presentationTimeStamp: CMTime(value: timestamp, timescale: CMTimeScale(NSEC_PER_SEC)),
												  decodeTimeStamp: CMTime.invalid)
			
			// Create the sample buffer
			var sampleBuffer: CMSampleBuffer?
			CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault,
											   imageBuffer: pixelBuffer,
											   dataReady: true,
											   makeDataReadyCallback: nil,
											   refcon: nil,
											   formatDescription: formatDescription!,
											   sampleTiming: &sampleTiming,
											   sampleBufferOut: &sampleBuffer)
			
			return sampleBuffer
		}
	}
}

struct RemoteVideoView: UIViewRepresentable {
	
	typealias UIViewType = RemoteVideoRenderView
	
	@Binding var isVisible: Bool
	@Binding var videoGravity: AVLayerVideoGravity
	let mediaTrack: RTCMediaStreamTrack
	
	init(isVisible: Binding<Bool>, videoGravity: Binding<AVLayerVideoGravity>, mediaTrack: @autoclosure () -> RTCMediaStreamTrack) {
		self._isVisible = isVisible
		self._videoGravity = videoGravity
		self.mediaTrack = mediaTrack()
	}
	
	func makeCoordinator() -> PipCoordinator {
		PipCoordinator()
	}
	
	func makeUIView(context: Context) -> UIViewType {
		let view = UIViewType()
		view.sampleBufferDisplayLayer.videoGravity = videoGravity
		context.coordinator.configurePip(for: view.sampleBufferDisplayLayer)
		return view
	}
	
	func updateUIView(_ uiView: UIViewType, context: Context) {
		uiView.sampleBufferDisplayLayer.videoGravity = videoGravity
		
		if let videoTrack = mediaTrack as? RTCVideoTrack {
			Logger.plog(oslog: RemoteVideoRenderView.log, publicMessage: "uiview: \(uiView)")
			if isVisible == true {
				Logger.plog(oslog: RemoteVideoRenderView.log, publicMessage: "adding videoTrack: \(videoTrack.trackId) to renderer: \(uiView.videoRenderer)")
				videoTrack.add(uiView.videoRenderer)
			} else {
				Logger.plog(oslog: RemoteVideoRenderView.log, publicMessage: "removing videoTrack: \(videoTrack.trackId) from renderer: \(uiView.videoRenderer)")
				videoTrack.remove(uiView.videoRenderer)
			}
		}
	}
	
	class PipCoordinator: NSObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
		
		var controller: AVPictureInPictureController?
		weak var displayLayer: AVSampleBufferDisplayLayer?
		private var currentVideoGravity: AVLayerVideoGravity?
		
		func configurePip(for displayLayer: AVSampleBufferDisplayLayer) {
			guard controller == nil else { return }
			let contentSource = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: displayLayer, playbackDelegate: self)
			let controller = AVPictureInPictureController(contentSource: contentSource)
			controller.canStartPictureInPictureAutomaticallyFromInline = true
			controller.delegate = self
			self.controller = controller
			self.displayLayer = displayLayer
		}
		
		func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
			currentVideoGravity = displayLayer?.videoGravity
			displayLayer?.videoGravity = .resizeAspect
			print("DEBUG: pipMode: ON")
		}
	
		func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
			print("DEBUG: pipMode: OFF")
			if let currentVideoGravity {
				displayLayer?.videoGravity = currentVideoGravity
			}
		}
		
		// MARK: sample buffer playback delegate
		
		// this should not be supported, we don't allow to 'pause' the stream
		func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {}
		
		func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
			return false
		}
		
		// Time ranges with finite duration should always contain the current time of the sample buffer display layer's timebase.
		// Clients should return a time range with a duration of kCMTimeInfinity to indicate live content.
		// When there is no content to play, they should return kCMTimeRangeInvalid. 
		// This method will be called whenever -[AVPictureInPictureController invalidatePlaybackState] is called and at other times as needed by the system.
		func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
			return CMTimeRange(start: .zero, duration: .positiveInfinity)
		}
		
		// The rendered size, in pixels, of Picture in Picture content.
		// This method is called when the system Picture in Picture window changes size.
		// Delegate take the new render size and AVPictureInPictureController.isPictureInPictureActive into account
		// when choosing media variants in order to avoid uncessary decoding overhead.
		func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
			print("DEBUG: didTransitionToRenderSize: \(newRenderSize)")
			let pipSize = CGSize(width: Double(newRenderSize.width), height: Double(newRenderSize.height))
			pictureInPictureController.playerLayer.bounds = CGRect(origin: .zero, size: pipSize)
			displayLayer?.bounds = CGRect(origin: .zero, size: pipSize)
		}
		
		func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime) async {
			print("DEBUG: skipByInterval: \(skipInterval)")
		}
	}
}
#endif

struct VideoView_Previews: PreviewProvider {
	static var previews: some View {
		Text("TODO")
	}
}
