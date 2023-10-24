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

public enum MessageChannelConnectionState: Sendable {
    case disconnected
    case connected
    case reconnecting
    case down
}

class MessageChannel: @unchecked Sendable {
    var currentWebSocketTask: some Publisher<URLSessionWebSocketTask, Never> {
        coordinator.$webSocketTask.publisher.compactMap { $0 }
    }
    
    var currentWebSocketStream: AsyncStream<URLSessionWebSocketTask> {
        currentWebSocketTask.stream()
    }
    
    var bufferedMessages: AsyncThrowingFlatMapSequence<AsyncStream<URLSessionWebSocketTask>, AsyncBufferSequence<URLSessionWebSocketTaskReceiver>> {
        currentWebSocketStream.flatMap {
            $0.bufferedMessages(policy: .bufferingLatest(20))
        }
    }
    
    var messages: AsyncFlatMapSequence<AsyncStream<URLSessionWebSocketTask>, URLSessionWebSocketTaskReceiver> {
        currentWebSocketStream.flatMap { $0.messages() }
    }
    
    var connectionState: some Publisher<MessageChannelConnectionState, Never> {
        coordinator.connectionState.eraseToAnyPublisher()
    }
    
    
    let urlSession: URLSession
    let coordinator: WebsocketTaskCoordinator
	
	init(urlSessionConfiguration: URLSessionConfiguration = .liveKitDefault, coordinator: WebsocketTaskCoordinator = WebsocketTaskCoordinator()) {
		self.urlSession = URLSession(configuration: urlSessionConfiguration, delegate: coordinator, delegateQueue: nil)
		self.coordinator = coordinator
	}
	
	#if DEBUG
	deinit {
		Logger.log(oslog: coordinator.messageChannelLog, message: "deinit MessageChannel")
	}
	#endif
	
	func teardown() {
		Logger.log(oslog: coordinator.messageChannelLog, message: "teardown MessageChannel")
		
		urlSession.invalidateAndCancel()
		coordinator.teardown()
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
		
		@Publishing var webSocketTask: URLSessionWebSocketTask? = nil
		let messageChannelLog = OSLog(subsystem: "MessageChannel", category: "LiveKitCore")
        let connectionState: CurrentValueSubject<MessageChannelConnectionState, Never>
		
        override init() {
            self.connectionState = CurrentValueSubject(.disconnected)
            super.init()
            Logger.log(oslog: messageChannelLog, message: "WebsocketTaskCoordinator init")
        }
        
#if DEBUG
		deinit {
			Logger.log(oslog: messageChannelLog, message: "WebsocketTaskCoordinator deinit")
		}
		#endif
		
		func openSocket(_ webSocketTask: URLSessionWebSocketTask) {
			webSocketTask.resume()
		}
		
		///Close the current (open) socket and wait for it to go through the system (openSocketSubject is nil)
		func teardown() {
			Logger.log(oslog: messageChannelLog, message: "tearddown WebsocketTaskCoordinator")
			_webSocketTask.finish()
            connectionState.send(.down)
		}
		
		//Indicates that the WebSocket handshake was successful and the connection has been upgraded to webSockets.
		func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
			self.webSocketTask = webSocketTask
            self.connectionState.send(.connected)
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
			webSocketTask = nil
            connectionState.send(.disconnected)
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

// TODO: should this be a class so the wst can be retained until we let it go?
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
		guard Task.isCancelled == false else { return nil }
		return try? await webSocketTask.receive()
	}
}
