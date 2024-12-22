// SystemVersionTests.swift
//
// Created by David Hunt on 12/11/24
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

@testable import FOSFoundation
import FOSTesting
import Foundation
import Testing

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
    @Test func testVersionStr() {
        let sv = SystemVersion.current
        #expect(sv.versionString == "\(sv.major).\(sv.minor).\(sv.patch)")
    }

    @Test func testDescription() {
        let sv = SystemVersion.current
        #expect(sv.description == "\(sv.major).\(sv.minor).\(sv.patch)")
    }

    @Test func testFalibleInit() {
        let sv = SystemVersion.current
        #expect(SystemVersion(sv.description) == sv)
    }

    @Test func testStringInit() throws {
        let svStr = SystemVersion.current.description
        #expect(try SystemVersion(string: svStr) == SystemVersion.current)

        let badSVStr = "1.2"
        #expect(throws: SystemVersionError.self) {
            try SystemVersion(string: badSVStr)
        }
    }

    @Test func testCodable() throws {
        try expectCodable(SystemVersion.self)
    }

    @Test func testURLRequestVersioningHeader() throws {
        let url = URL(string: "http://foo.com")!
        var urlRequest = URLRequest(url: url)
        let sv = SystemVersion.current
        urlRequest.addSystemVersioningHeader(systemVersion: sv)

        #expect(urlRequest.value(forHTTPHeaderField: URLRequest.systemVersioningHeader) == sv.versionString)
    }

    @Test func testHTTPURLResponseVersioningHeader() throws {
        let url = URL(string: "http://foo.com")!
        let sv = SystemVersion.current
        let urlResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [
            URLRequest.systemVersioningHeader: sv.versionString
        ])!

        #expect(try urlResponse.systemVersion.isSameVersion(as: sv))
    }

    @Test func testIsSameVersion() {
        #expect(SystemVersion.current.isSameVersion(as: SystemVersion.current))
        #expect(!SystemVersion(major: 99, minor: 99, patch: 99).isSameVersion(as: SystemVersion.current))
    }

    @Test func testIsCompatible() {
        #expect(SystemVersion.current.isCompatible(with: SystemVersion.current))

        // Differing Patches shouldn't matter
        #expect(SystemVersion(patch: SystemVersion.current.patch + 1).isCompatible(with: SystemVersion.current))
        #expect(SystemVersion(patch: SystemVersion.current.patch - 1).isCompatible(with: SystemVersion.current))

        // Incrementing minors
        #expect(!SystemVersion(minor: SystemVersion.current.minor + 1).isCompatible(with: SystemVersion.current))
        #expect(SystemVersion(minor: SystemVersion.current.minor - 1).isCompatible(with: SystemVersion.current))

        // Differing Majors
        #expect(!SystemVersion(major: SystemVersion.current.major + 1).isCompatible(with: SystemVersion.current))
        #expect(!SystemVersion(major: SystemVersion.current.major - 1).isCompatible(with: SystemVersion.current))
    }

    @Test func testSetCurrentVersion() {
        let major = 5
        let minor = 6
        let patch = 7

        #expect(SystemVersion.current.major != major)
        #expect(SystemVersion.current.minor != minor)
        #expect(SystemVersion.current.patch != patch)

        SystemVersion.setCurrentVersion(
            .init(major: major, minor: minor, patch: patch)
        )

        #expect(SystemVersion.current.major == major)
        #expect(SystemVersion.current.minor == minor)
        #expect(SystemVersion.current.patch == patch)
    }
}
