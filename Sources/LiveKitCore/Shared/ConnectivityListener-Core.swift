//
//  ConnectivityListener-Core.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 5/16/23.
//

import Foundation
import Network

#if LKCORE

open class MulticastDelegate<T>: NSObject {
	init(label: String = "livekit.multicast", qos: DispatchQoS = .default) {
		super.init()
	}
	
	/// Add a single delegate.
	public func add(delegate: T) {}
	
	/// Remove a single delegate.
	///
	/// In most cases this is not required to be called explicitly since all delegates are weak.
	public func remove(delegate: T) {}
	
	/// Remove all delegates.
	public func removeAllDelegates() {}
	
	/// Notify delegates inside the queue.
	/// Label is captured inside the queue for thread safety reasons.
	public func notify(label: (() -> String)? = nil, _ fnc: @escaping (T) -> Void) {}
}

@objc(ConnectionState)
public enum ConnectionStateObjC: Int {
	case disconnected
	case connecting
	case reconnecting
	case connected
}

#endif
