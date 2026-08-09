# fosmvvm-bootstrap Plan 1 — CLI Core + shared-library Template

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the `fosmvvm-bootstrap` repo with the typed scaffolder core (config, floor rules, renderer, emitter, verifier, CLI) proven end-to-end on the shared-library project shape.

**Architecture:** A Swift package: `BootstrapKit` library (all logic, fully testable) + a thin `fosmvvm-bootstrap` executable (swift-argument-parser). Templates ship as `Bundle.module` resources of `BootstrapKit`. Rendering is strict token substitution (`{{TOKEN}}`); any unrendered token is a fatal error. The `verify` phase runs `swift build` / `swift test` inside the generated project — the tool never hands over a broken skeleton.

**Tech Stack:** Swift 6 / Swift Testing, swift-argument-parser. Generated projects depend on FOSUtilities 0.10.0.

**Spec:** `docs/superpowers/specs/2026-07-24-fosmvvm-project-bootstrap-design.md` (FOSUtilities repo). This plan implements the spec's §6.1–§6.4 core for the shared-library shape only. Plans 2–5 add the other shapes, `doctor`, the skill wrapper, and CI publishing.

**Working directory:** `/Users/david/Repository/FOS/fosmvvm-bootstrap` (new repo — no worktree needed; nothing exists yet). Plan documents and spec stay in FOSUtilities.

**Naming note:** type names below (`BootstrapKit`, `ProjectShape`, `TemplateRenderer`, `Emitter`, `Verifier`, `FOSPlatformFloor`) are proposals. David arbitrates names; confirm before large-scale renames.

**One refinement vs the spec's §6.1 sketch:** templates live at `Sources/BootstrapKit/Templates/` (not repo root) because SPM resources must live inside the target directory for `Bundle.module` access. Conceptually identical; placement only.

---

### Task 1: Repo + package scaffold

**Files:**
- Create: `/Users/david/Repository/FOS/fosmvvm-bootstrap/Package.swift`
- Create: `Sources/BootstrapKit/BootstrapKit.swift` (placeholder)
- Create: `Sources/BootstrapCLI/Main.swift` (placeholder)
- Create: `Tests/BootstrapKitTests/SmokeTests.swift`
- Create: `.gitignore`

- [ ] **Step 1: Create the repo**

```bash
mkdir -p /Users/david/Repository/FOS/fosmvvm-bootstrap
cd /Users/david/Repository/FOS/fosmvvm-bootstrap
git init -b main
```

- [ ] **Step 2: Write Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "fosmvvm-bootstrap",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "fosmvvm-bootstrap", targets: ["BootstrapCLI"]),
        .library(name: "BootstrapKit", targets: ["BootstrapKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "BootstrapKit",
            resources: [
                .copy("Templates")
            ]
        ),
        .executableTarget(
            name: "BootstrapCLI",
            dependencies: [
                "BootstrapKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "BootstrapKitTests",
            dependencies: ["BootstrapKit"]
        )
    ],
    swiftLanguageModes: [.v6]
)
```

- [ ] **Step 3: Placeholder sources so the package builds**

`Sources/BootstrapKit/BootstrapKit.swift`:
```swift
// BootstrapKit.swift
public enum BootstrapKit {
    public static let version = "0.1.0"
}
```

`Sources/BootstrapKit/Templates/.gitkeep`: empty file (so the resource dir exists).

`Sources/BootstrapCLI/Main.swift`:
```swift
// Main.swift
import ArgumentParser
import BootstrapKit

@main
struct FOSMVVMBootstrap: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fosmvvm-bootstrap",
        abstract: "Scaffold FOSMVVM projects the FOS-mvvm way.",
        version: BootstrapKit.version
    )
}
```

`Tests/BootstrapKitTests/SmokeTests.swift`:
```swift
import BootstrapKit
import Testing

@Suite struct SmokeTests {
    @Test func versionExists() {
        #expect(!BootstrapKit.version.isEmpty)
    }
}
```

`.gitignore`:
```
.build/
.DS_Store
*.xcodeproj
```

- [ ] **Step 4: Verify build + test**

Run: `swift test`
Expected: PASS (1 test)

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "chore: package scaffold — BootstrapKit + CLI + test target"
```

---

### Task 2: ProjectShape + BootstrapConfig

**Files:**
- Create: `Sources/BootstrapKit/ProjectShape.swift`
- Create: `Sources/BootstrapKit/BootstrapConfig.swift`
- Test: `Tests/BootstrapKitTests/BootstrapConfigTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import BootstrapKit
import Foundation
import Testing

@Suite struct BootstrapConfigTests {
    @Test func decodesSharedLibraryConfig() throws {
        let json = """
        {
          "projectName": "PalettePress",
          "shape": "sharedLibrary",
          "platforms": { "macOS": "14.0", "iOS": "17.0" }
        }
        """
        let config = try JSONDecoder().decode(BootstrapConfig.self, from: Data(json.utf8))
        #expect(config.projectName == "PalettePress")
        #expect(config.shape == .sharedLibrary)
        #expect(config.platforms[.macOS] == "14.0")
    }

    @Test func rejectsInvalidProjectName() throws {
        let config = BootstrapConfig(
            projectName: "Palette Press!",
            shape: .sharedLibrary,
            platforms: [.macOS: "14.0"]
        )
        #expect(throws: BootstrapConfigError.invalidProjectName("Palette Press!")) {
            try config.validate()
        }
    }

    @Test func validSharedLibraryConfigPasses() throws {
        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .sharedLibrary,
            platforms: [.macOS: "14.0"]
        )
        try config.validate()
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter BootstrapConfigTests`
Expected: FAIL — `BootstrapConfig` not defined

- [ ] **Step 3: Implement**

`Sources/BootstrapKit/ProjectShape.swift`:
```swift
// ProjectShape.swift

/// The four canonical FOSMVVM project shapes (spec §5).
public enum ProjectShape: String, Codable, CaseIterable, Sendable {
    case localOnly
    case clientServer
    case hybrid
    case sharedLibrary
}

/// Platforms a generated project may declare.
///
/// `CodingKeyRepresentable` makes `[TargetPlatform: String]` encode and
/// decode as a JSON *object* (`{ "macOS": "14.0" }`). Without it,
/// Foundation codes enum-keyed dictionaries as an array of alternating
/// pairs and the config-file decode fails. For a String-raw enum the
/// stdlib synthesizes the conformance — no custom Codable glue.
public enum TargetPlatform: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
    case iOS, macOS, macCatalyst, tvOS, watchOS, visionOS
}
```

`Sources/BootstrapKit/BootstrapConfig.swift`:
```swift
// BootstrapConfig.swift
import Foundation

/// Typed input to the scaffolder. Loaded from JSON (`--config`); the
/// plugin skill authors this file from its conversational interview.
public struct BootstrapConfig: Codable, Sendable {
    public let projectName: String
    public let shape: ProjectShape
    /// Platform → minimum version string ("14.0"). Validated against
    /// the FOS floor (spec §9, invariant 2) in Task 3.
    public let platforms: [TargetPlatform: String]
    public let licenseHeader: String?

    public init(
        projectName: String,
        shape: ProjectShape,
        platforms: [TargetPlatform: String],
        licenseHeader: String? = nil
    ) {
        self.projectName = projectName
        self.shape = shape
        self.platforms = platforms
        self.licenseHeader = licenseHeader
    }

    /// Rejects configs that would generate broken or leak-prone projects.
    public func validate() throws {
        guard projectName.range(of: "^[A-Za-z][A-Za-z0-9]*$", options: .regularExpression) != nil else {
            throw BootstrapConfigError.invalidProjectName(projectName)
        }
        guard !platforms.isEmpty else {
            throw BootstrapConfigError.noPlatforms
        }
    }
}

public enum BootstrapConfigError: Error, Equatable {
    case invalidProjectName(String)
    case noPlatforms
    case belowFOSFloor(platform: TargetPlatform, asked: String, floor: String)
    case platformUnsupportedByFOS(TargetPlatform)
}
```

Note: the `CodingKeyRepresentable` conformance on `TargetPlatform` is
load-bearing — it is what makes the JSON-object form of `platforms`
decode. Do not remove it.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter BootstrapConfigTests`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: ProjectShape + BootstrapConfig with name/platform validation"
```

---

### Task 3: FOS platform floor rule

The first entry in the rules table shared by emit and (Plan 5) `doctor`.
Floors are FOSUtilities 0.10.0's `platforms:` — verified from
`FOSUtilities/Package.swift`: iOS 17, macOS 14, macCatalyst 17, tvOS 17,
watchOS 10, visionOS 1.

**Files:**
- Create: `Sources/BootstrapKit/FOSPlatformFloor.swift`
- Test: `Tests/BootstrapKitTests/FOSPlatformFloorTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import BootstrapKit
import Testing

@Suite struct FOSPlatformFloorTests {
    @Test func atFloorPasses() throws {
        try FOSPlatformFloor.validate(platforms: [.macOS: "14.0", .iOS: "17.0"])
    }

    @Test func aboveFloorPasses() throws {
        try FOSPlatformFloor.validate(platforms: [.macOS: "26.0"])
    }

    @Test func belowFloorThrows() {
        #expect(throws: BootstrapConfigError.belowFOSFloor(platform: .macOS, asked: "13.0", floor: "14.0")) {
            try FOSPlatformFloor.validate(platforms: [.macOS: "13.0"])
        }
    }

    @Test func minorVersionComparesNumerically() throws {
        // "10.4" < "10.15" numerically even though it sorts after lexically
        try FOSPlatformFloor.validate(platforms: [.watchOS: "10.4"])
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter FOSPlatformFloorTests`
Expected: FAIL — `FOSPlatformFloor` not defined

- [ ] **Step 3: Implement**

`Sources/BootstrapKit/FOSPlatformFloor.swift`:
```swift
// FOSPlatformFloor.swift

/// The pinned FOSUtilities release and its platform minimums.
///
/// Under source-inclusion, a generated app's real deployment floor comes
/// from the FOS products it links — not from anything the generated repo
/// declares (spec §9). Generation therefore validates every asked-for
/// target against these values, and `doctor` re-checks them for life.
///
/// UPDATE BOTH when re-pinning FOSUtilities: the version string and the
/// floor table (from FOSUtilities `Package.swift` `platforms:`).
public enum FOSPlatformFloor {
    public static let pinnedFOSVersion = "0.10.0"

    public static let floors: [TargetPlatform: String] = [
        .iOS: "17.0",
        .macOS: "14.0",
        .macCatalyst: "17.0",
        .tvOS: "17.0",
        .watchOS: "10.0",
        .visionOS: "1.0"
    ]

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
        for i in 0..<max(l.count, r.count) {
            let a = i < l.count ? l[i] : 0
            let b = i < r.count ? r[i] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
```

Wire into `BootstrapConfig.validate()` — add as the last line:
```swift
        try FOSPlatformFloor.validate(platforms: platforms)
```

- [ ] **Step 4: Run all tests**

Run: `swift test`
Expected: PASS (config tests still green — their platform values are at/above floor)

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: FOS platform floor validation (rules-table entry #1)"
```

---

### Task 4: TemplateRenderer — strict token substitution

**Files:**
- Create: `Sources/BootstrapKit/TemplateRenderer.swift`
- Test: `Tests/BootstrapKitTests/TemplateRendererTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import BootstrapKit
import Foundation
import Testing

@Suite struct TemplateRendererTests {
    let tokens = ["PROJECT_NAME": "PalettePress", "FOS_VERSION": "0.10.0"]

    @Test func substitutesTokensInContent() throws {
        let out = try TemplateRenderer.render(
            content: "let name = \"{{PROJECT_NAME}}\" // needs {{FOS_VERSION}}",
            tokens: tokens
        )
        #expect(out == "let name = \"PalettePress\" // needs 0.10.0")
    }

    @Test func unrenderedTokenIsFatal() {
        #expect(throws: TemplateError.unrenderedToken(token: "{{TEAM_ID}}", context: "id: {{TEAM_ID}}")) {
            _ = try TemplateRenderer.render(content: "id: {{TEAM_ID}}", tokens: tokens)
        }
    }

    @Test func rendersPathsAndStripsTmplSuffix() throws {
        let path = try TemplateRenderer.render(
            relativePath: "Sources/{{PROJECT_NAME}}ViewModels/Package.swift.tmpl",
            tokens: tokens
        )
        #expect(path == "Sources/PalettePressViewModels/Package.swift")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter TemplateRendererTests`
Expected: FAIL — `TemplateRenderer` not defined

- [ ] **Step 3: Implement**

`Sources/BootstrapKit/TemplateRenderer.swift`:
```swift
// TemplateRenderer.swift
import Foundation

public enum TemplateError: Error, Equatable {
    case unrenderedToken(token: String, context: String)
}

/// Strict `{{TOKEN}}` substitution. No logic, no loops, no filters —
/// derivation happens in typed Swift (TokenSet, Task 5), never in
/// templates. Any token left unrendered is a fatal error: the tool
/// must never emit a file containing `{{`.
public enum TemplateRenderer {
    public static func render(content: String, tokens: [String: String]) throws -> String {
        var out = content
        for (key, value) in tokens {
            out = out.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        if let range = out.range(of: #"\{\{[A-Z0-9_]+\}\}"#, options: .regularExpression) {
            let token = String(out[range])
            let lineRange = out.lineRange(for: range)
            let context = out[lineRange].trimmingCharacters(in: .whitespacesAndNewlines)
            throw TemplateError.unrenderedToken(token: token, context: context)
        }
        return out
    }

    public static func render(relativePath: String, tokens: [String: String]) throws -> String {
        var path = try render(content: relativePath, tokens: tokens)
        if path.hasSuffix(".tmpl") {
            path = String(path.dropLast(".tmpl".count))
        }
        return path
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter TemplateRendererTests`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: strict template renderer — unrendered tokens are fatal"
```

---

### Task 5: TokenSet — derived values, never asked (spec §6.2)

**Files:**
- Create: `Sources/BootstrapKit/TokenSet.swift`
- Test: `Tests/BootstrapKitTests/TokenSetTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import BootstrapKit
import Testing

@Suite struct TokenSetTests {
    @Test func derivesSharedLibraryTokens() throws {
        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .sharedLibrary,
            platforms: [.macOS: "14.0", .iOS: "17.0"]
        )
        let tokens = try TokenSet.derive(from: config)
        #expect(tokens["PROJECT_NAME"] == "PalettePress")
        #expect(tokens["FOS_VERSION"] == FOSPlatformFloor.pinnedFOSVersion)
        // platforms render deterministically (alphabetical by platform name)
        #expect(tokens["PLATFORMS"] == ".iOS(\"17.0\"),\n        .macOS(\"14.0\")")
    }

    @Test func defaultLicenseHeaderIsEmpty() throws {
        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .sharedLibrary,
            platforms: [.macOS: "14.0"]
        )
        let tokens = try TokenSet.derive(from: config)
        #expect(tokens["LICENSE_HEADER"] == "")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter TokenSetTests`
Expected: FAIL — `TokenSet` not defined

- [ ] **Step 3: Implement**

`Sources/BootstrapKit/TokenSet.swift`:
```swift
// TokenSet.swift

/// Derives every template token from the validated config.
/// Derived-not-asked is the leak-proofing rule (spec §6.2): bundle-id
/// suffixes, resource-access forms, and platform lines are computed
/// here in typed Swift so no free-text input can drift.
public enum TokenSet {
    public static func derive(from config: BootstrapConfig) throws -> [String: String] {
        try config.validate()

        return [
            "PROJECT_NAME": config.projectName,
            "FOS_VERSION": FOSPlatformFloor.pinnedFOSVersion,
            "PLATFORMS": platformsLine(config.platforms),
            "LICENSE_HEADER": config.licenseHeader ?? ""
        ]
    }

    /// `.iOS("17.0"),\n        .macOS("14.0")` — string-literal platform
    /// form (valid PackageDescription), deterministic ordering.
    static func platformsLine(_ platforms: [TargetPlatform: String]) -> String {
        platforms
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { ".\($0.key.rawValue)(\"\($0.value)\")" }
            .joined(separator: ",\n        ")
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter TokenSetTests`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: TokenSet — all template values derived from typed config"
```

---

### Task 6: shared-library template files

No test in this task — templates are data; Task 7's emitter tests and
Task 9's integration test exercise them. Every file below goes under
`Sources/BootstrapKit/Templates/`.

**Files (all Create):**
- `Templates/shared/CLAUDE.md.tmpl`
- `Templates/shared/memory/spm-libraries-settled.md`
- `Templates/shared/memory/stale-build-runbook.md`
- `Templates/shared/memory/entitlement-is-a-symptom.md`
- `Templates/shared/memory/macos-build-for-testing-faq.md`
- `Templates/shared/.swiftformat`
- `Templates/shared-library/Package.swift.tmpl`
- `Templates/shared-library/Sources/{{PROJECT_NAME}}ViewModels/{{PROJECT_NAME}}ViewModels.swift.tmpl`
- `Templates/shared-library/Sources/{{PROJECT_NAME}}ViewModels/ViewModels/WelcomeViewModel.swift.tmpl`
- `Templates/shared-library/Sources/{{PROJECT_NAME}}ViewModels/Resources/Localizations/ViewModels/WelcomeViewModel.yml`
- `Templates/shared-library/Tests/{{PROJECT_NAME}}ViewModelsTests/WelcomeViewModelTests.swift.tmpl`
- `Templates/shared-library/.github/workflows/ci.yml`
- `Templates/shared-library/README.md.tmpl`

- [ ] **Step 1: Write the doctrine seeds (`shared/`)**

`CLAUDE.md.tmpl` — the instinct-override catalog (spec §6.7):
```markdown
# CLAUDE.md — {{PROJECT_NAME}}

This project follows the FOS-mvvm way. The rules below are settled
doctrine, mined from real project histories. They are not preferences.

## SOLID is the foundation

A ViewModel is a *projection of* data, never the data. The ViewModels
module imports only FOSFoundation + FOSMVVM — never a domain/wire
module (the Factory adapts). Deviations surface far from their cause;
treat a SOLID violation as a hard stop.

## Your instincts will be wrong — the settled catalog

- **Routes are type-derived.** Middleware is not a path prefix. Never
  munge URLs, never `.grouped("string")` a path onto a ServerRequest.
- **Never hand-roll HTTP gateways or transport parameters.**
  `MVVMEnvironment` / ServerRequests are the only door to the network.
- **Views are generated from ViewModels** (fosmvvm-swiftui-view-generator),
  never transcribed from a mockup.
- **Code is added via the fosmvvm-* generator skills.** Hand-rolling is
  the exception that needs a stated justification.
- **SPM products are consumed through the SPMLibraries umbrella** in
  Xcode-project targets. See `memory/spm-libraries-settled.md` before
  touching linkage — this is settled; arguing it is a long dead-end.

## Memory

Read `memory/*.md` before proposing changes to build wiring, linkage,
entitlements, or test-target configuration.
```

`memory/spm-libraries-settled.md` — the pre-won war (spec §6.7, verbatim
from the design doc's four shapes):
```markdown
# SPMLibraries is settled doctrine — do not re-litigate

**The rule:** every Xcode-project target consumes SPM products through
the single `SPMLibraries` umbrella framework. Never link
FOSFoundation/FOSMVVM (or any SPM product) directly into a second
target or framework.

**Why (correctness, not hygiene):** linking an SPM library statically
into multiple targets compiles a separate copy of its types into each
target. Swift's mangled type name carries the linking context, so the
"same" type has a different runtime identity per target:
`TypeA != TypeA`. `is` / `as?` / `==` / `===` fail across target
boundaries, at runtime, far from the cause. It compiles clean and
breaks in very weird ways. This is a generic Xcode+SPM packaging bug —
nothing to do with FOS — but FOS internals rely on comparing types.

**The four counter-arguments, all already lost:**
1. "The umbrella is dead weight / just DRY / optional." — No: see the
   mechanism above. One umbrella dynamic framework = one canonical copy
   = one shared type identity everywhere.
2. "This second framework needs FOS — I'll link it directly." — No:
   two link sites → two non-identical copies (`SystemVersion` from
   framework A ≠ framework B). Every framework consumes FOS from
   SPMLibraries only.
3. "The boundary broke my iOS build — let's make host code iOS-safe."
   — No: the failure is a correct signal. Extract the platform-bound
   code; never soften the contract module.
4. "Undefined-symbol errors — the umbrella wiring must be wrong." —
   No: that is Xcode incremental-build staleness. See
   `stale-build-runbook.md`.

This is settled. Arguing it = a long dead-end.
```

`memory/stale-build-runbook.md`:
```markdown
# Stale-build runbook (Xcode + SPM incremental builds)

**Symptoms:** hundreds of bogus "Undefined symbol" errors in test
builds; or the running app silently executes old code (a fix that is
compiled in but never invoked).

**Cause:** Xcode's SPM incremental build relinks stale `.o` files.
An Apple bug, not a wiring defect.

**Fix:** Xcode "Clean Build Folder" (or `xcodebuild clean`).
**Never `rm -rf DerivedData`** — it races Xcode's package re-clone and
corrupts `SourcePackages/checkouts`.

**Also check:** the xcodeproj's resolved FOSUtilities pin must stay in
lockstep with `Package.swift` — a drifted pin runs old library code
while you debug "impossible" behavior.
```

`memory/entitlement-is-a-symptom.md`:
```markdown
# disable-library-validation is a symptom, not a setting

You only need `com.apple.security.cs.disable-library-validation` when
the app embeds ad-hoc-signed PackageFrameworks dylibs (wrong project
shape) or signing is off. With the correct shape — source-inclusion of
the contract module + a team-signed SPMLibraries framework + signing
on — the trap never fires and the entitlement is unnecessary.

Before adding it, fix the shape: is a target linking an SPM product it
should consume via SPMLibraries? Is `DEVELOPMENT_TEAM` blank on a new
framework target?
```

`memory/macos-build-for-testing-faq.md`:
```markdown
# xcodebuild build-for-testing fails on macOS — known platform limit

With test targets present, FOS builds as a separate dynamic
`PackageFrameworks/*.framework` and the umbrella no longer carries
those symbols; the link fails at `Ld`. Reproduced identically across
four independent apps — it is a shared Xcode limitation, not a
misconfiguration.

**Fix:** run those test targets on the iOS Simulator (pre-boot it:
`xcrun simctl boot <udid>`), not macOS. The app itself builds fine.
```

`shared/.swiftformat`:
```
--swiftversion 6.0
--indent 4
```

- [ ] **Step 2: Write the shared-library shape templates**

`shared-library/Package.swift.tmpl`:
```swift
// swift-tools-version: 6.0
{{LICENSE_HEADER}}
import PackageDescription

let package = Package(
    name: "{{PROJECT_NAME}}",
    platforms: [
        {{PLATFORMS}}
    ],
    products: [
        .library(
            name: "{{PROJECT_NAME}}ViewModels",
            targets: ["{{PROJECT_NAME}}ViewModels"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/foscomputerservices/FOSUtilities.git", from: "{{FOS_VERSION}}")
    ],
    targets: [
        .target(
            name: "{{PROJECT_NAME}}ViewModels",
            dependencies: [
                .product(name: "FOSFoundation", package: "FOSUtilities"),
                .product(name: "FOSMVVM", package: "FOSUtilities")
            ],
            resources: [
                .copy("Resources/Localizations")
            ]
        ),
        .testTarget(
            name: "{{PROJECT_NAME}}ViewModelsTests",
            dependencies: [
                "{{PROJECT_NAME}}ViewModels",
                .product(name: "FOSTesting", package: "FOSUtilities")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
```

`shared-library/Sources/{{PROJECT_NAME}}ViewModels/{{PROJECT_NAME}}ViewModels.swift.tmpl`
(the ResourceAccess pattern — `Bundle.module` because localization is
package-hosted; spec §6.4):
```swift
// {{PROJECT_NAME}}ViewModels.swift
{{LICENSE_HEADER}}
import Foundation

/// Access to {{PROJECT_NAME}}ViewModels' package-hosted resources.
///
/// A downstream app passes this library's localization bundle to its
/// `MVVMEnvironment` so client-hosted ViewModels resolve their
/// localized strings on-device:
///
/// ```swift
/// MVVMEnvironment(
///     appBundle: Bundle.main,
///     resourceBundles: [{{PROJECT_NAME}}ResourceAccess.localizationBundle],
///     deploymentURLs: [...]
/// )
/// ```
public enum {{PROJECT_NAME}}ResourceAccess {
    public static var localizationBundle: Bundle { Bundle.module }
}
```

`shared-library/Sources/{{PROJECT_NAME}}ViewModels/ViewModels/WelcomeViewModel.swift.tmpl`
(walking-skeleton ViewModel — canonical declaration shape, verbatim
from the FOSShowcase witness pattern):
```swift
// WelcomeViewModel.swift
{{LICENSE_HEADER}}
import FOSFoundation
import FOSMVVM
import Foundation

@ViewModel
public struct WelcomeViewModel {
    @LocalizedString public var welcomeTitle
    @LocalizedString public var welcomeMessage

    public var vmId = ViewModelId()

    public init() {}
}

public extension WelcomeViewModel {
    static func stub() -> Self {
        .init()
    }
}
```

`shared-library/Sources/{{PROJECT_NAME}}ViewModels/Resources/Localizations/ViewModels/WelcomeViewModel.yml`
(locale-keyed format, verified against
`FOSUtilities/Tests/FOSMVVMTests/TestYAML/TestViewModel.yml`):
```yaml
en:
  WelcomeViewModel:
    welcomeTitle: "Welcome"
    welcomeMessage: "Your FOSMVVM shared library is alive."
es:
  WelcomeViewModel:
    welcomeTitle: "Bienvenido"
    welcomeMessage: "Tu biblioteca compartida FOSMVVM está viva."
```

`shared-library/Tests/{{PROJECT_NAME}}ViewModelsTests/WelcomeViewModelTests.swift.tmpl`
(codable + translations round-trips per spec's shared-library finish
line; `LocalizableTestCase` conformance per
`FOSTesting/LocalizableTestCase.swift:30-38`; `.serialized` because
localization suites share the store):
```swift
// WelcomeViewModelTests.swift
{{LICENSE_HEADER}}
import FOSFoundation
import FOSMVVM
import FOSTesting
import Foundation
import Testing
@testable import {{PROJECT_NAME}}ViewModels

@Suite("WelcomeViewModel", .serialized)
struct WelcomeViewModelTests: LocalizableTestCase {
    let locStore: LocalizationStore
    var locales: Set<Locale> { [Self.en, Self.es] }

    @Test func codableRoundTrip() throws {
        try expectCodable(WelcomeViewModel.self)
    }

    @Test func translations() throws {
        try expectTranslations(WelcomeViewModel.self)
    }

    init() throws {
        self.locStore = try Self.loadLocalizationStore(
            bundle: {{PROJECT_NAME}}ResourceAccess.localizationBundle,
            resourceDirectoryName: "Localizations"
        )
    }
}
```

`shared-library/.github/workflows/ci.yml`:
```yaml
name: CI
on:
  push: { branches: [main] }
  pull_request:
jobs:
  test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Test
        run: swift test
```

`shared-library/README.md.tmpl`:
```markdown
# {{PROJECT_NAME}}

A FOSMVVM shared ViewModels library, scaffolded by fosmvvm-bootstrap.

- `{{PROJECT_NAME}}ViewModels` — the ViewModel product; localization is
  package-hosted (`{{PROJECT_NAME}}ResourceAccess.localizationBundle`).
- Consuming apps pass that bundle in `MVVMEnvironment.resourceBundles`.
- Add ViewModels with the `fosmvvm-viewmodel-generator` skill; read
  `CLAUDE.md` and `memory/` first.
```

- [ ] **Step 3: Build (resources must copy cleanly)**

Run: `swift build`
Expected: succeeds; no "invalid resource" warnings for Templates.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: shared doctrine seeds + shared-library shape templates"
```

---

### Task 7: Emitter — compose shared + shape into an output directory

**Files:**
- Create: `Sources/BootstrapKit/Emitter.swift`
- Test: `Tests/BootstrapKitTests/EmitterTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import BootstrapKit
import Foundation
import Testing

@Suite struct EmitterTests {
    func makeConfig() -> BootstrapConfig {
        BootstrapConfig(
            projectName: "PalettePress",
            shape: .sharedLibrary,
            platforms: [.macOS: "14.0", .iOS: "17.0"]
        )
    }

    @Test func emitsSharedLibraryFileSet() throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("emit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }

        let emitted = try Emitter.emit(config: makeConfig(), into: out)

        let expected = [
            "Package.swift",
            "CLAUDE.md",
            "README.md",
            ".swiftformat",
            "memory/spm-libraries-settled.md",
            "memory/stale-build-runbook.md",
            "memory/entitlement-is-a-symptom.md",
            "memory/macos-build-for-testing-faq.md",
            ".github/workflows/ci.yml",
            "Sources/PalettePressViewModels/PalettePressViewModels.swift",
            "Sources/PalettePressViewModels/ViewModels/WelcomeViewModel.swift",
            "Sources/PalettePressViewModels/Resources/Localizations/ViewModels/WelcomeViewModel.yml",
            "Tests/PalettePressViewModelsTests/WelcomeViewModelTests.swift"
        ]
        for path in expected {
            #expect(emitted.contains(path), "missing \(path)")
            #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent(path).path))
        }
    }

    @Test func emittedFilesContainNoTokens() throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("emit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }

        let emitted = try Emitter.emit(config: makeConfig(), into: out)
        for path in emitted {
            let content = try String(contentsOf: out.appendingPathComponent(path), encoding: .utf8)
            #expect(!content.contains("{{"), "unrendered token in \(path)")
        }
    }

    @Test func refusesNonEmptyOutputDirectory() throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("emit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: out.appendingPathComponent("existing.txt").path,
            contents: Data("x".utf8)
        )
        defer { try? FileManager.default.removeItem(at: out) }

        #expect(throws: EmitterError.outputDirectoryNotEmpty(out.path)) {
            _ = try Emitter.emit(config: makeConfig(), into: out)
        }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter EmitterTests`
Expected: FAIL — `Emitter` not defined

- [ ] **Step 3: Implement**

`Sources/BootstrapKit/Emitter.swift`:
```swift
// Emitter.swift
import Foundation

public enum EmitterError: Error, Equatable {
    case outputDirectoryNotEmpty(String)
    case templatesNotFound(String)
}

/// Renders `Templates/shared` + `Templates/<shape>` into the output
/// directory. Never overwrites: an existing non-empty output directory
/// is a fatal error — bootstrap is greenfield-only by design.
public enum Emitter {
    /// Returns the emitted relative paths (sorted, for stable assertions).
    @discardableResult
    public static func emit(config: BootstrapConfig, into outputDir: URL) throws -> [String] {
        let tokens = try TokenSet.derive(from: config)

        let fm = FileManager.default
        if fm.fileExists(atPath: outputDir.path),
           let existing = try? fm.contentsOfDirectory(atPath: outputDir.path),
           !existing.isEmpty {
            throw EmitterError.outputDirectoryNotEmpty(outputDir.path)
        }
        try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)

        guard let templatesRoot = Bundle.module.url(forResource: "Templates", withExtension: nil) else {
            throw EmitterError.templatesNotFound("Templates not in Bundle.module")
        }

        var emitted: [String] = []
        let shapeDirName: String = {
            switch config.shape {
            case .localOnly: "local-only"
            case .clientServer: "client-server"
            case .hybrid: "hybrid"
            case .sharedLibrary: "shared-library"
            }
        }()
        for sourceDir in ["shared", shapeDirName] {
            let root = templatesRoot.appendingPathComponent(sourceDir)
            emitted += try emitTree(from: root, into: outputDir, tokens: tokens)
        }
        return emitted.sorted()
    }

    private static func emitTree(from root: URL, into outputDir: URL, tokens: [String: String]) throws -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [] // include hidden files (.github, .swiftformat)
        ) else {
            throw EmitterError.templatesNotFound(root.path)
        }

        var emitted: [String] = []
        for case let fileURL as URL in enumerator {
            guard try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let relative = String(fileURL.path.dropFirst(root.path.count + 1))
            if relative.hasSuffix(".gitkeep") { continue }

            let renderedRelative = try TemplateRenderer.render(relativePath: relative, tokens: tokens)
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let renderedContent = try TemplateRenderer.render(content: content, tokens: tokens)

            let destination = outputDir.appendingPathComponent(renderedRelative)
            try fm.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try renderedContent.write(to: destination, atomically: true, encoding: .utf8)
            emitted.append(renderedRelative)
        }
        return emitted
    }
}
```

Move `CLAUDE.md.tmpl`, `README.md.tmpl` placement note: `CLAUDE.md.tmpl`
and `.swiftformat` live under `Templates/shared/`; `README.md.tmpl` and
`ci.yml` under `Templates/shared-library/` (Task 6 list is
authoritative).

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter EmitterTests`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: Emitter — shared + shape composition, greenfield-only, token-clean"
```

---

### Task 8: Verifier — never hand over a broken skeleton

**Files:**
- Create: `Sources/BootstrapKit/Verifier.swift`
- Test: `Tests/BootstrapKitTests/VerifierTests.swift`

- [ ] **Step 1: Write the failing tests**

Fast tests use a tiny throwaway package, not a full FOS-depending
project (that's Task 9's integration test).

```swift
import BootstrapKit
import Foundation
import Testing

@Suite struct VerifierTests {
    /// Writes a minimal valid SPM package to a temp dir.
    func writeTinyPackage(brokenSource: Bool) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("verify-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("Sources/Tiny"),
            withIntermediateDirectories: true
        )
        try """
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(name: "Tiny", targets: [.target(name: "Tiny")])
        """.write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try (brokenSource ? "let x: Int = \"nope\"" : "let x = 1")
            .write(to: dir.appendingPathComponent("Sources/Tiny/Tiny.swift"), atomically: true, encoding: .utf8)
        return dir
    }

    @Test func passesOnBuildableProject() throws {
        let dir = try writeTinyPackage(brokenSource: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Verifier.verify(projectDir: dir, steps: [.swiftBuild])
    }

    @Test func failsWithCapturedOutputOnBrokenProject() throws {
        let dir = try writeTinyPackage(brokenSource: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            try Verifier.verify(projectDir: dir, steps: [.swiftBuild])
            Issue.record("expected verification failure")
        } catch let error as VerifierError {
            guard case let .stepFailed(step, output) = error else {
                Issue.record("wrong error: \(error)"); return
            }
            #expect(step == .swiftBuild)
            #expect(output.contains("error:"))
        }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter VerifierTests`
Expected: FAIL — `Verifier` not defined

- [ ] **Step 3: Implement**

`Sources/BootstrapKit/Verifier.swift`:
```swift
// Verifier.swift
import Foundation

public enum VerifyStep: String, Sendable, CaseIterable {
    case swiftBuild
    case swiftTest

    var command: [String] {
        switch self {
        case .swiftBuild: ["swift", "build"]
        case .swiftTest: ["swift", "test"]
        }
    }
}

public enum VerifierError: Error {
    case stepFailed(step: VerifyStep, output: String)
}

/// Runs the shape's verification steps inside the generated project.
/// A failure is fatal and carries the tool output — the scaffolder
/// never hands over a broken skeleton (spec §6.3 phase 4).
public enum Verifier {
    /// Steps for a shape. shared-library: build + test is the entire
    /// finish line (spec §2). App-bearing shapes extend this in Plans 2–4.
    public static func steps(for shape: ProjectShape) -> [VerifyStep] {
        switch shape {
        case .sharedLibrary: [.swiftBuild, .swiftTest]
        case .localOnly, .clientServer, .hybrid: [.swiftBuild, .swiftTest] // extended in Plans 2–4
        }
    }

    public static func verify(projectDir: URL, steps: [VerifyStep]) throws {
        for step in steps {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = step.command
            process.currentDirectoryURL = projectDir
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            process.waitUntilExit()
            let output = String(
                data: pipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            guard process.terminationStatus == 0 else {
                throw VerifierError.stepFailed(step: step, output: output)
            }
        }
    }
}
```

Note: reading the pipe *after* `waitUntilExit()` can deadlock on very
large outputs (pipe buffer fills). If the integration test (Task 9)
hangs, switch to draining `fileHandleForReading` on a background thread
before waiting. Do not pre-emptively complicate; the tiny-package tests
will not hit it.

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter VerifierTests`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: Verifier — build/test the generated project, fail loudly"
```

---

### Task 9: CLI `new` subcommand + end-to-end integration test

**Files:**
- Create: `Sources/BootstrapCLI/NewCommand.swift`
- Modify: `Sources/BootstrapCLI/Main.swift`
- Test: `Tests/BootstrapKitTests/IntegrationTests.swift`

- [ ] **Step 1: Write the integration test (slow; tagged)**

```swift
import BootstrapKit
import Foundation
import Testing

extension Tag {
    @Tag static var integration: Tag
}

@Suite(.tags(.integration)) struct IntegrationTests {
    /// Full walking-skeleton proof for the shared-library shape:
    /// emit → swift build → swift test inside the generated project,
    /// exercising the real FOSUtilities dependency, the YAML
    /// localization round-trip, and the codable round-trip.
    @Test(.timeLimit(.minutes(10)))
    func sharedLibraryWalkingSkeletonIsGreen() throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("skeleton-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }

        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .sharedLibrary,
            platforms: [.macOS: "14.0", .iOS: "17.0"]
        )
        try Emitter.emit(config: config, into: out)
        try Verifier.verify(projectDir: out, steps: Verifier.steps(for: .sharedLibrary))
    }
}
```

- [ ] **Step 2: Run it — expect real signal**

Run: `swift test --filter IntegrationTests`
Expected: PASS in a few minutes (first run resolves + builds
FOSUtilities inside the generated project). Any failure here is a
template defect — fix the template, not the test. Likely first-run
issues: YAML directory name mismatch (`Localizations` vs `Resources`),
missing `import` in a template, macro platform constraints.

- [ ] **Step 3: Implement the CLI**

`Sources/BootstrapCLI/NewCommand.swift`:
```swift
// NewCommand.swift
import ArgumentParser
import BootstrapKit
import Foundation

struct New: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Scaffold a new FOSMVVM project from a config file."
    )

    @Option(name: .shortAndLong, help: "Path to a BootstrapConfig JSON file.")
    var config: String

    @Option(name: .shortAndLong, help: "Output directory for the new project (must be empty or absent).")
    var output: String

    @Flag(help: "Skip the build/test verification phase (CI of this repo only — never for real use).")
    var skipVerify = false

    func run() throws {
        let configURL = URL(fileURLWithPath: config)
        let outputURL = URL(fileURLWithPath: output)

        let bootstrapConfig = try JSONDecoder().decode(
            BootstrapConfig.self,
            from: Data(contentsOf: configURL)
        )

        print("Scaffolding \(bootstrapConfig.projectName) (\(bootstrapConfig.shape.rawValue)) …")
        let emitted = try Emitter.emit(config: bootstrapConfig, into: outputURL)
        print("Emitted \(emitted.count) files.")

        if !skipVerify {
            print("Verifying (swift build / swift test) …")
            try Verifier.verify(
                projectDir: outputURL,
                steps: Verifier.steps(for: bootstrapConfig.shape)
            )
            print("✅ Walking skeleton verified green.")
        }

        print(HandoffChecklist.text(for: bootstrapConfig.shape))
    }
}
```

Add to `Sources/BootstrapKit/HandoffChecklist.swift` (new file, part of
this task — shared-library needs only next-steps guidance; xcodeproj
steps arrive in Plans 2–4):
```swift
// HandoffChecklist.swift

/// Human finishing steps the tooling structurally cannot do (spec §6.6).
public enum HandoffChecklist {
    public static func text(for shape: ProjectShape) -> String {
        switch shape {
        case .sharedLibrary:
            """

            Next steps:
            1. git init && git add -A && git commit  (the tool does not create the repo)
            2. Read CLAUDE.md and memory/ — settled doctrine ships with the project.
            3. Add ViewModels via the fosmvvm-viewmodel-generator skill.
            """
        case .localOnly, .clientServer, .hybrid:
            "(finishing checklist for this shape arrives in a later plan)"
        }
    }
}
```

Update `Main.swift` to register the subcommand:
```swift
// Main.swift
import ArgumentParser
import BootstrapKit

@main
struct FOSMVVMBootstrap: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fosmvvm-bootstrap",
        abstract: "Scaffold FOSMVVM projects the FOS-mvvm way.",
        version: BootstrapKit.version,
        subcommands: [New.self]
    )
}
```

- [ ] **Step 4: Smoke the CLI by hand**

```bash
cat > /tmp/pp-config.json <<'EOF'
{ "projectName": "PalettePress", "shape": "sharedLibrary",
  "platforms": { "macOS": "14.0", "iOS": "17.0" } }
EOF
swift run fosmvvm-bootstrap new --config /tmp/pp-config.json \
    --output /tmp/PalettePress
```
Expected: emits, verifies green, prints the handoff text.
Clean up: `rm -rf /tmp/PalettePress /tmp/pp-config.json`

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: all PASS (integration test included; use
`swift test --skip IntegrationTests` for the fast loop afterward —
SwiftPM's CLI has no tag filtering, only `--filter` / `--skip` name
regexes; the `.tags(.integration)` declaration stays for Xcode use)

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: new subcommand + end-to-end shared-library walking-skeleton proof"
```

---

### Task 10: This repo's own CI + README

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `README.md`

- [ ] **Step 1: CI for fosmvvm-bootstrap itself**

`.github/workflows/ci.yml`:
```yaml
name: CI
on:
  push: { branches: [main] }
  pull_request:
jobs:
  test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Fast tests
        run: swift test --skip IntegrationTests
      - name: Walking-skeleton integration
        run: swift test --filter IntegrationTests
```

(Release-tag CI that scaffolds all four shapes and publishes
`fosmvvm-example-{type}` repos is Plan 5 — do not build it here.)

- [ ] **Step 2: README**

```markdown
# fosmvvm-bootstrap

Deterministic scaffolder for FOSMVVM projects. Driven by the
`fosmvvm-project-bootstrap` skill in the fosmvvm-generators plugin;
not intended for direct interactive use.

Design: FOSUtilities
`docs/superpowers/specs/2026-07-24-fosmvvm-project-bootstrap-design.md`.

Status: Plan 1 — CLI core + shared-library shape. Remaining shapes,
`doctor`, and release CI land in subsequent plans.
```

- [ ] **Step 3: Final full-suite run**

Run: `swift test`
Expected: all PASS

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "chore: repo CI (fast + integration legs) and README"
```

GitHub repo creation (`gh repo create foscomputerservices/fosmvvm-bootstrap`)
and any push are **gated on David** — stop and ask before publishing.

---

## Out of scope for Plan 1 (later plans)

- client-server / local-only / hybrid templates, XcodeGen, `project.yml`,
  xcodeproj verification legs (Plans 2–4)
- `doctor` (Plan 5; `FOSPlatformFloor` is already rules-table-shaped)
- the `fosmvvm-project-bootstrap` plugin skill (Plan 5)
- release-tag CI publishing `fosmvvm-example-{type}` repos (Plan 5)
- the FOSUtilities `FOSMVVMArchitecture.md` SPMLibraries section (Plan 5)
- interactive interview in the CLI — the skill authors the config JSON;
  `--config` is the only input path in v1
