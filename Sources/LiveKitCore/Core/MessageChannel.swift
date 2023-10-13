//
//  MessageChannel.swift
//  LiveKitCore
//
//  Created by Falk, Ronny on 4/3/23.
//

import Foundation
import OSLog
import Combine
import AsyncAlgorithms

class MessageChannel: @unchecked Sendable {
	let urlSession: URLSession
	let coordinator: WebsocketTaskCoordinator
	
	var currentWebSocketTask: some Publisher<URLSessionWebSocketTask, Never> {
		coordinator.$openSocketsSubject.publisher.compactMap { $0 }
	}
	
	var currentWebSocketStream: AsyncStream<URLSessionWebSocketTask> {
		coordinator.$openSocketsSubject.publisher.compactMap { $0 }.stream()
	}
	
	var bufferedMessages: AsyncThrowingFlatMapSequence<AsyncStream<URLSessionWebSocketTask>, AsyncBufferSequence<URLSessionWebSocketTaskReceiver>> {
		currentWebSocketStream.flatMap {
			$0.bufferedMessages(policy: .bufferingLatest(10))
		}
	}
	
	var messages: AsyncFlatMapSequence<AsyncStream<URLSessionWebSocketTask>, URLSessionWebSocketTaskReceiver> {
		currentWebSocketStream.flatMap { $0.messages() }
	}
	
	init(urlSessionConfiguration: URLSessionConfiguration = .liveKitDefault, coordinator: WebsocketTaskCoordinator = WebsocketTaskCoordinator()) {
		self.urlSession = URLSession(configuration: urlSessionConfiguration, delegate: coordinator, delegateQueue: nil)
		self.coordinator = coordinator
	}
	
	#if DEBUG
	deinit {
		Logger.log(oslog: coordinator.messageChannelLog, message: "deinit")
	}
	#endif
	
	func teardown() {
		Logger.log(oslog: coordinator.messageChannelLog, message: "teardown")
		
		urlSession.invalidateAndCancel()
		coordinator.closeSocket()
	}
	
	func send(data: Data, timeout: TimeInterval) async throws {
		let websocketTask = try await currentWebSocketTask.firstValue(timeout: timeout)
		try await websocketTask.send(data: data)
	}
	
	func createWebSocketTask(urlRequest: URLRequest) -> URLSessionWebSocketTask {
		let webSocketTask = urlSession.webSocketTask(with: urlRequest)
		webSocketTask.delegate = coordinator
		return webSocketTask
	}
}

//MARK: - URLSessionWebSocketDelegate

extension MessageChannel {
	final class WebsocketTaskCoordinator: NSObject, URLSessionWebSocketDelegate, URLSessionDelegate, @unchecked Sendable {
		@Publishing var openSocketsSubject: URLSessionWebSocketTask? = nil
		let messageChannelLog = OSLog(subsystem: "MessageChannel", category: "LiveKitCore")
		#if DEBUG
		override init() {
			super.init()
			Logger.log(oslog: messageChannelLog, message: "coordinator init")
		}
		#endif
		
		#if DEBUG
		deinit {
			Logger.log(oslog: messageChannelLog, message: "coordinator deinit")
		}
		#endif
		
		func openSocket(_ webSocketTask: URLSessionWebSocketTask) {
			webSocketTask.resume()
		}
		
		///Close the current (open) socket and wait for it to go through the system (openSocketSubject is nil)
		func closeSocket() {
			_openSocketsSubject.finish()
		}
		
		//Indicates that the WebSocket handshake was successful and the connection has been upgraded to webSockets.
		func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
			openSocketsSubject = webSocketTask
			Logger.log(oslog: messageChannelLog, message: "socket opened \(webSocketTask)")
		}
		
		//Indicates that the WebSocket has received a close frame from the server endpoint.
		func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
			webSocketTask.cancel(with: closeCode, reason: reason)
			Logger.log(oslog: messageChannelLog, message: "socket did close \(webSocketTask)")
		}
		
		// Sent as the last message related to a specific task.  Error may be nil, which implies that no error occurred and this task is complete.
		func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
			Logger.log(oslog: messageChannelLog, message: "socket did complete \(task)")
			#if DEBUG
			if let error {
				Logger.log(level: .error, oslog: messageChannelLog, message: "\(error)")
			}
			#endif
			openSocketsSubject = nil
		}
		
		#if DEBUG
		func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
			if let trust = challenge.protectionSpace.serverTrust {
				let cred = URLCredential(trust: trust)
				Logger.log(oslog: messageChannelLog, message: "override https certificate acceptance")
				return (.useCredential, cred)
			}
			
			return (.rejectProtectionSpace, nil)
		}
		#endif
	}
}

extension URLSessionWebSocketTask {
	func bufferedMessages(policy: AsyncBufferSequencePolicy) -> AsyncBufferSequence<URLSessionWebSocketTaskReceiver> {
		AsyncBufferSequence(base: messages(), policy: policy)
	}
	
	func messages() -> URLSessionWebSocketTaskReceiver {
		URLSessionWebSocketTaskReceiver(webSocketTask: self)
	}
	
	func send(data: Data) async throws {
		try await send(URLSessionWebSocketTask.Message.data(data))
	}
	
	func send(string: String) async throws {
		try await send(URLSessionWebSocketTask.Message.string(string))
	}
}

struct URLSessionWebSocketTaskReceiver: AsyncSequence, AsyncIteratorProtocol {
	typealias AsyncIterator = URLSessionWebSocketTaskReceiver
	typealias Element = URLSessionWebSocketTask.Message
	
	let webSocketTask: URLSessionWebSocketTask
	init(webSocketTask: URLSessionWebSocketTask) {
		self.webSocketTask = webSocketTask
	}
	
	func makeAsyncIterator() -> AsyncIterator {
		self
	}
	
	func next() async -> Element? {
		try? await webSocketTask.receive()
	}
}
