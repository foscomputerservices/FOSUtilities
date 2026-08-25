// IntegrationTests.swift
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

extension Tag {
    @Tag static var integration: Tag
}

// Walking skeletons (migration design §7): emit each shape and run its
// verification doors. Slow (~8 min) and network-resolving, so they only run
// when FOSMVVM_BOOTSTRAP_SKELETONS=1 — CI's generation-matrix job sets it;
// bare `swift test` skips them.
// .serialized: each skeleton resolves and compiles the full FOSUtilities
// dependency graph; in parallel they contend for a 3–4 core hosted runner
// (localOnly: 123s alone vs 300s contended), and one timed-out test's
// process kill discards the skeletons that haven't run yet.
@Suite(
    .tags(.integration),
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["FOSMVVM_BOOTSTRAP_SKELETONS"] == "1")
) struct IntegrationTests {
    /// Full walking-skeleton proof for the shared-library shape:
    /// emit → swift build → swift test inside the generated project,
    /// exercising the real FOSUtilities dependency, the YAML
    /// localization round-trip, and the codable round-trip.
    @Test(.timeLimit(.minutes(10)))
    func sharedLibraryWalkingSkeletonIsGreen() throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("skeleton-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }

        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .sharedLibrary,
            platforms: [.macOS: "14.0", .iOS: "17.0"]
        )
        try Emitter.emit(config: config, into: out)
        try Verifier.verify(projectDir: out, steps: Verifier.steps(for: .sharedLibrary))
        try expectDoctorClean(out, shape: .sharedLibrary)
    }

    /// Local-only walking-skeleton proof: emit → xcodegen generate →
    /// xcodebuild build (macOS, unsigned). Fails with a typed
    /// toolMissing when xcodegen is not installed (brew install xcodegen).
    @Test(.timeLimit(.minutes(15)))
    func localOnlyWalkingSkeletonBuilds() throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("skeleton-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }

        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .localOnly,
            platforms: [.macOS: "14.0"],
            bundleIdRoot: "com.example.palettepress",
            teamId: "ABCDE12345"
        )
        try Emitter.emit(config: config, into: out)
        try Verifier.verify(
            projectDir: out,
            steps: Verifier.generationSteps(for: .localOnly) + Verifier.steps(for: .localOnly),
            projectName: "PalettePress"
        )
        try expectDoctorClean(out, shape: .localOnly)
    }

    /// Client-server (= hybrid) walking-skeleton proof: emit → the four-step door.
    /// `swift build` + `swift test` boot Fluent on SQLite-in-memory, create a card
    /// through the real pipeline, and assert the refreshed live board (no database
    /// server, no simulator); `xcodegen` + `xcodebuild` build the app (umbrella +
    /// client-hosted framework + source-included contract).
    @Test(.timeLimit(.minutes(25)))
    func clientServerWalkingSkeletonBuilds() throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("cs-skeleton-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }

        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .clientServer,
            platforms: [.macOS: "14.0"],
            bundleIdRoot: "com.example.palettepress",
            teamId: "ABCDE12345"
        )
        try Emitter.emit(config: config, into: out)
        try Verifier.verify(
            projectDir: out,
            steps: Verifier.generationSteps(for: .clientServer) + Verifier.steps(for: .clientServer),
            projectName: "PalettePress"
        )
        try expectDoctorClean(out, shape: .clientServer)
    }

    /// The conformance assertion: the rules table judges a project the emitter
    /// just produced, and finds nothing.
    ///
    /// This is what makes the table truth rather than a second opinion. Without
    /// it, `doctor` and the templates could drift apart indefinitely, each
    /// internally consistent — and the first person to notice would be a
    /// customer whose correctly-generated project was told it was wrong.
    ///
    /// It rides here, rather than in the fast suite, because judging a real
    /// `.xcodeproj` means one has to exist — and these tests have already paid
    /// for `xcodegen`.
    private func expectDoctorClean(_ projectDir: URL, shape: ProjectShape) throws {
        let report = try Doctor.examine(projectAt: projectDir, shape: shape)
        #expect(
            report.findings.isEmpty,
            "doctor found problems in a freshly generated \(shape.rawValue) project:\n\(report.text)"
        )
    }
}
