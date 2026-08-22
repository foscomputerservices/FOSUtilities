// Interview.swift
import ArgumentParser
import FOSFoundation
import FOSMVVMBootstrap
import Foundation

/// Collects a `BootstrapConfig` conversationally when `new` is run without
/// `--config` — each answer is validated as it is given (the same rules
/// `validate()` enforces), with the FOSUtilities floors as defaults.
/// Answers can be piped through stdin; end-of-input without a complete
/// config fails with a pointer to `--config` for non-interactive use.
enum Interview {
    static func conduct(outputDir: URL) throws -> BootstrapConfig {
        // The output directory's name, CamelCased (FOSFoundation), is the
        // default project name — camelCased() splits on underscores, so the
        // usual directory separators normalize to them first. An invalid
        // candidate (e.g. a leading digit) simply yields no default.
        let candidate = outputDir.lastPathComponent
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .camelCased()
        let projectName = try ask(
            "Project name",
            default: BootstrapConfig.isValidProjectName(candidate) ? candidate : nil,
            invalid: "must start with a letter and contain only letters and digits",
            valid: BootstrapConfig.isValidProjectName
        )

        let shape = try askShape()

        // Per-device questions, every platform opt-in; iPhone/iPad share the
        // iOS destination and differ by device family. At least one of
        // Mac/iPhone/iPad/TV/Vision must be chosen (the watch rides a
        // separate target and cannot yet be the only platform).
        var platforms: [TargetPlatform: String] = [:]
        var iosDevices: [String] = []
        repeat {
            if try askYesNo("Include Mac?") {
                platforms[.macOS] = try askVersion(for: .macOS)
            }
            if try askYesNo("Include iPhone?") { iosDevices.append("iPhone") }
            if try askYesNo("Include iPad?") { iosDevices.append("iPad") }
            if !iosDevices.isEmpty {
                platforms[.iOS] = try askVersion(for: .iOS)
            }
            if try askYesNo("Include Apple TV?") {
                platforms[.tvOS] = try askVersion(for: .tvOS)
            }
            if try askYesNo("Include Apple Vision?") {
                platforms[.visionOS] = try askVersion(for: .visionOS)
            }
            if try askYesNo("Include Apple Watch?") {
                platforms[.watchOS] = try askVersion(for: .watchOS)
            }
            if platforms.keys.contains(where: { $0 != .watchOS }) { break }
            print("  ✗ choose at least one of Mac, iPhone, iPad, Apple TV, or Apple Vision")
        } while true

        // "Designed for iPad" compatibility: the unmodified iPad app on Apple
        // Silicon Macs / Apple Vision. Asked only when iOS is chosen and the
        // native platform is not; Apple's default is yes.
        var macDesignedForIPad: Bool?
        var visionDesignedForIPad: Bool?
        if platforms[.iOS] != nil {
            // The compat modes carry whichever iOS device family exists —
            // Apple labels the destination "Designed for iPad" when the app
            // has an iPad variant, "Designed for iPhone" otherwise.
            let app = iosDevices == ["iPhone"] ? "iPhone app" :
                iosDevices == ["iPad"] ? "iPad app" : "iPhone/iPad app"
            let label = iosDevices.contains("iPad") ? "iPad" : "iPhone"
            if platforms[.macOS] == nil {
                macDesignedForIPad = try askYesNo(
                    "Allow the \(app) on Apple Silicon Macs (Designed for \(label))?",
                    default: true
                )
            }
            if platforms[.visionOS] == nil {
                visionDesignedForIPad = try askYesNo(
                    "Allow the \(app) on Apple Vision (Designed for \(label))?",
                    default: true
                )
            }
        }

        var bundleIdRoot: String?
        var teamId: String?
        if shape != .sharedLibrary {
            bundleIdRoot = try ask(
                "Bundle id root (reverse-DNS, e.g. com.example.\(projectName.lowercased()))",
                invalid: "must be lowercase reverse-DNS with at least two segments",
                valid: BootstrapConfig.isValidBundleIdRoot
            )
            teamId = try ask(
                "Apple Development Team ID (10 characters)",
                invalid: "must be exactly 10 characters, A-Z and 0-9",
                valid: BootstrapConfig.isValidTeamId
            )
        }

        let config = BootstrapConfig(
            projectName: projectName,
            shape: shape,
            platforms: platforms,
            bundleIdRoot: bundleIdRoot,
            teamId: teamId,
            iosDevices: iosDevices.count == 1 ? iosDevices : nil,
            macDesignedForIPad: macDesignedForIPad,
            visionDesignedForIPad: visionDesignedForIPad
        )
        try config.validate()

        return config
    }

    // MARK: Prompt primitives

    private static func readAnswer(_ prompt: String) throws -> String {
        print(prompt, terminator: " ")
        guard let line = readLine() else {
            throw ValidationError(
                "stdin ended before the interview finished — pass --config <file> for non-interactive use"
            )
        }
        return line.trimmingCharacters(in: .whitespaces)
    }

    private static func ask(
        _ prompt: String,
        default defaultValue: String? = nil,
        invalid: String,
        valid: (String) -> Bool
    ) throws -> String {
        while true {
            let suffix = defaultValue.map { " (\($0))" } ?? ""
            let answer = try readAnswer("\(prompt)\(suffix):")
            let value = answer.isEmpty ? (defaultValue ?? "") : answer
            if valid(value) { return value }
            print("  ✗ \(invalid)")
        }
    }

    private static func askYesNo(_ prompt: String, default defaultValue: Bool = false) throws -> Bool {
        let suffix = defaultValue ? "[Y/n]" : "[y/N]"
        while true {
            switch try readAnswer("\(prompt) \(suffix):").lowercased() {
            case "": return defaultValue
            case "n", "no": return false
            case "y", "yes": return true
            default: print("  ✗ answer y or n")
            }
        }
    }

    private static func askShape() throws -> ProjectShape {
        while true {
            let answer = try readAnswer(
                "Shape [1 localOnly · 2 clientServer · 3 sharedLibrary] (2):"
            )
            switch answer {
            case "", "2", "clientServer": return .clientServer
            case "1", "localOnly": return .localOnly
            case "3", "sharedLibrary": return .sharedLibrary
            default: print("  ✗ answer 1, 2, or 3")
            }
        }
    }

    private static func askVersion(for platform: TargetPlatform) throws -> String {
        let floor = FOSPlatformFloor.floors[platform] ?? "1.0"
        return try ask(
            "\(platform.rawValue) minimum version",
            default: floor,
            invalid: "must be a version at or above the FOSUtilities floor of \(floor)",
            valid: { (try? FOSPlatformFloor.validate(platforms: [platform: $0])) != nil }
        )
    }
}
