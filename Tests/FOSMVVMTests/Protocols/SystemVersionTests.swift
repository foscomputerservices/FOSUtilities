// SystemVersionTests.swift
//
// Created by David Hunt on 9/4/24
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

import FOSFoundation
@testable import FOSMVVM
import FOSTesting
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
#if canImport(Vapor)
import Vapor
#endif

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
    // MARK: HTTPURLResponse Tests

    @Test func testHTTPURLResponseVersion() throws {
        let major = 1
        let minor = 2
        let patch = 3

        SystemVersion.setCurrentVersion(
            .init(major: major, minor: minor, patch: patch)
        )

        let compatibleResponse = HTTPURLResponse.response(
            withVersion: SystemVersion.current
        )
        do {
            try compatibleResponse.requireCompatibleSystemVersion()
        } catch let e {
            #expect(Bool(false), "requireCompatibleSystemVersion threw: \(e) when a compatible response was expected")
        }

        let incompatibleResponse = HTTPURLResponse.response(
            withVersion: SystemVersion(major: major + 1, minor: minor, patch: patch)
        )
        #expect(throws: SystemVersionError.self) {
            try incompatibleResponse.requireCompatibleSystemVersion()
        }
    }

    @Test func testMissingResponseVersionHeader() throws {
        let response = HTTPURLResponse(url: URL(string: "https://www.github.com")!, statusCode: 0, httpVersion: nil, headerFields: nil)!
        #expect(throws: SystemVersionError.self) {
            try response.systemVersion
        }
    }

    @Test(arguments: [
        (
            a: SystemVersion.first,
            b: SystemVersion.second,
            aIsLess: true
        ),
        (
            a: SystemVersion.second,
            b: SystemVersion.first,
            aIsLess: false
        ),
        (
            a: SystemVersion.second,
            b: SystemVersion.forth,
            aIsLess: true
        ),
        (
            a: SystemVersion.forth,
            b: SystemVersion.second,
            aIsLess: false
        ),
        (
            a: SystemVersion.forth,
            b: SystemVersion.second,
            aIsLess: false
        )
    ]) func testComparable(tuple: (a: SystemVersion, b: SystemVersion, aIsLess: Bool)) throws {
        #expect((tuple.a < tuple.b) == tuple.aIsLess)
        #expect((tuple.a > tuple.b) == !tuple.aIsLess)
    }

    @Test(arguments: [
        (
            random: [SystemVersion.first, .second, .third],
            expected: [SystemVersion.first, .second, .third]
        ),
        (
            random: [SystemVersion.second, .third, .first],
            expected: [SystemVersion.first, .second, .third]
        ),
        (
            random: [SystemVersion.fifth, .third, .first],
            expected: [SystemVersion.first, .third, .fifth]
        ),
        (
            random: [SystemVersion.fifth, .third, .second],
            expected: [SystemVersion.second, .third, .fifth]
        )
    ]) func testSorted(tuple: (random: [SystemVersion], expected: [SystemVersion])) throws {
        #expect(tuple.random.sorted() == tuple.expected)
    }

    // MARK: Vapor Request Tests

    #if canImport(Vapor)
    @Test func testVaporRequestVersion() throws {
        let major = 1
        let minor = 2
        let patch = 3

        SystemVersion.setCurrentVersion(
            .init(major: major, minor: minor, patch: patch)
        )

        let compatibleRequest = Request.request(
            withVersion: SystemVersion.current
        )
        defer { compatibleRequest.application.shutdown() }
        do {
            try compatibleRequest.requireCompatibleSystemVersion()
        } catch let e {
            #expect(Bool(false), "requireCompatibleSystemVersion threw: \(e) when a compatible response was expected")
        }

        let incompatibleRequest = Request.request(
            withVersion: SystemVersion(major: major + 1, minor: minor, patch: patch)
        )
        defer { incompatibleRequest.application.shutdown() }
        #expect(throws: SystemVersionError.self) {
            try incompatibleRequest.requireCompatibleSystemVersion()
        }
    }

    @Test func testMissingRequestVersionHeader() throws {
        let app = Application.app()
        defer { app.shutdown() }
        let request = Request(
            application: app,
            on: app.eventLoopGroup.next()
        )
        #expect(throws: SystemVersionError.self) {
            try request.systemVersion
        }
    }
    #endif
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

#if canImport(Vapor)
private extension Request {
    static func request(withVersion version: SystemVersion) -> Request {
        let app = Application.app()

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
    static func app() -> Application {
        .init()
    }
}
#endif

private extension SystemVersion {
    static var first: SystemVersion { .init(major: 1, minor: 0) }
    static var second: SystemVersion { .init(major: 1, minor: 1) }
    static var third: SystemVersion { .init(major: 1, minor: 1, patch: 3) }
    static var forth: SystemVersion { .init(major: 2, minor: 0, patch: 0) }
    static var fifth: SystemVersion { .init(major: 3, minor: 3, patch: 1) }
}
