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
	
	public var projectedValue: (binding: Binding<Value>, publisher: some Publisher<Value, Never>) {
		return (binding: binding, publisher: subject)
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
