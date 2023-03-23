//
//  Publishing.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 4/21/23.
//

import Combine
import SwiftUI

///Somewhat similar to @Published but this is actually more like a convenience wrapper.
///It's mainly used when an AsyncChannel wouldn't work due to the back-pressure feature.
///Sometimes we simply need a publisher that can be subscribed to by several subscribers without
///backpressure. So it can be mapped to an async stream per subscriber.

@propertyWrapper
public struct Publishing<Value> {
	
	public var wrappedValue: Value {
		get {
			subject.value
		}
		nonmutating set {
			subject.send(newValue)
		}
	}
	
	public var binding: Binding<Value> {
		Binding {
			subject.value
		} set: { newValue in
			subject.send(newValue)
		}
	}
	
	public var projectedValue: (binding: Binding<Value>, publisher: AnyPublisher<Value, Never>) {
		return (binding: binding, publisher: subject.eraseToAnyPublisher())
	}
	
	public let subject: CurrentValueSubject<Value, Never>

	public init(wrappedValue value: Value) {
		self.subject = CurrentValueSubject(value)
	}
	
	public init<T>(_ type: T.Type) where Value == Optional<T> {
		self.subject = CurrentValueSubject(nil)
	}
	
	public func finish(_ completion: Subscribers.Completion<Never> = .finished) {
		subject.send(completion: completion)
	}
}

public struct _Publishing<Value, Failure: Error>: Sendable {
		
	public let subject: CurrentValueSubject<Value?, Failure>
	
	public var value: Value? {
		subject.value
	}
	
	public var publisher: some Publisher<Value, Failure> {
		subject.compactMap { $0 }
	}
	
	public init(_ value: Value? = nil) {
		self.subject = CurrentValueSubject<Value?, Failure>(value)
	}
	
	public func stream() -> AsyncStream<Value> where Failure == Never {
		publisher.stream()
	}
	
	public func throwingStream() -> AsyncThrowingStream<Value, Failure> where Failure == Error {
		publisher.throwingStream()
	}
	
	public func update(_ value: Value?) {
		subject.send(value)
	}
	
	public func finish(completion: Subscribers.Completion<Failure> = .finished) {
		subject.send(completion: completion)
	}
	
	public func append<Element>(_ element: Element) where Value == Array<Element> {
		subject.value?.append(element)
	}
	
	public func updateValue<Key: Hashable, V>(_ key: Key, value: V) where Value == Dictionary<Key, V> {
		subject.value?.updateValue(value, forKey: key)
	}
	
	public func removeValue<Key: Hashable, V>(_ key: Key) -> V? where Value == Dictionary<Key, V> {
		return subject.value?.removeValue(forKey: key)
	}
}
