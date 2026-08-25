// AuditedProject.swift
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

// AuditedProject.swift
import Foundation
import PathKit
import XcodeProj

/// The project as the rules see it: the facts `ProjectRule.all` needs, lifted
/// out of the `.xcodeproj`, the package manifest, and the tree on disk.
///
/// This is the seam that keeps every rule off XcodeProj's API. A breaking
/// change upstream lands here and nowhere else.
struct AuditedProject {
    /// The directory that was audited.
    let root: URL

    /// False when the tree holds no `.xcodeproj` — the shared-library shape.
    /// Rules that read Xcode settings stay silent rather than reporting a
    /// project-wide failure.
    let hasXcodeProject: Bool

    /// The audited project's file name (`MyApp.xcodeproj`), so a test plan
    /// belonging to a sibling project can be told apart from one belonging here.
    let xcodeProjectName: String?

    let targets: [AuditedTarget]

    /// Every build-setting key declared anywhere in the project, at any level.
    /// R2 scans this for near-miss spellings, which a per-target lookup by
    /// exact key cannot see.
    let declaredSettingKeys: Set<String>

    let manifestPlatforms: ManifestPlatforms

    let testPlans: [AuditedTestPlan]

    /// Localization YAML, relative to `root`.
    let localizationYAMLPaths: [String]

    /// Non-test Swift sources, scanned for their imports and for `@ViewModel`
    /// declarations. R13 and R14 read these.
    let swiftSources: [ScannedSwiftSource]

    /// Directories under `Sources/` that are the shared ViewModels module's
    /// home by the scaffolder's convention — `ViewModels`, or a `…ViewModels`
    /// suffix. The name only defines the sanctioned home; the typed content
    /// (`@ViewModel` declarations) is what the rules key their findings on.
    let sharedModuleRoots: [String]
}

/// One Swift source as the shared-module rules see it: where it lives, what it
/// imports, and whether it declares a `@ViewModel` type.
///
/// Test sources are excluded at scan time — a ViewModel declared inside a test
/// target is a fixture, and test targets legitimately import server products.
struct ScannedSwiftSource {
    let relativePath: String
    let imports: [String]
    let declaresViewModel: Bool
}

/// What the package manifest says about platforms — including the case where
/// it says something this reader could not follow.
///
/// Ruling 2b reads declared values, and a manifest is Swift rather than data,
/// so the `platforms:` array is scanned rather than evaluated. `unreadable`
/// exists so R10 can report that it could not check instead of passing.
enum ManifestPlatforms: Equatable {
    case absent
    case unreadable
    case declared([TargetPlatform: String])
}

struct AuditedTarget {
    /// The pbxproj object identifier. Test plans reference targets by this,
    /// and R9 exists because regenerating a project re-mints them.
    let identifier: String

    let name: String
    let productName: String?
    let kind: TargetKind

    /// Settings by configuration name, with project-level values merged in and
    /// target-level values winning. The templates set `SWIFT_VERSION` once at
    /// the project level, so a rule asking "on every target" has to see it
    /// through the merge to be answerable.
    let settings: [String: [String: String]]

    /// SPM product names this target links directly.
    let packageProducts: [String]

    /// Names of other targets in this project that this one depends on.
    let localDependencies: [String]

    /// Frameworks copied into this target's bundle.
    let embedded: [EmbeddedFramework]

    /// Entitlement keys set to `true`, or nil when the target declares no
    /// entitlements file.
    let entitlements: Set<String>?
}

struct EmbeddedFramework: Equatable {
    let name: String
    let signOnCopy: Bool
}

enum TargetKind: Equatable {
    case application
    case framework
    case unitTestBundle
    case uiTestBundle
    case other

    var isTestBundle: Bool {
        self == .unitTestBundle || self == .uiTestBundle
    }
}

struct AuditedTestPlan {
    let name: String
    /// Targets the plan names, as (identifier, target name) pairs straight from
    /// the plan's JSON — unresolved, because whether they resolve is the finding.
    ///
    /// A repo can hold more than one Xcode project, and a plan belonging to a
    /// sibling project must not be judged against this one. `container` carries
    /// the plan's own `containerPath` so R9 can tell them apart.
    let references: [(identifier: String, name: String, container: String?)]
}

enum AuditedProjectError: Error, Equatable {
    case rootNotFound(String)
    case unreadableProject(String)
}

extension AuditedProjectError: CustomStringConvertible {
    var description: String {
        switch self {
        case .rootNotFound(let path):
            "no such directory: \(path)"
        case .unreadableProject(let detail):
            "could not read the Xcode project: \(detail)"
        }
    }
}

extension AuditedProject {
    /// Reads everything the rules need from a project directory.
    static func read(from root: URL) throws -> AuditedProject {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            throw AuditedProjectError.rootNotFound(root.path)
        }

        let projectPath = try locateXcodeProject(in: root)
        var targets: [AuditedTarget] = []
        var declaredKeys: Set<String> = []

        if let projectPath {
            let proj: XcodeProj
            do {
                proj = try XcodeProj(path: Path(projectPath.path))
            } catch {
                throw AuditedProjectError.unreadableProject("\(projectPath.lastPathComponent): \(error)")
            }
            let projectSettings = settingsByConfiguration(
                proj.pbxproj.rootObject?.buildConfigurationList
            )
            for configured in projectSettings.values {
                declaredKeys.formUnion(configured.keys)
            }

            for target in proj.pbxproj.rootObject?.targets ?? [] {
                let own = settingsByConfiguration(target.buildConfigurationList)
                for configured in own.values {
                    declaredKeys.formUnion(configured.keys)
                }
                targets.append(
                    audited(target, own: own, projectSettings: projectSettings, root: root)
                )
            }
        }

        return AuditedProject(
            root: root,
            hasXcodeProject: projectPath != nil,
            xcodeProjectName: projectPath?.lastPathComponent,
            targets: targets.sorted { $0.name < $1.name },
            declaredSettingKeys: declaredKeys,
            manifestPlatforms: readManifestPlatforms(in: root),
            testPlans: readTestPlans(in: root),
            localizationYAMLPaths: localizationYAML(in: root),
            swiftSources: scanSwiftSources(in: root),
            sharedModuleRoots: sharedModuleRoots(in: root)
        )
    }

    private static func locateXcodeProject(in root: URL) throws -> URL? {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let projects = entries.filter { $0.hasSuffix(".xcodeproj") }.sorted()
        guard let first = projects.first else { return nil }
        return root.appendingPathComponent(first)
    }

    private static func audited(
        _ target: PBXTarget,
        own: [String: [String: String]],
        projectSettings: [String: [String: String]],
        root: URL
    ) -> AuditedTarget {
        // Merge project-level under target-level, per configuration. A
        // configuration named at either level appears in the result.
        var merged: [String: [String: String]] = [:]
        for name in Set(own.keys).union(projectSettings.keys) {
            merged[name] = (projectSettings[name] ?? [:]).merging(own[name] ?? [:]) { _, target in target }
        }

        let kind: TargetKind = switch target.productType {
        case .application: .application
        case .framework: .framework
        case .unitTestBundle: .unitTestBundle
        case .uiTestBundle: .uiTestBundle
        default: .other
        }

        return AuditedTarget(
            identifier: target.uuid,
            name: target.name,
            productName: target.productName,
            kind: kind,
            settings: merged,
            packageProducts: (target.packageProductDependencies ?? []).map(\.productName).sorted(),
            localDependencies: target.dependencies.compactMap { $0.target?.name }.sorted(),
            embedded: embeddedFrameworks(of: target),
            entitlements: entitlements(of: merged, root: root)
        )
    }

    /// Frameworks the target copies into its own bundle, and whether each is
    /// re-signed on the way in. Xcode models "Embed & Sign" as a copy-files
    /// phase into the Frameworks subfolder with `CodeSignOnCopy` attached.
    private static func embeddedFrameworks(of target: PBXTarget) -> [EmbeddedFramework] {
        var found: [EmbeddedFramework] = []
        for phase in target.buildPhases {
            guard let copy = phase as? PBXCopyFilesBuildPhase,
                  copy.dstSubfolderSpec == .frameworks else { continue }
            for file in copy.files ?? [] {
                let attributes = file.settings?["ATTRIBUTES"]?.arrayValue ?? []
                let name = file.file?.name
                    ?? file.file?.path
                    ?? file.product?.productName
                guard let name else { continue }
                found.append(
                    EmbeddedFramework(
                        name: (name as NSString).deletingPathExtension,
                        signOnCopy: attributes.contains("CodeSignOnCopy")
                    )
                )
            }
        }
        return found.sorted { $0.name < $1.name }
    }

    /// Entitlement keys set to `true`. Configurations are searched in a stable
    /// order and the first declared file wins — the templates point every
    /// configuration at the same one.
    private static func entitlements(of settings: [String: [String: String]], root: URL) -> Set<String>? {
        let declared = settings.keys.sorted()
            .compactMap { settings[$0]?["CODE_SIGN_ENTITLEMENTS"] }
            .first { !$0.isEmpty }
        guard let declared else { return nil }

        let url = root.appendingPathComponent(declared)
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = plist as? [String: Any]
        else { return nil }

        return Set(dict.compactMap { key, value in (value as? Bool) == true ? key : nil })
    }

    private static func settingsByConfiguration(_ list: XCConfigurationList?) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        for configuration in list?.buildConfigurations ?? [] {
            result[configuration.name] = configuration.buildSettings.mapValues(\.description)
        }
        return result
    }
}

// MARK: - Manifest

private extension AuditedProject {
    /// Scans `Package.swift` for its `platforms:` array.
    ///
    /// Not an evaluation — ruling 2b reads declared values, and evaluating a
    /// manifest means running SwiftPM. A manifest whose platforms line this
    /// cannot follow reports `.unreadable`, which R10 turns into a warning
    /// rather than silence.
    static func readManifestPlatforms(in root: URL) -> ManifestPlatforms {
        let manifest = root.appendingPathComponent("Package.swift")
        guard let source = try? String(contentsOf: manifest, encoding: .utf8) else {
            return .absent
        }
        guard let platformsRange = source.range(of: "platforms:") else {
            // A manifest may legitimately omit platforms; that is a declaration
            // of nothing, not an unreadable one.
            return .declared([:])
        }

        // Take the bracketed array that follows and read the platform entries
        // out of it.
        let tail = source[platformsRange.upperBound...]
        guard let open = tail.firstIndex(of: "["), let close = tail[open...].firstIndex(of: "]") else {
            return .unreadable
        }
        let body = String(tail[tail.index(after: open)..<close])

        // Two spellings, both common. The scaffolder emits string literals
        // (`.macOS("14.0")`); hand-written manifests usually use the version
        // constants (`.macOS(.v14)`, `.iOS(.v17_4)`) — FOSUtilities' own
        // manifest does. Reading only the first would leave R10 silently
        // unable to check the majority of the projects doctor exists for.
        var declared: [TargetPlatform: String] = [:]
        let pattern = #"\.([A-Za-z]+)\(\s*(?:"([0-9.]+)"|\.v([0-9]+(?:_[0-9]+)*))\s*\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return .unreadable }
        let matches = regex.matches(in: body, range: NSRange(body.startIndex..., in: body))
        for match in matches {
            guard let nameRange = Range(match.range(at: 1), in: body),
                  let platform = TargetPlatform(rawValue: String(body[nameRange]))
            else { continue }

            if let literal = Range(match.range(at: 2), in: body) {
                declared[platform] = String(body[literal])
            } else if let constant = Range(match.range(at: 3), in: body) {
                // `.v14` is 14.0; `.v17_4` is 17.4. The bare-major form gains
                // its `.0` so findings read as versions ("macOS 12.0") rather
                // than as the constant's spelling ("macOS 12").
                let version = String(body[constant]).replacingOccurrences(of: "_", with: ".")
                declared[platform] = version.contains(".") ? version : version + ".0"
            }
        }

        // Entries were present but none parsed — say so rather than reporting
        // a platform-free manifest.
        if declared.isEmpty, body.contains(".") {
            return .unreadable
        }
        return .declared(declared)
    }
}

// MARK: - Swift sources

private extension AuditedProject {
    static func sharedModuleRoots(in root: URL) -> [String] {
        let sources = root.appendingPathComponent("Sources")
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: sources.path)) ?? []
        return entries
            .filter { $0 == "ViewModels" || $0.hasSuffix("ViewModels") }
            .map { "Sources/\($0)" }
            .sorted()
    }

    static func scanSwiftSources(in root: URL) -> [ScannedSwiftSource] {
        guard let importPattern = try? NSRegularExpression(
            pattern: #"^\s*(?:@testable\s+)?import\s+([A-Za-z_][A-Za-z0-9_]*)"#,
            options: [.anchorsMatchLines]
        ) else { return [] }

        var scanned: [ScannedSwiftSource] = []
        for url in files(under: root) where url.pathExtension == "swift" {
            guard let relativePath = relative(url, to: root) else { continue }
            // SPM manifests are build scripts, not module sources — a `@ViewModel`
            // in one can only be prose (measured: a comment in a manifest produced
            // a false R13 finding naming Package.swift itself).
            guard !url.lastPathComponent.hasPrefix("Package") else { continue }
            let components = relativePath.split(separator: "/").map(String.init)
            guard !components.contains(where: { $0 == "Tests" || $0.hasSuffix("Tests") }) else { continue }
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }

            let range = NSRange(contents.startIndex..., in: contents)
            let imports = importPattern.matches(in: contents, range: range).compactMap { match -> String? in
                guard let moduleRange = Range(match.range(at: 1), in: contents) else { return nil }
                return String(contents[moduleRange])
            }

            scanned.append(
                ScannedSwiftSource(
                    relativePath: relativePath,
                    imports: Set(imports).sorted(),
                    // Anchored to line start: a Swift attribute leads its declaration
                    // line, while a `@ViewModel` mentioned mid-line is prose in a
                    // comment (measured: two comment mentions produced false R13
                    // findings). The trailing \b keeps @ViewModelFactory out.
                    declaresViewModel: contents.range(
                        of: #"(?m)^\s*@ViewModel\b"#,
                        options: .regularExpression
                    ) != nil
                )
            )
        }
        return scanned.sorted { $0.relativePath < $1.relativePath }
    }
}

// MARK: - Test plans and YAML

private extension AuditedProject {
    static func readTestPlans(in root: URL) -> [AuditedTestPlan] {
        var plans: [AuditedTestPlan] = []
        for url in files(under: root) where url.pathExtension == "xctestplan" {
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let testTargets = json["testTargets"] as? [[String: Any]]
            else { continue }

            let references: [(identifier: String, name: String, container: String?)] = testTargets.compactMap { entry in
                guard let target = entry["target"] as? [String: Any],
                      let identifier = target["identifier"] as? String
                else { return nil }
                return (identifier, target["name"] as? String ?? "", target["containerPath"] as? String)
            }
            plans.append(
                AuditedTestPlan(name: url.deletingPathExtension().lastPathComponent, references: references)
            )
        }
        return plans.sorted { $0.name < $1.name }
    }

    /// YAML under `Sources/`, which is where localization lives regardless of
    /// hosting. Scoped to `Sources/` rather than filtered by `Resources/`:
    /// whether a file sits in the right Resources tree is R8's finding to make,
    /// so pre-filtering on it would leave that rule unable to fail.
    static func localizationYAML(in root: URL) -> [String] {
        files(under: root.appendingPathComponent("Sources"))
            .filter { $0.pathExtension == "yml" || $0.pathExtension == "yaml" }
            .compactMap { relative($0, to: root) }
            .sorted()
    }

    static func files(under root: URL) -> [URL] {
        let skipped: Set = [".build", ".git", "DerivedData", "build"]
        guard let walker = FileManager.default.enumerator(
            at: root.standardizedFileURL,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }

        var found: [URL] = []
        for case let url as URL in walker {
            if skipped.contains(url.lastPathComponent) || url.pathExtension == "xcodeproj" {
                walker.skipDescendants()
                continue
            }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            found.append(url)
        }
        return found
    }

    static func relative(_ url: URL, to root: URL) -> String? {
        let base = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(base + "/") else { return nil }
        return String(path.dropFirst(base.count + 1))
    }
}
