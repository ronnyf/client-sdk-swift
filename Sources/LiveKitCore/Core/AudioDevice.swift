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
		
		let isRecordingPublisher = rtc.$shouldRecord.publisher.dropFirst()
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
		print("DEBUG: made audio sink node: \(audioSinkNode!)")
	}
	
	public func stopAudioDelivery() {
		print("DEBUG: stopping audio delivery")
		audioSinkNode = nil
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
	
	var audioRenderActionFlags: AudioUnitRenderActionFlags = []
	
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
		return true
	}
	
	func stopPlayout() -> Bool {
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
//			print("DEBUG: delivering converted audio: \(converter.debugDescription)")
			return deliverRecordedData(&audioRenderActionFlags, payload.timestamp, 0, payload.frameCount, withUnsafePointer(to: convertedAudioBufferList, { $0 }), nil, nil)
		} else {
			return deliverRecordedData(&audioRenderActionFlags, payload.timestamp, 0, payload.frameCount, payload.audioBufferList, nil, nil)
		}
	}
}

//		NotificationCenter.default.addObserver(self,
//											   selector: #selector(self.handleInterruption(_:)),
//											   name: AVAudioSession.interruptionNotification,
//											   object: AVAudioSession.sharedInstance())
//		NotificationCenter.default.addObserver(self,
//											   selector: #selector(self.handleRouteChange(_:)),
//											   name: AVAudioSession.routeChangeNotification,
//											   object: AVAudioSession.sharedInstance())
//		NotificationCenter.default.addObserver(self,
//											   selector: #selector(self.handleMediaServicesWereReset(_:)),
//											   name: AVAudioSession.mediaServicesWereResetNotification,
//											   object: AVAudioSession.sharedInstance())
//}

//	func setupAudioEngine() throws {
//		do {
//			try rtc.avAudioSession.setCategory(.playAndRecord, options: .defaultToSpeaker)
//		} catch {
//			print("Could not set the audio category: \(error.localizedDescription)")
//		}
//
//		audioEngine.isAutoShutdownEnabled = true
//
//		let useVoiceProcessingAudioUnit = rtc.avAudioSession.supportsVoiceProcessing
//		// NOTE: Toggle voice processing state over outputNode, not to eagerly create inputNote.
//		// Also do it just after creation of AVAudioEngine to avoid random crashes observed when voice processing changed on later stages.
//		if audioEngine.outputNode.isVoiceProcessingEnabled != useVoiceProcessingAudioUnit {
//			do {
//				// Use VPIO to as I/O audio unit.
//				try audioEngine.outputNode.setVoiceProcessingEnabled(useVoiceProcessingAudioUnit)
//			}
//			catch let e {
//				print("setVoiceProcessingEnabled error: \(e)")
//				return
//			}
//		}
//
//		let inputNode = audioEngine.inputNode
//		// Configure the microphone input.
//		let recordingFormat = inputNode.outputFormat(forBus: 0)
//
//// TODO: later we add speech recognition
////		inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
////			self.recognitionRequest?.append(buffer)
////		}
//
//		audioEngine.prepare()
//		try audioEngine.start()
//	}
//
//	func resetAudioEngine() {
//		if audioEngine.isRunning {
//			audioEngine.stop()
//		}
//	}
//
//	func updateAudioEngine() {
//		rtc.updateEngine()
//	}

//	@objc
//	func handleInterruption(_ notification: Notification) {
//		guard let userInfo = notification.userInfo,
//			  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
//			  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
//
//		switch type {
//		case .began:
//			// Interruption begins so you need to take appropriate actions.
//			break
//
//		case .ended:
//			do {
//				try AVAudioSession.sharedInstance().setActive(true)
//			} catch {
//				print("Could not set the audio session to active: \(error)")
//			}
//
//			if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
//				let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
//				if options.contains(.shouldResume) {
//					// Interruption ends. Resume playback.
//				} else {
//					// Interruption ends. Don't resume playback.
//				}
//			}
//		@unknown default:
//			fatalError("Unknown type: \(type)")
//		}
//	}
//
//	@objc
//	func handleRouteChange(_ notification: Notification) {
//		guard let userInfo = notification.userInfo,
//			  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
//			  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
//			  let routeDescription = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription else { return }
//		switch reason {
//		case .newDeviceAvailable:
//			print("newDeviceAvailable")
//		case .oldDeviceUnavailable:
//			print("oldDeviceUnavailable")
//		case .categoryChange:
//			print("categoryChange")
//			print("New category: \(AVAudioSession.sharedInstance().category)")
//		case .override:
//			print("override")
//		case .wakeFromSleep:
//			print("wakeFromSleep")
//		case .noSuitableRouteForCategory:
//			print("noSuitableRouteForCategory")
//		case .routeConfigurationChange:
//			print("routeConfigurationChange")
//		case .unknown:
//			print("unknown")
//		@unknown default:
//			fatalError("Really unknown reason: \(reason)")
//		}
//
//		print("Previous route:\n\(routeDescription)")
//		print("Current route:\n\(AVAudioSession.sharedInstance().currentRoute)")
//	}
//
//	@objc
//	func handleMediaServicesWereReset(_ notification: Notification) {
//		resetAudioEngine()
//		try? setupAudioEngine()
//	}
