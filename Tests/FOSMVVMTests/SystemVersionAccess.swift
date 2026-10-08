// SystemVersionAccess.swift
//
// Copyright 2026 FOS Computer Services, LLC
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

import FOSFoundation
import Testing

/// Runs one test at a time among every suite that carries it.
///
/// `SystemVersion.current` is process-wide, and constructing an `MVVMEnvironment` writes it.
/// `.serialized` orders tests only within one suite, so it cannot stop another suite from writing
/// while `SystemVersionTests` asserts. Put this on every suite that writes or asserts the version.
struct SystemVersionAccess: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool {
        true
    }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        // Scope each test, not the suite around them: the gate is not reentrant.
        guard !test.isSuite else {
            try await function()
            return
        }

        try await Self.gate.wait()
        do {
            try await function()
        } catch {
            await Self.gate.signal()
            throw error
        }
        await Self.gate.signal()
    }

    private static let gate = AsyncSemaphore(maxConcurrentTasks: 1)
}

extension Trait where Self == SystemVersionAccess {
    static var systemVersionAccess: Self {
        .init()
    }
}
