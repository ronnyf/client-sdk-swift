/*
 * Copyright 2024 LiveKit
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import Foundation

actor QueueActor<T>: Loggable {
    typealias OnProcess = (T) async -> Void

    // MARK: - Public

    public enum State {
        case resumed
        case suspended
    }

    public private(set) var state: State = .resumed

    public var count: Int { queue.count }

    // MARK: - Private

    private var queue = [T]()
    private let onProcess: OnProcess

    init(onProcess: @escaping OnProcess) {
        self.onProcess = onProcess
    }

    /// Mark as `.suspended`.
    func suspend() {
        state = .suspended
    }

    /// Only process if `.resumed` state, otherwise enqueue.
    func processIfResumed(_ value: T) async {
        await process(value, if: state == .resumed)
    }

    /// Only process if `condition` is true, otherwise enqueue.
    func process(_ value: T, if condition: Bool) async {
        if condition {
            await onProcess(value)
        } else {
            queue.append(value)
        }
        log("process if: \(condition ? "true" : "false"), count: \(queue.count)")
    }

    func clear() {
        if !queue.isEmpty {
            log("Clearing queue which is not empty", .warning)
        }

        queue.removeAll()
        state = .resumed
    }

    /// Mark as `.resumed` and process each element with an async `block`.
    func resume() async {
        log("resuming...")

        state = .resumed
        if queue.isEmpty { return }
        for element in queue {
            // Check cancellation before processing next block...
            // try Task.checkCancellation()
            log("resume: processing element...")
            await onProcess(element)
        }
        queue.removeAll()
    }
}
