// ReleaseConsistencyTests.swift
import FOSMVVMBootstrap
import Foundation
import Testing

// The two drift-proofing tests from the migration design (§6): the release
// ritual stamps CHANGELOG.md and Release.version in one commit, and the
// floors table must mirror this package's own platforms. Both are compared
// against the repo files via #filePath, so drift fails CI instead of a user.
@Suite struct ReleaseConsistencyTests {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath) // .../Tests/FOSMVVMBootstrapTests/ReleaseConsistencyTests.swift
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test func releaseVersionMatchesTopmostChangelogStamp() throws {
        let changelog = try String(contentsOf: repoRoot.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
        let pattern = #/^## \[(\d+\.\d+\.\d+)\] - /#.anchorsMatchLineEndings()
        let stamped = try #require(changelog.firstMatch(of: pattern)?.1)
        #expect(
            String(stamped) == Release.version,
            "Release.version (\(Release.version)) must match the topmost stamped CHANGELOG release (\(stamped)) — the stamp commit updates both."
        )
    }

    @Test func floorsMatchThisPackagesPlatforms() throws {
        let manifest = try String(contentsOf: repoRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
        let platformNames: [TargetPlatform: String] = [
            .iOS: "iOS", .macOS: "macOS", .macCatalyst: "macCatalyst",
            .tvOS: "tvOS", .watchOS: "watchOS", .visionOS: "visionOS"
        ]
        for (platform, manifestName) in platformNames {
            let floor = try #require(FOSPlatformFloor.floors[platform], "floors table is missing \(manifestName)")
            // Manifest form: .iOS(.v17) / .macOS(.v14) — major-only versions.
            let major = floor.split(separator: ".").first.map(String.init) ?? floor
            #expect(
                manifest.contains(".\(manifestName)(.v\(major))"),
                "floors[\(manifestName)] = \(floor) has no matching .\(manifestName)(.v\(major)) in Package.swift platforms:"
            )
        }
    }
}
