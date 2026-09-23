// DoctorAssetTests.swift
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

/// R15 — the app-icon setting and the icon set it names.
@Suite("Doctor — asset catalog")
struct DoctorAssetTests {
    @Test("R15 — an icon setting that names a missing set is a warning")
    func iconSettingNamesAMissingSet() throws {
        let report = try Fixture.localOnly(shape: .localOnly) { root in
            try FileManager.default.removeItem(
                at: root.appendingPathComponent("Sources/PalettePress/Assets.xcassets/AppIcon.appiconset")
            )
        }
        let finding = try #require(report.findings.first { $0.summary.contains("no icon set called AppIcon") })
        #expect(finding.severity == .warning)
        #expect(finding.target == "PalettePress")
        #expect(!report.hasErrors, "an absent icon does not fail the build, so it must not fail the gate")
    }

    @Test("R15 — the finding names the set the setting asked for")
    func findingNamesTheDeclaredSet() throws {
        let report = try Fixture.localOnly(
            mutatingProject: { $0.replacingOccurrences(of: "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;", with: "ASSETCATALOG_COMPILER_APPICON_NAME = Missing;") },
            shape: .localOnly
        )
        let finding = try #require(report.findings.first { $0.summary.contains("no icon set called Missing") })
        #expect(finding.remedy.contains("Missing.appiconset"))
    }

    @Test("R15 — a project whose icon set is a vision stack passes")
    func visionStackCountsAsAnIconSet() throws {
        let report = try Fixture.localOnly(shape: .localOnly) { root in
            let catalog = root.appendingPathComponent("Sources/PalettePress/Assets.xcassets")
            try FileManager.default.removeItem(at: catalog.appendingPathComponent("AppIcon.appiconset"))
            try FileManager.default.createDirectory(
                at: catalog.appendingPathComponent("AppIcon.solidimagestack"),
                withIntermediateDirectories: false
            )
        }
        #expect(!report.findings.contains { $0.summary.contains("no icon set called") }, "unexpected: \(report.text)")
    }

    @Test("R15 — an app target with no icon setting at all is a warning")
    func missingIconSetting() throws {
        let report = try Fixture.localOnly(
            mutatingProject: { $0.replacingOccurrences(of: "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;", with: "") },
            shape: .localOnly
        )
        let finding = try #require(report.findings.first { $0.summary.contains("ASSETCATALOG_COMPILER_APPICON_NAME is not set") })
        #expect(finding.severity == .warning)
    }
}
