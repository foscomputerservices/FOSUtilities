// ProjectRule+Floors.swift
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

// ProjectRule+Floors.swift
import Foundation

extension ProjectRule {
    /// R10 — deployment floors hold, both ways.
    ///
    /// Two invariants, both from the spec's §9 ruling. The xcodeproj deployment
    /// targets and the `Package.swift` platforms line are separately
    /// hand-maintained and must agree; and both must be at or above the pinned
    /// FOSUtilities minimums, because under source-inclusion the app's real
    /// floor comes from the FOS products it links rather than from anything the
    /// repo declares.
    static var deploymentFloors: ProjectRule {
        ProjectRule(
            summary: "deployment targets agree with Package.swift and clear the FOSUtilities floors",
            requiresXcodeProject: false
        ) { project, _ in
            var findings: [Finding] = []

            switch project.manifestPlatforms {
            case .unreadable:
                findings.append(
                    Finding(
                        severity: .warning,
                        summary: "Package.swift declares platforms in a form this check could not read.",
                        remedy: "Confirm by hand that every platform is at or above the FOSUtilities floor (\(floorsDescription)). String literals — .macOS(\"14.0\") — and version constants — .macOS(.v14), .iOS(.v17_4) — are both read; a version built from a variable or expression is not."
                    )
                )
            case .declared(let declared):
                findings += manifestFindings(declared)
            case .absent:
                break
            }

            findings += xcodeFindings(project)
            return findings
        }
    }

    private static func manifestFindings(_ declared: [TargetPlatform: String]) -> [Finding] {
        declared.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { platform in
            guard let asked = declared[platform], let floor = FOSPlatformFloor.floors[platform] else { return nil }
            guard FOSPlatformFloor.compareVersions(asked, floor) == .orderedAscending else { return nil }
            return Finding(
                severity: .error,
                summary: "Package.swift declares \(platform.rawValue) \(asked), below the FOSUtilities floor of \(floor).",
                remedy: "Raise \(platform.rawValue) to \(floor) or later in the platforms: line. Under source-inclusion the app's real floor comes from the FOS products it links, so a lower declaration does not make the app run on older systems — it makes the link fail."
            )
        }
    }

    /// The xcodeproj half: every declared deployment target clears its floor,
    /// and where the manifest declares the same platform, the two agree.
    private static func xcodeFindings(_ project: AuditedProject) -> [Finding] {
        guard project.hasXcodeProject else { return [] }

        let manifest: [TargetPlatform: String] = if case .declared(let declared) = project.manifestPlatforms {
            declared
        } else {
            [:]
        }

        var findings: [Finding] = []
        var reportedDisagreement: Set<TargetPlatform> = []

        for target in project.targets {
            for (platform, key) in deploymentSettingKeys {
                guard let asked = target.setting(key), let floor = FOSPlatformFloor.floors[platform] else { continue }

                if FOSPlatformFloor.compareVersions(asked, floor) == .orderedAscending {
                    findings.append(
                        Finding(
                            severity: .error,
                            target: target.name,
                            summary: "\(key) is \(asked), below the FOSUtilities floor of \(floor).",
                            remedy: "Raise \(key) to \(floor) or later. The app links FOS products built against that minimum, so a lower target does not widen support — it breaks the link."
                        )
                    )
                    continue
                }

                if let expected = manifest[platform],
                   FOSPlatformFloor.compareVersions(asked, expected) != .orderedSame,
                   !reportedDisagreement.contains(platform) {
                    reportedDisagreement.insert(platform)
                    findings.append(
                        Finding(
                            severity: .error,
                            target: target.name,
                            summary: "\(key) is \(asked) but Package.swift declares \(platform.rawValue) \(expected).",
                            remedy: "Make the two agree. Both are hand-maintained and neither derives from the other, so they drift silently — and the half that is wrong is only discovered when a build picks the other one."
                        )
                    )
                }
            }
        }

        return findings
    }

    private static var deploymentSettingKeys: [(TargetPlatform, String)] {
        [
            (.macOS, "MACOSX_DEPLOYMENT_TARGET"),
            (.iOS, "IPHONEOS_DEPLOYMENT_TARGET"),
            (.tvOS, "TVOS_DEPLOYMENT_TARGET"),
            (.watchOS, "WATCHOS_DEPLOYMENT_TARGET"),
            (.visionOS, "XROS_DEPLOYMENT_TARGET")
        ]
    }

    private static var floorsDescription: String {
        FOSPlatformFloor.floors
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue) \($0.value)" }
            .joined(separator: ", ")
    }
}
