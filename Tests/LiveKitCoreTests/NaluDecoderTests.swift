//
//  NaluDecoderTests.swift
//  LiveKitCoreTests
//
//  Created by Falk, Ronny on 12/4/23.
//

import XCTest
@testable import LiveKitCore
import CoreMedia

final class NaluDecoderTests: XCTestCase {

	var buffer: Data?
	var nalu_test_buffer_0: [UInt8] = [0xAA, 0xBB, 0xCC]
	var nalu_test_buffer_1: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF]
	var sps_pps_buffer: [UInt8] = [
		// SPS nalu.
		0x00, 0x00, 0x00, 0x01, 0x27, 0x42, 0x00, 0x1E, 0xAB, 0x40, 0xF0, 0x28,
		0xD3, 0x70, 0x20, 0x20, 0x20, 0x20,
		// PPS nalu.
		0x00, 0x00, 0x00, 0x01, 0x28, 0xCE, 0x3C, 0x30
	]
	
	var sps_pps_not_at_start_buffer: [UInt8] = [
		// Add some non-SPS/PPS NALUs at the beginning
		0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0xFF, 
		0x00, 0x00, 0x00, 0x01, 0xAB, 0x33, 0x21,
		// SPS nalu.
		0x00, 0x00, 0x01, 0x27, 0x42, 0x00, 0x1E, 0xAB, 0x40, 0xF0, 0x28, 0xD3,
		0x70, 0x20, 0x20, 0x20, 0x20,
		// PPS nalu.
		0x00, 0x00, 0x01, 0x28, 0xCE, 0x3C, 0x30
	]
	
    override func setUpWithError() throws {
		let testBundle = Bundle(for: type(of: self))
		guard let url = testBundle.url(forResource: "encodedImage", withExtension: "bin") else { fatalError() }
		buffer = try Data(contentsOf: url)
		XCTAssertNotNil(buffer)
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

	func testReadRawNalu() throws {
		let annex_b_test_data = Data([0xAA])
		guard let nalu = Nalu(data: annex_b_test_data, headerBytes: 0) else { XCTFail(); return }
		XCTAssertEqual(nalu.kind, .endOfSequence) // 0xAA & 0x1F = 0x0A (decimal: 10)
		XCTAssertEqual(nalu.size, 1)
		XCTAssertEqual(nalu.bytes, annex_b_test_data)
	}
	
	func testReadSingleNalu() throws {
		let annex_b_test_data = Data([0x00, 0x00, 0x00, 0x01, 0xAA])
		guard let nalu = Nalu(data: annex_b_test_data, headerBytes: 4) else { XCTFail(); return }
		XCTAssertEqual(nalu.size, 1)
		XCTAssertEqual(nalu.kind, .endOfSequence)
		XCTAssertEqual(nalu.bytes, Data([0xAA]))
	}
	
	func testReadSingleNalu3ByteHeader() throws {
		let annex_b_test_data = Data([0x00, 0x00, 0x01, 0xAA])
		guard let nalu = Nalu(data: annex_b_test_data, headerBytes: 3) else { XCTFail(); return }
		XCTAssertEqual(nalu.size, 1)
		XCTAssertEqual(nalu.kind, .endOfSequence)
		XCTAssertEqual(nalu.bytes, Data([0xAA]))
	}
	
	func testReadMultipleNalus() throws {
		let annex_b_test_data = Data([0x00, 0x00, 0x00, 0x01, // < 4 byte header
									  0xFF, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0xFF,
									  0x00, 0x00, 0x01,       // < 3 byte header
									  0xAA, 0xBB])
		let expectedSizes = [8, 2]
		for (index, nalu) in NaluSequence(base: annex_b_test_data).enumerated() {
			print(nalu)
			let expectedSize = expectedSizes[index]
			XCTAssertEqual(expectedSize, nalu.size)
		}
	}
	
	func test_sps_pps_parsing() throws {
		guard let buffer else {
			XCTFail()
			return
		}
		
		let nalus = NaluSequence(base: buffer)
		
		var parameterSets: [UnsafePointer<Data.Element>] = []
		for nalu in nalus.filter({ $0.kind == .sps || $0.kind == .pps }) {
			nalu.bytes.withUnsafeBytes({
				if let ba = $0.assumingMemoryBound(to: UInt8.self).baseAddress {
					parameterSets.append(ba)
				}
			})
		}
		
		XCTAssertEqual(parameterSets.count, 2)
		
		let paramterSetSizes = Array(nalus.map { $0.size })
		
		var formatDescription: CMFormatDescription?
		let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
			allocator: kCFAllocatorDefault,
			parameterSetCount: 2,
			parameterSetPointers: parameterSets,
			parameterSetSizes: paramterSetSizes,
			nalUnitHeaderLength: 4,
			formatDescriptionOut: &formatDescription)
		
		XCTAssertNotNil(formatDescription)
		XCTAssertEqual(status, noErr)
	}
	
	func test_sps_pps_alt_parsing() throws {
		let naluBuffer = Data(sps_pps_not_at_start_buffer)
		XCTAssertEqual(naluBuffer.count, sps_pps_not_at_start_buffer.count)
		
		let expecting = [(NaluType.undefined, 1), (NaluType.endOfStream, 3), (NaluType.sps, 14), (NaluType.pps, 4)]
		for (index, nalu) in NaluSequence(base: naluBuffer).enumerated() {
			let expected = expecting[index]
			XCTAssertEqual(nalu.kind, expected.0)
			XCTAssertEqual(nalu.size, expected.1)
		}
	}
	
	func test_makeSingleNalu() throws {
		let expected_buffer = Data([0x00, 0x00, 0x00, 0x03, 0xAA, 0xBB, 0xCC])
		guard var nalu = Nalu(data: Data(nalu_test_buffer_0), headerBytes: 0) else { XCTFail(); return }
		nalu.convertToAvcc()
		XCTAssertEqual(nalu.buffer, expected_buffer)
	}
	
	func test_writeMultipleNalus() throws {
		let expected_buffer = Data([0x00, 0x00, 0x00, 0x03, 0xAA, 0xBB, 0xCC,
									0x00, 0x00, 0x00, 0x04, 0xDE, 0xAD, 0xBE, 0xEF])
		
		let inputData = [nalu_test_buffer_0, nalu_test_buffer_1]
		let avccBuffer = inputData.reduce(into: Data(), { partialResult, values in
			guard let nalu = Nalu(data: Data(values), headerBytes: 0) else { fatalError() }
			partialResult.append(nalu.convertedToAvcc().buffer)
		})
		
		XCTAssertEqual(avccBuffer, expected_buffer)
	}
	
	func testH264AnnexBBufferToCMSampleBuffer() throws {
		let annex_b_test_data = Data([
			0x00, 0x00, 0x00, 0x01, // start sequence 4 bytes
			0x01, 0x00, 0x00, 0xFF, // first chunk, 4 bytes
			0x00, 0x00, 0x01,       // start sequence 3 bytes
			0xAA, 0xFF,             // second chunk, 2 bytes
			0x00, 0x00, 0x01,       // start sequence 3 bytes
			0xBB                    // third chunk, 1 byte, will not fit into output array (yes it does!!)
		])
		
		let expected_cmsample_data = Data([
			0x00, 0x00, 0x00, 0x04, // avcc header, size 4
			0x01, 0x00, 0x00, 0xFF, // first chunk, 4 bytes
			0x00, 0x00, 0x00, 0x02, // avcc header, size 2
			0xAA, 0xFF,             // second chunk, 2 bytes
			0x00, 0x00, 0x00, 0x01, // avcc header, size 1
			0xBB                    // third chunk, 1 byte (yes it will fit into the output array)
		])
		
		let nalus = NaluSequence(base: annex_b_test_data)
		let avccBuffer = nalus.reduce(into: Data(), { partialResult, nalu in
			partialResult.append(nalu.convertedToAvcc().buffer)
		})
		XCTAssertEqual(expected_cmsample_data, avccBuffer)
	}
	
	func test_formatDescription() throws {
		guard let buffer else {
			XCTFail()
			return
		}
		
		var parameterSets: [UnsafePointer<UInt8>] = []
		var parameterSizes: [Int] = []
		let nalus = NaluSequence(base: buffer)
		for nalu in nalus {
			switch nalu.kind {
			case .sps, .pps:
				nalu.bytes.withUnsafeBytes {
					if let ptr = $0.assumingMemoryBound(to: UInt8.self).baseAddress {
						parameterSets.append(ptr)
						parameterSizes.append($0.count)
					}
				}
				
			default:
				break
				
			}
		}
		
		let decoder = PassthroughVideoDecoder()
		let fd = decoder.makeFormatDescription(parameterSets: parameterSets, parameterSizes: parameterSizes)
		XCTAssertNotNil(fd)
	}
	
	func test_makeEmptyBlockBuffer() throws {
		let decoder = PassthroughVideoDecoder()
		let blockBuffer = decoder.makeEmptyBlockBuffer(capacity: 100)
		XCTAssertNotNil(blockBuffer)
		XCTAssertEqual(blockBuffer?.dataLength, 0)
	}
	
	func test_makeBlockBuffer() throws {
		let decoder = PassthroughVideoDecoder()
		let blockBuffer = decoder.makeBlockBuffer(blockLength: 100)
		XCTAssertNotNil(blockBuffer)
		XCTAssertEqual(blockBuffer?.dataLength, 100)
	}
	
	func test_moveBlockBuffer() throws {
		guard let naluBuffer = buffer else {
			XCTFail()
			return
		}
				
		let nalus = NaluSequence(base: naluBuffer).lazy.filter { $0.kind == .idr }
		for nalu in nalus {
			
			let decoder = PassthroughVideoDecoder()
			
			let emptyBlockBuffer = decoder.makeEmptyBlockBuffer(capacity: UInt32(nalu.avccBufferSize))
			XCTAssertNotNil(emptyBlockBuffer)
			
			let blockBuffer = decoder.makeBlockBuffer(blockLength: nalu.avccBufferSize)
			XCTAssertNotNil(blockBuffer)
			XCTAssertEqual(blockBuffer?.dataLength, nalu.avccBufferSize)
			
			let updateResult = decoder.updateBlockBuffer(blockBuffer!, from: nalu.avccBuffer)
			XCTAssertEqual(updateResult, noErr)
			XCTAssertEqual(blockBuffer!.dataLength, nalu.avccBufferSize)
			
			try emptyBlockBuffer?.append(bufferReference: blockBuffer!)
			XCTAssertEqual(emptyBlockBuffer!.dataLength, nalu.avccBufferSize)
		}
	}
}

