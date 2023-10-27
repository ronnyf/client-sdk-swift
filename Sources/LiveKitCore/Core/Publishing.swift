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

public struct ForwardingSubscription<Input>: Subscriber {
	
	public typealias Failure = Never
	public let combineIdentifier = CombineIdentifier()
	
	let subject: any Subject<Input, Never>
	
	public init(_ subject: any Subject<Input, Failure>) {
		self.subject = subject
	}
	
	public func receive(subscription: Subscription) {
		subject.send(subscription: subscription)
	}
	
	public func receive(_ input: Input) -> Subscribers.Demand {
		subject.send(input)
		return .none
	}
	
	public func receive(completion: Subscribers.Completion<Never>) {
		//we certainly will not cancel the receiving subscriber when the source completes ...
	}
}

extension Publisher where Failure == Never {
	public func assign(to publishing: inout Publishing<Output>) {
		let forward = ForwardingSubscription(publishing.subject)
		return subscribe(forward)
	}
}
