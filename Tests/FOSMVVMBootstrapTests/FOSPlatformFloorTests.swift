// FOSPlatformFloorTests.swift
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

struct FOSPlatformFloorTests {
    @Test func atFloorPasses() throws {
        try FOSPlatformFloor.validate(platforms: [.macOS: "14.0", .iOS: "17.0"])
    }

    @Test func aboveFloorPasses() throws {
        try FOSPlatformFloor.validate(platforms: [.macOS: "26.0"])
    }

    @Test func belowFloorThrows() {
        #expect(throws: BootstrapConfigError.belowFOSFloor(platform: .macOS, asked: "13.0", floor: "14.0")) {
            try FOSPlatformFloor.validate(platforms: [.macOS: "13.0"])
        }
    }

    @Test func minorVersionComparesNumerically() {
        // "10.4" < "10.15" numerically even though it sorts *after* lexically —
        // this is the case a lexical-compare regression would get wrong.
        #expect(FOSPlatformFloor.compareVersions("10.4", "10.15") == .orderedAscending)
        // A missing component defaults to 0, so "14" and "14.0" are equal.
        #expect(FOSPlatformFloor.compareVersions("14", "14.0") == .orderedSame)
    }
}
