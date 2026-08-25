// BootstrapConfig.swift
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
    /// Which iOS device families the app targets when `platforms` includes
    /// iOS: any of "iPhone", "iPad". Omitted means both.
    public let iosDevices: [String]?
    /// Run the unmodified iPad app on Apple Silicon Macs ("Designed for
    /// iPad"). Only meaningful when iOS is present and macOS is not;
    /// omitted means the platform default (allowed).
    public let macDesignedForIPad: Bool?
    /// Run the unmodified iPad app on Apple Vision ("Designed for iPad").
    /// Only meaningful when iOS is present and visionOS is not; omitted
    /// means the platform default (allowed).
    public let visionDesignedForIPad: Bool?

    public init(
        projectName: String,
        shape: ProjectShape,
        platforms: [TargetPlatform: String],
        licenseHeader: String? = nil,
        bundleIdRoot: String? = nil,
        teamId: String? = nil,
        iosDevices: [String]? = nil,
        macDesignedForIPad: Bool? = nil,
        visionDesignedForIPad: Bool? = nil
    ) {
        self.projectName = projectName
        self.shape = shape
        self.platforms = platforms
        self.licenseHeader = licenseHeader
        self.bundleIdRoot = bundleIdRoot
        self.teamId = teamId
        self.iosDevices = iosDevices
        self.macDesignedForIPad = macDesignedForIPad
        self.visionDesignedForIPad = visionDesignedForIPad
    }

    /// Per-field predicates, public so an interactive front end can validate
    /// each answer as it is given; validate() composes the same rules.
    public static func isValidProjectName(_ name: String) -> Bool {
        name.range(of: "^[A-Za-z][A-Za-z0-9]*$", options: .regularExpression) != nil
    }

    public static func isValidBundleIdRoot(_ root: String) -> Bool {
        root.range(of: bundleIdRootPattern, options: .regularExpression) != nil
    }

    public static func isValidTeamId(_ id: String) -> Bool {
        id.range(of: teamIdPattern, options: .regularExpression) != nil
    }

    /// Rejects configs that would generate broken or leak-prone projects.
    public func validate() throws {
        guard Self.isValidProjectName(projectName) else {
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
        guard Self.isValidBundleIdRoot(bundleIdRoot) else {
            throw BootstrapConfigError.invalidBundleIdRoot(bundleIdRoot)
        }

        guard let teamId else {
            throw BootstrapConfigError.missingTeamId
        }
        guard Self.isValidTeamId(teamId) else {
            throw BootstrapConfigError.invalidTeamId(teamId)
        }

        // App shapes need at least one destination the multiplatform app
        // target can host (watchOS rides a separate target and cannot be the
        // only platform yet).
        let appDestinations: [TargetPlatform] = [.macOS, .iOS, .tvOS, .visionOS]
        if shape == .localOnly || shape == .clientServer,
           !appDestinations.contains(where: { platforms[$0] != nil }) {
            throw BootstrapConfigError.noAppDestinations
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
    case noAppDestinations
}
