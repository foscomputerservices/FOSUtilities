// TokenSet.swift
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

/// Derives every template token from the validated config.
/// Derivation lives here in typed Swift — never in templates and never
/// as free-text inputs — so a token's value cannot drift or leak.
public enum TokenSet {
    /// Derives the full `{{TOKEN}}` → value map for `TemplateRenderer`:
    /// `let tokens = try TokenSet.derive(from: config)`. Validates
    /// `config` first, so a bad config throws here rather than emitting
    /// a broken project.
    public static func derive(from config: BootstrapConfig) throws -> [String: String] {
        try config.validate()

        var tokens = [
            "PROJECT_NAME": config.projectName,
            "FOS_VERSION": FOSPlatformFloor.pinnedFOSVersion,
            "PLATFORMS": platformsLine(config.platforms),
            "LICENSE_HEADER": config.licenseHeader ?? ""
        ]

        // App shapes carry the bundle-id root, signing team, and macOS
        // deployment target; sharedLibrary keeps exactly the four tokens above.
        // validate() has already guaranteed these are present and well-formed.
        if config.shape != .sharedLibrary {
            tokens["BUNDLE_ID_ROOT"] = config.bundleIdRoot
            tokens["TEAM_ID"] = config.teamId
            tokens["MACOS_DEPLOYMENT"] = config.platforms[.macOS]

            // The Xcode-project surface follows the config's platforms map —
            // every platform, macOS included, is opt-in; validate() requires
            // at least one destination the app target can host.
            // xcodegen's supportedDestinations (not platform:) is load-bearing:
            // it emits SDKROOT=auto and TARGETED_DEVICE_FAMILY, without which
            // Xcode's destination editor shows Mac only even though xcodebuild
            // can already build every listed destination (measured 2026-08-22).
            // watchOS is deliberately absent: a multiplatform app target
            // cannot contain it (xcodegen validation) — it is the separate-
            // target follow-on of the migration design's §4.
            var destinations: [String] = []
            var deploymentLines = ""
            var families: [String] = []

            if let macDeployment = config.platforms[.macOS] {
                destinations.append("macOS")
                deploymentLines += "\n    macOS: \"\(macDeployment)\""
            }
            if let iOSDeployment = config.platforms[.iOS] {
                destinations.append("iOS")
                deploymentLines += "\n    iOS: \"\(iOSDeployment)\""
                let devices = config.iosDevices ?? ["iPhone", "iPad"]
                if devices.contains("iPhone") {
                    families.append("1")
                }
                if devices.contains("iPad") {
                    families.append("2")
                }
            }
            if let tvDeployment = config.platforms[.tvOS] {
                destinations.append("tvOS")
                deploymentLines += "\n    tvOS: \"\(tvDeployment)\""
                families.append("3")
            }
            if let visionDeployment = config.platforms[.visionOS] {
                destinations.append("visionOS")
                deploymentLines += "\n    visionOS: \"\(visionDeployment)\""
                families.append("7")
            }

            // Frameworks additionally carry watchOS (probed green) — the app
            // target cannot, so the watch app is its own emitted target.
            var frameworkDestinations = destinations
            if let watchDeployment = config.platforms[.watchOS] {
                frameworkDestinations.append("watchOS")
                deploymentLines += "\n    watchOS: \"\(watchDeployment)\""
            }

            tokens["SUPPORTED_DESTINATIONS"] = "[\(destinations.joined(separator: ", "))]"
            tokens["FRAMEWORK_DESTINATIONS"] = "[\(frameworkDestinations.joined(separator: ", "))]"
            tokens["WATCH_TARGET"] = Self.watchTargetYAML(config: config)
            tokens["WATCH_SCHEME"] = Self.watchSchemeYAML(config: config)
            tokens["DEPLOYMENT_TARGETS"] = deploymentLines
            // Both overrides are injected into the APP TARGET's settings
            // (8-space YAML indent): xcodegen's supportedDestinations emits
            // its own target-level values, and target-level settings override
            // project-level ones — a base-settings override silently loses
            // (measured 2026-08-22). Empty when xcodegen's derivation stands.
            tokens["DEVICE_FAMILY_OVERRIDE"] = families.isEmpty
                ? ""
                : "\n        TARGETED_DEVICE_FAMILY: \"\(families.joined(separator: ","))\""
            // An iOS app is offered on Apple Vision and on Apple Silicon
            // Macs in "Designed for iPad" compatibility mode by default
            // (Apple's default). The config records an EXPLICIT decline from
            // the interview's questions; omitted means allowed.
            var compatOverrides = ""
            if config.platforms[.iOS] != nil, config.visionDesignedForIPad == false {
                compatOverrides += "\n        SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD: NO"
            }
            if config.platforms[.iOS] != nil, config.macDesignedForIPad == false {
                compatOverrides += "\n        SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: NO"
            }
            tokens["XR_COMPAT_OVERRIDE"] = compatOverrides
        }

        return tokens
    }

    /// `.iOS("17.0"),\n        .macOS("14.0")` — string-literal platform
    /// form (valid PackageDescription), deterministic ordering.
    static func platformsLine(_ platforms: [TargetPlatform: String]) -> String {
        platforms
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { ".\($0.key.rawValue)(\"\($0.value)\")" }
            .joined(separator: ",\n        ")
    }
}
