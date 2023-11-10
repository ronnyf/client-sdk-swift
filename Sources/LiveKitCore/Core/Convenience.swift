//
//  Convenience.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 4/24/23.
//

import Foundation
import Combine

//MARK: - support extensions

extension Publisher {
	public func stream() -> AsyncStream<Output> where Failure == Never {
		AsyncStream<Output> { continuation in
			let subscription = self
				.sink { completion in
					continuation.finish()
				} receiveValue: { value in
					continuation.yield(value)
				}
			
			continuation.onTermination = { @Sendable _ in
				subscription.cancel()
			}
		}
	}
	
	public func throwingStream() -> AsyncThrowingStream<Output, Error> {
		AsyncThrowingStream<Output, Error> { continuation in
			let subscription = self
				.sink { completion in
					switch completion {
					case .failure(let error):
						continuation.finish(throwing: error)
					case .finished:
						continuation.finish()
					}
				} receiveValue: { value in
					continuation.yield(value)
				}
			
			continuation.onTermination = { @Sendable _ in
				subscription.cancel()
			}
		}
	}
	
	public func stream<T>(
		filter: @escaping (Self.Output) -> Bool,
		map transform: @escaping (Self.Output) -> T
	) -> AsyncStream<T> where Failure == Never {
		AsyncStream<T> { continuation in
			let subscription = self
				.filter(filter)
				.map { transform($0) }
				.sink { completion in
					continuation.finish()
				} receiveValue: { value in
					continuation.yield(value)
				}
			
			continuation.onTermination = { @Sendable _ in
				subscription.cancel()
			}
		}
	}
	
	public func stream<P: Publisher>(flatMap transform: @escaping (Self.Output) -> P) -> AsyncStream<P.Output> where Failure == Never {
		AsyncStream<P.Output> { continuation in
			let subscription = self
				.flatMap { transform($0) }
				.sink { completion in
					continuation.finish()
				} receiveValue: { value in
					continuation.yield(value)
				}
			
			continuation.onTermination = { @Sendable _ in
				subscription.cancel()
			}
		}
	}
	
	public func throwingStream<T>(
		filter: @escaping (Self.Output) -> Bool,
		map transform: @escaping (Self.Output) throws -> T
	) -> AsyncThrowingStream<T, Failure> where Failure == Error {
		AsyncThrowingStream<T, Failure> { continuation in
			let subscription = self
				.filter(filter)
				.tryMap(transform)
				.sink { completion in
					switch completion {
					case .finished:
						continuation.finish()
						
					case .failure(let error):
						continuation.finish(throwing: error)
					}
				} receiveValue: { value in
					continuation.yield(value)
				}
			
			continuation.onTermination = { @Sendable _ in
				subscription.cancel()
			}
		}
	}
}

extension Publisher {
	public func firstValue() async throws -> Self.Output where Failure == Never, Self.Output: Sendable {
		guard let value = await values.first(where: { _ in true }) else { throw NoValueError() }
		return value
	}
	
	public func firstValue(timeout: TimeInterval) async throws -> Self.Output where Failure == Never, Self.Output: Sendable {
		let pub = self.setFailureType(to: TimeoutError.self)
			.timeout(.seconds(timeout), scheduler: DispatchQueue.global(qos: .background)) {
				TimeoutError()
			}
		guard let value = try await pub.values.first(where: { _ in true }) else { throw NoValueError() }
		return value
	}
	
	public func firstValue(condition: (@Sendable (Self.Output) async throws -> Bool)) async throws -> Self.Output where Failure == Never, Self.Output: Sendable {
		guard let value = try await values.first(where: condition) else { throw NoValueError() }
		return value
	}
	
	public func firstValue(timeout: TimeInterval, condition: (@Sendable (Self.Output) async throws -> Bool)) async throws -> Self.Output where Self.Output: Sendable {
		let pub = self.timeout(.seconds(timeout), scheduler: DispatchQueue.global(qos: .background))
		guard let value = try await pub.values.first(where: condition) else { throw TimeoutError() }
		return value
	}
	
	public func firstValue(timeout: TimeInterval, condition: (@Sendable (Self.Output) async throws -> Bool)) async throws -> Self.Output where Failure == Never, Self.Output: Sendable {
		let pub = self.setFailureType(to: TimeoutError.self)
			.timeout(.seconds(timeout), scheduler: DispatchQueue.global(qos: .background)) {
				TimeoutError()
			}
		guard let value = try await pub.values.first(where: condition) else { throw NoValueError() }
		return value
	}
	
	public func firstValue() async throws -> Self.Output where Self.Output: Sendable {
		guard let value = try await values.first(where: { _ in true }) else { throw NoValueError() }
		return value
	}
	
	public func firstValue(condition: (Self.Output) async throws -> Bool) async throws -> Self.Output where Self.Output: Sendable {
		guard let value = try await values.first(where: condition) else { throw NoValueError() }
		return value
	}
}

public struct TimeoutError: Error {}
public struct NoValueError: Error {}

extension ThrowingTaskGroup {
	@discardableResult
	mutating func timeout(_ timeInterval: TimeInterval, priority: TaskPriority? = nil) async throws -> ChildTaskResult {
		if #available(iOS 16.0, macOS 13.0, *) {
			addTimeoutTask(timeout: .seconds(timeInterval), priority: priority)
		} else {
			addTimeoutTask(timeout: timeInterval, priority: priority)
		}
		
		guard let result = try await next() else { throw TimeoutError() }
		cancelAll()
		return result
	}
	
	mutating func addTimeoutTask(timeout: TimeInterval, priority: TaskPriority? = nil) {
		addTask(priority: priority ?? .utility) {
			try await Task.sleep(nanoseconds: UInt64(timeout) * NSEC_PER_SEC)
			try Task.checkCancellation()
			throw TimeoutError() //<< if not cancelled, then timeout
		}
	}
	
	@available(iOS 16.0, macOS 13.0, *)
	mutating func addTimeoutTask(timeout: Duration, priority: TaskPriority? = nil) {
		addTask(priority: priority ?? .utility) {
			try await Task.sleep(for: timeout)
			try Task.checkCancellation()
			throw TimeoutError() //<< if not cancelled, then timeout
		}
	}
	
	public mutating func cancelOnFirstCompletion() async throws {
		_ = try await next()
		cancelAll()
	}
}

extension TaskGroup {
	public mutating func cancelOnFirstCompletion() async {
		_ = await next()
		cancelAll()
	}
}

extension Subject where Output == Data {
	func enqueue(_ request: Livekit_SignalRequest) throws {
		send(try request.serializedData())
	}
	
	public var publisher: some Publisher<Output, Failure> {
		self.compactMap { $0 }
	}
	
	public func stream() -> AsyncStream<Output> where Failure == Never {
		self.publisher.stream()
	}
	
	public func throwingStream() -> AsyncThrowingStream<Output, Failure> where Failure == Error {
		publisher.throwingStream()
	}
}

extension CurrentValueSubject where Output : SetAlgebra {
	func insert<Element>(_ element: Element) where Element == Output.Element {
		value.insert(element)
	}
	
	func remove<Element>(_ element: Element) where Element == Output.Element {
		value.remove(element)
	}
}

extension CurrentValueSubject where Output: RangeReplaceableCollection {
	func append<Element>(_ element: Element) where Element == Output.Element {
		value.append(element)
	}
	
	func remove<Element: Equatable>(_ element: Element) where Element == Output.Element {
		if let index = value.firstIndex(of: element) {
			value.remove(at: index)
		}
	}
}

extension Sequence {
	public func grouped<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Key: Element] {
		reduce(into: [Key: Element]()) { result, value in
			let key = value[keyPath: keyPath]
			result[key] = value
		}
	}
	
	public func grouped<Key: Hashable, T>(by keyPath: KeyPath<T, Key>, transform: (Element) -> T) -> [Key: T] {
		map(transform)
			.reduce(into: [Key: T]()) { result, value in
				let key = value[keyPath: keyPath]
				result[key] = value
			}
	}
	
	public func mergingGrouped<Key: Hashable>(by keyPath: KeyPath<Element, Key>, into result: inout [Key: Element]) {
		for element in self {
			let key = element[keyPath: keyPath]
			result[key] = element
		}
	}
	
	public func mergingGrouped<Key: Hashable, T>(by keyPath: KeyPath<T, Key>, into result: inout [Key: T], transform: (Element) -> T) {
		map(transform)
			.forEach { transformedElement in
				let key = transformedElement[keyPath: keyPath]
				result[key] = transformedElement
			}
	}
}

extension RandomAccessCollection where Element: Comparable {
	public func binarySearch<Value>(_ value: Value, keyPath: KeyPath<Element, Value>) -> Self.Index where Value: Comparable {
		guard count > 0 else { return startIndex }
		
		var low = startIndex
		var high = index(endIndex, offsetBy: -1)
		
		while low <= high {
			let delta = distance(from: low, to: high)
			let midIndex = index(low, offsetBy: delta / 2)
			let midValue = self[midIndex][keyPath: keyPath]
			
			if value == midValue {
				return midIndex
			} else if value < midValue {
				high = index(midIndex, offsetBy: -1)
			} else {
				low = index(midIndex, offsetBy: 1)
			}
		}
		return low
	}
	
	public func binarySearch(_ element: Element) -> Self.Index {
		guard count > 0 else { return startIndex }
		
		var low = startIndex
		var high = index(endIndex, offsetBy: -1)
		
		while low <= high {
			let delta = distance(from: low, to: high)
			let midIndex = index(low, offsetBy: delta / 2)
			let midValue = self[midIndex]
			if element == midValue {
				return midIndex
			} else if element < midValue {
				high = index(midIndex, offsetBy: -1)
			} else {
				low = index(midIndex, offsetBy: 1)
			}
		}
		return low
	}
}

//MARK: - serial executor

#if swift(>=5.9)
extension DispatchQueue: SerialExecutor {
	public func enqueue(_ job: UnownedJob) {
		self.async {
			job.runSynchronously(on: UnownedSerialExecutor(ordinary: self))
		}
	}
	
	public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
		UnownedSerialExecutor(ordinary: self)
	}
}
#else
extension DispatchQueue: @unchecked Sendable, SerialExecutor {
	public func enqueue(_ job: UnownedJob) {
		self.async {
			job._runSynchronously(on: UnownedSerialExecutor(ordinary: self))
		}
	}
	
	public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
		UnownedSerialExecutor(ordinary: self)
	}
}
#endif

#if swift(>=5.9)
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
final class DispatchQueueSerialExecutor: SerialExecutor, Sendable {
	let dispatchQueue: DispatchQueue
	
	public init(dispatchQueue: DispatchQueue = DispatchQueue(label: "DispatchQueueSerialExecutor-Q")) {
		self.dispatchQueue = dispatchQueue
	}
	
	public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
		UnownedSerialExecutor(ordinary: self)
	}
	
	public func enqueue(_ job: consuming ExecutorJob) {
		let unownedJob = UnownedJob(job)
		dispatchQueue.async {
			unownedJob.runSynchronously(on: UnownedSerialExecutor(ordinary: self))
		}
	}
}

@available(iOS, deprecated: 17.0, message: "Use DispatchQueueSerialExecutor()")
final class LegacyDispatchQueueSerialExecutor: SerialExecutor, Sendable {
	public let dispatchQueue: DispatchQueue
	
	public init(dispatchQueue: DispatchQueue = DispatchQueue(label: "LegacyDispatchQueueSerialExecutor-Q")) {
		self.dispatchQueue = dispatchQueue
	}
	
	public func enqueue(_ job: UnownedJob) {
		dispatchQueue.async {
			job.runSynchronously(on: UnownedSerialExecutor(ordinary: self))
		}
	}
	
	public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
		UnownedSerialExecutor(ordinary: self)
	}
}
#endif
