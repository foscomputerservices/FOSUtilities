// Fixture.swift
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

// Fixture.swift
@testable import FOSMVVMBootstrap
import Foundation
import Testing

/// Materializes a committed fixture project into a temp directory, optionally
/// breaking it on the way, and audits it.
///
/// Fixtures are real generated projects, frozen at the point they were
/// committed. They are stored with the `.xcodeprojfixture` suffix so nothing —
/// Xcode, SwiftPM, a repo-wide search — treats them as a live project; the
/// suffix is restored to `.xcodeproj` when a copy is made.
enum Fixture {
    enum FixtureError: Error {
        case notBundled(String)
    }

    static func localOnly(
        mutatingProject: ((String) -> String)? = nil,
        mutatingEntitlements: ((String) -> String)? = nil,
        shape: ProjectShape? = nil,
        then edit: ((URL) throws -> Void)? = nil
    ) throws -> Doctor.Report {
        try examine(
            "LocalOnly",
            entitlementsPath: "Sources/PalettePress/PalettePress.entitlements",
            mutatingProject: mutatingProject,
            mutatingEntitlements: mutatingEntitlements,
            shape: shape,
            then: edit
        )
    }

    static func clientServer(
        mutatingProject: ((String) -> String)? = nil,
        mutatingEntitlements: ((String) -> String)? = nil,
        mutatingManifest: ((String) -> String)? = nil,
        mutatingTestPlan: (([String: Any]) -> [String: Any])? = nil,
        shape: ProjectShape? = nil
    ) throws -> Doctor.Report {
        try examine(
            "ClientServer",
            entitlementsPath: "Sources/PalettePress/PalettePress.entitlements",
            mutatingProject: mutatingProject,
            mutatingEntitlements: mutatingEntitlements,
            mutatingManifest: mutatingManifest,
            mutatingTestPlan: mutatingTestPlan,
            shape: shape
        )
    }

    /// The unmutated project directory, for callers that want to audit it
    /// themselves.
    static func localOnly() throws -> URL {
        try materialize("LocalOnly")
    }

    static func clientServer() throws -> URL {
        try materialize("ClientServer")
    }

    /// The shared-library shape: an SPM package with no `.xcodeproj` at all.
    /// Every Xcode-reading rule has to stay silent here rather than report a
    /// project-wide failure.
    static func sharedLibrary() throws -> URL {
        try materialize("SharedLibrary")
    }

    static func sharedLibrary(
        mutatingManifest: ((String) -> String)? = nil,
        shape: ProjectShape? = nil,
        then edit: ((URL) throws -> Void)? = nil
    ) throws -> Doctor.Report {
        try examine(
            "SharedLibrary",
            entitlementsPath: nil,
            mutatingManifest: mutatingManifest,
            shape: shape,
            then: edit
        )
    }
}

private extension Fixture {
    static func examine(
        _ name: String,
        entitlementsPath: String?,
        mutatingProject: ((String) -> String)? = nil,
        mutatingEntitlements: ((String) -> String)? = nil,
        mutatingManifest: ((String) -> String)? = nil,
        mutatingTestPlan: (([String: Any]) -> [String: Any])? = nil,
        shape: ProjectShape?,
        then edit: ((URL) throws -> Void)? = nil
    ) throws -> Doctor.Report {
        let root = try materialize(name)

        if let mutatingProject {
            try rewrite(root.appendingPathComponent("PalettePress.xcodeproj/project.pbxproj"), mutatingProject)
        }
        if let mutatingEntitlements, let entitlementsPath {
            try rewrite(root.appendingPathComponent(entitlementsPath), mutatingEntitlements)
        }
        if let mutatingManifest {
            try rewrite(root.appendingPathComponent("Package.swift"), mutatingManifest)
        }
        if let mutatingTestPlan {
            let url = root.appendingPathComponent("PalettePress.xctestplan")
            let plan = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
            let data = try JSONSerialization.data(withJSONObject: mutatingTestPlan(plan), options: .prettyPrinted)
            try data.write(to: url)
        }
        try edit?(root)

        return try Doctor.examine(projectAt: root, shape: shape)
    }

    static func rewrite(_ url: URL, _ transform: (String) -> String) throws {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let rewritten = transform(contents)
        #expect(rewritten != contents, "mutation changed nothing — the fixture no longer contains what the test edits")
        try Data(rewritten.utf8).write(to: url)
    }

    /// Copies a fixture into a fresh temp directory, restoring the real
    /// `.xcodeproj` suffix.
    static func materialize(_ name: String) throws -> URL {
        guard let source = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil) else {
            throw FixtureError.notBundled(name)
        }

        let fm = FileManager.default
        let destination = fm.temporaryDirectory
            .appendingPathComponent("doctor-fixture-\(UUID().uuidString)")
        try fm.copyItem(at: source, to: destination)

        if let walker = fm.enumerator(at: destination, includingPropertiesForKeys: nil) {
            for case let url as URL in walker where url.pathExtension == "xcodeprojfixture" {
                try fm.moveItem(
                    at: url,
                    to: url.deletingPathExtension().appendingPathExtension("xcodeproj")
                )
            }
        }
        return destination
    }
}
