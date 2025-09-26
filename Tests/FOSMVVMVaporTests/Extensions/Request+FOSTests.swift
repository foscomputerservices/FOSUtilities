// Request+FOSTests.swift
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
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("FOS Vapor Request Additions Tests")
struct RequestFOSAdditionTests: LocalizableTestCase {
    // MARK: Vapor Tests

    @Test func requestAction() async throws {
        let app = try await vaporApplication()
        defer { Task {
            try await app.asyncShutdown()
        }}
        let req = try await vaporRequest(application: app)
        req.method = .POST
        req.url = URI(string: "http://example.com")

        #expect(try req.requestAction() == .create)
    }

    @Test func applicationVersion() async throws {
        let app = try await vaporApplication()
        defer { Task {
            try await app.asyncShutdown()
        }}
        let req = try await vaporRequest(application: app)
        req.headers.add(name: SystemVersion.httpHeader, value: "\"1.2.99\"")

        #expect(try req.applicationVersion() == .init(major: 1, minor: 2, patch: 99))
    }

    @Test func requireApplicationVersion() async throws {
        let app = try await vaporApplication()
        defer { Task {
            try await app.asyncShutdown()
        }}
        let req = try await vaporRequest(application: app)
        req.headers.remove(name: SystemVersion.httpHeader)

        #expect(throws: SystemVersionError.self) {
            try req.applicationVersion()
        }
    }

    @Test @MainActor func requireCompatibleAppVersion() async throws {
        let app = try await vaporApplication()
        defer { Task {
            try await app.asyncShutdown()
        }}
        let req = try await vaporRequest(application: app)
        SystemVersion.setCurrentVersion(.init(major: 2, minor: 1, patch: 1))
        req.headers.add(name: SystemVersion.httpHeader, value: "\"2.1.99\"")

        // Should not throw
        try req.requireCompatibleAppVersion()
    }

    @Test @MainActor func requireIncompatibleAppVersion() async throws {
        let app = try await vaporApplication()
        defer { Task {
            try await app.asyncShutdown()
        }}
        let req = try await vaporRequest(application: app)
        SystemVersion.setCurrentVersion(.init(major: 2, minor: 1, patch: 1))
        req.headers.add(name: SystemVersion.httpHeader, value: "\"1.1.1\"")

        #expect(throws: SystemVersionError.self) {
            try req.requireCompatibleAppVersion()
        }
    }

    @Test func locale() async throws {
        let app = try await vaporApplication()
        defer { Task {
            try await app.asyncShutdown()
        }}
        let req = try await vaporRequest(application: app)
        req.headers.remove(name: HTTPHeaders.Name.acceptLanguage)
        req.headers.add(name: HTTPHeaders.Name.acceptLanguage, value: "es")

        #expect(req.locale == Self.es)
    }

    @Test func requireLocale() async throws {
        let app = try await vaporApplication()
        defer { Task {
            try await app.asyncShutdown()
        }}
        let req = try await vaporRequest(application: app)
        req.headers.remove(name: HTTPHeaders.Name.acceptLanguage)
        req.headers.add(name: HTTPHeaders.Name.acceptLanguage, value: "es")

        #expect(try req.requireLocale() == Self.es)
    }

    @Test func requireMissingLocale() async throws {
        let app = try await vaporApplication()
        defer { Task {
            try await app.asyncShutdown()
        }}
        let req = try await vaporRequest(application: app)
        req.headers.remove(name: HTTPHeaders.Name.acceptLanguage)

        #expect(throws: YamlStoreError.self) {
            try req.requireLocale()
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
