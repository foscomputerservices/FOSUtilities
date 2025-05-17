// SystemVersionTests.swift
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

#if canImport(Vapor)
import FOSFoundation
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTesting
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import Vapor

// NOTE: These tests must be serialized due to the shared
//       global state SystemVersion.current.
//
//       This is generally not an issue with client/server
//       applications, as this shared state is set during
//       initialization in a single thread and then only
//       consumed thereafter.  However, in tests, we are
//       modifying and reading this state, so serialization
//       is absolutely required for the tests to function
//       correctly.

@Suite("SystemVersion Tests", .serialized)
struct SystemVersionTests {
    @Test func vaporRequestVersion() async throws {
        let major = 1
        let minor = 2
        let patch = 3

        SystemVersion.setCurrentVersion(
            .init(major: major, minor: minor, patch: patch)
        )

        let compatibleRequest = try await Request.request(
            withVersion: SystemVersion.current
        )
        defer { Task {
            try? await compatibleRequest.application.asyncShutdown()
        } }

        do {
            try compatibleRequest.requireCompatibleSystemVersion()
        } catch let e {
            #expect(Bool(false), "requireCompatibleSystemVersion threw: \(e) when a compatible response was expected")
        }

        let incompatibleRequest = try await Request.request(
            withVersion: SystemVersion(major: major + 1, minor: minor, patch: patch)
        )
        defer { Task {
            try? await incompatibleRequest.application.asyncShutdown()
        } }
        #expect(throws: SystemVersionError.self) {
            try incompatibleRequest.requireCompatibleSystemVersion()
        }
    }

    @Test func missingRequestVersionHeader() async throws {
        let app = try await Application.app()
        defer { Task {
            try? await app.asyncShutdown()
        } }
        let request = Request(
            application: app,
            on: app.eventLoopGroup.next()
        )
        #expect(throws: SystemVersionError.self) {
            try request.systemVersion
        }
    }
}

private extension HTTPURLResponse {
    static func response(withVersion version: SystemVersion) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "http://localhost:8080")!,
            statusCode: 200,
            httpVersion: nil, headerFields: [
                URLRequest.systemVersioningHeader: version.versionString
            ]
        )!
    }
}

private extension Request {
    static func request(withVersion version: SystemVersion) async throws -> Request {
        let app = try await Application.make()

        return .init(
            application: app,
            headers: .init([
                (URLRequest.systemVersioningHeader, version.versionString)
            ]),
            on: app.eventLoopGroup.next()
        )
    }
}

private extension Application {
    static func app() async throws -> Application {
        try await .make()
    }
}

private extension SystemVersion {
    static var first: SystemVersion { .init(major: 1, minor: 0) }
    static var second: SystemVersion { .init(major: 1, minor: 1) }
    static var third: SystemVersion { .init(major: 1, minor: 1, patch: 3) }
    static var forth: SystemVersion { .init(major: 2, minor: 0, patch: 0) }
    static var fifth: SystemVersion { .init(major: 3, minor: 3, patch: 1) }
}
#endif
