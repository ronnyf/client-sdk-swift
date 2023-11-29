//
//  AudioDevice.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 11/2/23.
//

import AVFAudio
import Combine
import OSLog
@_implementationOnly import WebRTC

public class AudioDevice {
	
	public enum Errors: Error {
		case noDeliveryFormat
		case noOutputFormat
		case rtcFormat
		case getPlayoutData
		case getPlayoutDataResult
	}
	
	let audioDeviceLog = OSLog(subsystem: "AudioDevice", category: "LiveKitCore")
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
		Logger.plog(level: .debug, oslog: audioDeviceLog, publicMessage: "deinit <AudioDevice>")
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
		Logger.plog(level: .debug, oslog: audioDeviceLog, publicMessage: "attempting to make new audio converter from: \(String(describing: recordingFormat.debugDescription)) -> \(deliveryFormat.debugDescription)")
		AudioConverterNew(recordingFormat.streamDescription, deliveryFormat.streamDescription, &audioConverter)
		Logger.plog(level: .debug, oslog: audioDeviceLog, publicMessage: "made new audio converter: \(String(describing: audioConverter))")
		
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
		Logger.plog(oslog: audioDeviceLog, publicMessage: "starting audio delivery")
		audioSinkNode = AVAudioSinkNode { [rtc, audioConverter] timestamp, framecount, audioBufferList in
			let payload = AudioPayload(timestamp: timestamp, frameCount: framecount, audioBufferList: audioBufferList)
			return rtc.deliver(payload, converter: audioConverter)
		}
	}
	
	public func stopAudioDelivery() {
		Logger.plog(oslog: audioDeviceLog, publicMessage: "stopping audio delivery")
		audioSinkNode = nil
	}
	
	public func prepareAudioCapture(outputFormat: AVAudioFormat) throws {
		Logger.plog(level: .debug, oslog: audioDeviceLog, publicMessage: "preparing audio capture with format: \(outputFormat)")
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
		Logger.plog(oslog: audioDeviceLog, publicMessage: "starting audio capture")
		
		audioSourceNode = AVAudioSourceNode(format: format, renderBlock: { [rtc] (isSilence: UnsafeMutablePointer<ObjCBool>, timestamp: UnsafePointer<AudioTimeStamp>, frameCount: AVAudioFrameCount, audioBufferList: UnsafeMutablePointer<AudioBufferList>) in
			// rtc delivers the payload directly to the audio source node ...
			guard let getPlayoutData = rtc.audioDeviceDelegate?.getPlayoutData else { return -1 }
			var flags: AudioUnitRenderActionFlags = []
			let playResult = getPlayoutData(&flags, timestamp, inputBus, frameCount, audioBufferList)
			return playResult
		})
	}
	
	public func stopAudioCapture() {
		Logger.plog(oslog: audioDeviceLog, publicMessage: "stopping audio capture")
		audioSourceNode = nil
	}
	
	func teardown() {
		Logger.plog(oslog: audioDeviceLog, publicMessage: "teardown")
		// TODO: need some inspration about how to do this more neatly...
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
	
	let audioDeviceProxyLog = OSLog(subsystem: "RTCAudioDevice", category: "LiveKitCore")
	
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
		Logger.plog(level: .debug, oslog: audioDeviceProxyLog, publicMessage: "init \(self)")
	}
	
	deinit {
		Logger.plog(level: .debug, oslog: audioDeviceProxyLog, publicMessage: "deinit \(self)")
	}
	
	func initialize(with delegate: RTCAudioDeviceDelegate) -> Bool {
		Logger.plog(level: .debug, oslog: audioDeviceProxyLog, publicMessage: "initialize with delegate \(delegate)")
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
		Logger.plog(oslog: audioDeviceProxyLog, publicMessage: "startPlayout()")
		return true
	}
	
	func stopPlayout() -> Bool {
		shouldPlay = false
		Logger.plog(oslog: audioDeviceProxyLog, publicMessage: "stopPlayout()")
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
		Logger.plog(oslog: audioDeviceProxyLog, publicMessage: "startRecording()")
		return true
	}
	
	func stopRecording() -> Bool {
		guard shouldRecord == true else { return false }
		shouldRecord = false
		Logger.plog(oslog: audioDeviceProxyLog, publicMessage: "stopRecording()")
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
