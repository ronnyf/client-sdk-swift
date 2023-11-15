//
//  Receiver.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 11/15/23.
//

import Combine
import Foundation
@_implementationOnly import WebRTC

public class VideoTransmitter: MediaTransmitter {
	init(sender: RTCRtpSender, videoTrack: RTCVideoTrack, videoSource: RTCVideoSource) {
		super.init(sender: sender, track: videoTrack, source: videoSource)
	}
}

public class AudioTransmitter: MediaTransmitter {
	init(sender: RTCRtpSender, audioTrack: RTCAudioTrack, audioSource: RTCAudioSource) {
		super.init(sender: sender, track: audioTrack, source: audioSource)
	}
}

@objcMembers
public class MediaTransmitter: @unchecked Sendable, Identifiable {
	let sender: RTCRtpSender
	let track: RTCMediaStreamTrack
	let source: RTCMediaSource
	var trackInfo: LiveKitTrackInfo?
	
	public var muted: Bool {
		get {
			track.isEnabled == false
		}
		set {
			track.isEnabled = !newValue
		}
	}
	
	public var enabled: Bool {
		get {
			track.isEnabled
		}
		set {
			track.isEnabled = newValue
		}
	}
	
	public var trackId: String {
		trackInfo?.trackSid ?? track.trackId
	}
	
	@Publishing var trackEnabled: Bool
	public var trackEnabledPublisher: some Publisher<Bool, Never> {
		$trackEnabled.publisher
	}
	
	public var trackMutedPublisher: some Publisher<Bool, Never> {
		$trackEnabled.publisher.map { !$0 }
	}
	
	private var observationToken: NSKeyValueObservation?
	
	nonisolated init(sender: RTCRtpSender, track: RTCMediaStreamTrack, source: RTCMediaSource) {
		self.sender = sender
		self.track = track
		self.source = source
		self._trackEnabled = Publishing<Bool>(wrappedValue: track.isEnabled)
		
		// first, we observe (remember kvo?) the objc property of track, this should not fire immediately
		observationToken = track.observe(\.isEnabled, options: [.new]) { _, change in
			print("DEBUG: KVO: track.isEnabled: \(change)")
			guard let enabled = change.newValue, self.enabled != self.trackEnabled else { return }
			self.trackEnabled = enabled
		}
	}
	
	deinit {
		print("DEBUG: deinit <AudioTransmitter \(track)>")
	}
}
