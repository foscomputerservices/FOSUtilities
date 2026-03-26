// Task.swift
//
// Copyright 2024 FOS Computer Services, LLC
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

import Foundation

/// Thread-safe box for passing results across concurrency boundaries.
/// Safety is ensured by the `DispatchSemaphore` in `Task.synchronous` —
/// the write completes and signals before the read occurs after `wait()`.
private final class ResultBox<T>: @unchecked Sendable {
    var value: T?
}

public extension Task where Failure == Error {
    /// Performs an async task in a synchronous context
    ///
    /// This can be used when it is necessary to call an **async** function
    /// from a function that is not marked **async**.
    ///
    /// - Note: This function blocks the current thread until the given operation is finished.
    ///
    /// ## Example
    ///
    /// ```swift
    /// func asyncFuncCall() async throws {}
    ///
    /// func syncFunc() throws {
    ///     try Task.synchronous {
    ///         try await asyncFuncCall()
    ///     }
    ///
    ///     // continue ...
    /// }
    /// ```
    static func synchronous(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async throws -> Success
    ) throws {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox<Error>()

        Task<Void, Never>.detached(priority: priority) {
            do {
                _ = try await operation()
            } catch {
                box.value = error
            }
            semaphore.signal()
        }

        semaphore.wait()
        if let error = box.value { throw error }
    }
}

public extension Task where Failure == Error, Success == Void {
    /// Performs an async task returning a value in a synchronous context
    ///
    /// This can be used when it is necessary to call an **async** function
    /// that returns a value from a function that is not marked **async**.
    ///
    /// - Note: This function blocks the current thread until the given operation is finished.
    ///
    /// ## Example
    ///
    /// ```swift
    /// func asyncFuncCall() async throws -> Int { 42 }
    ///
    /// func syncFunc() throws {
    ///     let value = try Task.synchronous {
    ///         try await asyncFuncCall()
    ///     }
    ///
    ///     // continue ...
    /// }
    /// ```
    static func synchronous<R: Sendable>(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async throws -> R
    ) throws -> R {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox<Result<R, Error>>()

        Task<Void, Never>.detached(priority: priority) {
            do {
                let value = try await operation()
                box.value = .success(value)
            } catch {
                box.value = .failure(error)
            }
            semaphore.signal()
        }

        semaphore.wait()
        return try box.value!.get()
    }
}
