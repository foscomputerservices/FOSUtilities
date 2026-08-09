# fosmvvm-bootstrap Plan 2 — local-only Template

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The `fosmvvm-bootstrap` CLI generates a **local-only** FOSMVVM app (witness-shaped: xcodeproj via XcodeGen, SPMLibraries umbrella, ViewModels *framework* target with client-hosted localization) whose walking skeleton verifies headlessly.

**Architecture:** Extends Plan 1's machine — config gains app-shape fields (bundle-id root, team ID); TokenSet derives the app tokens; a `local-only` template tree lands (project.yml + Sources + Tests); Verifier gains `xcodegenGenerate` and `xcodebuildBuild` steps. Layout ruling (David, 2026-07-25): **ViewModels framework** (the local-only witness), NOT the client-server witness's source-inclusion — the client-server witness is the hybrid witness.

**Tech Stack:** Swift 6 / Swift Testing; XcodeGen (headless via `xcodegen generate --spec`); `xcodebuild build … CODE_SIGNING_ALLOWED=NO`.

**Spec:** FOSUtilities `docs/superpowers/specs/2026-07-24-fosmvvm-project-bootstrap-design.md`.
**Fact sheet decisions** (from the 2026-07-25 witness survey; D1 ruled by David):

- **D1 layout:** ViewModels framework target (the local-only witness shape).
- **D2 ResourceAccess:** `Bundle(for:)` (the skill's framework form). The local-only witness's own
  `Bundle.main` contradicts its framework layout — do not copy it. No
  `resourceDirectoryName` in `MVVMEnvironment`; explicit `""` in tests.
- **D3:** `SWIFT_VERSION 6.0` + `SWIFT_STRICT_CONCURRENCY complete`, and no
  `SWIFT_APPROACHABLE_CONCURRENCY`/`SWIFT_DEFAULT_ACTOR_ISOLATION` keys.
- **D4 verify:** `xcodegen generate` + `xcodebuild build` (app scheme, macOS,
  `CODE_SIGNING_ALLOWED=NO`). `build-for-testing` on macOS FAILS at `Ld` for this
  layout (known PackageFrameworks limitation) — test *execution* is proven on the
  iOS Simulator leg (Task 7) and by the human in Xcode.
- **D5:** no committed `.xctestplan`; the scheme lists `test.targets` (XcodeGen
  re-mints UUIDs, a committed plan would dangle).
- **D6 embedding:** the app embeds `SPMLibraries.framework` + `ViewModels.framework`
  (CodeSignOnCopy); the ViewModels framework and both test targets **link only,
  embed: false** (Template 7 single-embed rule — not the local-only witness's double-embed).
- **D7:** test-mode detection reads `ProcessInfo.processInfo.environment["__FOS_ViewModel"]`
  (never `arguments.count` — the local-only witness's older form is a known divergence).
- **TEST_HOST:** generator keeps app target name == PRODUCT_NAME (both
  `{{PROJECT_NAME}}`), and emits the explicit `TEST_HOST`/`BUNDLE_LOADER` pin anyway
  (harmless when equal, saves the trap if a user renames later).

**Working directory:** `/Users/david/Repository/FOS/fosmvvm-bootstrap`.

**Finish line for this plan (scoreboard units):** `fosmvvm-bootstrap new` with a
`localOnly` config produces a project where `xcodegen generate` +
`xcodebuild build` succeed headlessly, and the bootstrap repo's integration test
proves it; unit-test execution is additionally proven on an iOS Simulator when one
is available. **After this plan: 1 of 3 project types generatable.**

---

### Task 1: Shape guard — typed error for unimplemented shapes

The Plan-1 final review found: a `clientServer`/`hybrid` config today part-emits
(shared/ only) then fails opaquely in `swift build`. Guard before Task 3 makes
`local-only` real.

**Files:**
- Modify: `Sources/BootstrapKit/Emitter.swift`
- Test: `Tests/BootstrapKitTests/EmitterTests.swift`

- [ ] **Step 1: failing test** — add to `EmitterTests`:

```swift
    @Test func refusesShapeWithoutTemplates() throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("emit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }

        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .hybrid,
            platforms: [.macOS: "14.0"]
        )
        #expect(throws: EmitterError.shapeNotImplemented("hybrid")) {
            _ = try Emitter.emit(config: config, into: out)
        }
        // Nothing may be written before the guard fires.
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }
```

- [ ] **Step 2: run** — `swift test --filter EmitterTests` → fails (`shapeNotImplemented` undefined).

- [ ] **Step 3: implement** — in `Emitter.swift`:
  - Add `case shapeNotImplemented(String)` to `EmitterError` (+ a
    `CustomStringConvertible` line: `"project shape not implemented by this version: <shape>"`).
  - **The guard must be the VERY FIRST statement of `emit()` — before
    `TokenSet.derive` (which validates the config).** Rationale: Task 2
    makes `validate()` reject app shapes lacking `bundleIdRoot`; if the
    guard ran after derivation, this task's `.hybrid` test fixture would
    start throwing `missingBundleIdRoot` instead of
    `shapeNotImplemented` and the suite would go red at Task 2. Don't
    validate a config for a shape you can't emit. Concretely: compute
    `shapeDirName` from `config.shape`, locate `templatesRoot`, check
    `Templates/<shapeDirName>` exists as a directory
    (`fm.fileExists(atPath:isDirectory:)`), throw
    `shapeNotImplemented(shapeDirName)` if absent — all before
    `TokenSet.derive` and before any `createDirectory`.

- [ ] **Step 4: run** — EmitterTests all green (4 tests), full fast suite green.

- [ ] **Step 5: commit** — `feat: typed guard for shapes without templates`

---

### Task 2: Config + TokenSet extensions for app shapes

**Files:**
- Modify: `Sources/BootstrapKit/BootstrapConfig.swift`
- Modify: `Sources/BootstrapKit/TokenSet.swift`
- Test: `Tests/BootstrapKitTests/BootstrapConfigTests.swift`, `Tests/BootstrapKitTests/TokenSetTests.swift`

**New config fields** (all optional at the type level; required-by-shape in `validate()`):

```swift
    /// Reverse-DNS root for the app and derived per-module bundle ids
    /// (e.g. "com.example.palettepress"). Required for app shapes.
    public let bundleIdRoot: String?
    /// Apple Development Team ID (10 chars). Required for app shapes.
    public let teamId: String?
```

(Extend the memberwise `init` with `bundleIdRoot: String? = nil, teamId: String? = nil`.)

**New error cases** (`BootstrapConfigError`): `missingBundleIdRoot`,
`invalidBundleIdRoot(String)`, `missingTeamId`, `invalidTeamId(String)`,
`missingPlatform(TargetPlatform)`.

**Validation additions** in `validate()` — app shapes only
(`shape != .sharedLibrary`):
- `bundleIdRoot` present and matches `^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$`
  (lowercase reverse-DNS; segments may contain hyphens)
- `teamId` present and matches `^[A-Z0-9]{10}$`
- `.localOnly` requires `platforms[.macOS]` (the generated project.yml is
  macOS-platform in this plan; iOS destination is a finishing-checklist step)
  → else `missingPlatform(.macOS)`

**New derived tokens** in `TokenSet.derive` (app shapes only — for
`sharedLibrary`, derive exactly the Plan-1 four so existing tests stay green):
- `BUNDLE_ID_ROOT` = config.bundleIdRoot
- `TEAM_ID` = config.teamId
- `MACOS_DEPLOYMENT` = platforms[.macOS]

Bundle-id suffixes (`{{BUNDLE_ID_ROOT}}.SPMLibraries` etc.) stay **in the
template text**, composed from the one root token — that is the derivation;
no separate suffix tokens.

- [ ] **Step 1: failing tests** — add:

```swift
    // BootstrapConfigTests
    @Test func localOnlyRequiresBundleIdRootAndTeam() throws {
        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .localOnly,
            platforms: [.macOS: "14.0"]
        )
        #expect(throws: BootstrapConfigError.missingBundleIdRoot) {
            try config.validate()
        }
    }

    @Test func validLocalOnlyConfigPasses() throws {
        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .localOnly,
            platforms: [.macOS: "14.0"],
            bundleIdRoot: "com.example.palettepress",
            teamId: "ABCDE12345"
        )
        try config.validate()
    }

    @Test func rejectsMalformedTeamId() throws {
        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .localOnly,
            platforms: [.macOS: "14.0"],
            bundleIdRoot: "com.example.palettepress",
            teamId: "abc"
        )
        #expect(throws: BootstrapConfigError.invalidTeamId("abc")) {
            try config.validate()
        }
    }

    // TokenSetTests
    @Test func derivesLocalOnlyTokens() throws {
        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .localOnly,
            platforms: [.macOS: "14.0"],
            bundleIdRoot: "com.example.palettepress",
            teamId: "ABCDE12345"
        )
        let tokens = try TokenSet.derive(from: config)
        #expect(tokens["BUNDLE_ID_ROOT"] == "com.example.palettepress")
        #expect(tokens["TEAM_ID"] == "ABCDE12345")
        #expect(tokens["MACOS_DEPLOYMENT"] == "14.0")
    }

    @Test func sharedLibraryTokensUnchanged() throws {
        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .sharedLibrary,
            platforms: [.macOS: "14.0"]
        )
        let tokens = try TokenSet.derive(from: config)
        #expect(tokens["BUNDLE_ID_ROOT"] == nil)
        #expect(tokens.count == 4)
    }
```

- [ ] **Step 2: run RED**, **Step 3: implement**, **Step 4: run GREEN (full fast suite)**.
- [ ] **Step 5: commit** — `feat: app-shape config fields (bundleIdRoot, teamId) + derived tokens`

---

### Task 3: local-only template tree

Data-entry (no unit test; Task 6's emitter assertions + Task 7's integration
exercise it). All under `Sources/BootstrapKit/Templates/local-only/`.
Walking-skeleton domain: `Welcome` (FOSShowcase-flavored, no customer refs).

**Note on doctrine seeds:** `shared/` (CLAUDE.md + 4 memos + .swiftformat) already
composes in from Plan 1 — for THIS shape every memo is live (umbrella, staleness,
entitlements, simulator FAQ all describe this exact layout).

**Files (all Create):**

**3a. `project.yml.tmpl`** — the witness build-verified template adapted to the
framework layout (D1/D3/D5/D6, TEST_HOST pin kept):

```yaml
name: {{PROJECT_NAME}}

options:
  deploymentTarget:
    macOS: "{{MACOS_DEPLOYMENT}}"
  createIntermediateGroups: true
  groupSortPosition: top

settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    BUILD_LIBRARY_FOR_DISTRIBUTION: NO
    DEVELOPMENT_TEAM: {{TEAM_ID}}

packages:
  FOSUtilities:
    url: https://github.com/foscomputerservices/FOSUtilities.git
    from: "{{FOS_VERSION}}"

targets:
  # The ONE doorway for external SPM products (type identity — see
  # memory/spm-libraries-settled.md).
  SPMLibraries:
    type: framework
    platform: macOS
    sources:
      - path: Sources/SPMLibraries
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: {{BUNDLE_ID_ROOT}}.SPMLibraries
        GENERATE_INFOPLIST_FILE: YES
    dependencies:
      - package: FOSUtilities
        product: FOSFoundation
      - package: FOSUtilities
        product: FOSMVVM

  # Shared contract module — client-hosted ViewModels + their YAML.
  ViewModels:
    type: framework
    platform: macOS
    sources:
      - path: Sources/ViewModels
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: {{BUNDLE_ID_ROOT}}.ViewModels
        GENERATE_INFOPLIST_FILE: YES
    dependencies:
      - target: SPMLibraries
        embed: false          # link only — the app embeds (single-embed rule)

  {{PROJECT_NAME}}:
    type: application
    platform: macOS
    sources:
      - path: Sources/{{PROJECT_NAME}}
        excludes:
          - "Info.plist"
          - "{{PROJECT_NAME}}.entitlements"
      - path: Sources/{{PROJECT_NAME}}/Info.plist
        buildPhase: none
      - path: Sources/{{PROJECT_NAME}}/{{PROJECT_NAME}}.entitlements
        buildPhase: none
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: {{BUNDLE_ID_ROOT}}
        PRODUCT_NAME: {{PROJECT_NAME}}
        INFOPLIST_FILE: Sources/{{PROJECT_NAME}}/Info.plist
        CODE_SIGN_ENTITLEMENTS: Sources/{{PROJECT_NAME}}/{{PROJECT_NAME}}.entitlements
        ENABLE_HARDENED_RUNTIME: YES
        MARKETING_VERSION: "0.1"
        CURRENT_PROJECT_VERSION: 1
    dependencies:
      - target: SPMLibraries
        embed: true
        codeSign: true
      - target: ViewModels
        embed: true
        codeSign: true

  {{PROJECT_NAME}}UnitTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: Tests/{{PROJECT_NAME}}UnitTests
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: {{BUNDLE_ID_ROOT}}-unit-tests
        GENERATE_INFOPLIST_FILE: YES
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/{{PROJECT_NAME}}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/{{PROJECT_NAME}}"
        BUNDLE_LOADER: "$(TEST_HOST)"
    dependencies:
      - target: {{PROJECT_NAME}}
      - target: SPMLibraries
        embed: false
      - target: ViewModels
        embed: false
      - package: FOSUtilities
        product: FOSTesting

  {{PROJECT_NAME}}UITests:
    type: bundle.ui-testing
    platform: macOS
    sources:
      - path: Tests/{{PROJECT_NAME}}UITests
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: {{BUNDLE_ID_ROOT}}-ui-tests
        GENERATE_INFOPLIST_FILE: YES
    dependencies:
      - target: {{PROJECT_NAME}}
      - package: FOSUtilities
        product: FOSTestingUI

schemes:
  {{PROJECT_NAME}}:
    build:
      targets:
        {{PROJECT_NAME}}: all
        {{PROJECT_NAME}}UnitTests: [test]
        {{PROJECT_NAME}}UITests: [test]
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - {{PROJECT_NAME}}UnitTests
        - {{PROJECT_NAME}}UITests
    archive:
      config: Release
```

**KNOWN-RISK note for the implementer:** test-target `package:` product deps
(`FOSTesting`/`FOSTestingUI`) alongside the umbrella are the exact surface of the
macOS `build-for-testing` `Ld` limitation — that is WHY verify uses plain `build`
(D4). Do not "fix" a failing build-for-testing by unwinding the umbrella; that is
counter-argument #4 in the doctrine.

**3b. `Sources/SPMLibraries/SPMLibraries.swift`** — verbatim from
`Templates/shared-library`-era doctrine, WITH the full type-identity rationale
comment (the stripped variant is the relapse vector):

```swift
// SPMLibraries.swift
{{LICENSE_HEADER}}
import Foundation

// ### SPMLibraries — SPM Dependencies
//
// It is required that ALL external SPM products are linked into THIS
// framework and NOT directly into any other target of the project.
//
// Linking an SPM library statically into multiple targets compiles a
// separate copy of its types into each target. Swift's mangled type
// name carries the linking context, so the "same" type has a different
// runtime identity per target: TypeA != TypeA. `is` / `as?` / `==` /
// `===` fail across target boundaries, at runtime, far from the cause.
// This is a generic Xcode+SPM packaging bug — nothing to do with FOS —
// but FOS internals rely heavily on comparing types (e.g.
// FOSMVVM.localizingEncoder's `value as? (any ViewModel)`).
//
// One umbrella dynamic framework = one canonical copy = one shared
// type identity everywhere. See memory/spm-libraries-settled.md.
```

**3c. `Sources/ViewModels/ViewModelsResourceAccess.swift.tmpl`** — the skill's
framework form (D2):

```swift
// ViewModelsResourceAccess.swift
{{LICENSE_HEADER}}
import Foundation

/// Access to the ViewModels framework's client-hosted resources.
///
/// The app passes this bundle to `MVVMEnvironment` so client-hosted
/// ViewModels resolve their localized strings on-device:
///
/// ```swift
/// MVVMEnvironment(
///     appBundle: Bundle.main,
///     resourceBundles: [ViewModelsResourceAccess.localizationBundle],
///     deploymentURLs: [Deployment: MVVMEnvironment.URLPackage]()
/// )
/// ```
public enum ViewModelsResourceAccess {
    private final class ResourceAccessClass {}

    public static var localizationBundle: Bundle {
        Bundle(for: ResourceAccessClass.self)
    }
}
```

**3d. `Sources/ViewModels/ViewModels/WelcomeViewModel.swift.tmpl`** — client-hosted
walking-skeleton VM (canonical `.clientHostedFactory` shape; init params become the
synthesized AppState — none here):

```swift
// WelcomeViewModel.swift
{{LICENSE_HEADER}}
import FOSFoundation
import FOSMVVM
import Foundation

@ViewModel(options: [.clientHostedFactory])
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

**3e. `Sources/ViewModels/Resources/ViewModels/WelcomeViewModel.yml`** — same
en/es content as the shared-library shape (locale → TypeName → property).

**3f. `Sources/ViewModels/Versioning/SystemVersion+App.swift.tmpl`:**

```swift
// SystemVersion+App.swift
{{LICENSE_HEADER}}
import FOSFoundation
import Foundation

public extension SystemVersion {
    /// The application's current system version.
    static let currentApplicationVersion: SystemVersion = .init(
        major: 0, minor: 1, patch: 0
    )
}
```

(Verified: `SystemVersion.init(major:minor:patch:)` exists at
FOSFoundation SystemVersion.swift:134 and matches the FOSShowcase witness.
It is consumed by the App template's
`MVVMEnvironment(currentVersion: .currentApplicationVersion, …)` — not dead
scaffolding. IMPLEMENTER: confirm the `currentVersion:` parameter label on
`MVVMEnvironment.init` against FOS 0.10.0 during the integration run; if the
label differs, match the shipped init and report the divergence.)

**3g. `Sources/{{PROJECT_NAME}}/App/{{PROJECT_NAME}}App.swift.tmpl`** — the @main
(Template-6-derived with the stored-env correction: empty deploymentURLs,
`.testHost`, `registerTestingViews`, `__FOS_ViewModel` detection via the
no-arg host):

```swift
// {{PROJECT_NAME}}App.swift
{{LICENSE_HEADER}}
import FOSFoundation
import FOSMVVM
import SwiftUI
import ViewModels

@main
struct {{PROJECT_NAME}}App: App {
    @State private var mvvmEnv = makeMVVMEnvironment()

    var body: some Scene {
        WindowGroup {
            WelcomeView.bind(appState: .init())
                .testHost()
        }
        .environment(mvvmEnv)
    }
}

private extension {{PROJECT_NAME}}App {
    @MainActor static func makeMVVMEnvironment() -> MVVMEnvironment {
        let env = MVVMEnvironment(
            currentVersion: .currentApplicationVersion,
            appBundle: Bundle.main,
            resourceBundles: [
                ViewModelsResourceAccess.localizationBundle
            ],
            // This app talks to no server. An empty dictionary is the
            // correct expression of that — do not invent placeholder URLs.
            deploymentURLs: [Deployment: MVVMEnvironment.URLPackage]()
        )
        #if DEBUG
        env.registerTestingViews()
        #endif
        return env
    }
}

#if DEBUG
private extension MVVMEnvironment {
    @MainActor func registerTestingViews() {
        registerTestView(WelcomeView.self)
    }
}
#endif
```

(IMPLEMENTER: the composition above is verified against FOSUtilities sources —
`ViewModelView.bind(appState:)` (ViewModelView.swift:382) matches exactly what
`.clientHostedFactory` synthesizes, and `.testHost()` no-arg is TestHost.swift:86.
**Keep the stored `@State` env form — do NOT "align" it to skill Template 6.**
Template 6 declares `mvvmEnv` as a *computed* property, which mints a fresh
`MVVMEnvironment` on each access; registering test views on one instance and
passing a different one to `.environment()` is a latent trap Template 6 only
survives because its `registerTestingViews()` is an empty placeholder. Ours
actually registers `WelcomeView`, so the stored instance is required.)

**3h. `Sources/{{PROJECT_NAME}}/Views/WelcomeView.swift.tmpl`:**

```swift
// WelcomeView.swift
{{LICENSE_HEADER}}
import FOSMVVM
import SwiftUI
import ViewModels

struct WelcomeView: ViewModelView {
    let viewModel: WelcomeViewModel

    var body: some View {
        VStack(spacing: 12) {
            Text(viewModel.welcomeTitle)
                .font(.largeTitle)
            Text(viewModel.welcomeMessage)
        }
        .padding()
    }
}

#Preview {
    WelcomeView.previewHost(
        bundle: ViewModelsResourceAccess.localizationBundle
    )
}
```

**3i. `Sources/{{PROJECT_NAME}}/Info.plist`** — minimal macOS app plist
(CFBundleName `$(PRODUCT_NAME)`, CFBundleIdentifier
`$(PRODUCT_BUNDLE_IDENTIFIER)`, CFBundlePackageType APPL,
LSMinimumSystemVersion `$(MACOSX_DEPLOYMENT_TARGET)`, NSPrincipalClass
NSApplication).

**3j. `Sources/{{PROJECT_NAME}}/{{PROJECT_NAME}}.entitlements`** — sandbox on,
NO disable-library-validation (the shape doesn't need it — see
memory/entitlement-is-a-symptom.md):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
</dict>
</plist>
```

**3k. `Tests/{{PROJECT_NAME}}UnitTests/WelcomeViewModelTests.swift.tmpl`** — the
framework-bundle localization round-trip; `resourceDirectoryName: ""` is the
load-bearing detail (flattening gotcha):

```swift
// WelcomeViewModelTests.swift
{{LICENSE_HEADER}}
import FOSFoundation
import FOSMVVM
import FOSTesting
import Foundation
import Testing
import ViewModels

@Suite("WelcomeViewModel", .serialized)
struct WelcomeViewModelTests: LocalizableTestCase {
    let locStore: LocalizationStore
    var locales: Set<Locale> { [Self.en, Self.es] }

    @Test func codableRoundTrip() throws {
        try expectCodable(WelcomeViewModel.self, encoder: encoder(locale: Self.en))
    }

    @Test func translations() throws {
        try expectTranslations(WelcomeViewModel.self)
    }

    init() throws {
        // "" — Xcode flattens a framework's grouped resources to the
        // bundle root; the default "Resources" misses on iOS. Empty
        // string recurses from the root and is correct on BOTH platforms.
        self.locStore = try Self.loadLocalizationStore(
            bundle: ViewModelsResourceAccess.localizationBundle,
            resourceDirectoryName: ""
        )
    }
}
```

**3l. `Tests/{{PROJECT_NAME}}UITests/{{PROJECT_NAME}}UITests.swift.tmpl`** —
minimal harness proof (launch under the test host, first screen renders).
XCTest (UI tests are XCTest-only):

```swift
// {{PROJECT_NAME}}UITests.swift
{{LICENSE_HEADER}}
import XCTest

final class {{PROJECT_NAME}}UITests: XCTestCase {
    @MainActor func testAppLaunchesToWelcome() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }
}
```

(The full FOSTestingUI `ViewModelViewTestCase` per-view harness is generated later
by the `fosmvvm-ui-tests-generator` skill — the app-side wiring (`.testHost()` +
`registerTestingViews`) ships ready for it. State this in the README.)

**3m. `README.md.tmpl`** — shape summary: local-only, client-hosted localization,
umbrella doctrine pointer, the finishing checklist recap, "tests run in Xcode /
iOS Simulator (macOS build-for-testing is a known Xcode limitation — see
memory/macos-build-for-testing-faq.md)".

- [ ] **Step 1: write all files** (exact content above).
- [ ] **Step 2:** `swift build` clean; fast suite green.
- [ ] **Step 3: commit** — `feat: local-only template tree (witness-shaped, framework layout)`

---

### Task 4: Verifier steps — xcodegen + xcodebuild

**Files:**
- Modify: `Sources/BootstrapKit/Verifier.swift`
- Test: `Tests/BootstrapKitTests/VerifierTests.swift`

**New `VerifyStep` cases:**

```swift
    case xcodegenGenerate    // ["xcodegen", "generate", "--spec", "project.yml"]
    case xcodebuildBuild     // ["xcodebuild", "-project", "<Name>.xcodeproj",
                             //  "-scheme", "<Name>", "-destination", "platform=macOS",
                             //  "build", "CODE_SIGNING_ALLOWED=NO"]
```

`xcodebuildBuild` needs the project name — change `command` to
`command(projectName: String?)` internally, and thread the name through
`verify(projectDir:steps:projectName:)` (new parameter, default `nil`; the two
Plan-1 steps ignore it). Keep the public Plan-1 call signature compiling via a
default — existing tests must not change.

**Tool-missing precheck:** before running `xcodegenGenerate`, check
`command -v xcodegen` via `["/bin/sh", "-c", "command -v xcodegen"]` —
**absolute `/bin/sh`** (an `env sh` form would need PATH to find the
shell itself, failing 127 under PATH overlays and even returning a
false toolMissing when PATH has xcodegen but lacks /bin), and
**plain `-c`, NOT `-lc`**: a login shell sources profile scripts
(`path_helper`, brew shellenv) that can restore a real PATH and defeat
the test's `PATH=/nonexistent` override. `command -v` inside the
absolute shell still honors the overlaid PATH — correct in both
directions. On absence throw new
`VerifierError.toolMissing(tool: "xcodegen", installHint: "brew install xcodegen")`
with a matching `CustomStringConvertible` line.

**stepFailed description with the command change:** `command` becoming
`command(projectName: String?)` breaks the existing
`step.command.joined(separator: " ")` in `CustomStringConvertible`.
Render a nil project name as the placeholder `<project>` in the error
description so the description path can never crash.

**`steps(for:)`:** `.localOnly` → `[.xcodegenGenerate, .xcodebuildBuild]`.
(`.sharedLibrary` unchanged; `.clientServer`/`.hybrid` keep the placeholder
`[.swiftBuild, .swiftTest]` until their plans.)

- [ ] **Step 1: failing tests** — add to `VerifierTests`:

```swift
    @Test func localOnlyStepsAreXcodeSteps() {
        #expect(Verifier.steps(for: .localOnly) == [.xcodegenGenerate, .xcodebuildBuild])
    }

    @Test func missingToolThrowsToolMissing() throws {
        // Point PATH at an empty dir so xcodegen can't be found.
        // Implement via an environment override on Verifier.verify
        // (add `environment: [String: String]? = nil` passthrough to Process).
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("verify-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            try Verifier.verify(
                projectDir: dir,
                steps: [.xcodegenGenerate],
                environment: ["PATH": "/nonexistent"]
            )
            Issue.record("expected toolMissing")
        } catch let error as VerifierError {
            guard case let .toolMissing(tool, _) = error else {
                Issue.record("wrong error: \(error)"); return
            }
            #expect(tool == "xcodegen")
        }
    }
```

- [ ] **Step 2: RED**, **Step 3: implement** (env passthrough applies to both the
  precheck and the step Process), **Step 4: full fast suite GREEN**.
- [ ] **Step 5: commit** — `feat: verifier xcodegen/xcodebuild steps + tool-missing precheck`

---

### Task 5: CLI + HandoffChecklist for local-only

**Files:**
- Modify: `Sources/BootstrapCLI/NewCommand.swift` (thread
  `projectName: bootstrapConfig.projectName` into `Verifier.verify`)
- Modify: `Sources/BootstrapKit/HandoffChecklist.swift`

`HandoffChecklist.text(for: .localOnly)`:

```
Next steps (things tooling structurally cannot do):
1. git init && git add -A && git commit
2. Open {Name}.xcodeproj in Xcode:
   a. Convert the enumerated source groups to synchronized folders
      (File Inspector → each top-level group; XcodeGen cannot emit
      PBXFileSystemSynchronizedRootGroup).
   b. Confirm signing: your real DEVELOPMENT_TEAM on every target.
   c. Run the test suite (⌘U). Note: `xcodebuild build-for-testing`
      on macOS fails at Ld for this layout — a known Xcode
      limitation (memory/macos-build-for-testing-faq.md). Tests run
      fine from Xcode and on the iOS Simulator.
   d. Add iOS/iPadOS destinations if wanted.
3. Delete project.yml; commit the .xcodeproj. It is hand-maintained
   from here — do not regenerate.
4. Read CLAUDE.md and memory/ — settled doctrine ships with the project.
5. Add screens via the fosmvvm-viewmodel-generator +
   fosmvvm-swiftui-view-generator skills.
```

(Since HandoffChecklist needs the project name for `{Name}.xcodeproj`, change the
signature to `text(for shape: ProjectShape, projectName: String)` and update the
one call site + shared-library text accordingly.)

- [ ] **Step 1:** implement; **Step 2:** fast suite green (adjust any signature
  fallout); **Step 3: commit** — `feat: local-only handoff checklist + CLI project-name threading`

---

### Task 6: Emitter assertions for the local-only file set

**Files:**
- Test: `Tests/BootstrapKitTests/EmitterTests.swift`

- [ ] **Step 1: failing test** — emit a `localOnly` config (valid, from Task 2's
  fixtures) and assert the full expected relative-path set (analogous to the
  shared-library test): `project.yml`, `Sources/SPMLibraries/SPMLibraries.swift`,
  `Sources/ViewModels/ViewModelsResourceAccess.swift`,
  `Sources/ViewModels/ViewModels/WelcomeViewModel.swift`,
  `Sources/ViewModels/Resources/ViewModels/WelcomeViewModel.yml`,
  `Sources/ViewModels/Versioning/SystemVersion+App.swift`,
  `Sources/PalettePress/App/PalettePressApp.swift`,
  `Sources/PalettePress/Views/WelcomeView.swift`,
  `Sources/PalettePress/Info.plist`,
  `Sources/PalettePress/PalettePress.entitlements`,
  `Tests/PalettePressUnitTests/WelcomeViewModelTests.swift`,
  `Tests/PalettePressUITests/PalettePressUITests.swift`,
  `README.md`, plus the shared doctrine set. Re-assert token-cleanliness across
  the emitted tree (the existing no-tokens test loops `emitted` — extend it to a
  parameterized test over both shapes, or add a second test).
- [ ] **Step 2: RED** (before Task 3's files? — NO: Task 3 already landed; this
  test should go GREEN immediately if Task 3 was complete. If it fails, the
  failure list IS the defect list — fix templates.)
- [ ] **Step 3: full fast suite green.**
- [ ] **Step 4: commit** — `test: local-only emission file-set + token-clean assertions`

---

### Task 7: Integration — the local-only walking skeleton, headless

**Files:**
- Modify: `Tests/BootstrapKitTests/IntegrationTests.swift`

- [ ] **Step 1: add the integration test:**

```swift
    /// Local-only walking-skeleton proof: emit → xcodegen generate →
    /// xcodebuild build (macOS, unsigned). Skips (with a clear message)
    /// when xcodegen is not installed.
    @Test(.timeLimit(.minutes(15)))
    func localOnlyWalkingSkeletonBuilds() throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("skeleton-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }

        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .localOnly,
            platforms: [.macOS: "14.0"],
            bundleIdRoot: "com.example.palettepress",
            teamId: "ABCDE12345"
        )
        try Emitter.emit(config: config, into: out)
        try Verifier.verify(
            projectDir: out,
            steps: Verifier.steps(for: .localOnly),
            projectName: "PalettePress"
        )
    }
```

  Notes for the implementer:
  - `CODE_SIGNING_ALLOWED=NO` makes the fake team ID harmless headlessly.
  - If `xcodegen` is missing locally, the test should FAIL with the typed
    `toolMissing` (that is correct behavior — install it: `brew install xcodegen`).
    In the repo CI workflow, add `brew install xcodegen` before the integration leg.
  - ANY build failure is a template defect (or a wrong fact in this plan) — fix
    the template; never weaken the verify. Read the captured xcodebuild log in
    the error description.
  - Deployment floor: macOS "14.0" — at the FOS floor; xcodebuild must accept it.

- [ ] **Step 2: run** — `swift test --filter IntegrationTests` (both skeletons;
  the new one does a full SPM resolve of FOSUtilities inside xcodebuild — first
  run can take several minutes).
- [ ] **Step 3:** update `.github/workflows/ci.yml`: add `brew install xcodegen`
  step before the integration leg.
- [ ] **Step 4: full `swift test` green.**
- [ ] **Step 5: commit** — `feat: local-only end-to-end walking-skeleton integration (xcodegen + xcodebuild)`

---

### Task 8: README + status truth

- [ ] Update the repo `README.md` status line: shapes supported = shared-library,
  local-only; remaining = client-server, hybrid, doctor, skill, release CI.
- [ ] Full suite green. Commit — `docs: README status — local-only shape supported`

---

## Out of scope (later plans)

- client-server and hybrid templates (Plans 3–4)
- iOS Simulator test-execution leg in this repo's CI (evaluate after the shape
  ships; xcodebuild-test-on-simulator needs simctl boot management)
- `doctor`, the plugin skill, release CI, example-repo publishing,
  FOSMVVMArchitecture.md SPMLibraries section (Plan 5)
- Xcode-project maintenance features (synchronized-folder emission — structurally
  impossible in XcodeGen; stays a human finishing step)
