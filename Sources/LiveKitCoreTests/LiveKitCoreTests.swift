//
//  LiveKitCoreTests.swift
//  LiveKitCoreTests
//
//  Created by Falk, Ronny on 4/26/23.
//

import XCTest
import Combine
@testable import LiveKitCore

final class LiveKitCoreTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
	
	func test_convenience_streams() async throws {
		let x = Int.random(in: (100..<1000))
		let numbers = (x..<(x+10)).map { $0 }
		
		var asyncNums: [Int] = []
		for await num in numbers.publisher.stream() {
			asyncNums.append(num)
		}
		
		XCTAssertEqual(numbers, asyncNums)
	}
	
	func test_convenience_streams_throwing() async throws {
		struct SomeError: Error {}
		let pub = Fail(outputType: Int.self, failure: SomeError())
	
		do {
			for try await _ in pub.throwingStream() {}
		} catch _ as SomeError {
			//success
		} catch {
			XCTFail("wrong error type: \(error)")
		}
	}
	
	func test_convenience_publisher_firstValue() async throws {
		let values = [1,2]
		let result = try await values.publisher.firstValue()
		XCTAssertEqual(result, values.first)
	}

	func test_convenience_publisher_firstValue_timeout() async throws {
		let publisher = PassthroughSubject<Int, Never>()
		let timeout: TimeInterval = TimeInterval.random(in: (1..<3))
		let start = CFAbsoluteTimeGetCurrent()
		do {
			let _ = try await publisher.firstValue(timeout: timeout)
		} catch _ as TimeoutError {
			//success
			let end = CFAbsoluteTimeGetCurrent()
			let delta = abs(timeout - abs(end - start))
			XCTAssertTrue(delta < timeout * 0.1) //10% gets us at least into the ball park of ok, maybe?
		} catch {
			XCTFail("wrong error type: \(error)")
		}
	}
	
	// MARK: - message chennel
	
	func test_messageChannel_1() {
		
	}
	
	func test_SerialExecutor() async throws {
		let q = DispatchSerialQueue(label: "TestQ")
		let a = TestActor(dispatchQueue: q)
		await withTaskGroup(of: Void.self) { group in
			for _ in (0..<100) {
				group.addTask {
					await a.test()
				}
				group.addTask {
					await a.test2()
				}
				
				group.addTask {
					await a.test3()
				}
			}
		}
		
		Task.detached {
			await a.test()
			await a.test2()
			await a.test3()
		}
		
		print("DONE")
	}
	
	func testBinarySearch() {
		var values: [Int] = []
		
		let range = (0..<100)
		let valueRange = (0..<1000)
		range.forEach { _ in
			let value = Int.random(in: valueRange)
			values.insert(value, at: values.binarySearch(value))
		}
		XCTAssertEqual(values, values.sorted())
	}
}

actor TestActor {
	let dispatchQueue: DispatchSerialQueue
	nonisolated var unownedExecutor: UnownedSerialExecutor {
		dispatchQueue.asUnownedSerialExecutor()
	}
	
	init(dispatchQueue: DispatchSerialQueue) {
		self.dispatchQueue = dispatchQueue
	}
	
	func test() {
		dispatchPrecondition(condition: .onQueue(dispatchQueue))
		print("on queue: \(dispatchQueue)")
	}
	
	func test2() {
		dispatchPrecondition(condition: .onQueue(dispatchQueue))
		print("on queue: \(dispatchQueue)")
	}	
	
	func test3() {
		dispatchPrecondition(condition: .onQueue(dispatchQueue))
		print("on queue: \(dispatchQueue)")
	}
}
