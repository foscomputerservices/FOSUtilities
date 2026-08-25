// DoctorTests.swift
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

// DoctorTests.swift
@testable import FOSMVVMBootstrap
import Foundation
import Testing

// Contract tests: everything goes through Doctor.examine, the way a caller
// reaches it. @testable is present only because ProjectShape and the fixture
// helper live in the module; no rule or read-model internal is touched.
//
// The fixtures are real generated projects, committed and frozen. Each broken
// variant is produced by mutating a copy in a temp directory, so a fixture
// cannot be silently repaired by a change to the emitter — which would leave
// these tests passing while checking nothing.

@Suite("Doctor")
struct DoctorTests {
    // MARK: Clean projects

    @Test("a generated local-only project has no findings")
    func localOnlyIsClean() throws {
        let project = try Fixture.localOnly()
        let report = try Doctor.examine(projectAt: project, shape: .localOnly)
        #expect(report.findings.isEmpty, "unexpected: \(report.text)")
        #expect(!report.hasErrors)
    }

    @Test("a generated client-server project has no findings")
    func clientServerIsClean() throws {
        let project = try Fixture.clientServer()
        let report = try Doctor.examine(projectAt: project, shape: .clientServer)
        #expect(report.findings.isEmpty, "unexpected: \(report.text)")
    }

    @Test("a generated shared-library package has no findings")
    func sharedLibraryIsClean() throws {
        let project = try Fixture.sharedLibrary()
        let report = try Doctor.examine(projectAt: project, shape: .sharedLibrary)
        #expect(report.findings.isEmpty, "unexpected: \(report.text)")
    }

    @Test("a package with no .xcodeproj is not itself a finding")
    func missingXcodeProjectIsNotAFinding() throws {
        // Every Xcode-reading rule has to stay silent for the shared-library
        // shape. If any of them reported instead, the shape would be unusable —
        // eleven errors for a package that is exactly right.
        let report = try Doctor.examine(projectAt: Fixture.sharedLibrary(), shape: .sharedLibrary)
        #expect(!report.hasErrors)
        #expect(report.unchecked.isEmpty, "a given shape leaves nothing unchecked")
    }

    @Test("R10 — a package-only floor breach is still caught without an Xcode project")
    func sharedLibraryBelowFloor() throws {
        let report = try Fixture.sharedLibrary(
            mutatingManifest: { $0.replacingOccurrences(of: ".macOS(\"14.0\")", with: ".macOS(\"12.0\")") },
            shape: .sharedLibrary
        )
        let finding = try #require(report.findings.first { $0.summary.contains("below the FOSUtilities floor") })
        #expect(finding.severity == .error)
    }

    @Test("R8 — shared-library YAML belongs under Resources/Localizations")
    func sharedLibraryYAMLTree() throws {
        let report = try Fixture.sharedLibrary(shape: .sharedLibrary) { root in
            let stray = root.appendingPathComponent("Sources/PalettePressViewModels/Stray.yml")
            try Data("title: stray\n".utf8).write(to: stray)
        }
        #expect(report.findings.contains { $0.severity == .warning && $0.summary.contains("outside the tree") })
    }

    @Test("shape-conditional rules report as unchecked without a shape")
    func withoutShapeTwoRulesAreUnchecked() throws {
        let project = try Fixture.localOnly()
        let report = try Doctor.examine(projectAt: project)
        #expect(report.unchecked.count == 2)
        #expect(report.findings.isEmpty)
    }

    // MARK: Build settings

    @Test("R1 — a target below Swift 6 is an error")
    func swiftVersionBelowSix() throws {
        let report = try Fixture.localOnly(
            mutatingProject: { $0.replacingOccurrences(of: "SWIFT_VERSION = 6.0;", with: "SWIFT_VERSION = 5.0;") },
            shape: .localOnly
        )
        #expect(report.hasErrors)
        #expect(report.findings.contains { $0.summary.contains("SWIFT_VERSION is 5.0") })
    }

    @Test("R2 — a misspelled distribution flag is named, not merely missed")
    func misspelledDistributionFlag() throws {
        let report = try Fixture.localOnly(
            mutatingProject: {
                $0.replacingOccurrences(
                    of: "BUILD_LIBRARY_FOR_DISTRIBUTION = NO;",
                    with: "BUILD_LIBRARY_FOR_DISTRIBUTIONS = NO;"
                )
            },
            shape: .localOnly
        )
        let finding = try #require(report.findings.first { $0.summary.contains("BUILD_LIBRARY_FOR_DISTRIBUTIONS") })
        #expect(finding.severity == .error)
        #expect(finding.remedy.contains("BUILD_LIBRARY_FOR_DISTRIBUTION"))
    }

    @Test("R2 — the correct spelling set YES is an error")
    func distributionFlagOn() throws {
        let report = try Fixture.localOnly(
            mutatingProject: {
                $0.replacingOccurrences(
                    of: "BUILD_LIBRARY_FOR_DISTRIBUTION = NO;",
                    with: "BUILD_LIBRARY_FOR_DISTRIBUTION = YES;"
                )
            },
            shape: .localOnly
        )
        #expect(report.findings.contains { $0.summary.contains("is YES, not NO") })
    }

    @Test("R6 — a target without a team is an error")
    func missingDevelopmentTeam() throws {
        let report = try Fixture.localOnly(
            mutatingProject: { $0.replacingOccurrences(of: "DEVELOPMENT_TEAM = ABCDE12345;", with: "") },
            shape: .localOnly
        )
        #expect(report.findings.allSatisfy { $0.severity == .error })
        #expect(report.findings.contains { $0.summary.contains("DEVELOPMENT_TEAM is not set") })
    }

    @Test("a project-wide omission reports once, not once per target")
    func projectWideFindingsCollapse() throws {
        // DEVELOPMENT_TEAM is written once at the project level, so removing it
        // fails every target. That is one omission and one edit — reporting it
        // per target buries the findings that really are per-target.
        let report = try Fixture.localOnly(
            mutatingProject: { $0.replacingOccurrences(of: "DEVELOPMENT_TEAM = ABCDE12345;", with: "") },
            shape: .localOnly
        )
        let team = report.findings.filter { $0.summary.contains("DEVELOPMENT_TEAM") }
        #expect(team.count == 1, "expected one collapsed finding, got \(team.count)")
        #expect(team.first?.target == nil, "a project-wide finding is not attributed to a target")
        // The sentence survives the collapse — it carries the offending value,
        // which `(project)` placement cannot.
        #expect(team.first?.summary == "DEVELOPMENT_TEAM is not set.")
    }

    @Test("per-target findings are not collapsed")
    func perTargetFindingsStaySeparate() throws {
        // Embedding is decided per target, so several targets embedding wrongly
        // is several defects. The collapse must not flatten them.
        let report = try Fixture.clientServer(
            mutatingProject: { $0.replacingOccurrences(of: "ATTRIBUTES = (CodeSignOnCopy, ", with: "ATTRIBUTES = (") },
            shape: .clientServer
        )
        let embeds = report.findings.filter { $0.summary.contains("Code Sign On Copy") }
        #expect(embeds.count >= 1)
        #expect(embeds.allSatisfy { $0.target != nil }, "embed findings stay attributed to their target")
    }

    @Test("R11 — manual signing is an error")
    func manualCodeSignStyle() throws {
        let report = try Fixture.localOnly(
            mutatingProject: { $0.replacingOccurrences(of: "CODE_SIGN_STYLE = Automatic;", with: "CODE_SIGN_STYLE = Manual;") },
            shape: .localOnly
        )
        #expect(report.findings.contains { $0.summary.contains("CODE_SIGN_STYLE is Manual") })
    }

    @Test("R12 — a hardened runtime in Debug is an error")
    func hardenedRuntimeInDebug() throws {
        let report = try Fixture.localOnly(
            mutatingProject: { $0.replacingOccurrences(of: "ENABLE_HARDENED_RUNTIME = NO;", with: "ENABLE_HARDENED_RUNTIME = YES;") },
            shape: .localOnly
        )
        #expect(report.findings.contains { $0.summary.contains("YES in the Debug configuration") })
    }

    @Test("R12 — a hardened runtime off in Release is an error too")
    func hardenedRuntimeOffInRelease() throws {
        // The Debug value is already NO, so flipping Release to NO leaves the
        // Debug half of the rule satisfied and exercises the notarization half
        // on its own.
        let report = try Fixture.localOnly(
            mutatingProject: { $0.replacingOccurrences(of: "ENABLE_HARDENED_RUNTIME = YES;", with: "ENABLE_HARDENED_RUNTIME = NO;") },
            shape: .localOnly
        )
        let finding = try #require(report.findings.first { $0.summary.contains("Release configuration") })
        #expect(finding.severity == .error)
        #expect(finding.remedy.contains("Notarization"))
    }

    @Test("R7 — an app with no entitlements file at all is an error")
    func appWithoutAnyEntitlements() throws {
        let report = try Fixture.localOnly(shape: .localOnly) { root in
            try FileManager.default.removeItem(
                at: root.appendingPathComponent("Sources/PalettePress/PalettePress.entitlements")
            )
        }
        let finding = try #require(report.findings.first { $0.summary.contains("declares no entitlements file") })
        #expect(finding.severity == .error)
    }
}

/// The link/embed graph, test plans, and shape-conditional rules — split from
/// `DoctorTests` so neither suite's body outgrows the lint ceiling as rules
/// accumulate.
@Suite("Doctor — linkage and project structure")
struct DoctorStructureRuleTests {
    // MARK: Linkage

    @Test("R4b — a testing product outside a test target is an error")
    func shippingTargetLinksATestingProduct() throws {
        // Retarget the app's own package-product reference at FOSTesting. The
        // app is not a test bundle, so the product has no business there.
        let report = try Fixture.clientServer(
            mutatingProject: { $0.replacingOccurrences(of: "productName = FOSMVVM;", with: "productName = FOSTesting;") },
            shape: .clientServer
        )
        #expect(report.findings.contains { $0.summary.contains("which is a testing product") })
    }

    @Test("R4a — a second direct link to a shipping product is an error")
    func secondShippingLinkSite() throws {
        // Point a test bundle's FOSTesting reference at FOSMVVM. That target now
        // links a shipping product directly, alongside the umbrella — two link
        // sites, two non-identical copies of the same types.
        let report = try Fixture.clientServer(
            mutatingProject: { $0.replacingOccurrences(of: "productName = FOSTestingUI;", with: "productName = FOSMVVM;") },
            shape: .clientServer
        )
        let finding = try #require(report.findings.first { $0.summary.contains("links FOSMVVM directly") })
        #expect(finding.severity == .error)
        #expect(finding.remedy.contains("SPMLibraries"))
    }

    @Test("R5 — embedding without sign-on-copy is an error")
    func embedWithoutSigning() throws {
        let report = try Fixture.localOnly(
            mutatingProject: { $0.replacingOccurrences(of: "ATTRIBUTES = (CodeSignOnCopy, ", with: "ATTRIBUTES = (") },
            shape: .localOnly
        )
        #expect(report.findings.contains { $0.summary.contains("without Code Sign On Copy") })
    }

    @Test("R3 — a hosted test bundle without TEST_HOST is an error")
    func hostedBundleMissingItsHost() throws {
        let report = try Fixture.localOnly(
            mutatingProject: { project in
                project
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .filter { !$0.contains("TEST_HOST = ") && !$0.contains("BUNDLE_LOADER = ") }
                    .joined(separator: "\n")
            },
            shape: .localOnly
        )
        #expect(report.findings.contains { $0.summary.contains("does not pin TEST_HOST") })
        #expect(report.findings.contains { $0.summary.contains("does not set BUNDLE_LOADER") })
    }

    // MARK: Test plans

    @Test("R9 — a test plan pointing at a re-minted identifier is an error")
    func danglingTestPlanReference() throws {
        let report = try Fixture.clientServer(
            mutatingTestPlan: { plan in
                var plan = plan
                plan["testTargets"] = (plan["testTargets"] as? [[String: Any]] ?? []).map { entry in
                    var entry = entry
                    if var target = entry["target"] as? [String: Any] {
                        target["identifier"] = "DEADBEEFDEADBEEFDEADBEEF"
                        entry["target"] = target
                    }
                    return entry
                }
                return plan
            },
            shape: .clientServer
        )
        let finding = try #require(report.findings.first { $0.summary.contains("identifier no target") })
        #expect(finding.severity == .error)
    }

    @Test("R9 — a plan belonging to a sibling project is left alone")
    func planForAnotherContainer() throws {
        // A repo can hold more than one Xcode project. Judging a sibling's plan
        // against this project reports a dangling reference for a target that
        // is present elsewhere — or, as found in the field, one whose project
        // has not been generated yet.
        let report = try Fixture.clientServer(
            mutatingTestPlan: { plan in
                var plan = plan
                plan["testTargets"] = [[
                    "target": [
                        "containerPath": "container:SomethingElse.xcodeproj",
                        "identifier": "NotAUUIDAtAll",
                        "name": "SomeOtherTests"
                    ]
                ]]
                return plan
            },
            shape: .clientServer
        )
        #expect(report.findings.isEmpty, "unexpected: \(report.text)")
    }

    @Test("R9 — a plan naming this project by container is still judged")
    func planForThisContainer() throws {
        let report = try Fixture.clientServer(
            mutatingTestPlan: { plan in
                var plan = plan
                plan["testTargets"] = [[
                    "target": [
                        "containerPath": "container:PalettePress.xcodeproj",
                        "identifier": "DEADBEEFDEADBEEFDEADBEEF",
                        "name": "PalettePressUnitTests"
                    ]
                ]]
                return plan
            },
            shape: .clientServer
        )
        #expect(report.findings.contains { $0.summary.contains("identifier no target") })
    }

    // MARK: Shape-conditional

    @Test("R7 — a client-server app without outgoing connections is an error")
    func clientServerNeedsNetworkClient() throws {
        let report = try Fixture.clientServer(
            mutatingEntitlements: { $0.replacingOccurrences(of: "com.apple.security.network.client", with: "com.apple.security.unused") },
            shape: .clientServer
        )
        let finding = try #require(report.findings.first { $0.summary.contains("network.client") })
        #expect(finding.severity == .error)
    }

    @Test("R7 — disabling library validation is reported as the symptom it is")
    func disabledLibraryValidation() throws {
        let report = try Fixture.localOnly(
            mutatingEntitlements: {
                $0.replacingOccurrences(
                    of: "<key>com.apple.security.app-sandbox</key>",
                    with: "<key>com.apple.security.cs.disable-library-validation</key><true/><key>com.apple.security.app-sandbox</key>"
                )
            },
            shape: .localOnly
        )
        #expect(report.findings.contains { $0.summary.contains("disables library validation") })
    }

    @Test("R8 — YAML outside the hosting's tree is a warning, not an error")
    func strayLocalizationYAML() throws {
        let report = try Fixture.localOnly(shape: .localOnly) { root in
            let stray = root.appendingPathComponent("Sources/ViewModels/Stray.yml")
            try Data("title: stray\n".utf8).write(to: stray)
        }
        let finding = try #require(report.findings.first { $0.summary.contains("outside the tree") })
        #expect(finding.severity == .warning)
        #expect(!report.hasErrors, "R8 alone must not fail the run")
    }

    @Test("R8 — FieldModels YAML is the Fields-messages sibling, not a stray")
    func fieldModelsYAMLIsInTree() throws {
        let report = try Fixture.localOnly(shape: .localOnly) { root in
            let dir = root.appendingPathComponent("Sources/ViewModels/Resources/FieldModels")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("en:\n  CardFieldsMessages:\n    title:\n      title: \"Title\"\n".utf8)
                .write(to: dir.appendingPathComponent("CardFieldsMessages.yml"))
        }
        #expect(!report.findings.contains { $0.summary.contains("outside the tree") })
    }

    // MARK: Floors

    @Test("R10 — a deployment target below the FOSUtilities floor is an error")
    func belowPlatformFloor() throws {
        let report = try Fixture.localOnly(
            mutatingProject: { $0.replacingOccurrences(of: "MACOSX_DEPLOYMENT_TARGET = 14.0;", with: "MACOSX_DEPLOYMENT_TARGET = 12.0;") },
            shape: .localOnly
        )
        let finding = try #require(report.findings.first { $0.summary.contains("below the FOSUtilities floor") })
        #expect(finding.severity == .error)
    }

    @Test("R10 — the manifest and the xcodeproj disagreeing is an error")
    func manifestDisagreesWithProject() throws {
        let report = try Fixture.clientServer(
            mutatingManifest: { $0.replacingOccurrences(of: ".macOS(\"14.0\")", with: ".macOS(\"15.0\")") },
            shape: .clientServer
        )
        #expect(report.findings.contains { $0.summary.contains("but Package.swift declares macOS 15.0") })
    }

    @Test("R10 — version constants are read, not given up on")
    func manifestVersionConstants() throws {
        // `.macOS(.v14)` is how hand-written manifests are usually spelled —
        // FOSUtilities' own is. Reading only string literals would leave R10
        // silently unable to check most of the projects doctor exists for.
        let report = try Fixture.clientServer(
            mutatingManifest: { $0.replacingOccurrences(of: ".macOS(\"14.0\")", with: ".macOS(.v14)") },
            shape: .clientServer
        )
        #expect(report.findings.isEmpty, "unexpected: \(report.text)")
    }

    @Test("R10 — a point-release constant carries its minor version")
    func manifestPointReleaseConstant() throws {
        // .v14_5 is 14.5, which disagrees with the xcodeproj's 14.0 — proving
        // the minor component survives rather than being rounded to .0.
        let report = try Fixture.clientServer(
            mutatingManifest: { $0.replacingOccurrences(of: ".macOS(\"14.0\")", with: ".macOS(.v14_5)") },
            shape: .clientServer
        )
        #expect(report.findings.contains { $0.summary.contains("Package.swift declares macOS 14.5") })
    }

    @Test("R10 — a version constant below the floor is still caught")
    func manifestConstantBelowFloor() throws {
        let report = try Fixture.clientServer(
            mutatingManifest: { $0.replacingOccurrences(of: ".macOS(\"14.0\")", with: ".macOS(.v12)") },
            shape: .clientServer
        )
        #expect(report.findings.contains { $0.summary.contains("macOS 12.0, below the FOSUtilities floor") })
    }

    @Test("R10 — a manifest this reader cannot follow is a warning, not silence")
    func unreadableManifestPlatforms() throws {
        let report = try Fixture.clientServer(
            mutatingManifest: { $0.replacingOccurrences(of: ".macOS(\"14.0\")", with: ".macOS(someConstant)") },
            shape: .clientServer
        )
        let finding = try #require(report.findings.first { $0.summary.contains("could not read") })
        #expect(finding.severity == .warning)
    }
}

/// The report surface — verdict, rendering, ordering, JSON — separate from the
/// rule suite, whose body length grows with every rule.
@Suite("Doctor report")
struct DoctorReportTests {
    @Test("only errors fail the run")
    func warningsDoNotFailTheRun() {
        let warned = Doctor.Report(
            findings: [Finding(severity: .warning, summary: "s", remedy: "r")],
            unchecked: []
        )
        #expect(!warned.hasErrors)

        let errored = Doctor.Report(
            findings: [Finding(severity: .error, summary: "s", remedy: "r")],
            unchecked: []
        )
        #expect(errored.hasErrors)
    }

    @Test("a clean report says so")
    func cleanReportText() {
        let report = Doctor.Report(findings: [], unchecked: [])
        #expect(report.text.contains("No findings"))
    }

    @Test("errors sort ahead of warnings")
    func findingsSortBySeverity() {
        let report = Doctor.Report(
            findings: [
                Finding(severity: .warning, summary: "w", remedy: "r"),
                Finding(severity: .error, summary: "e", remedy: "r")
            ],
            unchecked: []
        )
        #expect(report.findings.first?.severity == .error)
    }

    // MARK: JSON

    @Test("the JSON report round-trips its findings and carries the verdict")
    func jsonReportContract() throws {
        let report = Doctor.Report(
            findings: [
                Finding(severity: .error, target: "PalettePress", summary: "e", remedy: "fix e"),
                Finding(severity: .warning, summary: "w", remedy: "fix w")
            ],
            unchecked: ["entitlements posture (needs --shape)"]
        )

        let data = try Data(report.json.utf8)
        let top = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(top["hasErrors"] as? Bool == true)
        #expect(top["unchecked"] as? [String] == report.unchecked)

        let findingsData = try JSONSerialization.data(withJSONObject: top["findings"] as Any)
        let decoded = try JSONDecoder().decode([Finding].self, from: findingsData)
        #expect(decoded == report.findings)
    }

    @Test("a clean report's JSON gates false")
    func cleanJSONReport() throws {
        let report = Doctor.Report(findings: [], unchecked: [])
        let top = try #require(
            try JSONSerialization.jsonObject(with: Data(report.json.utf8)) as? [String: Any]
        )
        #expect(top["hasErrors"] as? Bool == false)
        #expect((top["findings"] as? [Any])?.isEmpty == true)
    }
}

/// R13/R14 — the shared-module pair. Keyed on scanned sources rather than on
/// project structure, so both run for every shape, shared-library included.
@Suite("Doctor — shared module")
struct DoctorSharedModuleRuleTests {
    @Test("R13 — a ViewModel declared outside the shared module is an error")
    func viewModelOutsideSharedModule() throws {
        let report = try Fixture.localOnly(shape: .localOnly) { root in
            try Data("""
            import FOSMVVM

            @ViewModel
            public struct StrayViewModel {}
            """.utf8).write(to: root.appendingPathComponent("Sources/PalettePress/StrayViewModel.swift"))
        }
        let finding = try #require(report.findings.first { $0.summary.contains("outside a shared ViewModels module") })
        #expect(finding.severity == .error)
        #expect(finding.summary.contains("StrayViewModel.swift"))
    }

    @Test("R13 — a ViewModel inside the shared module is silent")
    func viewModelInsideSharedModule() throws {
        let report = try Fixture.localOnly(shape: .localOnly) { root in
            try Data("import FOSMVVM\n\n@ViewModel\npublic struct HomeViewModel {}\n".utf8)
                .write(to: root.appendingPathComponent("Sources/ViewModels/HomeViewModel.swift"))
        }
        #expect(!report.findings.contains { $0.summary.contains("ViewModels module") })
    }

    @Test("R13 — a comment mentioning @ViewModel is prose, not a declaration")
    func viewModelInCommentIsNotADeclaration() throws {
        let report = try Fixture.localOnly(shape: .localOnly) { root in
            try Data("""
            import Vapor

            // Serves the read slice — now LIVE (`@ViewModel(options: [.live])`); the
            // grouped register mounts it behind the credential middleware.
            func routes() {}
            """.utf8).write(to: root.appendingPathComponent("Sources/PalettePress/Routes.swift"))
        }
        #expect(!report.findings.contains { $0.summary.contains("ViewModels module") })
    }

    @Test("R13 — a Package.swift mentioning @ViewModel is a manifest, not a source")
    func manifestMentionIsNotADeclaration() throws {
        let report = try Fixture.localOnly(shape: .localOnly) { root in
            let manifest = root.appendingPathComponent("Package.swift")
            let existing = (try? String(contentsOf: manifest, encoding: .utf8)) ?? ""
            try Data((existing + "\n// the shared library — every per-screen `@ViewModel` lives here\n").utf8)
                .write(to: manifest)
        }
        #expect(!report.findings.contains { $0.summary.contains("Package.swift") })
    }

    @Test("R13 — a test-target ViewModel is a fixture, not a finding")
    func viewModelIsExempt() throws {
        let report = try Fixture.sharedLibrary(shape: .sharedLibrary) { root in
            let dir = root.appendingPathComponent("Tests/PalettePressViewModelsTests")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("@ViewModel\nstruct FixtureViewModel {}\n".utf8)
                .write(to: dir.appendingPathComponent("FixtureViewModel.swift"))
        }
        #expect(!report.findings.contains { $0.summary.contains("ViewModels module") })
    }

    @Test("R14 — a Fluent import inside the shared module is an error")
    func serverImportInsideSharedModule() throws {
        let report = try Fixture.sharedLibrary(shape: .sharedLibrary) { root in
            try Data("import Fluent\nimport FOSMVVM\n".utf8)
                .write(to: root.appendingPathComponent("Sources/PalettePressViewModels/Leak.swift"))
        }
        let finding = try #require(report.findings.first { $0.summary.contains("server code inside the shared module") })
        #expect(finding.severity == .error)
        #expect(finding.summary.contains("Leak.swift"))
        #expect(finding.summary.contains("Fluent"))
    }

    @Test("R14 — server imports outside the shared module are not its business")
    func serverImportElsewhereIsSilent() throws {
        // A server target importing Vapor is exactly right; R14 polices only
        // the shared module's own sources.
        let report = try Fixture.localOnly(shape: .localOnly) { root in
            try Data("import Vapor\n".utf8)
                .write(to: root.appendingPathComponent("Sources/PalettePress/Serverish.swift"))
        }
        #expect(!report.findings.contains { $0.summary.contains("server code inside the shared module") })
    }
}
