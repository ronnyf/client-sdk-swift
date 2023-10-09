//
//  MessageChannel+Connect.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 10/3/23.
//

import Foundation
import AsyncAlgorithms

extension MessageChannel {
	func connect(
		urlRequest: URLRequest,
		rateLimit: Int = 30,
		outgoingDataStream: AsyncStream<Data>
	) async throws {
		let openWebSocketTasks = coordinator.$webSocketTask.publisher.compactMap{ $0 }.stream()
		let outgoingMessages = outgoingDataStream.map { URLSessionWebSocketTask.Message.data($0) }
		let bufferedOutgoingMessages = AsyncBufferSequence(base: outgoingMessages, policy: .bounded(20))
		// this should create sufficient demand on the publisher --------^
		
		try await withThrowingTaskGroup(of: Void.self) { [coordinator] group in
			group.addTask {
				for await (webSocketTask, message) in combineLatest(openWebSocketTasks, bufferedOutgoingMessages) {
					try await webSocketTask.send(message)
//					#if DEBUG
//					switch message {
//					case .data(let data):
//						if let lkRequest = try? Livekit_SignalRequest(contiguousBytes: data) {
//							Logger.log(oslog: coordinator.messageChannelLog, message: "did send: \(lkRequest)")
//						}
//					default:
//						break
//					}
//					#endif
				}
			}
			
			group.addTask {
				// we skip the ratelimit for the first one...
				var webSocketTask: URLSessionWebSocketTask = self.createWebSocketTask(urlRequest: urlRequest)
				webSocketTask.resume()

//				if #available(iOS 16.0, *) {
//					let rateLimitedNilSequence = coordinator
//						.openSocketsSubject
//						.values
//						.filter({ $0 == nil })
//						.debounce(for: .seconds(rateLimit))
//				} else {
//				}
				
				let rateLimitedValues = coordinator.$webSocketTask.publisher
					.dropFirst()
					.filter({ $0 == nil})
					.debounce(for: .seconds(rateLimit), scheduler: DispatchQueue.global(qos: .background))
					.stream()
				
				for await _ in rateLimitedValues {
					try Task.checkCancellation()
					// using the local property so we don't hang on to the first websocket task indefinitely
					webSocketTask = self.createWebSocketTask(urlRequest: urlRequest)
					webSocketTask.resume()
				}
				Logger.log(oslog: coordinator.messageChannelLog, message: "WebSocketTask factory is down!")
			}
		
			try await group.cancelOnFirstCompletion()
		}
	}
}
