// ProjectRule+TestTargets.swift
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

// ProjectRule+TestTargets.swift
import Foundation

extension ProjectRule {
    /// R3 — hosted unit-test bundles pin `TEST_HOST` and `BUNDLE_LOADER`.
    ///
    /// Xcode derives the default host path from the target name. When a target
    /// name and its `PRODUCT_NAME` differ the derived path is wrong, and the
    /// test bundle fails to load with an error that names neither setting. The
    /// templates pin both unconditionally rather than depend on the derivation.
    ///
    /// Only bundles that actually host are checked — a bundle depending on no
    /// application target is a logic-test bundle and wants no host.
    static var testHostPinned: ProjectRule {
        ProjectRule(summary: "hosted unit-test bundles pin TEST_HOST and BUNDLE_LOADER") { project, _ in
            let applications = Set(
                project.targets.filter { $0.kind == .application }.map(\.name)
            )

            return project.targets
                .filter { $0.kind == .unitTestBundle }
                .filter { !$0.localDependencies.filter(applications.contains).isEmpty }
                .flatMap { target -> [Finding] in
                    var findings: [Finding] = []
                    if target.setting("TEST_HOST") == nil {
                        findings.append(
                            Finding(
                                severity: .error,
                                target: target.name,
                                summary: "hosts in an app target but does not pin TEST_HOST.",
                                remedy: "Set TEST_HOST to $(BUILT_PRODUCTS_DIR)/<App>.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/<App>. Xcode's derived default is built from the target name and is wrong whenever that differs from PRODUCT_NAME."
                            )
                        )
                    }
                    if target.setting("BUNDLE_LOADER") == nil {
                        findings.append(
                            Finding(
                                severity: .error,
                                target: target.name,
                                summary: "hosts in an app target but does not set BUNDLE_LOADER.",
                                remedy: "Set BUNDLE_LOADER to $(TEST_HOST). Without it the test bundle cannot resolve symbols from the host app at link time."
                            )
                        )
                    }
                    return findings
                }
        }
    }

    /// R9 — test-plan target references resolve.
    ///
    /// A `.xctestplan` names its targets by pbxproj object identifier.
    /// Regenerating a project re-mints every identifier, so a plan committed
    /// before the regeneration points at targets that no longer exist — and
    /// Xcode reports it as an empty test run rather than as an error.
    static var testPlanReferences: ProjectRule {
        ProjectRule(summary: "test-plan target references resolve to real targets") { project, _ in
            guard !project.testPlans.isEmpty else { return [] }
            let identifiers = Set(project.targets.map(\.identifier))

            return project.testPlans.flatMap { plan in
                plan.references
                    // A repo can hold several Xcode projects. A plan naming a
                    // sibling container is that project's business — judging it
                    // here reports a dangling reference for a target that is
                    // perfectly present somewhere else, or not yet generated.
                    .filter { belongsHere($0.container, project: project) }
                    .filter { !identifiers.contains($0.identifier) }
                    .map { reference in
                        let named = reference.name.isEmpty ? "a target" : reference.name
                        return Finding(
                            severity: .error,
                            target: "\(plan.name).xctestplan",
                            summary: "references \(named) by an identifier no target in the project has.",
                            remedy: "Open the test plan in Xcode and re-add \(named). Regenerating the project re-mints target identifiers, and a stale reference runs as an empty test suite rather than failing."
                        )
                    }
            }
        }
    }

    /// Whether a test-plan reference names the project being audited.
    ///
    /// `containerPath` is `container:MyApp.xcodeproj`. A reference with no
    /// container is taken as this project's; one naming a different `.xcodeproj`
    /// belongs to a sibling and is left alone.
    private static func belongsHere(_ container: String?, project: AuditedProject) -> Bool {
        guard let container, container.hasSuffix(".xcodeproj") else { return true }
        guard let name = project.xcodeProjectName else { return false }
        return container.hasSuffix("/\(name)") || container == "container:\(name)"
    }
}
