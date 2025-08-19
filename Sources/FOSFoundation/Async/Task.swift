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
    /// func asyncFuncCall() async {}
    ///
    /// func syncFunc() {
    ///     Task.synchronous {
    ///         await asyncFuncCall()
    ///     }
    ///
    ///     // continue ...
    /// }
    /// ```
    static func synchronous(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async throws -> Success
    ) {
        let semaphore = DispatchSemaphore(value: 0)

        Task(priority: priority) {
            defer { semaphore.signal() }
            return try await operation()
        }

        semaphore.wait()
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
    /// func asyncFuncCall() async -> Int {}
    ///
    /// func syncFunc() {
    ///     let value = Task.synchronous {
    ///         await asyncFuncCall()
    ///     }
    ///
    ///     // continue ...
    /// }
    /// ```
    static func synchronous<R: Sendable>(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async throws -> R
    ) -> R {
        let semaphore = DispatchSemaphore(value: 0)

        var result: R!

        Task(priority: priority) {
            defer { semaphore.signal() }
            result = try await operation()
        }

        semaphore.wait()
        return result
    }
}
