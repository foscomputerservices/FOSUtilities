// EmitterSourceTests.swift
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

import FOSMVVMBootstrap
import Foundation
import Testing

/// Where an emitted project resolves FOSUtilities from — the release pin by
/// default, or a local checkout.
struct EmitterSourceTests {
    func emittedText(_ out: URL, _ path: String) throws -> String {
        try String(contentsOf: out.appendingPathComponent(path), encoding: .utf8)
    }

    func makeLocalOnlyConfig() -> BootstrapConfig {
        BootstrapConfig(
            projectName: "PalettePress",
            shape: .localOnly,
            platforms: [.macOS: "14.0"],
            bundleIdRoot: "com.example.palettepress",
            teamId: "ABCDE12345"
        )
    }

    @Test func localCheckoutRendersAPathDependency() throws {
        let checkout = FileManager.default.temporaryDirectory
            .appendingPathComponent("checkout-\(UUID().uuidString)")
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("emit-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: checkout)
            try? FileManager.default.removeItem(at: out)
        }
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        try "// swift-tools-version: 6.0".write(
            to: checkout.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8
        )

        try Emitter.emit(config: makeLocalOnlyConfig(), into: out, fosUtilities: .localCheckout(checkout))

        let projectYAML = try emittedText(out, "project.yml")
        #expect(projectYAML.contains("  FOSUtilities:\n    path: \(checkout.path)\n"))
        #expect(!projectYAML.contains("FOSUtilities.git"))
    }

    @Test func localCheckoutWithoutAManifestIsRefused() throws {
        let checkout = FileManager.default.temporaryDirectory
            .appendingPathComponent("checkout-\(UUID().uuidString)")
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("emit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }

        #expect(throws: EmitterError.fosUtilitiesCheckoutNotFound(checkout.path)) {
            _ = try Emitter.emit(config: makeLocalOnlyConfig(), into: out, fosUtilities: .localCheckout(checkout))
        }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }
}
