//
//  VideoView.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 9/5/23.
//

import SwiftUI
import Combine
@_implementationOnly import WebRTC

// This View is part of the LiveKitCore module because it needs to have knowledge of WebRTC...
public struct LiveKitVideoView: View {
	
	let mediaTrack: MediaStreamTrack
	@State private var isVisible: Bool = false
	
	public init(mediatrack: @autoclosure () -> MediaStreamTrack) {
		self.mediaTrack = mediatrack()
	}
	
	public var body: some View {
		RTCMTLVideoViewWrapper(isVisible: $isVisible, mediaTrack: mediaTrack.rtcMediaStreamTrack)
			.onAppear {
				isVisible = true
			}
			.onDisappear {
				isVisible = false
			}
	}
}

#if os(iOS)
// The RTCMediaStreamTrack type is internal only, we don't want to expose this to the outside world.
struct RTCMTLVideoViewWrapper: UIViewRepresentable {
	
	typealias UIViewType = RTCMTLVideoView
	
	@Binding var isVisible: Bool
	let mediaTrack: RTCMediaStreamTrack
	
	init(isVisible: Binding<Bool>, mediaTrack: @autoclosure () -> RTCMediaStreamTrack) {
		self._isVisible = isVisible
		self.mediaTrack = mediaTrack()
	}
	
	func makeUIView(context: Context) -> UIViewType {
		let view = UIViewType()
		view.videoContentMode = .scaleAspectFit
		return view
	}
	
	func updateUIView(_ uiView: UIViewType, context: Context) {
		if let videoTrack = mediaTrack as? RTCVideoTrack {
			if isVisible == true {
				videoTrack.add(uiView)
			} else {
				videoTrack.remove(uiView)
			}
		}
	}
}
#endif

#if os(macOS)
struct RTCMTLVideoViewWrapper: NSViewRepresentable {
	
	typealias NSViewType = RTCMTLVideoView
	
	@Binding var isVisible: Bool
	let mediaTrack: RTCMediaStreamTrack
	
	init(isVisible: Binding<Bool>, mediaTrack: @autoclosure () -> RTCMediaStreamTrack) {
		self._isVisible = isVisible
		self.mediaTrack = mediaTrack()
	}
	
	func makeNSView(context: Context) -> NSViewType {
		let view = NSViewType()
// FIXME: on macOS this seems to work differently. Let's look at this when the time is right.
//		view.videoContentMode = .scaleAspectFit
		return view
	}
	
	func updateNSView(_ uiView: NSViewType, context: Context) {
		if let videoTrack = mediaTrack as? RTCVideoTrack {
			if isVisible == true {
				videoTrack.add(uiView)
			} else {
				videoTrack.remove(uiView)
			}
		}
	}
}
#endif

struct VideoView_Previews: PreviewProvider {
	static var previews: some View {
		Text("TODO")
	}
}
