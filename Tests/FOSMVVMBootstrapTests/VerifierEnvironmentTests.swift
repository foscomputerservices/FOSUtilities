// VerifierEnvironmentTests.swift
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

@testable import FOSMVVMBootstrap
import Foundation
import Testing

struct VerifierEnvironmentTests {
    @Test func stripsHarnessSessionVariables() {
        let base = [
            "PATH": "/usr/bin",
            "HOME": "/Users/dev",
            "XCTestConfigurationFilePath": "/tmp/session.xctestconfiguration",
            "XCTestSessionIdentifier": "ABC-123",
            "XCTestBundlePath": "/tmp/Some.xctest",
            "DYLD_INSERT_LIBRARIES": "/tmp/inject.dylib",
            "DYLD_FRAMEWORK_PATH": "/tmp/frameworks"
        ]

        let child = Verifier.childEnvironment(from: base, overlaying: nil)

        #expect(child == ["PATH": "/usr/bin", "HOME": "/Users/dev"])
    }

    @Test func overlayWinsOverInheritedValues() {
        let base = [
            "PATH": "/usr/bin",
            "XCTestSessionIdentifier": "ABC-123"
        ]

        let child = Verifier.childEnvironment(
            from: base,
            overlaying: ["PATH": "/nonexistent", "EXTRA": "1"]
        )

        #expect(child == ["PATH": "/nonexistent", "EXTRA": "1"])
    }
}
