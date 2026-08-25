// ProjectRule.swift
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

// ProjectRule.swift
import Foundation

/// One invariant a FOSMVVM project has to hold, and how to test a project for it.
///
/// The table is `ProjectRule.all`. It is declared once and read twice: `Doctor`
/// audits a customer's project with it, and the walking skeletons audit our own
/// emitted projects with it — which is what makes the table truth rather than a
/// second opinion.
struct ProjectRule {
    /// Named in `Doctor.Report.unchecked` when the rule cannot run.
    let summary: String

    /// Rules that judge shape-specific posture. Without `--shape` they are
    /// reported as unchecked rather than guessed at.
    let requiresShape: Bool

    /// Rules that read Xcode settings. The shared-library shape ships no
    /// `.xcodeproj`, and a missing project is not a finding there.
    let requiresXcodeProject: Bool

    let evaluate: (AuditedProject, ProjectShape?) -> [Finding]

    init(
        summary: String,
        requiresShape: Bool = false,
        requiresXcodeProject: Bool = true,
        evaluate: @escaping (AuditedProject, ProjectShape?) -> [Finding]
    ) {
        self.summary = summary
        self.requiresShape = requiresShape
        self.requiresXcodeProject = requiresXcodeProject
        self.evaluate = evaluate
    }
}

extension ProjectRule {
    /// The rules table (design: `docs/work/fosmvvm-doctor-design.md`).
    static var all: [ProjectRule] {
        [
            swiftVersion, // R1
            libraryForDistribution, // R2
            testHostPinned, // R3
            shippingProductsDoor, // R4a
            testingProductsDoor, // R4b
            singleEmbed, // R5
            developmentTeam, // R6
            entitlementsPosture, // R7
            localizationYAMLTrees, // R8
            testPlanReferences, // R9
            deploymentFloors, // R10
            codeSignStyle, // R11
            hardenedRuntime, // R12
            sharedModuleHome, // R13
            sharedModuleImports // R14
        ]
    }
}

// MARK: - Shared helpers

extension ProjectRule {
    /// Folds identical per-target findings into one project-scoped finding when
    /// every target examined reported it.
    ///
    /// The templates write settings like `SWIFT_VERSION` and `DEVELOPMENT_TEAM`
    /// once, at the project level. When one goes missing, a per-target rule
    /// reports it once per target — six copies of the same sentence with the
    /// same remedy, which reads as six problems and buries the findings that
    /// really are per-target. It is one omission and one edit, so it is one
    /// finding.
    ///
    /// A setting missing from *some* targets is genuinely per-target and is
    /// left alone: that is a different defect with a different fix.
    /// The collapsed finding keeps the original sentence — which carries the
    /// offending value — and drops only the target, so it renders under
    /// `(project)`. That placement already says "everywhere"; rewriting the
    /// summary to say so would cost the value and buy nothing.
    static func collapsingProjectWide(_ findings: [Finding], examined: Int) -> [Finding] {
        guard examined > 1, findings.count == examined else { return findings }

        // Identical means same severity, same sentence, same remedy — a value
        // that differs per target (one is 5.0, another 4.2) is not one omission.
        let first = findings[0]
        let uniform = findings.allSatisfy {
            $0.severity == first.severity && $0.summary == first.summary && $0.remedy == first.remedy
        }
        guard uniform else { return findings }

        return [
            Finding(
                severity: first.severity,
                target: nil,
                summary: first.summary,
                remedy: first.remedy
            )
        ]
    }
}

extension AuditedTarget {
    /// A setting's value, looked up in a stable configuration order. Used by
    /// rules whose expected value is the same in every configuration.
    func setting(_ key: String) -> String? {
        for name in settings.keys.sorted() {
            if let value = settings[name]?[key], !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// A setting's value in one named configuration.
    func setting(_ key: String, in configuration: String) -> String? {
        let value = settings[configuration]?[key]
        return (value?.isEmpty ?? true) ? nil : value
    }

    /// Configuration names present on this target, in a stable order.
    var configurations: [String] {
        settings.keys.sorted()
    }

    /// True when the target builds for macOS, which is the only platform the
    /// hardened runtime applies to.
    var buildsForMacOS: Bool {
        if setting("MACOSX_DEPLOYMENT_TARGET") != nil {
            return true
        }
        return setting("SUPPORTED_PLATFORMS")?.contains("macosx") ?? false
    }
}
