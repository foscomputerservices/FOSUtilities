// ProjectRule+Shape.swift
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

// ProjectRule+Shape.swift
import Foundation

// The two rules that consult the shape. Without `--shape` they are reported as
// unchecked rather than guessed at — a heuristic that guesses wrong produces
// confident wrong findings, which is worse than silence.

extension ProjectRule {
    /// R7 — entitlements posture matches the shape.
    ///
    /// A client-server app that cannot open an outbound connection fails at
    /// runtime, when it first tries to reach its own server — which is what
    /// puts this at error rather than warning.
    static var entitlementsPosture: ProjectRule {
        ProjectRule(
            summary: "entitlements match the project shape",
            requiresShape: true
        ) { project, shape in
            guard let shape else { return [] }

            var findings: [Finding] = []
            for target in project.targets where target.kind == .application {
                guard let entitlements = target.entitlements else {
                    findings.append(
                        Finding(
                            severity: .error,
                            target: target.name,
                            summary: "declares no entitlements file.",
                            remedy: "Add an entitlements file and point CODE_SIGN_ENTITLEMENTS at it. A \(shape.rawValue) app needs at least com.apple.security.app-sandbox."
                        )
                    )
                    continue
                }

                for required in Self.requiredEntitlements(for: shape) where !entitlements.contains(required) {
                    findings.append(
                        Finding(
                            severity: .error,
                            target: target.name,
                            summary: "entitlements do not enable \(required).",
                            remedy: Self.entitlementRemedy(required, shape: shape),
                            rule: Self.disableableRule(behind: required)
                        )
                    )
                }

                if entitlements.contains("com.apple.security.cs.disable-library-validation") {
                    findings.append(
                        Finding(
                            severity: .error,
                            target: target.name,
                            summary: "disables library validation.",
                            remedy: "Remove com.apple.security.cs.disable-library-validation and fix the shape instead. It is a symptom: the app is embedding ad-hoc-signed frameworks, or signing is off. See memory/entitlement-is-a-symptom.md in a generated project."
                        )
                    )
                }
            }
            return findings
        }
    }

    private static func requiredEntitlements(for shape: ProjectShape) -> [String] {
        switch shape {
        case .clientServer, .hybrid:
            ["com.apple.security.app-sandbox", "com.apple.security.network.client"]
        case .localOnly:
            ["com.apple.security.app-sandbox"]
        case .sharedLibrary:
            []
        }
    }

    /// The sandbox is the one required entitlement an app can withhold on
    /// purpose; `network.client` is not — without it a client-server app
    /// cannot reach its own server.
    private static func disableableRule(behind entitlement: String) -> DisableableRule? {
        entitlement == "com.apple.security.app-sandbox" ? .appSandbox : nil
    }

    private static func entitlementRemedy(_ entitlement: String, shape: ProjectShape) -> String {
        switch entitlement {
        case "com.apple.security.network.client":
            "Enable com.apple.security.network.client (Outgoing Connections). A \(shape.rawValue) app reaches its own server over HTTP, and the sandbox blocks that silently until the request fails at runtime."
        default:
            "Enable \(entitlement) in the app's entitlements file."
        }
    }

    /// R8 — localization YAML sits where its hosting expects.
    ///
    /// The table's only warning. Where the YAML lives follows from who serves
    /// it, and a project can legitimately arrange its own tree differently —
    /// so this reports what it sees rather than asserting a layout.
    static var localizationYAMLTrees: ProjectRule {
        ProjectRule(
            summary: "localization YAML is split by hosting",
            requiresShape: true,
            requiresXcodeProject: false
        ) { project, shape in
            guard let shape else { return [] }
            let paths = project.localizationYAMLPaths

            guard !paths.isEmpty else {
                return [
                    Finding(
                        severity: .warning,
                        summary: "no localization YAML found under any Resources directory.",
                        remedy: "A FOSMVVM ViewModel localizes from YAML. Add it under the Resources tree its hosting expects — \(Self.expectedYAMLTree(for: shape))."
                    )
                ]
            }

            let expectedFragments = Self.expectedYAMLFragments(for: shape)
            let misplaced = paths.filter { path in
                !expectedFragments.contains(where: path.contains)
            }
            guard !misplaced.isEmpty else { return [] }

            return [
                Finding(
                    severity: .warning,
                    summary: "\(misplaced.count) localization YAML file\(misplaced.count == 1 ? " sits" : "s sit") outside the tree a \(shape.rawValue) project uses — first is \(misplaced[0]).",
                    remedy: "Confirm this is deliberate. A \(shape.rawValue) project hosts its YAML at \(Self.expectedYAMLTree(for: shape)); YAML outside that tree loads only if the ViewModel's resource bundle is wired to reach it."
                )
            ]
        }
    }

    /// The path fragment a correctly-placed YAML file carries.
    ///
    /// A package-hosted library reads through `Bundle.module` and declares its
    /// tree with `.copy("Resources/Localizations")`; every other shape reads
    /// through a framework or app bundle whose YAML sits under
    /// `Resources/ViewModels`, on the client and server sides alike — with
    /// `Resources/FieldModels` as the Fields-messages sibling the fields
    /// generator prescribes (the store's search is recursive, so both load).
    private static func expectedYAMLFragments(for shape: ProjectShape) -> [String] {
        switch shape {
        case .sharedLibrary: ["Resources/Localizations/"]
        case .localOnly, .clientServer, .hybrid: ["Resources/ViewModels/", "Resources/FieldModels/"]
        }
    }

    private static func expectedYAMLTree(for shape: ProjectShape) -> String {
        switch shape {
        case .sharedLibrary:
            "Sources/<Lib>ViewModels/Resources/Localizations, declared with .copy and read through Bundle.module"
        case .localOnly:
            "Sources/ViewModels/Resources/ViewModels, read through the framework's own bundle"
        case .clientServer:
            "Sources/Resources/ViewModels for server-hosted ViewModels, and the client framework's Resources for client-hosted ones"
        case .hybrid:
            "split trees — the client framework's Resources for client-hosted ViewModels, Sources/Resources for server-hosted ones"
        }
    }
}
