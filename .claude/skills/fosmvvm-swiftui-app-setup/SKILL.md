---
name: fosmvvm-swiftui-app-setup
description: Set up the @main App struct for FOSMVVM SwiftUI apps. Configures MVVMEnvironment, deployment URLs, and test infrastructure.
homepage: https://github.com/foscomputerservices/FOSUtilities
metadata: {"clawdbot": {"emoji": "🚀", "os": ["darwin"]}}
---

# FOSMVVM SwiftUI App Setup

Generate the main App struct for a SwiftUI application using FOSMVVM architecture.

## Conceptual Foundation

> For full architecture context, see [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md) | [OpenClaw reference]({baseDir}/references/FOSMVVMArchitecture.md)

> **API catalog:** check [`../shared/api-catalog/FOSMVVM.md`](../shared/api-catalog/FOSMVVM.md) § SwiftUI Support, § Versioning before hand-writing helpers.

The **App struct** is the entry point of a SwiftUI application. In FOSMVVM, it has three core responsibilities:

```
┌─────────────────────────────────────────────────────────────┐
│                      @main App Struct                        │
├─────────────────────────────────────────────────────────────┤
│  1. MVVMEnvironment Setup                                   │
│     - Bundles (app + localization resources)                │
│     - Deployment URLs (production, staging, debug)          │
│                                                              │
│  2. Environment Injection                                   │
│     - .environment(mvvmEnv) on WindowGroup                  │
│     - Custom environment values                             │
│                                                              │
│  3. Test Infrastructure (DEBUG only)                        │
│     - .testHost { } modifier for UI testing                 │
│     - registerTestingViews() for individual view testing    │
└─────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. MVVMEnvironment

The `MVVMEnvironment` provides FOSMVVM infrastructure to all views:

```swift
private var mvvmEnv: MVVMEnvironment {
    MVVMEnvironment(
        appBundle: Bundle.main,
        resourceBundles: [
            MyAppViewModelsResourceAccess.localizationBundle,
            SharedResourceAccess.localizationBundle
        ],
        deploymentURLs: [
            .production: .init(serverBaseURL: URL(string: "https://api.example.com")!),
            .debug: .init(serverBaseURL: URL(string: "http://localhost:8080")!)
        ]
    )
}
```

**Key configuration:**
- `appBundle` - Usually `Bundle.main` (the app bundle)
- `resourceBundles` - Array of localization bundles from your modules
- `deploymentURLs` - URLs for each deployment environment

**Resource Bundle Accessors:**

Each module that contains localization resources should provide a bundle accessor:

```swift
// In your ViewModels module (e.g., MyAppViewModels/ResourceAccess.swift)
public enum MyAppViewModelsResourceAccess {
    public static var localizationBundle: Bundle { Bundle.module }
}
```

This pattern:
- Uses `Bundle.module` which SPM automatically provides for each module
- Provides a clean public API for accessing the module's resources
- Keeps bundle access centralized in one place per module

### 2. Environment Injection

The `MVVMEnvironment` is injected at the WindowGroup level:

```swift
var body: some Scene {
    WindowGroup {
        MyView()
    }
    .environment(mvvmEnv)  // ← Makes FOSMVVM infrastructure available
}
```

This makes the environment available to all views in the hierarchy.

### 3. Test Infrastructure

The test infrastructure enables UI testing with specific configurations:

**Baseline: `.testHost()` (no-arg) for display-only apps.** If the app has **no typed
`TestConfiguration`** and nothing reads an `underTest` flag, the minimal wiring is the
no-arg form — the FOSTestingUI harness swaps the registered view in on `onAppear`
regardless:

```swift
WindowGroup {
    LandingPageView()
        .testHost()          // display-only: no decorator, no underTest needed
}
```

Adopt the `.testHost { testConfiguration, testView in … }` **closure** form (below) only
when a view must branch on a specific test scenario or seed the environment for a typed
config — not as the default.

**`.testHost { }` modifier (typed-config opt-in):**
```swift
var body: some Scene {
    WindowGroup {
        ZStack {
            LandingPageView()
        }
        #if DEBUG
        .testHost { testConfiguration, testView in
            // Handle specific test configurations...

            default:
                testView
                    .onAppear {
                        underTest = ProcessInfo.processInfo.environment["__FOS_ViewModel"] != nil
                    }
        }
        #endif
    }
}
```

**Key points:**
- **Apply to the top-level view** in WindowGroup (the outermost view in your hierarchy)
- This ensures the modifier wraps the entire view hierarchy to intercept test configurations
- Always include the `default:` case
- **Detect test mode via `launchEnvironment`, not process arguments.** The FOSTestingUI
  harness (`ViewModelDisplayTestCase.presentView`) passes the target VM via
  `app.launchEnvironment` (`__FOS_ViewModelType` / `__FOS_ViewModel` /
  `__FOS_TestConfiguration`) and sets **no** launch *arguments* — so
  `ProcessInfo.processInfo.arguments.count > 1` stays false under `presentView` and is
  unreliable. Read `ProcessInfo.processInfo.environment["__FOS_ViewModel"]` instead.
- Sets `@State private var underTest = false` flag
- Optional: Add specific test configurations for advanced scenarios

**`registerTestingViews()` function:**
```swift
#if DEBUG
private extension MyApp {
    @MainActor func registerTestingViews() {
        mvvmEnv.registerTestView(LandingPageView.self)
        mvvmEnv.registerTestView(SettingsView.self)
        // ... register all ViewModelViews for individual testing
    }
}
#endif
```

**Key points:**
- Extension on the **App struct** (not MVVMEnvironment)
- Called from `init()`
- Registers every ViewModelView for isolated testing
- DEBUG only

## When to Use This Skill

- Starting a new FOSMVVM SwiftUI application
- Migrating an existing SwiftUI app to FOSMVVM
- Setting up the App struct with proper FOSMVVM infrastructure
- Configuring test infrastructure for UI testing

## What This Skill Generates

| Component | Location | Purpose |
|-----------|----------|---------|
| Main App struct | `Sources/App/{AppName}.swift` | Entry point with MVVMEnvironment setup |
| MVVMEnvironment configuration | Computed property in App struct | Bundles and deployment URLs |
| Test infrastructure | DEBUG blocks in App struct | UI testing support |
| Project conventions doc | `CLAUDE.md` / `AGENTS.md` at the app repo root | Anchors the app on SOLID (see below) |

## Seed the App's `CLAUDE.md` (project conventions)

When setting up a **new FOSMVVM app**, seed (or extend) a `CLAUDE.md`/`AGENTS.md` at the app
repo root with a short **"SOLID Is the Foundation"** entry, mirroring FOSUtilities' own. A
FOSMVVM app inherits FOSMVVM's SOLID contract — deviations (a domain type in a ViewModel,
per-target SPM linking, `.grouped("string")` routes, throwaway `vmId`s) break in baffling
ways — so every future session on the app should read this before touching code. Drop-in:

```markdown
## SOLID Is the Foundation

This app is built on **FOSMVVM**, which is built on the **SOLID principles** — deviations
cause catastrophic failures (runtime type-identity mismatches, leaked domain types, SwiftUI
identity churn) that surface far from their cause. Treat a SOLID violation as a hard stop.

- Source-of-truth ordering: SOLID → FOSMVVM architecture → this app's code.
- Add ViewModels / Requests / Fields / Views / tests via the `fosmvvm-*` generator skills
  rather than hand-rolling — they encode the SOLID patterns (noun-first requests, one file
  per ViewModel, the domain-free ViewModel boundary, the `SPMLibraries` umbrella, …).
- Key rules: a ViewModel is a *projection of* data, never the data (the Factory adapts);
  the ViewModel module never imports the domain/wire module; consume SPM products through
  the one `SPMLibraries` umbrella; `vmId` is stable data identity, never a throwaway.

### Encapsulation Is the Precondition SOLID Assumes

Encapsulation is **not** a SOLID principle and **not** something a "SOLID-clean" verdict
certifies — it is the precondition SOLID relies on. SOLID governs structure/dependency
direction; encapsulation governs state visibility. SOLID's benefits **degrade silently**
without it (SRP is satisfied by all-`public var`; OCP is "followed" while an extension pokes
another type's hidden state and the safe-extension payoff evaporates), so **review it
separately**. Scalable, maintainable, testable apps require perfect encapsulation to run
predictably over time — break one wall and it's the small hole in the dam that cascades.

- **Stringly-typing is the encapsulation break.** A `String` used as an identity/route/key/
  token has no wall — anyone can mint, parse, or route on it. Prefer a typed/opaque value;
  never expose a `String` "just for a test" or "just to derive X."
- **Don't publish the representation.** Never state a sealed type's internal shape (encoded
  keys, token format) in DocC / CHANGELOG / README — it becomes a schema others parse or forge.
  State the *contract* (opaque; round-trips; stable within a major version), not the shape.
- **Test the contract, not the representation** (equality, determinism, "old data still
  decodes"), never an incidental encoded byte layout.
```

Also seed an **"API Discovery"** entry so future sessions on the app check the FOSUtilities
catalog before reinventing shipped API. Reference the discovery skill **by name only — never
by a filesystem path** (the catalog files live inside the installed plugin, not in the app
repo's `.claude/skills/`). Drop-in:

```markdown
## API Discovery

Before writing helpers for JSON/Codable, dates, networking/URLSession, strings,
collections, async bridging, versioning, model identifiers, or testing, invoke the
`fosutilities-api-catalog` skill — FOSUtilities likely already provides the API.
Prefer the catalogued API over hand-rolled code.
```

## Project Structure Configuration

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{AppName}` | Your app name | `MyApp`, `AccelApp` |
| `{AppTarget}` | Main app target | `App` |
| `{ResourceBundles}` | Module names with localization | `MyAppViewModels`, `SharedResources` |

## How to Use This Skill

**Invocation:**
/fosmvvm-swiftui-app-setup

**Prerequisites:**
- App name understood from conversation context
- Deployment URLs discussed or documented
- Resource bundles identified (modules with localization)
- Test support requirements clarified

**Workflow integration:**
This skill is used when setting up a new FOSMVVM SwiftUI application or adding FOSMVVM infrastructure to an existing app. The skill references conversation context automatically—no file paths or Q&A needed.

## Pattern Implementation

This skill references conversation context to determine App struct configuration:

### Configuration Detection

From conversation context, the skill identifies:
- **App name** (from project discussion or existing code)
- **Deployment environments** (production, staging, debug URLs)
- **Resource bundles** (modules containing localization YAML files)
- **Test infrastructure** (whether UI testing support needed)

### MVVMEnvironment Setup

Based on project structure:
- **App bundle** (typically Bundle.main)
- **Resource bundle accessors** (from identified modules)
- **Deployment URLs** (for each environment)
- **Current version** (from shared module)

### Test Infrastructure Planning

If test support needed:
- **Test detection** (process arguments check)
- **Test host modifier** (wrapping top-level view)
- **View registration** (all ViewModelViews for testing)

### File Generation

1. Main App struct with @main attribute
2. MVVMEnvironment computed property
3. WindowGroup with environment injection
4. Test infrastructure (if requested, DEBUG-only)
5. registerTestingViews() extension (if test support)

### Context Sources

Skill references information from:
- **Prior conversation**: App requirements, deployment environments discussed
- **Project structure**: From codebase analysis of module organization
- **Existing patterns**: From other FOSMVVM apps if context available

## Key Patterns

### MVVMEnvironment as Computed Property

The `MVVMEnvironment` is a computed property, not a stored property:

```swift
private var mvvmEnv: MVVMEnvironment {
    MVVMEnvironment(
        appBundle: Bundle.main,
        resourceBundles: [...],
        deploymentURLs: [...]
    )
}
```

**Why computed?**
- Keeps initialization logic separate
- Can be customized in DEBUG vs RELEASE
- Clear dependency on bundles and URLs

### Test Detection Pattern

The default test detection uses process arguments:

```swift
@State private var underTest = false

// In .testHost default case:
testView
    .onAppear {
        // Right now there's no other way to detect if the app is under test.
        // This is only debug code, so we can proceed for now.
        underTest = ProcessInfo.processInfo.environment["__FOS_ViewModel"] != nil
    }
```

**Why this approach?**
- Simple and reliable for DEBUG builds
- No additional dependencies
- Process arguments are set by test runner

### Register All ViewModelViews

Every ViewModelView should be registered for testing:

```swift
@MainActor func registerTestingViews() {
    // Landing Page
    mvvmEnv.registerTestView(LandingPageView.self)

    // Settings
    mvvmEnv.registerTestView(SettingsView.self)
    mvvmEnv.registerTestView(ProfileView.self)

    // Dashboard
    mvvmEnv.registerTestView(DashboardView.self)
    mvvmEnv.registerTestView(CardView.self)
}
```

**Organization tips:**
- Group by feature/screen with comments
- Alphabetical order within groups
- One view per line for easy scanning

## Common Customizations

### Multiple Environment Values

You can inject multiple environment values:

```swift
var body: some Scene {
    WindowGroup {
        MyView()
    }
    .environment(mvvmEnv)
    .environment(appState)
    .environment(\.colorScheme, .dark)
    .environment(\.customValue, myCustomValue)
}
```

### Conditional Test Registration

You can conditionally register views based on build configuration:

```swift
#if DEBUG
@MainActor func registerTestingViews() {
    mvvmEnv.registerTestView(LandingPageView.self)

    #if INCLUDE_ADMIN_FEATURES
    mvvmEnv.registerTestView(AdminPanelView.self)
    #endif
}
#endif
```

### Advanced Test Configurations

You can add specific test configurations in `.testHost`:

```swift
.testHost { testConfiguration, testView in
    switch try? testConfiguration.fromJSON() as MyTestConfiguration {
    case .specificScenario(let data):
        testView.environment(MyState.stub(data: data))
            .onAppear { underTest = true }

    default:
        testView
            .onAppear {
                underTest = ProcessInfo.processInfo.environment["__FOS_ViewModel"] != nil
            }
    }
}
```

## Project File Structure

The App struct does not stand alone. It is one consumer of a shared module that holds ServerRequests, ViewModels, Fields, and SystemVersion (see [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md) §"The Shared Module Pattern"). The on-disk layout depends on the build system.

### Build system: Xcode project vs. SPM

| | Xcode project (`*.xcodeproj`) | Swift Package (`Package.swift`) |
|---|---|---|
| Targets | Xcode-managed framework targets | SPM library products |
| Resource bundle | `Bundle(for: ResourceAccessClass.self)` | `Bundle.module` |
| macOS signing | Frameworks sign with app's Team ID — no entitlement workaround needed | Hardened-runtime + ad-hoc-signed `PackageFrameworks` requires `com.apple.security.cs.disable-library-validation` (see "Code Signing for SPMLibraries Umbrella Frameworks" above) |
| Info.plist / entitlements | App target `Sources/{AppTarget}/` or `Resources/` | App target's resource directory |
| SPMLibraries umbrella | **Required** `Sources/SPMLibraries/SPMLibraries.swift` umbrella when multiple targets consume SPM products — one canonical type identity across targets (see "The SPMLibraries umbrella") | N/A |

Default to **Xcode project** for app projects unless there is a specific reason to use SPM at the top level. The Xcode layout sidesteps the PackageFrameworks signing trap and gives natural homes for `Info.plist`, `Assets.xcassets`, and `.entitlements`.

### Sources/ tree (canonical app layout)

```
{ProjectName}/
├── {ProjectName}.xcodeproj          # Xcode project (no Package.swift)
│
├── Sources/
│   ├── ViewModels/                  # SHARED MODULE (framework target)
│   │   ├── ViewModels/              # @ViewModel structs — ONE type per file,
│   │   │   └── Docks/               #   grouped in a dir named for the container VM
│   │   │       ├── DocksViewModel.swift       # top-level (composite)
│   │   │       ├── DockViewModel.swift        # child — its own file
│   │   │       ├── BerthViewModel.swift       # grandchild — its own file
│   │   │       ├── HarbormasterSummary.swift  # display type — its own file
│   │   │       └── BerthLiveness.swift        # display enum — its own file
│   │   ├── Operations/              # Op protocols + StubOps (no live impls)
│   │   ├── Fields/                  # Fields protocols + FieldsMessages
│   │   ├── Errors/                  # ServerRequestError types
│   │   ├── Versioning/
│   │   │   └── SystemVersion+App.swift   # extension on SystemVersion — name for the
│   │   │                                 #   TYPE (+ matching header), NOT <Module>Version.swift
│   │   ├── Resources/ViewModels/    # *.yml — client-hosted apps ONLY;
│   │   │                            #   server-hosted → sibling Sources/Resources/ (see Contract Wiring)
│   │   └── ViewModelsResourceAccess.swift   # exposes localizationBundle
│   │
│   ├── Models/                      # OPTIONAL framework — @Model classes
│   │
│   ├── SPMLibraries/                # umbrella — REQUIRED for one type identity
│   │   └── SPMLibraries.swift       #   across targets (Xcode; see below)
│   │
│   └── {AppTarget}/                 # APP TARGET
│       ├── App/
│       │   ├── {AppName}App.swift   # @main — the file this skill generates
│       │   ├── TestConfiguration.swift   # if .testHost uses typed configs
│       │   └── Assets.xcassets
│       ├── Views/
│       │   └── Docks/               # Views mirror the same container grouping
│       │       ├── DocksView.swift
│       │       └── DockView.swift
│       ├── Operations/              # Live op implementations
│       ├── AppState/                # @Observable session state
│       ├── Info.plist
│       └── {AppName}.entitlements
│
└── Tests/                          # mirrors Sources/ one-to-one
    ├── UnitTests/
    │   ├── Docks/                   # same grouping again
    │   │   └── DocksViewModelTests.swift
    │   └── TestYAML/                # FOSMVVM test fixtures
    └── UITests/
```

### File Organization Conventions

Three rules govern how ViewModel code is laid out. They apply to **every** layer, and
the generators scaffold to them by default.

1. **One type per file, named for the type.** Each `@ViewModel` type — the top-level
   composite **and** every composed child — lives in its **own file** named for the type
   (`DocksViewModel.swift`, `DockViewModel.swift`, `BerthViewModel.swift`). Display
   structs and display enums the ViewModels use get their own files too
   (`HarbormasterSummary.swift`, `BerthLiveness.swift`). **Never chain several
   `@ViewModel` types into one file.** A long multi-type file hides the model and fights
   reviewability; one-file-per-type keeps each display snapshot independently readable,
   diffable, and testable — this is **Single Responsibility applied to the file**.

2. **Group a collection in a directory named for its container.** A composite ViewModel
   and its children live in a directory named after the containing top-level VM **minus
   the `ViewModel` suffix**: `ViewModels/Docks/`. The directory name (`Docks`) signals
   which VM owns the collection.

3. **The same grouping repeats across every layer.** `Views/Docks/`,
   `Tests/UnitTests/Docks/`, and — server-side — `ViewModelFactories/Docks/` and
   `Controllers/Docks/` all use the identical `Docks/` folder, so a screen's ViewModel,
   View, Factory, and tests sit in parallel folders. **`Tests/` mirrors `Sources/`
   one-to-one.** (Factories/Controllers/DataModels are server-only and live in the server
   target, not the shared module — see the contract-wiring section for which side owns
   the shared module. The shared module carries only what both client and server must
   agree on: ViewModels, Requests, Fields, Versioning.)

Other skills reference these rules rather than restating them (e.g. the
[viewmodel-generator](../fosmvvm-viewmodel-generator/SKILL.md) scaffolds one file per VM).

### ResourceAccess.swift — the two forms

Each module carrying YAML resources exposes a single `localizationBundle` accessor. The body differs by build system:

**Xcode framework target** (`Bundle(for:)`):
```swift
public enum {Module}ResourceAccess {
    private final class ResourceAccessClass {}
    public static var localizationBundle: Bundle {
        Bundle(for: ResourceAccessClass.self)
    }
}
```

**SPM library target** (`Bundle.module`):
```swift
public enum {Module}ResourceAccess {
    public static var localizationBundle: Bundle { Bundle.module }
}
```

Both are consumed identically from the App struct:
```swift
resourceBundles: [{Module}ResourceAccess.localizationBundle]
```

### Wholly client-hosted apps: empty deploymentURLs

A FOSMVVM app may be entirely client-hosted (every ViewModel built via `@ViewModel(options: [.clientHostedFactory])`, no project server). For these apps, `deploymentURLs` is legitimately empty:

```swift
deploymentURLs: [Deployment: MVVMEnvironment.URLPackage]()
```

Do not invent placeholder URLs. An empty dictionary is the correct expression of "this app talks to no server."

### Canonical app-target imports

The App struct file's import set is small and stable:

```swift
import FOSFoundation
import FOSMVVM
import SwiftUI
import {SharedModule}              // typically `ViewModels`
// + any per-module ResourceAccess imports if the accessor's module differs
```

If the App struct references types from `Models` or other implementation-side targets at top level, that is a smell — App-level wiring should go through the shared module.

## Server-Hosted ViewModel Contract Wiring (Both Sides)

**How a client reaches a server-hosted ViewModel.** Mainstream REST instincts —
"namespace the API under `/admin`", "make the client URL match the server route" — **fight
the FOSMVVM model and cause 404s.** FOSMVVM derives the path from the request **type** on
both sides, so neither side invents a URL. Four rules:

**Rule 1 — A `ViewModelRequest`'s path is derived from its TYPE and is globally unique.**
You never need `.grouped("string")` to namespace ViewModels — there are no collisions to
avoid. Register on `app.routes`; the client points at a clean host, and the two paths agree
automatically because neither side invents one. Canonical — FOSShowcase
`Sources/WebServer/routes.swift`:

```swift
let unauthGroup = app.routes
try unauthGroup.register(viewModel: LandingPageViewModel.self)   // served at the type-derived path
```

**Rule 2 — Middleware ≠ path.** Auth (mTLS client-cert, etc.) is applied with
`.grouped(SomeMiddleware())`, which adds **no** path segment — **never** `.grouped("admin")`
(a string), which adds a path the type-derived client resolver cannot reproduce. To gate a
ViewModel behind an admin contract:

```swift
app.grouped(AdminClientCertMiddleware()).register(viewModel: AdminInfoViewModel.self)  // gate, NO prefix
```

**Rule 3 — Base URLs are clean hosts, never `…/path`.** The client `MVVMEnvironment` base
URL is scheme + host + port only. FOSShowcase `Sources/SwiftUIApp/FOSShowcaseApp.swift`:

```swift
deploymentURLs: [.debug: URL(string: "http://localhost:8080")!]   // no path
```

`requestURL` derives the path from the request type and **discards any base-URL path** —
that is **correct by design, not a bug**.

**Rule 4 — File structure: one folded tree, a shared contract module, resources as a
server-side sibling.** The whole system (server + every client + shared contract +
resources + mirrored tests) lives in ONE directory (see "File Organization Conventions"
and the canonical tree above). Placements that matter for the contract:

- The **shared contract module** (`ViewModels`) holds only what both sides must agree on —
  `ViewModels/`, `Requests/`, `Fields/`, `Versioning/` — **pure Swift, no resources.**
- Localization `*.yml` are **server-only resources** in a **sibling `Sources/Resources/`**
  tree (mirroring the module), `.copy`'d by the **server** target (and any server-rendered
  web client, and tests) — FOSShowcase `.copy("../Resources")`. Deferred localization means
  the server resolves all strings at encode time, so a release native client decodes an
  **already-localized** ViewModel and needs no strings. The `*.yml` therefore **must NOT
  live in the shared contract module** — the client links that module and would ship the
  strings. *(A **wholly** client-hosted app with no server is the exception: it resolves
  localization itself and legitimately bundles the resources — see "Wholly client-hosted
  apps" above.)*
- `ViewModelFactories` / `Controllers` / `DataModels` are **server-only**; `Views` are
  **client-only**.
- The native app is a **target in the one tree's root `.xcodeproj`** (apps require Xcode),
  sharing the contract module directly — not a separate bolted-on XcodeGen project.
- **`Tests/` mirrors `Sources/` one-to-one**; version baselines commit under
  `Tests/.../.VersionedTestJSON/`.

Fuller treatment: [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md) "Project
Structure", "What Belongs Where", "File Organization Conventions".

> **Anti-drift callout.** Do **not** `.grouped("string")` a ViewModel route; do **not** put
> a path on the client base URL; if a fetch 404s, you added a stray path segment — **do not
> change FOSMVVM**. The server path and client path agree automatically because neither side
> invents one.

## Generating the Xcode Project (XcodeGen)

The Xcode-project layout has many easy-to-forget settings that must be set on **every** target: `SWIFT_VERSION = 6.0`, `BUILD_LIBRARY_FOR_DISTRIBUTION = NO`, embed-and-sign vs. link-only on the app target, `SPMLibraries` umbrella wiring, signing identity, deployment targets, entitlements path, Info.plist path. Configuring these by hand is repetitive and drifts.

**Recommendation:** declare the project in [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`) and regenerate the `.xcodeproj` from it. Commit `project.yml`; treat the `.xcodeproj` as derived.

### Why XcodeGen

- **Diff-able** — `project.yml` is one file; `project.pbxproj` is a giant generated graph hostile to review.
- **Reproducible** — every target gets the same Swift version, distribution flag, deployment target, signing — no per-target drift.
- **Claude-editable** — adding a target, package, or build setting is a small YAML edit, not a click sequence.
- **Single tool** — `brew install xcodegen` then `xcodegen generate`. No Tuist cache, no Bazel.

### Workflow

1. `brew install xcodegen` (one time per machine).
2. Edit `project.yml` at the repo root.
3. Run `xcodegen generate` — produces/updates `{ProjectName}.xcodeproj`.
4. Open in Xcode normally. Re-run the command after every `project.yml` change.

### The SPMLibraries umbrella, declaratively — REQUIRED for type identity

**When more than one Xcode target consumes SPM package products (app + unit tests + UI
tests …), vend them through a SINGLE `SPMLibraries` umbrella framework that every target
depends on — never link the SPM products directly into each target.** `SPMLibraries` is a
thin framework whose dependencies list every external package product (FOSFoundation,
FOSMVVM, …); the app target depends on `SPMLibraries` (plus `ViewModels` and `Models`). In
XcodeGen this is one stanza.

**Why (a generic Xcode + SPM bug — not FOS-specific):** linking an SPM library statically
into multiple targets compiles a **separate copy of its types into each target**, and
Swift's mangled type name carries the linking context — so the "same" type has a
**different runtime identity per target**. An instance crossing a target boundary then
fails `is` / `as?` / `==` / `===` against the same type on the other side: **`TypeA != TypeA`.**
It **compiles clean and breaks at runtime in baffling ways, far from the cause.** One
umbrella *dynamic* framework = one canonical copy = one shared type identity everywhere.

**Why it matters ESPECIALLY for FOSMVVM:** FOSMVVM leans hard on **comparing types** —
type-derived request paths, ViewModel/Request resolution, versioning. A FOS app that skips
the umbrella breaks exactly where those comparisons happen. The umbrella *looks* like
redundant re-vending to a mainstream eye — which is precisely why it must be stated, not
emitted silently.

> **Do NOT "simplify" by linking SPM products directly per-target.** `TypeA != TypeA`
> across target boundaries at runtime (a generic Xcode packaging bug); FOS relies on type
> comparison, so this **WILL** break in baffling ways. Every target depends on the one
> `SPMLibraries` framework. (UI-test targets are the one exception — they run in a separate
> process and link FOS products directly; see the ui-tests generator.)

### What `project.yml` settles in one place

| Setting | Applied to | Why |
|---|---|---|
| `SWIFT_VERSION: 6.0` | All targets via `settings.base` | Must match across the project |
| `BUILD_LIBRARY_FOR_DISTRIBUTION: NO` | All targets | App is not a library; setting YES bloats build & breaks `@_spi` |
| `ENABLE_HARDENED_RUNTIME: YES` | App + tests | macOS notarization |
| `GENERATE_INFOPLIST_FILE: YES` | Frameworks + tests | Saves writing empty Info.plists |
| `INFOPLIST_FILE: Sources/{App}/Info.plist` | App target only | Carries `FOS-DEPLOYMENT`, `NS*UsageDescription` |
| `CODE_SIGN_ENTITLEMENTS: Sources/{App}/{App}.entitlements` | App target only | CloudKit, audio background, etc. |
| `DEVELOPMENT_TEAM` | All targets via `settings.base` | Avoids the SPM ad-hoc-signing trap |
| Package dependencies on `SPMLibraries` only | App imports just `import {AppModule}` shape | One place to add/remove SPM deps |

See [reference.md](reference.md) Template 7 for the complete `project.yml`.

### Verified, build-tested `project.yml` (Option A — source inclusion)

For a **one-shot, build-verified** setup, use
[`docs/work/fosmvvm-app-project-template.md`](../../docs/work/fosmvvm-app-project-template.md)
— reverse-engineered from a real hand-built `.xcodeproj` and confirmed with
`xcodebuild … build-for-testing → ** TEST BUILD SUCCEEDED **` (app + app-hosted unit-test
bundle + UI-test bundle all compile and link). It refines Template 7 with these load-bearing
corrections — apply them whichever template you start from:

- **Option A (source inclusion).** The app target `sources:` **include the folders** of the
  shared contract module and the Views layer (they compile *into* the app; Views reference
  ViewModels with no cross-module `import`). The app links **only** `SPMLibraries`. (Template
  7 is Option B — a separate `ViewModels` framework; both are valid.)
- **Singular `BUILD_LIBRARY_FOR_DISTRIBUTION: NO`** — the plural `…LIBRARIES…` is a no-op typo.
- **Test-target names `{Base}UnitTests` / `{Base}UITests`**, where `{Base}` strips a trailing
  `UI` from the app name. Never bare `{AppName}Tests` (a unit target should say "Unit") or
  `{AppName}UITests` when `{AppName}` already ends in `UI` (→ doubled `…UIUITests`).
- **Pin `TEST_HOST` when the app target name ≠ `PRODUCT_NAME`** — XcodeGen otherwise derives
  it from the target name and the unit test fails to link (`ld: library '…' not found`):
  `TEST_HOST: "$(BUILT_PRODUCTS_DIR)/{ProductName}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/{ProductName}"` + `BUNDLE_LOADER: "$(TEST_HOST)"`.
- **App-hosted tests** (unit test depends on the app target) so the tests share the app's
  exact FOS type identity — the real proof the `SPMLibraries` umbrella works.
- **Multi-platform → `supportedDestinations: [macOS, iOS]`**, NOT `platform: [macOS, iOS]`
  (the latter splits into per-platform targets and breaks a single-name scheme entry).
- **`.xctestplan` caveat:** a committed plan pins targets by UUID, which XcodeGen re-mints on
  generate → dangling references. Either drop the plan and list `test.targets:` in the scheme
  (regenerable default), or reconcile the plan's UUIDs once in Xcode after the first generate.

### Lifecycle: XcodeGen scaffolds, it does not maintain

The generator is a **one-shot scaffolder**, not a lifetime project manager. It earns its keep
once — nailing the hard, easy-to-forget setup (umbrella, source-inclusion, app-hosted tests,
`TEST_HOST`, Swift 6 + strict concurrency). Once the project is stable, the few tweaks it
accrues (a setting, a destination, a folder) are better made **in Xcode by hand** — a regen
clobbers them. The workflow:

1. **Scaffold once** from the template.
2. **Do the two things XcodeGen structurally can't**, once, in Xcode after the final generate:
   - **Synchronized folders** (`PBXFileSystemSynchronizedRootGroup`). XcodeGen (≤ 2.45.4)
     emits classic enumerated groups, not the Xcode-16 folders that auto-mirror the
     filesystem. The build is identical, but auto-mirroring is lost — re-add the source
     folders as synchronized folders.
   - Add **iOS/iPadOS destinations** if needed (destinations-only under source-inclusion — no
     package change, provided the included source is iOS-clean).
3. **Commit the `.xcodeproj`** (stop git-ignoring it) — it becomes the hand-maintained source
   of truth; keep `project.yml` as a documented **seed**, not a live regen target.

**Keep the strict-concurrency win.** Verify the generated project has `SWIFT_VERSION 6.0` +
`SWIFT_STRICT_CONCURRENCY complete` and **no** `SWIFT_APPROACHABLE_CONCURRENCY` /
`SWIFT_DEFAULT_ACTOR_ISOLATION` keys. A fresh Xcode 26 app turns on Approachable Concurrency
(`@MainActor`-by-default) by default; XcodeGen sets only what `project.yml` declares, so you
keep clean strict-complete concurrency the IDE would otherwise relax.

## File Templates

See [reference.md](reference.md) for complete file templates.

## Naming Conventions

| Concept | Convention | Example |
|---------|------------|---------|
| App struct | `{Name}App` | `MyApp`, `AccelApp` |
| Main file | `{Name}App.swift` | `MyApp.swift` |
| MVVMEnvironment property | `mvvmEnv` | Always `mvvmEnv` |
| Test flag | `underTest` | Always `underTest` |

## Deployment Configuration

FOSMVVM supports deployment detection via Info.plist:

```
CI Pipeline Sets:
   FOS_DEPLOYMENT build setting (e.g., "staging" or "production")
        ↓
Info.plist Contains:
   FOS-DEPLOYMENT = $(FOS_DEPLOYMENT)
        ↓
Runtime Detection:
   FOSMVVM.Deployment.current reads from Bundle.main.infoDictionary
```

**Local development override:**
- Edit Scheme → Run → Arguments → Environment Variables
- Add: `FOS-DEPLOYMENT = staging`

## Code Signing for SPMLibraries Umbrella Frameworks

**Required when** the project uses an `SPMLibraries.framework` umbrella target that links FOSFoundation/FOSMVVM (or any other SwiftPM products) and the app is built for **macOS** with `ENABLE_HARDENED_RUNTIME = YES` (the default for new macOS / multiplatform apps).

**Symptom at launch / first test run:**
```
dyld[...]: Library not loaded: @rpath/FOSFoundation.framework/...
Reason: ... code signature in '...PackageFrameworks/FOSFoundation.framework' not valid
        for use in process: mapping process and mapped file (non-platform) have different Team IDs
```

**Why it happens:** SwiftPM builds dynamic package frameworks into `Build/Products/<config>/PackageFrameworks/` and **always ad-hoc-signs them** (`TeamIdentifier=not set`), regardless of the consuming project's `DEVELOPMENT_TEAM`. The app binary is signed with the developer's team, so under hardened-runtime library validation dyld refuses to load the ad-hoc-signed framework. This does **not** affect iOS Simulator builds (library validation isn't enforced there), so iOS-only projects never see it.

**Fix — add to the app's `.entitlements` file:**
```xml
<key>com.apple.security.cs.disable-library-validation</key>
<true/>
```

This is Apple's documented escape hatch for apps that load dylibs not signed by their team. It only relaxes library validation; the rest of hardened runtime stays in effect.

**Verify** with:
```
codesign -dvv <DerivedData>/Build/Products/Debug/PackageFrameworks/FOSFoundation.framework
```
Expect `Signature=adhoc`, `TeamIdentifier=not set` — that is the trigger condition.

**Apply the same entitlement to** any additional bundles that load `SPMLibraries.framework` out-of-process: standalone test bundles, app extensions, helper tools. (Tests hosted by the app inherit the host app's entitlements and need no change.)

## See Also

- [Architecture Patterns](../shared/architecture-patterns.md) - Mental models and patterns
- [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md) - Full FOSMVVM architecture
- [fosmvvm-viewmodel-generator](../fosmvvm-viewmodel-generator/SKILL.md) - For creating ViewModels
- [reference.md](reference.md) - Complete file templates

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-23 | Initial skill for SwiftUI app setup |
| 1.1 | 2026-01-24 | Update to context-aware approach (remove file-parsing/Q&A). Skill references conversation context instead of asking questions or accepting file paths. |
| 1.2 | 2026-04-27 | Add "Code Signing for SPMLibraries Umbrella Frameworks" section documenting the macOS hardened-runtime + ad-hoc-signed PackageFrameworks Team ID mismatch and the `com.apple.security.cs.disable-library-validation` entitlement fix. |
| 1.3 | 2026-05-03 | Add "Project File Structure" section covering Xcode-project vs. SPM layout, the two `ResourceAccess` forms (`Bundle(for:)` vs. `Bundle.module`), wholly client-hosted apps with empty `deploymentURLs`, and canonical app-target imports. Add Template 6 to reference.md for a wholly client-hosted Xcode-project app. |
| 1.4 | 2026-05-03 | Add "Generating the Xcode Project (XcodeGen)" section with declarative project setup (`SWIFT_VERSION`, `BUILD_LIBRARY_FOR_DISTRIBUTION = NO`, signing, `SPMLibraries` umbrella wiring) so the `.xcodeproj` is regenerable from a committed `project.yml`. Add Template 7 to reference.md with a complete `project.yml`. |
| 1.5 | 2026-07-02 | Add "File Organization Conventions" (canonical owner): one type per file, collection grouped in a container-named directory (`ViewModels/Docks/`), the same grouping repeated across Views/Factories/Tests, and `Tests/` mirrors `Sources/`. Canonical tree now demonstrates the grouping. (backlog B2/L59; other skills reference this.) |
| 1.6 | 2026-07-02 | **BLOCKERS.** Add "Server-Hosted ViewModel Contract Wiring (Both Sides)": type-derived globally-unique paths (no `.grouped("string")`), middleware≠path, clean-host base URLs, resources server-only in sibling `Sources/Resources/`, native app in root `.xcodeproj`, Tests mirror Sources; anti-drift callout; grounded in FOSShowcase `routes.swift`/`FOSShowcaseApp.swift` (C1). Add the SPMLibraries **type-identity** rationale (`TypeA != TypeA` across targets; FOS relies on type comparison) + "do not link per-target" callout; retitled umbrella REQUIRED (was "Optional") (C2). |
| 1.7 | 2026-07-02 | Fold in the build-verified [`fosmvvm-app-project-template.md`](../../docs/work/fosmvvm-app-project-template.md) (copied into this repo): Option-A source inclusion, singular `BUILD_LIBRARY_FOR_DISTRIBUTION` (fixed the plural no-op typo throughout), `{Base}UnitTests`/`{Base}UITests` naming, `TEST_HOST` pin, app-hosted tests, `supportedDestinations`, `.xctestplan` caveat (C3). `.testHost()` no-arg baseline + `underTest` detection via `launchEnvironment` (`__FOS_ViewModel`) not `arguments.count` — verified against `ViewModelViewTestCase.presentView` (C4). "Lifecycle: scaffolds not maintains" — synchronized folders, commit the `.xcodeproj`, keep strict-concurrency (C5). Reinforced `SystemVersion+<App>.swift` naming (C6). |
| 1.8 | 2026-07-02 | Add "Seed the App's `CLAUDE.md`": recommend the scaffolded app repo adopt a "SOLID Is the Foundation" project-conventions entry (drop-in template) so downstream apps inherit FOSMVVM's SOLID discipline and point future sessions at the `fosmvvm-*` skills. |
| 1.9 | 2026-07-03 | Wire in the FOSUtilities API catalog: pointer to `../shared/api-catalog/FOSMVVM.md` (§ SwiftUI Support, § Versioning) near the top, and an "API Discovery" drop-in for the seeded app `CLAUDE.md` referencing the `fosutilities-api-catalog` skill by name only (never a filesystem path — the catalog lives in the installed plugin). |
