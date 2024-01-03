//
//  Nalu.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 12/4/23.
//

import Foundation

// inspired by https://github.com/tidwall/Avios/blob/master/Avios/NALU.swift
// and https://github.com/shogo4405/HaishinKit.swift/blob/1660479586b3eff87e532cf1021410211c9607ed/Sources/MPEG/AVCNALUnit.swift
// and of course https://chromium.googlesource.com/external/webrtc/+/refs/heads/main/common_video/h264/h264_common.h
// the spec: https://datatracker.ietf.org/doc/html/rfc3984#section-1.3

/*
 https://datatracker.ietf.org/doc/html/rfc3984#section-5.2
 
 The payload format defines three different basic payload structures.
 A receiver can identify the payload structure by the first byte of
 the RTP payload, which co-serves as the RTP payload header and, in
 some cases, as the first byte of the payload.  This byte is always
 structured as a NAL unit header.  The NAL unit type field indicates
 which structure is present.  The possible structures are as follows:
 
 Single NAL Unit Packet: Contains only a single NAL unit in the
 payload.  The NAL header type field will be equal to the original NAL
 unit type; i.e., in the range of 1 to 23, inclusive.  Specified in
 (secion 5.6)[https://datatracker.ietf.org/doc/html/rfc3984#section-5.6]
 
 Type   Packet    Type name                        Section
 ---------------------------------------------------------
 0      undefined                                    -
 1-23   NAL unit  Single NAL unit packet per H.264   5.6
 24     STAP-A    Single-time aggregation packet     5.7.1
 25     STAP-B    Single-time aggregation packet     5.7.1
 26     MTAP16    Multi-time aggregation packet      5.7.2
 27     MTAP24    Multi-time aggregation packet      5.7.2
 28     FU-A      Fragmentation unit                 5.8
 29     FU-B      Fragmentation unit                 5.8
 30-31  undefined                                    -

 */

public enum NaluType: UInt8 {
	// The size of a shortened NALU start sequence {0 0 1}, that may be used if
	// not the first NALU of an access unit or an SPS or PPS block.
	@usableFromInline
	static let naluShortStartSequence: Data = Data([0x00, 0x00, 0x01])
	
	case undefined = 0
	case codedSlice = 1
	case dataPartitionA = 2
	case dataPartitionB = 3
	case dataPartitionC = 4
	case idr = 5 // (Instantaneous Decoding Refresh) Picture
	case sei = 6 // (Supplemental Enhancement Information)
	case sps = 7 // (Sequence Parameter Set)
	case pps = 8 // (Picture Parameter Set)
	case accessUnitDelimiter = 9
	case endOfSequence = 10
	case endOfStream = 11
	case filterData = 12
	// 13-23 [extended]
}

extension NaluType: CustomStringConvertible {
	
	public var description: String {
		switch self {
		case .undefined:
			return "undefined"
		case .codedSlice:
			return "codedSlice"
		case .dataPartitionA:
			return "dataPartitionA"
		case .dataPartitionB:
			return "dataPartitionB"
		case .dataPartitionC:
			return "dataPartitionC"
		case .idr:
			return "idr"
		case .sei:
			return "sei"
		case .sps:
			return "sps"
		case .pps:
			return "pps"
		case .accessUnitDelimiter:
			return "accessUnitDelimiter"
		case .endOfSequence:
			return "endOfSequence"
		case .endOfStream:
			return "endOfStream"
		case .filterData:
			return "filterData"
		}
	}
}

public struct Nalu {
	
	public let kind: NaluType
	
	@usableFromInline
	private(set) var headerSize: Int
	
	public var buffer: Data
	
	public var size: Int {
		buffer.count - headerSize
	}
	
	public var avccBufferSize: Int {
		size + MemoryLayout<UInt32>.stride
	}
	
	public var bytes: Data {
		guard headerSize > 0 else { return buffer }
		return buffer[buffer.startIndex.advanced(by: headerSize)..<buffer.endIndex]
	}
	
	public var avccBuffer: Data {
		precondition(size < UInt32.max)
		
		let avccHeaderSize = MemoryLayout<UInt32>.stride
		var avccBuffer: Data
		if headerSize < avccHeaderSize {
			let prependSize = avccHeaderSize - headerSize
			avccBuffer = Data(repeating: 0x00, count: prependSize)
			avccBuffer.append(buffer)
		} else {
			avccBuffer = buffer
		}
		
		let startRange = (buffer.startIndex..<buffer.startIndex.advanced(by: avccHeaderSize))
		var bufferSize = UInt32(size).bigEndian
		let sizeData = Data(bytes: &bufferSize, count: avccHeaderSize)
		avccBuffer.replaceSubrange(startRange, with: sizeData)
		return avccBuffer
	}
	
	@inlinable
	public init?(data: Data, headerBytes: Int = 4) {
		guard data.count > headerBytes else { return nil }
		let rawType = data[data.startIndex.advanced(by: headerBytes)]
		self.kind = NaluType(rawValue: rawType & 0x1F) ?? .undefined
		self.headerSize = headerBytes
		self.buffer = data
	}
	
	func convertedToAvcc() -> Nalu {
		var naluCopy = self
		naluCopy.convertToAvcc()
		return naluCopy
	}
	
	mutating func convertToAvcc() {
		precondition(size < UInt32.max)
		
		let avccHeaderSize = MemoryLayout<UInt32>.stride
		if headerSize < avccHeaderSize {
			let prependSize = avccHeaderSize - headerSize
			var newBuffer = Data(repeating: 0x00, count: prependSize)
			newBuffer.append(buffer)
			buffer = newBuffer
			headerSize += prependSize
		}
		precondition(headerSize == avccHeaderSize)
		precondition(buffer.count > headerSize)
		
		let startRange = (buffer.startIndex..<buffer.startIndex.advanced(by: headerSize))
		var bufferSize = UInt32(size).bigEndian
		let sizeData = Data(bytes: &bufferSize, count: headerSize)
		buffer.replaceSubrange(startRange, with: sizeData)
	}
}

extension Nalu: CustomStringConvertible {
	public var description: String {
		"<Nalu: type: \(kind), size: \(size), data: \(buffer.prefix(16).map { $0 })>"
	}
}
