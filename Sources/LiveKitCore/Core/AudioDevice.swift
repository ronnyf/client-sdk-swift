//
//  AudioDevice.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 11/2/23.
//

import AVFAudio
import Combine
@_implementationOnly import WebRTC

public class AudioDevice {
	public enum Errors: Error {
		case noDeliveryFormat
		case noOutputFormat
		case rtcFormat
		case getPlayoutData
		case getPlayoutDataResult
	}
	
	let rtc: AudioDeviceProxy // RTCAudioDevice
	
	public var shouldPlay: some Publisher<Bool, Never> {
		rtc.$shouldPlay.publisher
	}
	
	public var shouldRecord: some Publisher<Bool, Never> {
		rtc.$shouldRecord.publisher
	}
	
	@Publishing var conversionStatus: OSStatus = noErr
	@Publishing var deliveryStatus: OSStatus = noErr
	
	@Publishing var audioConverter: AudioConverterRef?
	
	@Publishing public var audioSourceNode: AVAudioSourceNode?
	@Publishing public var audioSinkNode: AVAudioSinkNode?
	
	private var subscriptions: Set<AnyCancellable> = []
	
	convenience public init() {
		let proxy = AudioDeviceProxy()
		self.init(rtcAudioDevice: proxy)
	}
	
	init(rtcAudioDevice: AudioDeviceProxy) {
		self.rtc = rtcAudioDevice
	}
	
	deinit {
		if let audioConverter {
			AudioConverterDispose(audioConverter)
			self.audioConverter = nil
		}
		#if DEBUG
		print("DEBUG: deinit <AudioDevice>")
		#endif
	}
	
	public func prepareDelivery(recordingFormat: AVAudioFormat) throws {
		// NOTE: AVAudioSinkNode provides audio data with HW sample rate in 32-bit float format,
		// WebRTC requires 16-bit int format, so do the conversion
		guard let deliveryFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
												 sampleRate: recordingFormat.sampleRate,
												 channels: recordingFormat.channelCount,
												 interleaved: true) 
		else { throw Errors.noDeliveryFormat }

		// if there's an old audio converter, get rid of it
		if let audioConverter {
			AudioConverterDispose(audioConverter)
			self.audioConverter = nil
		}
		
		//make a new audio converter, this one definitely matches the recording and delivery formats
		print("DEBUG: attempting to make new audio converter from: \(String(describing: recordingFormat.debugDescription)) -> \(deliveryFormat.debugDescription)")
		AudioConverterNew(recordingFormat.streamDescription, deliveryFormat.streamDescription, &audioConverter)
		print("DEBUG: made new audio converter: \(String(describing: audioConverter))")
		
		let isRecordingPublisher = rtc.$shouldRecord.publisher
		isRecordingPublisher
			.sink { [weak self] isRecording in
				guard let self else { return }
				if isRecording == true {
					self.startAudioBufferDelivery()
				} else {
					self.stopAudioDelivery()
				}
			}
		.store(in: &subscriptions)
	}
	
	func startAudioBufferDelivery() {
		print("DEBUG: starting audio delivery")
		audioSinkNode = AVAudioSinkNode { [rtc, audioConverter] timestamp, framecount, audioBufferList in
			let payload = AudioPayload(timestamp: timestamp, frameCount: framecount, audioBufferList: audioBufferList)
			return rtc.deliver(payload, converter: audioConverter)
		}
	}
	
	public func stopAudioDelivery() {
		print("DEBUG: stopping audio delivery")
		audioSinkNode = nil
	}
	
	public func prepareAudioCapture(outputFormat: AVAudioFormat) throws {
		print("DEBUG: preparing audio capture with format: \(outputFormat)")
		guard let rtcFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
											sampleRate: outputFormat.sampleRate,
											channels: outputFormat.channelCount,
											interleaved: true) else { throw Errors.rtcFormat }
		
		let isPlayingPublisher = rtc.$shouldPlay.publisher
		isPlayingPublisher
			.sink { [weak self] isPlaying in
				guard let self else { return }
				if isPlaying == true {
					self.startAudioCapture(format: rtcFormat)
				} else {
					self.stopAudioCapture()
				}
			}
			.store(in: &subscriptions)
	}
	
	public func startAudioCapture(format: AVAudioFormat, inputBus: Int = 0) {
		print("DEBUG: starting audio capture")
		
		audioSourceNode = AVAudioSourceNode(format: format, renderBlock: { [rtc] (isSilence: UnsafeMutablePointer<ObjCBool>, timestamp: UnsafePointer<AudioTimeStamp>, frameCount: AVAudioFrameCount, audioBufferList: UnsafeMutablePointer<AudioBufferList>) in
			// rtc delivers the payload directly to the audio source node ...
			guard let getPlayoutData = rtc.audioDeviceDelegate?.getPlayoutData else { return -1 }
			var flags: AudioUnitRenderActionFlags = []
			let playResult = getPlayoutData(&flags, timestamp, inputBus, frameCount, audioBufferList)
			return playResult
		})
	}
	
	public func stopAudioCapture() {
		print("DEBUG: stopping audio capture")
		audioSourceNode = nil
	}
	
	func teardown() {
		// TODO: need some inspration about how to do this cleanly
		stopAudioDelivery()
		subscriptions.removeAll(keepingCapacity: true)
	}
}

struct AudioPayload {
	let timestamp: UnsafePointer<AudioTimeStamp>
	let frameCount: AVAudioFrameCount
	let audioBufferList: UnsafePointer<AudioBufferList>
	
	func convert(audioConverter: AudioConverterRef) -> AudioBufferList {
		var convertedAudioBufferList = audioBufferList.pointee
		AudioConverterConvertComplexBuffer(audioConverter, frameCount, audioBufferList, &convertedAudioBufferList)
		return convertedAudioBufferList
	}
}

class AudioDeviceProxy: NSObject, RTCAudioDevice {
	var deviceInputSampleRate: Double {
		avAudioSession.sampleRate
	}
	
	var deviceOutputSampleRate: Double {
		avAudioSession.sampleRate
	}
	
	var inputIOBufferDuration: TimeInterval {
		avAudioSession.ioBufferDuration
		
	}
	
	var outputIOBufferDuration: TimeInterval {
		avAudioSession.ioBufferDuration
	}
	
	var inputNumberOfChannels: Int {
		avAudioSession.inputNumberOfChannels
	}
	
	var outputNumberOfChannels: Int {
		avAudioSession.outputNumberOfChannels
	}
	
	var inputLatency: TimeInterval {
		avAudioSession.inputLatency
	}
	
	var outputLatency: TimeInterval {
		avAudioSession.outputLatency
	}
	
	var isInitialized: Bool {
		audioDeviceDelegate != nil
	}
	
	var avAudioSession: AVAudioSession {
		AVAudioSession.sharedInstance()
	}
	
	@Publishing var shouldPlay: Bool = false
	@Publishing var shouldRecord: Bool = false
	
	@Publishing var audioDeviceDelegate: RTCAudioDeviceDelegate?
	@Publishing var audioRenderActionFlags: AudioUnitRenderActionFlags = []
	
	override init() {
		super.init()
		print("DEBUG: init \(self)")
	}
	
	#if DEBUG
	deinit {
		print("DEBUG: deinit \(self)")
	}
	#endif
	
	func initialize(with delegate: RTCAudioDeviceDelegate) -> Bool {
		print("DEBUG: initialize with delegate \(delegate)")
		guard self.audioDeviceDelegate == nil else { return false }
		self.audioDeviceDelegate = delegate
		return true
	}
	
	@discardableResult
	func terminateDevice() -> Bool {
		shouldPlay = false
		shouldRecord = false
		
		_shouldPlay.subject.send(completion: .finished)
		_shouldRecord.subject.send(completion: .finished)
		
		audioDeviceDelegate = nil
		_audioDeviceDelegate.subject.send(completion: .finished)
		return true
	}
	
	var isPlayoutInitialized: Bool {
		isInitialized && playoutInitialized
	}
	
	private var playoutInitialized = false
	
	func initializePlayout() -> Bool {
		guard playoutInitialized == false else { return false }
		playoutInitialized = true
		return true
	}
	
	var isPlaying: Bool {
		shouldPlay
	}
	
	func startPlayout() -> Bool {
		shouldPlay = true
		print("DEBUG: startPlayout()")
		return true
	}
	
	func stopPlayout() -> Bool {
		print("DEBUG: stopPlayout()")
		shouldPlay = false
		return true
	}
	
	var isRecordingInitialized: Bool {
		isInitialized && recordingInitialized
	}
	
	private var recordingInitialized = false
	
	func initializeRecording() -> Bool {
		guard recordingInitialized == false else { return false }
		recordingInitialized = true
		return recordingInitialized
	}
	
	var isRecording: Bool {
		shouldRecord
	}
	
	func startRecording() -> Bool {
		guard shouldRecord == false else { return false }
		shouldRecord = true
		return true
	}
	
	func stopRecording() -> Bool {
		guard shouldRecord == true else { return false }
		shouldRecord = false
		return true
	}
}

extension AudioDeviceProxy {
	func deliver(_ payload: AudioPayload, converter: AudioConverterRef?) -> OSStatus {
		guard let deliverRecordedData = audioDeviceDelegate?.deliverRecordedData else { return noErr }
		
		if let converter {
			let convertedAudioBufferList = payload.convert(audioConverter: converter)
			return deliverRecordedData(&audioRenderActionFlags, payload.timestamp, 0, payload.frameCount, withUnsafePointer(to: convertedAudioBufferList, { $0 }), nil, nil)
		} else {
			return deliverRecordedData(&audioRenderActionFlags, payload.timestamp, 0, payload.frameCount, payload.audioBufferList, nil, nil)
		}
	}
}
