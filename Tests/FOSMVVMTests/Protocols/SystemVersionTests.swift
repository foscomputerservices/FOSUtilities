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

import FOSMVVM
import FOSTesting
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing

@Suite("SystemVersion Tests")
struct SystemVersionTests {
    @Test func testVersionStr() {
        let sv = MySystemVersion()
        #expect(sv.versionString == "\(MySystemVersion.defaultMajor).\(MySystemVersion.defaultMinor).\(MySystemVersion.defaultPatch)")
    }

    @Test func testCodable() throws {
        try expectCodable(MySystemVersion.self)
    }

    @Test func testURLRequestVersioningHeader() throws {
        let url = URL(string: "http://foo.com")!
        var urlRequest = URLRequest(url: url)
        let sv = MySystemVersion.currentVersion
        urlRequest.addSystemVersioningHeader(systemVersion: sv)

        #expect(urlRequest.value(forHTTPHeaderField: URLRequest.systemVersioningHeader) == sv.versionString)
    }

    @Test func testHTTPURLResponseVersioningHeader() throws {
        let url = URL(string: "http://foo.com")!
        let sv = MySystemVersion.currentVersion
        let urlResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [
            URLRequest.systemVersioningHeader: sv.versionString
        ])!

        #expect(try urlResponse.systemVersion.isSameVersion(as: sv))
    }

    @Test func testIsSameVersion() {
        #expect(MySystemVersion().isSameVersion(as: MySystemVersion()))
        #expect(!MySystemVersion(majorVersion: 99, minorVersion: 99, patchVersion: 99).isSameVersion(as: MySystemVersion()))
    }

    @Test func testIsCompatible() {
        #expect(MySystemVersion().isCompatible(with: MySystemVersion()))

        // Differing Patches shouldn't matter
        #expect(MySystemVersion(patchVersion: MySystemVersion.defaultPatch + 1).isCompatible(with: MySystemVersion()))
        #expect(MySystemVersion(patchVersion: MySystemVersion.defaultPatch - 1).isCompatible(with: MySystemVersion()))

        // Incrementing minors
        #expect(!MySystemVersion(minorVersion: MySystemVersion.defaultMinor + 1).isCompatible(with: MySystemVersion()))
        #expect(MySystemVersion(minorVersion: MySystemVersion.defaultMinor - 1).isCompatible(with: MySystemVersion()))

        // Differing Majors
        #expect(!MySystemVersion(majorVersion: MySystemVersion.defaultMajor + 1).isCompatible(with: MySystemVersion()))
        #expect(!MySystemVersion(majorVersion: MySystemVersion.defaultMajor - 1).isCompatible(with: MySystemVersion()))
    }
}

struct MySystemVersion: SystemVersion {
    let majorVersion: Int
    let minorVersion: Int
    let patchVersion: Int

    static let currentVersion = Self()

    static let defaultMajor = 1
    static let defaultMinor = 2
    static let defaultPatch = 3

    init(majorVersion: Int = Self.defaultMajor, minorVersion: Int = Self.defaultMinor, patchVersion: Int = Self.defaultPatch) {
        self.majorVersion = majorVersion
        self.minorVersion = minorVersion
        self.patchVersion = patchVersion
    }
}
