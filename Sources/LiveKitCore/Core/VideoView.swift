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

#if os(iOS)
public typealias ViewRepresentable = UIViewRepresentable
public typealias ViewType = UIView
#elseif os(macOS)
public typealias ViewRepresentable = NSViewRepresentable
public typealias ViewType = NSView
#endif

public struct LiveKitVideoView: View {
	
	var mediaTrack: () -> MediaTrack
	@State private var isVisible: Bool = false
	
	public init(_ mediatrack: @autoclosure @escaping () -> MediaTrack) {
		self.mediaTrack = mediatrack
	}
	
	public var body: some View {
		RTCMTLVideoViewWrapper(isVisible: $isVisible, mediaTrack: mediaTrack())
			.onAppear {
				isVisible = true
			}
			.onDisappear {
				isVisible = false
			}
	}
}

struct RTCMTLVideoViewWrapper: ViewRepresentable {
	
	@Binding var isVisible: Bool
	var mediaTrack: () -> MediaTrack
	
	init(isVisible: Binding<Bool>, mediaTrack: @escaping @autoclosure () -> MediaTrack) {
		self._isVisible = isVisible
		self.mediaTrack = mediaTrack
	}
	
	func makeCoordinator() -> Coordinator {
		Coordinator()
	}

#if os(iOS)
	typealias UIViewType = ViewType
	
	func makeUIView(context: Context) -> UIViewType {
		makeView(context: context)
	}
	
	func updateUIView(_ uiView: UIViewType, context: Context) {
		updateView(uiView, context: context)
	}
	
#elseif os(macOS)
	typealias NSViewType = ViewType
	
	func makeNSView(context: Context) -> NSViewType {
		makeView(context: context)
	}
	
	func updateNSView(_ nsView: NSViewType, context: Context) {
		updateView(nsView, context: context)
	}
#endif
	
	func makeView(context: Context) -> RTCMTLVideoView {
		context.coordinator.view
	}
	
	func updateView(_ view: ViewType, context: Context) {
		//the rtcMediaStreamTrack is internal only, we don't want to expose this to the outside world.
		guard let videoTrack = mediaTrack().rtcMediaStreamTrack as? RTCVideoTrack else {
			fatalError() // or just bail?
		}
		
		let renderer = context.coordinator.view
		
		if isVisible == true {
			videoTrack.add(renderer)
		} else {
			videoTrack.remove(renderer)
		}
	}
	
	class Coordinator {
		lazy var view = RTCMTLVideoView()
	}
}

struct VideoView_Previews: PreviewProvider {
	static var previews: some View {
		Text("TODO")
	}
}
