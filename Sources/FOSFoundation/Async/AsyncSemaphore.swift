// AsyncSemaphore.swift
//
// Created by David Hunt on 5/20/24
// Copyright 2024 FOS Services, LLC
//
// Licensed under the Apache License, Version 2.0 (the  License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// An actor-based semaphore designed to manage concurrency in Swift’s asynchronous environment
///
/// This class ensures that a limited number of tasks can proceed concurrently, as defined
/// by the maxConcurrentTasks property.
///
/// This actor is useful in scenarios where you need to control the number of concurrent tasks, such as
/// limiting access to shared resources or managing a pool of connections. By utilizing Swift’s concurrency
/// model, ``AsyncSemaphore`` provides a safe and efficient way to handle concurrent tasks without
/// race conditions.
///
/// ## Example
///
/// ```swift
/// let semaphore = AsyncSemaphore(maxConcurrentTasks: 1)
///
/// func performSyncRequest() async throws {
///   await semaphore.wait()
///   defer { Task { await semaphore.signal() } }
///
///   try mySynchronousFunction()
/// }
///
/// // Executes one at a time
/// try await performSyncRequest()
/// try await performSyncRequest()
/// try await performSyncRequest()
/// ```
public actor AsyncSemaphore {
    public let maxConcurrentTasks: Int

    private var currentCount: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Waits until the semaphore is available
    public func wait() async {
        await withCheckedContinuation { continuation in
            if currentCount < maxConcurrentTasks {
                currentCount += 1
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
    }

    /// Signals that the task is complete and releases the semaphore
    ///
    /// It is often handy to call this from a swift **defer** statement to guarantee
    /// that the call is made when the function exits.
    ///
    /// ## Example
    ///
    /// ```swift
    /// func performSyncRequest() async throws {
    ///   await semaphore.wait()
    ///   defer { Task { await semaphore.signal() } }
    ///
    ///   try mySynchronousFunction()
    /// }
    /// ```
    public func signal() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            currentCount -= 1
        }
    }

    public init(maxConcurrentTasks: Int) {
        self.maxConcurrentTasks = maxConcurrentTasks
    }
}
