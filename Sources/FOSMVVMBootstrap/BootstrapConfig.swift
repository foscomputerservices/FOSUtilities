// BootstrapConfig.swift
import Foundation

/// Typed input to the scaffolder. Loaded from JSON (`--config`); the
/// plugin skill authors this file from its conversational interview.
public struct BootstrapConfig: Codable, Sendable {
    public let projectName: String
    public let shape: ProjectShape
    /// Platform → minimum version string ("14.0"). Must be at or above the
    /// pinned FOSUtilities floor — `validate()` enforces this.
    public let platforms: [TargetPlatform: String]
    public let licenseHeader: String?
    /// Reverse-DNS root for the app and derived per-module bundle ids
    /// (e.g. "com.example.palettepress"). Required for app shapes.
    public let bundleIdRoot: String?
    /// Apple Development Team ID (10 chars). Required for app shapes.
    public let teamId: String?

    public init(
        projectName: String,
        shape: ProjectShape,
        platforms: [TargetPlatform: String],
        licenseHeader: String? = nil,
        bundleIdRoot: String? = nil,
        teamId: String? = nil
    ) {
        self.projectName = projectName
        self.shape = shape
        self.platforms = platforms
        self.licenseHeader = licenseHeader
        self.bundleIdRoot = bundleIdRoot
        self.teamId = teamId
    }

    /// Rejects configs that would generate broken or leak-prone projects.
    public func validate() throws {
        guard projectName.range(of: "^[A-Za-z][A-Za-z0-9]*$", options: .regularExpression) != nil else {
            throw BootstrapConfigError.invalidProjectName(projectName)
        }
        guard !platforms.isEmpty else {
            throw BootstrapConfigError.noPlatforms
        }
        try FOSPlatformFloor.validate(platforms: platforms)

        // App shapes ship a real Xcode app target, so they need a bundle-id
        // root and a signing team; sharedLibrary is a plain SPM package and
        // needs neither.
        guard shape != .sharedLibrary else { return }

        guard let bundleIdRoot else {
            throw BootstrapConfigError.missingBundleIdRoot
        }
        guard bundleIdRoot.range(of: Self.bundleIdRootPattern, options: .regularExpression) != nil else {
            throw BootstrapConfigError.invalidBundleIdRoot(bundleIdRoot)
        }

        guard let teamId else {
            throw BootstrapConfigError.missingTeamId
        }
        guard teamId.range(of: Self.teamIdPattern, options: .regularExpression) != nil else {
            throw BootstrapConfigError.invalidTeamId(teamId)
        }

        // Both app shapes this repo emits generate a macOS Xcode project, so
        // both require a macOS deployment target.
        if shape == .localOnly || shape == .clientServer, platforms[.macOS] == nil {
            throw BootstrapConfigError.missingPlatform(.macOS)
        }
    }

    private static let bundleIdRootPattern = "^[a-z][a-z0-9-]*(\\.[a-z][a-z0-9-]*)+$"
    private static let teamIdPattern = "^[A-Z0-9]{10}$"
}

public enum BootstrapConfigError: Error, Equatable {
    case invalidProjectName(String)
    case noPlatforms
    case belowFOSFloor(platform: TargetPlatform, asked: String, floor: String)
    case platformUnsupportedByFOS(TargetPlatform)
    case missingBundleIdRoot
    case invalidBundleIdRoot(String)
    case missingTeamId
    case invalidTeamId(String)
    case missingPlatform(TargetPlatform)
}
