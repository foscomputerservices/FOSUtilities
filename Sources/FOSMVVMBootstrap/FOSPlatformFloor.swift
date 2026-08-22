// FOSPlatformFloor.swift
import Foundation

/// The pinned FOSUtilities release and its platform minimums.
///
/// Under source-inclusion, a generated app's real deployment floor comes
/// from the FOS products it links — not from anything the generated repo
/// declares. Generation therefore validates every asked-for target
/// against these values, and `doctor` re-checks them for life.
public enum FOSPlatformFloor {
    /// The release-stamped pin (see `Release`); kept as the emitter-facing name.
    public static let pinnedFOSVersion = Release.version

    public static let floors: [TargetPlatform: String] = [
        .iOS: "17.0",
        .macOS: "14.0",
        .macCatalyst: "17.0",
        .tvOS: "17.0",
        .watchOS: "10.0",
        .visionOS: "1.0"
    ]

    /// Rejects any target below the pinned FOSUtilities minimum:
    /// `try FOSPlatformFloor.validate(platforms: [.macOS: "14.0"])`.
    ///
    /// Throws `BootstrapConfigError.belowFOSFloor` when a target's asked-for
    /// version is under its floor, or `.platformUnsupportedByFOS` for a
    /// platform FOS does not ship.
    public static func validate(platforms: [TargetPlatform: String]) throws {
        for (platform, asked) in platforms {
            guard let floor = floors[platform] else {
                throw BootstrapConfigError.platformUnsupportedByFOS(platform)
            }
            if compareVersions(asked, floor) == .orderedAscending {
                throw BootstrapConfigError.belowFOSFloor(platform: platform, asked: asked, floor: floor)
            }
        }
    }

    /// Numeric, component-wise version comparison ("10.4" < "10.15").
    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let l = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let r = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0 ..< max(l.count, r.count) {
            let a = i < l.count ? l[i] : 0
            let b = i < r.count ? r[i] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
