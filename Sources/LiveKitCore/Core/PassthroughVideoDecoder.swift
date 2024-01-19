//
//  PassthroughVideoDecoder.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 11/30/23.
//

import AVFoundation
import Combine
import CoreMedia
import Foundation
import OSLog
@_implementationOnly import WebRTC

class PassthroughVideoDecoder: NSObject, RTCVideoDecoder {
	
	static let log = OSLog(subsystem: "PassthroughVideoDecoder", category: "LiveKitCore")
	
	fileprivate let WEBRTC_VIDEO_CODEC_OK: Int = 0
	fileprivate let WEBRTC_VIDEO_CODEC_ERROR: Int = -1
	
	var callback: RTCVideoDecoderCallback?
	
	deinit {
		CMMemoryPoolInvalidate(memoryPool)
		Logger.plog(level: .debug, oslog: Self.log, publicMessage: "deinit \(self)")
	}
	
	func setCallback(_ callback: @escaping RTCVideoDecoderCallback) {
		self.callback = callback
		Logger.plog(level: .debug, oslog: Self.log, publicMessage: "did set callback \(String(describing: callback))")
	}
	
	func startDecode(withNumberOfCores numberOfCores: Int32) -> Int {
		Logger.plog(level: .debug, oslog: Self.log, publicMessage: "start decode")
		return WEBRTC_VIDEO_CODEC_OK
	}
	
	func release() -> Int {
		Logger.plog(level: .debug, oslog: Self.log, publicMessage: "release")
		callback = nil
		return WEBRTC_VIDEO_CODEC_OK
	}
	
	func implementationName() -> String {
		"h264-passthrough"
	}
	
	// MARK: - decode tools support
	
	let memoryPool: CMMemoryPool = CMMemoryPoolCreate(options: nil)
	lazy var blockAllocator = {
		CMMemoryPoolGetAllocator(memoryPool)
	}()
	
	private var sampleFormatDescription: CMFormatDescription?
	private let videoFrameBuffer = VideoFrameBuffer()
	private lazy var videoFrame = RTCVideoFrame(buffer: videoFrameBuffer, rotation: ._0, timeStampNs: 0)
	
	//MARK: decode
	
	func decode(_ encodedImage: RTCEncodedImage, missingFrames: Bool, codecSpecificInfo info: RTCCodecSpecificInfo?, renderTimeMs: Int64) -> Int {
		// Get the NALUs for the purpose of creating the format description
		// we have an Annex-B buffer (RTP stream) and we need to get to AVCC...
		
		var parameterSizes: [Int] = []
		var parameterSets: [UnsafePointer<UInt8>] = []
		let sampleBlockBuffer = makeEmptyBlockBuffer(capacity: UInt32(encodedImage.buffer.count))
		var sampleTimings: [CMSampleTimingInfo] = []
		
		var result = WEBRTC_VIDEO_CODEC_OK
		
		guard sampleBlockBuffer != nil, callback != nil else {
			Logger.plog(level: .debug, oslog: Self.log, publicMessage: "ignoring frame")
			return result
		}
		
		for nalu in NaluSequence(base: encodedImage.buffer) {
			switch nalu.kind {
			case .sps:
				nalu.bytes.withUnsafeBytes {
					if let baseAddress = $0.assumingMemoryBound(to: UInt8.self).baseAddress {
						parameterSets = [baseAddress]
					}
				}
				parameterSizes = [nalu.size]
				
			case .pps:
				nalu.bytes.withUnsafeBytes {
					if let baseAddress = $0.assumingMemoryBound(to: UInt8.self).baseAddress {
						parameterSets.append(baseAddress)
					}
				}
				parameterSizes.append(nalu.size)
				// CMSampleBuffer's blockBuffer (pt 1)
				sampleFormatDescription = makeFormatDescription(parameterSets: parameterSets, parameterSizes: parameterSizes)
				
			default:
				do {
					let blockBuffer = makeBlockBuffer(blockLength: nalu.avccBufferSize)
					guard let blockBuffer else {
						Logger.plog(level: .error, oslog: Self.log, publicMessage: "failed to make block buffer from nalu: \(nalu)")
						return WEBRTC_VIDEO_CODEC_ERROR
					}
					
					let result = updateBlockBuffer(blockBuffer, from: nalu.avccBuffer)
					guard result == noErr else {
						Logger.plog(level: .error, oslog: Self.log, publicMessage: "failed to update block buffer from nalu: \(nalu)")
						return WEBRTC_VIDEO_CODEC_ERROR
					}
					
					// CMSampleBuffer's blockBuffer (pt 2)
					try sampleBlockBuffer?.append(bufferReference: blockBuffer)
					
					let convertedTimestamp = Int64(encodedImage.timeStamp) * 90 // 90khz timestamp conversion x * 90000 / 1000
					let presentationTime = CMTime(value: CMTimeValue(convertedTimestamp), timescale: CMTimeScale(NSEC_PER_SEC));
					let decodedTime = CMTime(value: CMTimeValue(CFAbsoluteTimeGetCurrent()), timescale: CMTimeScale(1))
					
					let timingInfo = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: presentationTime, decodeTimeStamp: decodedTime)
					
					// CMSampleBuffer's blockBuffer timing info (pt 3)
					sampleTimings.append(timingInfo)
				} catch {
					Logger.plog(level: .error, oslog: Self.log, publicMessage: error.localizedDescription)
					return WEBRTC_VIDEO_CODEC_ERROR
				}
			}
		}
		
		// finish current sample buffer
		result = emitSampleBuffer(sampleBlockBuffer, sampleFormatDescription: sampleFormatDescription, sampleTimings: sampleTimings, imageTimeStamp: encodedImage.timeStamp)
		return result
	}
	
	func emitSampleBuffer(_ sampleBlockBuffer: CMBlockBuffer?, sampleFormatDescription: CMFormatDescription?, sampleTimings: [CMSampleTimingInfo], imageTimeStamp: UInt32) -> Int {
		// this happens in the 1st pass, we just should not do anything, returning an error requests a new key frame (afaik)
		// we don't want that either. Chances are, the next frame is a key frame.
		guard let sampleBlockBuffer else { return WEBRTC_VIDEO_CODEC_OK }
		
		guard let sampleFormatDescription, sampleTimings.isEmpty == false else {
			Logger.plog(level: .error, oslog: Self.log, publicMessage: "format description invalid or no sample timeings: \(sampleTimings)")
			return WEBRTC_VIDEO_CODEC_ERROR
		}
		
		guard let sampleBuffer = makeSampleBuffer(formatDescription: sampleFormatDescription, blockBuffer: sampleBlockBuffer, timingInfo: sampleTimings) else {
			Logger.plog(level: .error, oslog: Self.log, publicMessage: "failed to make sample buffer from format: \(sampleFormatDescription), blockBuffer: \(sampleBlockBuffer), timingInfo: \(sampleTimings)")
			return WEBRTC_VIDEO_CODEC_ERROR
		}

		videoFrameBuffer.sampleBuffer = sampleBuffer
		videoFrame.timeStamp = RTCTimestampIntegerType(imageTimeStamp)
		self.callback?(videoFrame)
		
		return sampleTimings.last?.presentationTimeStamp != nil ? WEBRTC_VIDEO_CODEC_OK : WEBRTC_VIDEO_CODEC_ERROR
	}
	
	func makeFormatDescription(parameterSets: [UnsafePointer<UInt8>], parameterSizes: [Int]) -> CMFormatDescription? {
		var formatDescription: CMFormatDescription?
		let _ = CMVideoFormatDescriptionCreateFromH264ParameterSets(
			allocator: kCFAllocatorDefault,
			parameterSetCount: parameterSets.count,
			parameterSetPointers: parameterSets,
			parameterSetSizes: parameterSizes,
			nalUnitHeaderLength: 4,
			formatDescriptionOut: &formatDescription)
		return formatDescription
	}
	
	private func makeSampleBuffer(formatDescription: CMFormatDescription, blockBuffer: CMBlockBuffer, timingInfo: [CMSampleTimingInfo]) -> CMSampleBuffer? {
		// Create a CMSampleBuffer
		var sampleBuffer: CMSampleBuffer?
		let _ = CMSampleBufferCreate(
			allocator: kCFAllocatorDefault,
			dataBuffer: blockBuffer,
			dataReady: true,
			makeDataReadyCallback: nil,
			refcon: nil,
			formatDescription: formatDescription,
			sampleCount: 1,
			sampleTimingEntryCount: 1,
			sampleTimingArray: timingInfo,
			sampleSizeEntryCount: 0,
			sampleSizeArray: nil,
			sampleBufferOut: &sampleBuffer
		)
		
		return sampleBuffer
	}
	
	func makeEmptyBlockBuffer(capacity: UInt32, flags: CMBlockBufferFlags = 0) -> CMBlockBuffer? {
		var blockBuffer: CMBlockBuffer?
		let _ = CMBlockBufferCreateEmpty(
			allocator: kCFAllocatorDefault,
			capacity: capacity,
			flags: flags,
			blockBufferOut: &blockBuffer)
		
		return blockBuffer
	}
	
	func makeBlockBuffer(memoryBlock: UnsafeMutableRawPointer? = nil, blockLength: Int, dataLength: Int? = nil, flags: CMBlockBufferFlags = kCMBlockBufferAssureMemoryNowFlag) -> CMBlockBuffer? {
		var blockBuffer: CMBlockBuffer?
		let _ = CMBlockBufferCreateWithMemoryBlock(
			allocator: kCFAllocatorDefault,
			memoryBlock: memoryBlock,
			blockLength: blockLength,
			blockAllocator: blockAllocator,
			customBlockSource: nil,
			offsetToData: 0,
			dataLength: dataLength ?? blockLength,
			flags: flags,
			blockBufferOut: &blockBuffer)
		
		return blockBuffer
	}
	
	func updateBlockBuffer(_ blockBuffer: CMBlockBuffer, from source: Data) -> OSStatus {
		var blockBufferSize: Int = 0
		var blockBufferPointer: UnsafeMutablePointer<CChar>?
		
		let status = CMBlockBufferGetDataPointer(
			blockBuffer,
			atOffset: 0,
			lengthAtOffsetOut: nil,
			totalLengthOut: &blockBufferSize,
			dataPointerOut: &blockBufferPointer
		)
		
		guard status == noErr else { return status }
		
		source.withUnsafeBytes { avccBufferPtr in
			precondition(avccBufferPtr.count == blockBufferSize)
			if let source = avccBufferPtr.assumingMemoryBound(to: CChar.self).baseAddress {
				blockBufferPointer?.update(from: source, count: blockBufferSize)
			}
		}
		
		return status
	}
		
	func makePixelBuffer(from fileURL: URL) -> CVPixelBuffer? {
		guard let image = UIImage(contentsOfFile: fileURL.path) else {
			return nil
		}
		
		let imageWidth = Int(image.size.width)
		let imageHeight = Int(image.size.height)
		
		let options: [String: Any] = [
			kCVPixelBufferCGImageCompatibilityKey as String: true,
			kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
		]
		
		var pixelBuffer: CVPixelBuffer?
		let status = CVPixelBufferCreate(kCFAllocatorDefault,
										 imageWidth,
										 imageHeight,
										 kCVPixelFormatType_32BGRA,
										 options as CFDictionary,
										 &pixelBuffer)
		
		guard status == kCVReturnSuccess, let unwrappedPixelBuffer = pixelBuffer else {
			return nil
		}
		
		CVPixelBufferLockBaseAddress(unwrappedPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
		defer {
			CVPixelBufferUnlockBaseAddress(unwrappedPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
		}
		
		let baseAddress = CVPixelBufferGetBaseAddress(unwrappedPixelBuffer)
		let colorSpace = CGColorSpaceCreateDeviceRGB()
		
		guard let context = CGContext(data: baseAddress,
									  width: imageWidth,
									  height: imageHeight,
									  bitsPerComponent: 8,
									  bytesPerRow: CVPixelBufferGetBytesPerRow(unwrappedPixelBuffer),
									  space: colorSpace,
									  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
			return nil
		}
		
		context.draw(image.cgImage!, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
		
		return unwrappedPixelBuffer
	}
}

extension RTCFrameType {
	var _debugDescription: String {
		let typeDescription: String
		switch self {
		case .emptyFrame:
			typeDescription = "emptyFrame"
		case .audioFrameSpeech:
			typeDescription = "audioFrameSpeech"
		case .audioFrameCN:
			typeDescription = "audioFrameCN"
		case .videoFrameKey:
			typeDescription = "videoFrameKey"
		case .videoFrameDelta:
			typeDescription = "videoFrameDelta"
		@unknown default:
			typeDescription = "??"
		}
		
		return "<RTCFrameType \(typeDescription)>"
	}
}

#if LKCORE_USE_EBAY_WEBRTC
typealias RTCIntegerType = Int
typealias RTCTimestampIntegerType = Int
#else
// this WebRTC framework defines:
typealias RTCTimestampIntegerType = Int32
// v----width, height in RTCVideoFrame/VideoFrameBuffer as (int) / Int32 types
typealias RTCIntegerType = Int32
#endif

//FIXME: This could/should be possible with standard webrtc api!
class VideoFrameBuffer: NSObject, RTCVideoFrameBuffer {
	var width: RTCIntegerType = 0
	var height: RTCIntegerType = 0
	
	var sampleBuffer: CMSampleBuffer? {
		didSet {
			guard let format = sampleBuffer?.formatDescription else { return }
			width = RTCIntegerType(format.dimensions.width)
			height = RTCIntegerType(format.dimensions.height)
		}
	}
	
	init(sampleBuffer: CMSampleBuffer? = nil) {
		self.sampleBuffer = sampleBuffer
		super.init()
	}
	
	#if DEBUG
	deinit {
		print("DEBUG: deinit \(self)")
	}
	#endif
	
	func toI420() -> RTCI420BufferProtocol {
		fatalError("Not supported")
	}
}
