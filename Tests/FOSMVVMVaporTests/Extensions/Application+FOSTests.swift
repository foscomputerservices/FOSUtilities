// Application+FOSTests.swift
//
// Copyright 2025 FOS Computer Services, LLC
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

@Suite("FOS Vapor Application Additions Tests")
struct ApplicationFOSAdditionTests: LocalizableTestCase {
    @Test func localizationStore() async throws {
        let app = try await vaporApplication()
        defer { Task {
            try await app.asyncShutdown()
        }}

        #expect(app.localizationStore != nil)
    }

    @Test func updateLocalizationStore() async throws {
        let app = try await vaporApplication()
        defer { Task {
            try await app.asyncShutdown()
        }}

        #expect(app.localizationStore != nil)
        app.localizationStore = nil
        #expect(app.localizationStore == nil)
    }

    @Test func requireLocalizationStore() async throws {
        let app = try await vaporApplication()
        defer { Task {
            try await app.asyncShutdown()
        }}

        // shouldn't throw
        _ = try app.requireLocalizationStore()
    }

    @Test func requireMissingLocalizationStore() async throws {
        let app = try await vaporApplication()
        defer { Task {
            try await app.asyncShutdown()
        }}

        // shouldn't throw
        app.localizationStore = nil
        #expect(throws: YamlStoreError.self) {
            _ = try app.requireLocalizationStore()
        }
    }

    @Test func reactResourcesServed() async throws {
        let app = try await vaporApplication()
        defer { Task {
            try await app.asyncShutdown()
        }}

        try app.initYamlLocalization(bundle: Bundle.module, resourceDirectoryName: "TestYAML")

        Task { try await app.execute() }

        sleep(1)

        // Test that React resources are accessible at /fosmvvm/react/
        let testFiles = ["fosmvvmWasmRuntime.js", "viewModelComponent.js", "fosmvvm.css", "README.md"]

        for fileName in testFiles {
            try await app.test(.GET, "fosmvvm/react/\(fileName)") { response in
                #expect(response.status == .ok, "Expected \(fileName) to be served with status 200, got \(response.status)")

                // Verify content is not empty
                let body = response.body.string
                #expect(!body.isEmpty, "Expected fosmvvm/react/\(fileName) to have content")
            }
        }
    }

    let locStore: LocalizationStore
    init() throws {
        self.locStore = try Self.loadLocalizationStore(
            bundle: .module,
            resourceDirectoryName: "TestYAML"
        )
    }
}
