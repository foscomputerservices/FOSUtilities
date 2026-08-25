// ProjectRule+BuildSettings.swift
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

// ProjectRule+BuildSettings.swift
import Foundation

// The rules that read a build setting and compare it to a value. They share
// nothing but shape, so they live together and the graph rules live apart.

extension ProjectRule {
    /// R1 — `SWIFT_VERSION` is 6.0 on every target.
    static var swiftVersion: ProjectRule {
        ProjectRule(summary: "SWIFT_VERSION is 6.0 on every target") { project, _ in
            let findings = project.targets.compactMap { target -> Finding? in
                let declared = target.setting("SWIFT_VERSION")
                guard declared != "6.0" else { return nil }
                return Finding(
                    severity: .error,
                    target: target.name,
                    summary: declared.map { "SWIFT_VERSION is \($0), not 6.0." }
                        ?? "SWIFT_VERSION is not set.",
                    remedy: "Set SWIFT_VERSION to 6.0. FOSUtilities builds in Swift 6 language mode; a target below it fails to compile against the framework's Sendable requirements."
                )
            }
            return collapsingProjectWide(findings, examined: project.targets.count)
        }
    }

    /// R2 — `BUILD_LIBRARY_FOR_DISTRIBUTION` spelled singular, set NO.
    ///
    /// The misspelling is the whole point. Xcode accepts any key, so a plural
    /// or transposed spelling reads as a setting that was configured while
    /// having no effect at all — the silent-typo class from the friction
    /// cluster. An absent key is fine: NO is Xcode's default.
    static var libraryForDistribution: ProjectRule {
        ProjectRule(summary: "BUILD_LIBRARY_FOR_DISTRIBUTION spelled correctly and set NO") { project, _ in
            let canonical = "BUILD_LIBRARY_FOR_DISTRIBUTION"
            var findings: [Finding] = []

            for key in project.declaredSettingKeys.sorted() where key != canonical {
                guard key.contains("DISTRIBUTION"), editDistance(key, canonical) <= 3 else { continue }
                findings.append(
                    Finding(
                        severity: .error,
                        summary: "\(key) is set, which Xcode ignores — the setting is spelled \(canonical).",
                        remedy: "Rename \(key) to \(canonical). Xcode accepts unknown build-setting keys silently, so the misspelled one has never done anything."
                    )
                )
            }

            for target in project.targets {
                guard let value = target.setting(canonical), value != "NO" else { continue }
                findings.append(
                    Finding(
                        severity: .error,
                        target: target.name,
                        summary: "\(canonical) is \(value), not NO.",
                        remedy: "Set \(canonical) to NO. Library evolution is for binary-distributed frameworks; on a source-included target it changes mangling and costs build time for nothing."
                    )
                )
            }

            return findings
        }
    }

    /// R6 — `DEVELOPMENT_TEAM` present on every target.
    static var developmentTeam: ProjectRule {
        ProjectRule(summary: "DEVELOPMENT_TEAM is set on every target") { project, _ in
            let findings = project.targets.compactMap { target -> Finding? in
                guard target.setting("DEVELOPMENT_TEAM") == nil else { return nil }
                return Finding(
                    severity: .error,
                    target: target.name,
                    summary: "DEVELOPMENT_TEAM is not set.",
                    remedy: "Set DEVELOPMENT_TEAM to your 10-character Apple Development Team ID. Without it the embedded frameworks are signed by a different identity than the app, and dyld rejects the app at launch with a Team ID mismatch."
                )
            }
            return collapsingProjectWide(findings, examined: project.targets.count)
        }
    }

    /// R11 — `CODE_SIGN_STYLE` is Automatic.
    ///
    /// Scoped to the targets whose signing decides whether ⌘U runs at all: the
    /// app and its test bundles. Absent, Xcode defaults to Manual and cannot
    /// sign or launch the app or its test host.
    static var codeSignStyle: ProjectRule {
        ProjectRule(summary: "CODE_SIGN_STYLE is Automatic on the app and its test bundles") { project, _ in
            let signing = project.targets.filter { $0.kind == .application || $0.kind.isTestBundle }
            let findings = signing.compactMap { target -> Finding? in
                let declared = target.setting("CODE_SIGN_STYLE")
                guard declared != "Automatic" else { return nil }
                return Finding(
                    severity: .error,
                    target: target.name,
                    summary: declared.map { "CODE_SIGN_STYLE is \($0), not Automatic." }
                        ?? "CODE_SIGN_STYLE is not set, so Xcode defaults to Manual.",
                    remedy: "Set CODE_SIGN_STYLE to Automatic (\"Automatically manage signing\"). On Manual, ⌘U cannot sign or launch the app or its test host, so the tests never run."
                )
            }
            return collapsingProjectWide(findings, examined: signing.count)
        }
    }

    /// R12 — `ENABLE_HARDENED_RUNTIME` off in Debug, on in Release.
    ///
    /// Xcode signs SPM package frameworks ad-hoc, with no Team ID. Under a
    /// hardened runtime, library validation refuses to map them and the app
    /// dies in dyld before `main()` — which takes macOS UI testing with it.
    /// Release keeps it on so notarization still works.
    static var hardenedRuntime: ProjectRule {
        ProjectRule(summary: "ENABLE_HARDENED_RUNTIME is NO in Debug, YES in Release") { project, _ in
            var findings: [Finding] = []

            for target in project.targets where target.kind == .application && target.buildsForMacOS {
                if target.setting("ENABLE_HARDENED_RUNTIME", in: "Debug") == "YES" {
                    findings.append(
                        Finding(
                            severity: .error,
                            target: target.name,
                            summary: "ENABLE_HARDENED_RUNTIME is YES in the Debug configuration.",
                            remedy: "Set ENABLE_HARDENED_RUNTIME to NO for Debug only. Xcode signs SPM package frameworks ad-hoc, library validation refuses to map them into a hardened process, and the app dies in dyld before main() — which kills macOS UI testing."
                        )
                    )
                }

                let release = target.setting("ENABLE_HARDENED_RUNTIME", in: "Release")
                if target.configurations.contains("Release"), release != "YES" {
                    findings.append(
                        Finding(
                            severity: .error,
                            target: target.name,
                            summary: release.map { "ENABLE_HARDENED_RUNTIME is \($0) in the Release configuration." }
                                ?? "ENABLE_HARDENED_RUNTIME is not set in the Release configuration.",
                            remedy: "Set ENABLE_HARDENED_RUNTIME to YES for Release. Notarization requires it, so an app that ships without it is rejected."
                        )
                    )
                }
            }

            return findings
        }
    }
}

/// Levenshtein distance, used only to recognise a misspelled build-setting key.
///
/// Not a general utility — it exists so R2 can name the key someone actually
/// typed instead of reporting a vague "setting missing".
func editDistance(_ lhs: String, _ rhs: String) -> Int {
    let a = Array(lhs), b = Array(rhs)
    if a.isEmpty {
        return b.count
    }
    if b.isEmpty {
        return a.count
    }

    var previous = Array(0...b.count)
    var current = [Int](repeating: 0, count: b.count + 1)

    for i in 1...a.count {
        current[0] = i
        for j in 1...b.count {
            let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
            current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
        }
        swap(&previous, &current)
    }
    return previous[b.count]
}
