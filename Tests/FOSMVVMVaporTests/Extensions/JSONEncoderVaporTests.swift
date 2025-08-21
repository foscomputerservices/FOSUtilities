// JSONEncoderVaporTests.swift
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

import FOSFoundation
import FOSMVVM
import FOSTesting
import FOSTestingVapor
import Foundation
import Testing
import Vapor

@Suite("JSON Encoder Error Vapor Tests")
struct JSONEncoderVaporTests: LocalizableTestCase {
    // MARK: Vapor Tests

    @Test func localizeStringVapor() async throws {
        let app = try await vaporApplication()
        defer { Task {
            try await app.asyncShutdown()
        }}
        let localizingEncoder = try await vaporRequest(application: app).localizingEncoder

        // We're just testing that it functions when configured properly
        _ = try localizingEncoder.encode(TestViewModel())
    }

    let locStore: LocalizationStore
    init() async throws {
        self.locStore = try await Self.loadLocalizationStore(
            bundle: .module,
            resourceDirectoryName: "TestYAML"
        )
    }
}
