// VersionedBaselinePathTests.swift
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
import FOSMVVM
import FOSTesting
import Foundation
import Testing

/// Throwaway ViewModels used only to drive baseline-file placement.
@ViewModel
struct PathAnchorTestVM {
    let value: Int
    var vmId = ViewModelId()

    static func stub() -> Self {
        .init(value: 1)
    }
}

@ViewModel
struct ForwardingTestVM {
    let value: Int
    var vmId = ViewModelId()

    static func stub() -> Self {
        .init(value: 1)
    }
}

@Suite("Versioned Baseline Path Anchoring")
struct VersionedBaselinePathTests {
    /// The version baseline directory must anchor on the SwiftPM test-target root
    /// (`Tests/<Target>/.VersionedTestJSON`), independent of how deeply the calling
    /// test file is nested — NOT two directories up from the file.
    @Test func anchorsOnTestTargetRootRegardlessOfDepth() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("VTJ-\(UUID().uuidString)")

        // A deeply-nested test file path: <tempRoot>/Tests/AnchorTarget/Deep/Nested/Foo.swift
        let fakeFile = tempRoot
            .appendingPathComponent("Tests")
            .appendingPathComponent("AnchorTarget")
            .appendingPathComponent("Deep")
            .appendingPathComponent("Nested")
            .appendingPathComponent("FooTests.swift")

        let expectedDir = tempRoot
            .appendingPathComponent("Tests")
            .appendingPathComponent("AnchorTarget")
            .appendingPathComponent(".VersionedTestJSON")

        // The old (buggy) two-up location, which must NOT be used.
        let wrongDir = tempRoot
            .appendingPathComponent("Tests")
            .appendingPathComponent("AnchorTarget")
            .appendingPathComponent("Deep")
            .appendingPathComponent(".VersionedTestJSON")

        defer { try? fm.removeItem(at: tempRoot) }

        try expectVersionedViewModel(PathAnchorTestVM.self, file: fakeFile.path)

        #expect(fm.fileExists(atPath: expectedDir.path))
        #expect(!fm.fileExists(atPath: wrongDir.path))
    }
}

@Suite("Versioned Baseline Forwarding")
struct VersionedBaselineForwardingTests: LocalizableTestCase {
    let locStore: LocalizationStore
    init() throws {
        self.locStore = try Self.loadLocalizationStore(
            bundle: .module,
            resourceDirectoryName: "TestYAML"
        )
    }

    /// `expectFullViewModelTests` must persist its version baseline beside the
    /// *caller's* test file, not FOSTesting's own source. It proves this by
    /// forwarding an explicit `file:` and confirming the baseline lands under the
    /// target root derived from that path.
    @Test func fullViewModelTestsForwardsCallerFile() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("VTJ-\(UUID().uuidString)")

        let fakeFile = tempRoot
            .appendingPathComponent("Tests")
            .appendingPathComponent("FwdTarget")
            .appendingPathComponent("Sub")
            .appendingPathComponent("BarTests.swift")

        let expectedDir = tempRoot
            .appendingPathComponent("Tests")
            .appendingPathComponent("FwdTarget")
            .appendingPathComponent(".VersionedTestJSON")

        defer { try? fm.removeItem(at: tempRoot) }

        try expectFullViewModelTests(ForwardingTestVM.self, file: fakeFile.path)

        #expect(fm.fileExists(atPath: expectedDir.path))
    }
}
