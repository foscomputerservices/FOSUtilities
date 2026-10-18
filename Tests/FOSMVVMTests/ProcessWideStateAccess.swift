// ProcessWideStateAccess.swift
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
@testable import FOSMVVM
import Foundation
import Testing

/// Runs one test at a time among every suite that carries it, and leaves the deployment as it found
/// it.
///
/// `SystemVersion.current` and `Deployment.current` are process-wide: constructing an
/// `MVVMEnvironment` writes the version, and every request it sends reads the deployment.
/// `.serialized` orders tests only within one suite, so it cannot stop another suite from changing
/// either while a test depends on it. Put this on every suite that writes or reads them.
///
/// After each test the deployment override is cleared and `FOS-DEPLOYMENT` is put back, so a test
/// that changes the deployment cannot hand it to the next test.
struct ProcessWideStateAccess: SuiteTrait, TestTrait, TestScoping {
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
        let deploymentEnv = ProcessInfo.processInfo.environment[Deployment.envKey]
        do {
            try await function()
        } catch {
            await Self.restore(deploymentEnv: deploymentEnv)
            await Self.gate.signal()
            throw error
        }
        await Self.restore(deploymentEnv: deploymentEnv)
        await Self.gate.signal()
    }

    private static func restore(deploymentEnv: String?) async {
        await Deployment.testingReset()
        if let deploymentEnv {
            setenv(Deployment.envKey, deploymentEnv, 1)
        } else {
            unsetenv(Deployment.envKey)
        }
    }

    private static let gate = AsyncSemaphore(maxConcurrentTasks: 1)
}

extension Trait where Self == ProcessWideStateAccess {
    static var processWideState: Self {
        .init()
    }
}
