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
// dependency graph; run in parallel they starve a 3–4 core hosted runner
// past the time limits (sharedLibrary is ~40s alone, >600s contended).
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
    }
}
