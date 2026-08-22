// TokenSet.swift

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
