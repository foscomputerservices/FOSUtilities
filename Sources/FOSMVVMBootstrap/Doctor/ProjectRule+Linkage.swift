// ProjectRule+Linkage.swift
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

// ProjectRule+Linkage.swift
import Foundation

/// FOS products, split by whether they ship inside the app.
///
/// The split is the doctrine ruled 2026-08-19 and written into the templates:
/// the umbrella embeds in the shipping app, so testing products must not ride
/// along, and test targets link them directly instead. Their types are never
/// shared across target boundaries, so the type-identity rule that forces the
/// umbrella does not apply to them.
enum FOSProduct {
    static let shipping: Set<String> = [
        "FOSFoundation", "FOSMVVM", "FOSMVVMVapor", "FOSReporting", "FOSNetworkSecurity"
    ]

    static let testing: Set<String> = [
        "FOSTesting", "FOSTestingUI", "FOSTestingVapor"
    ]
}

extension ProjectRule {
    /// R4a — shipping FOS products enter through exactly one target.
    ///
    /// Static linking compiles a separate copy of the types into each target
    /// that links them, so `is` / `as?` / `==` fail across target boundaries at
    /// runtime, far from the cause. One door is the whole point.
    static var shippingProductsDoor: ProjectRule {
        ProjectRule(summary: "shipping FOS products enter only through the SPMLibraries umbrella") { project, _ in
            let doors = project.targets.filter { target in
                !FOSProduct.shipping.isDisjoint(with: target.packageProducts)
            }
            guard doors.count > 1 else {
                // One door, or none at all — a project that does not link FOS
                // yet is not the thing this rule is about.
                return doors.first.flatMap { door in
                    door.kind == .framework ? nil : [
                        Finding(
                            severity: .error,
                            target: door.name,
                            summary: "FOS products are linked by a \(door.kind.described) target rather than a framework.",
                            remedy: "Move the FOS product links into a framework target named SPMLibraries and have every other target depend on that. The umbrella has to be a framework so one copy of the types is embedded and shared."
                        )
                    ]
                } ?? []
            }

            // More than one door. The framework with the most FOS products is
            // the umbrella; everything else is a second link site.
            let umbrella = doors.max { lhs, rhs in
                (lhs.kind == .framework ? 1 : 0, lhs.packageProducts.count)
                    < (rhs.kind == .framework ? 1 : 0, rhs.packageProducts.count)
            }

            return doors.filter { $0.name != umbrella?.name }.map { extra in
                let products = extra.packageProducts
                    .filter(FOSProduct.shipping.contains)
                    .joined(separator: ", ")
                return Finding(
                    severity: .error,
                    target: extra.name,
                    summary: "links \(products) directly, alongside \(umbrella?.name ?? "the umbrella").",
                    remedy: "Remove the direct link and depend on \(umbrella?.name ?? "SPMLibraries") instead. Two link sites compile two non-identical copies of the same types — a value from one target fails `is`, `as?`, and `==` against the other at runtime."
                )
            }
        }
    }

    /// R4b — testing FOS products enter only through test targets.
    static var testingProductsDoor: ProjectRule {
        ProjectRule(summary: "testing FOS products are linked only by test targets") { project, _ in
            project.targets
                .filter { !$0.kind.isTestBundle }
                .compactMap { target in
                    let testing = target.packageProducts.filter(FOSProduct.testing.contains)
                    guard !testing.isEmpty else { return nil }
                    return Finding(
                        severity: .error,
                        target: target.name,
                        summary: "links \(testing.joined(separator: ", ")), which is a testing product, into a non-test target.",
                        remedy: "Remove the link here, and link \(testing.joined(separator: ", ")) directly on each test target that uses it. Testing products belong on test targets only — linked here they ride into the shipping app — and they do not go through SPMLibraries: test-only types are never shared across targets, so the one-doorway rule does not apply to them."
                    )
                }
        }
    }

    /// R5 — single-embed.
    ///
    /// The app embeds each local framework with sign-on-copy; every other
    /// target links without embedding, because the test host already carries
    /// the embedded copy. Embedding twice puts two copies in one bundle, which
    /// is the type-identity failure the umbrella exists to prevent.
    static var singleEmbed: ProjectRule {
        ProjectRule(summary: "the app embeds local frameworks with sign-on-copy; nothing else embeds") { project, _ in
            var findings: [Finding] = []
            let frameworkNames = Set(
                project.targets.filter { $0.kind == .framework }.map(\.name)
            )

            for target in project.targets {
                let localFrameworks = target.localDependencies.filter(frameworkNames.contains)

                guard target.kind == .application else {
                    for embedded in target.embedded where frameworkNames.contains(embedded.name) {
                        findings.append(
                            Finding(
                                severity: .error,
                                target: target.name,
                                summary: "embeds \(embedded.name), but only the app should embed.",
                                remedy: "Change \(embedded.name) to link-only (Do Not Embed) on \(target.name). Its test host already embeds the framework; a second copy in this bundle produces two non-identical copies of the same types."
                            )
                        )
                    }
                    continue
                }

                for name in localFrameworks {
                    guard let embedded = target.embedded.first(where: { $0.name == name }) else {
                        findings.append(
                            Finding(
                                severity: .error,
                                target: target.name,
                                summary: "depends on \(name) but does not embed it.",
                                remedy: "Set \(name) to Embed & Sign on \(target.name). An app that links a framework without embedding it launches only until dyld looks for the missing bundle."
                            )
                        )
                        continue
                    }
                    if !embedded.signOnCopy {
                        findings.append(
                            Finding(
                                severity: .error,
                                target: target.name,
                                summary: "embeds \(name) without Code Sign On Copy.",
                                remedy: "Set \(name) to Embed & Sign rather than Embed Without Signing. An unsigned framework inside a signed app is rejected at launch."
                            )
                        )
                    }
                }
            }

            return findings
        }
    }
}

extension TargetKind {
    var described: String {
        switch self {
        case .application: "application"
        case .framework: "framework"
        case .unitTestBundle: "unit-test"
        case .uiTestBundle: "UI-test"
        case .other: "non-framework"
        }
    }
}
