---
name: fosmvvm-swiftui-app-setup
description: Maintain and extend the @main App struct of an existing FOSMVVM SwiftUI app — MVVMEnvironment, deployment URLs, test-view registration, client-hosted localization (resourceBundles, missingLocalizationStore/noResourcePaths symptoms), and adding framework targets by hand after bootstrap. To CREATE an app, run fosmvvm-bootstrap instead.
homepage: https://github.com/foscomputerservices/FOSUtilities
metadata: {"clawdbot": {"emoji": "🚀", "os": ["darwin"]}}
---

# FOSMVVM SwiftUI App Setup

> **Read [`shared/functional-discipline.md`](../shared/functional-discipline.md) before proceeding.** Every rule below derives from it.

Maintain the App struct of a FOSMVVM SwiftUI application — the `MVVMEnvironment`, the test-view registry, the localization wiring, and the framework targets added by hand after generation.

> **Creating an app is `fosmvvm-bootstrap`'s job.** `swift run fosmvvm-bootstrap new` emits a complete, buildable project for any of the three shapes — App struct, environment, test infrastructure, seeded `CLAUDE.md` and memory files. This skill picks up where that leaves off: the scaffolder generates once and does not maintain, and an app's App struct changes for as long as the app lives.

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
@main struct MyApp: App {
    init() {
        MVVMEnvironment.registerTestingViews()
    }
}

private extension MVVMEnvironment {
    @MainActor static func registerTestingViews() {
        #if DEBUG
        registerTestView(LandingPageView.self)
        registerTestView(SettingsView.self)
        registerTestView(DeviceCardView.self, scrollable: true) // designed for a scrolling parent
        // ... register all ViewModelViews for individual testing
        #endif
    }
}
```

**Key points:**
- A `static` extension on **`MVVMEnvironment`** — `registerTestView(_:)` is static, so no instance is involved and the calls read unqualified
- Called from `init()`, and **only** from `init()`
- Registers every ViewModelView for isolated testing
- `#if DEBUG` goes **inside** the helper, not around the call — only `registerTestView(_:)`'s body is DEBUG-only, so the whole helper compiles away to a no-op in release and `init()` stays unguarded
- **`scrollable: true` for views designed to live inside a scrolling parent in production** (a form card inside a `ScrollView`, a section of a longer page) — the harness then presents the view inside a vertical `ScrollView`, as production does. Presented bare, such a view is taller than the window: content compresses and overlaps, bottom controls sit beyond any tap's reach, and keyboard avoidance displaces the whole content instead of scrolling. The declaration is a fact about the view's *designed environment*, stated once at registration so no two tests can disagree about it (SRP: one truth, one home) — it is not an escape hatch for a view that overflows its production container too, and there is no per-test override

**Timing is load-bearing.** `testHost()` resolves the view under test before the first render, so registration from a computed property (`var mvvmEnv`), from `.onAppear`, or from `.task` arrives too late. When that happens the app stops with a diagnostic on stderr naming the missing ViewModel, listing what *is* registered, and showing the `init()` fix — do not work around it by registering later. See `reference.md` → Pattern 3.

## When to Use This Skill

The App struct is generated once and then edited for the rest of the app's life. This skill is for the editing.

- **Adding a framework target by hand**, after bootstrap — Xcode's template defaults are wrong for FOSMVVM; see the checklist below.
- **Standing up the first client-hosted ViewModel** in an app that had none — `resourceBundles`, the bundle accessor, and the two symptoms (`missingLocalizationStore`, `noResourcePaths`).
- **Registering a new `ViewModelView`** so it can be driven in isolation under test.
- **Adding a deployment environment or changing a server URL.**
- **Adopting FOSMVVM in an existing SwiftUI app** the scaffolder never created.

**Creating a new app is not on this list.** `swift run fosmvvm-bootstrap new` emits the App struct, the `MVVMEnvironment`, the test infrastructure, and the app's seeded `CLAUDE.md` and memory files, for all three project shapes. Reach for the scaffolder, then come back here when the app starts changing.

## What This Skill Covers

| Concern | Where it lives | When you touch it |
|---------|----------------|-------------------|
| `MVVMEnvironment` | Computed property in the App struct | New resource bundle, new deployment URL |
| Test-view registration | `init()` of the App struct | Every new `ViewModelView` |
| Client-hosted localization | `resourceBundles` + a module's `ResourceAccess` | First client-hosted VM; every new resource-carrying framework |
| Server-hosted contract wiring | Shared module + server side | Every new server-fetched ViewModel |
| Deployment configuration | `deploymentURLs` + `FOS-DEPLOYMENT` | New environment, changed host |


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

## How to Use This Skill

**Invocation:** `/fosmvvm-swiftui-app-setup`

**Start by reading the App struct that already exists.** Every task below is an edit to a
file the scaffolder wrote, or to one a previous session extended — not a fresh generation.
Read it first, and match it.

**The recurring edits, and where each lands:**

| You are… | Edit | Then verify |
|---|---|---|
| Adding a `ViewModelView` | `registerTestView(_:)` in the App's `init()` | Drive it in isolation under test |
| Adding a resource-carrying framework | `resourceBundles` + a `{Module}ResourceAccess` | Translations round-trip in that module's tests |
| Standing up the first client-hosted VM | `resourceBundles`, and read Client-Hosted Localization below | No `missingLocalizationStore` / `noResourcePaths` |
| Adding a deployment environment | `deploymentURLs` + the `FOS-DEPLOYMENT` plist key | `Deployment.current` resolves as intended |
| Adding a framework target by hand | The new-framework-target checklist below | `swift package fosmvvm-doctor` |

**Registration timing is load-bearing** and is the one edit that fails silently if placed
wrong — it belongs in `init()`, not in a computed property, `.onAppear`, or `.task`. The
Core Components section above states why.

**When the edit is structural rather than in-file** — a new target, changed signing, a new
test bundle — the project settings are the scaffolder's territory and `fosmvvm-doctor`'s to
audit. See the hand-off section near the end of this file.


## Key Patterns

### MVVMEnvironment: built once by a static factory, held in `@State`

```swift
@main
struct MyApp: App {
    @State private var mvvmEnv = makeMVVMEnvironment()

    var body: some Scene {
        WindowGroup { … }
            .environment(mvvmEnv)
    }
}

private extension MyApp {
    @MainActor static func makeMVVMEnvironment() -> MVVMEnvironment {
        MVVMEnvironment(
            appBundle: Bundle.main,
            resourceBundles: [MyAppViewModelsResourceAccess.localizationBundle],
            deploymentURLs: [...]
        )
    }
}
```

**Why stored, and why a factory.** `body` is evaluated repeatedly. A computed
`var mvvmEnv: MVVMEnvironment { … }` therefore builds a **new** `MVVMEnvironment` on every
pass and hands `.environment()` a different instance each render — churn on a value that
should be stable for the app's lifetime, and wasted work resolving bundles and URLs. `@State`
holds one instance; the static factory keeps the construction out of the property
declaration, so DEBUG/RELEASE variation, pinned sessions, and credential providers all have
somewhere to live without turning the declaration into a wall of arguments.

> Earlier revisions of this skill specified a computed property, on the reasoning that it
> kept initialization separate and allowed per-configuration variation. The static factory
> satisfies both without rebuilding per render, and is what `fosmvvm-bootstrap` emits for
> every shape.

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
private extension MVVMEnvironment {
    @MainActor static func registerTestingViews() {
        #if DEBUG
        // Landing Page
        registerTestView(LandingPageView.self)

        // Settings
        registerTestView(SettingsView.self)
        registerTestView(ProfileView.self)

        // Dashboard
        registerTestView(DashboardView.self)
        registerTestView(CardView.self)
        #endif
    }
}
```

**Organization tips:**
- Group by feature/screen with comments
- Alphabetical order within groups
- One view per line for easy scanning

## Common Customizations

### The Environment Surface: `mvvmEnv` + One App State

The root injects exactly two things — the framework environment and **one top-level
Application State `@Observable final class`**:

```swift
var body: some Scene {
    WindowGroup {
        MyView()
    }
    .environment(mvvmEnv)
    .environment(appState)
}
```

Resist growing this list. Every custom `@Entry` and every additional `@Observable`
injected here is an obligation on every preview and test host that renders the
subtree — forget one `.environment(...)` and an `@Environment(X.self)` read crashes,
while a custom-keyed value silently defaults. App-state-shaped values (selection,
filters, navigation, session) belong as properties **on the App State class**, reaching
ViewModels as scalars through `.bind(appState: .init(...))`. One class also gives you
the persistence seam for free: store it, and the app resumes where the user left off.
The question any additional entry must answer: *why can't this live on the App State?*
See [Architecture Patterns → One Top-Level App State, Not an Environment of
Entries](../shared/architecture-patterns.md).

### The Test-Host Seam Arrives With the App State

A skeleton app whose only environment is `mvvmEnv` correctly uses plain
`.testHost()` — there is no state to transport, so it ships no `TestConfiguration`
and no decorator (ruled 2026-08-25). **The seam arrives the day
`.environment(appState)` does.** When you add the top-level App State, add the
pair together:

- a `TestConfiguration` (`Codable` enum) whose cases carry the state a UI test
  needs the app to mirror, and
- the decorator form — `.testHost { testConfiguration, testView in … }` — building
  env state from the decoded configuration, so the hosted view's environment
  mirrors the injected VM stub instead of production state.

A `TestConfiguration` with a single payload-free case that no test constructs is
a dead seam — scaffolding noise that teaches nothing. See *Advanced Test
Configurations* below for the decorator's shape.

### Conditional Test Registration

You can conditionally register views based on build configuration:

```swift
private extension MVVMEnvironment {
    @MainActor static func registerTestingViews() {
        #if DEBUG
        registerTestView(LandingPageView.self)

        #if INCLUDE_ADMIN_FEATURES
        registerTestView(AdminPanelView.self)
        #endif
        #endif
    }
}
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

## Wiring the App to Its Resources

The three things the App struct has to get right about resources — where a module's bundle comes from, what `deploymentURLs` says when there is no server, and what the App file is allowed to import.

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

Any app with client-hosted ViewModels — wholly client-hosted or mixed — must also wire up
client-side localization resources; see "Client-Hosted Localization" below.

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

## Client-Hosted Localization

**Read this before adding the app's FIRST `@ViewModel(options: [.clientHostedFactory])`
ViewModel** — whether the app is wholly client-hosted or a server-hosted app gaining one
client-hosted screen. Every failure below compiles clean and breaks at runtime, far from
the missing configuration.

### The concept — who resolves the strings

- A **server-hosted** ViewModel is localized **on encode**: the client receives an
  already-localized ViewModel and needs **no** localization resources at all.
- A **client-hosted** ViewModel resolves its `@LocalizedString`s **on the client, at bind
  time**, via `MVVMEnvironment.clientLocalizationStore` — which is built lazily from the
  environment's `resourceBundles`
  ([MVVMEnvironment.swift:170-178](../../../Sources/FOSMVVM/SwiftUI%20Support/MVVMEnvironment.swift)).
  If no configured bundle carries the ViewModel's YAML, resolution fails.

**Symptoms when the YAML isn't reachable:**
- **App at runtime:** `ViewModelViewError.missingLocalizationStore` /
  `YamlStoreError.noResourcePaths` surfaces on the client-hosted bind path
  ([ViewModelView.swift:588-589](../../../Sources/FOSMVVM/SwiftUI%20Support/ViewModelView.swift))
  — printed as `ViewModel Bind Error:`, after which the view silently falls back to `.stub()`.
- **Tests:** `YamlStoreError.noResourcePaths` from `loadLocalizationStore`.

A server-hosted app has needed none of this, so its `MVVMEnvironment` legitimately has no
`resourceBundles` — the first client-hosted ViewModel is exactly when the gap fires.

### The resource-carrying framework (overlay-based Xcode apps)

`Bundle.main` works for a fresh SwiftUI app (YAML in the app target); `Bundle.module` works
for SPM. **Neither applies when the app overlays shared source** via synchronized folders
(`PBXFileSystemSynchronizedRootGroup`) from a directory outside the app project. There, the
client YAML must ride a **framework target** that ships the `.yml` files and exposes its own
bundle via the `ResourceAccess` pattern (`Bundle(for:)` form — see "ResourceAccess.swift —
the two forms" above), fed to the environment:

```swift
MVVMEnvironment(
    appBundle: .main,
    resourceBundles: [ClientViewModelsResourceAccess.localizationBundle],
    // no resourceDirectoryName — see the flattening gotcha below
    ...
)
```

**Naming:** call the accessor `localizationBundle` (the established convention). Never name
it `clientLocalizationStore` — that collides with FOSMVVM's
`MVVMEnvironment.clientLocalizationStore: LocalizationStore?` (different type, same name →
confusing call sites).

### New-framework-target checklist (Xcode template defaults are wrong)

When client-hosted ViewModels live in their own Xcode **framework** target, Xcode's template
leaves it mis-configured in ways the compiler won't catch. Set all five:

1. **`DEVELOPMENT_TEAM`** — the template leaves it **empty** (does not inherit the app's
   team) → ad-hoc signing → the FOS frameworks it embeds carry a **different Team ID** than
   the app → macOS hardened-runtime library validation refuses the load at test time:
   `"…FOSFoundation.framework … not valid for use in process: … different Team IDs"`.
   **The error blames the FOS framework, not the mis-signed framework target** — hours lost
   if you don't know. Set it to the app's team.
2. **`BUILD_LIBRARY_FOR_DISTRIBUTION = NO`** — with `YES`, `@ViewModel`/`@LocalizedString`
   macro expansions can't be represented in the generated `.swiftinterface`:
   `unknown attribute 'MyVM.LocalizedString'`.
3. **Deployment targets** aligned to the app (template defaults lower).
4. **`SWIFT_VERSION = 6.0`** (template defaults to Swift 5).
5. **Link and embed `SPMLibraries` only** — never add FOSFoundation/FOSMVVM to the framework
   directly; that compiles a second copy of the FOS types → `TypeA != TypeA` across target
   boundaries (see "The SPMLibraries umbrella" — this is the LSP/type-identity rule).

### The resource-flattening gotcha (`resourceDirectoryName`)

Xcode **flattens** a framework target's grouped resources into the bundle's resource
**root** — on-disk `Resources/ViewModels/Foo.yml` lands at `…/Resources/Foo.yml`, not under
a `ViewModels/` subdirectory. Consequences:

- **In `MVVMEnvironment`, pass NO `resourceDirectoryName`.** `nil` coalesces to `""`
  ([MVVMEnvironment.swift:174-176](../../../Sources/FOSMVVM/SwiftUI%20Support/MVVMEnvironment.swift)),
  and the YAML search **recurses** from the bundle's resource roots
  (`findFiles` walks the whole tree —
  [URL+Files.swift:23-37](../../../Sources/FOSFoundation/Networking/URL%2BFiles.swift);
  roots at
  [YamlLocalizationStore.swift:103-113](../../../Sources/FOSMVVM/Localization/YamlLocalizationStore.swift)).
  Passing the on-disk subfolder name (`"ViewModels"`) silently searches a path that does not
  exist in the built bundle → zero files → `.noResourcePaths`.
- **In tests, pass the empty string explicitly:**
  `loadLocalizationStore(bundle: …, resourceDirectoryName: "")`. The parameter **defaults to
  `"Resources"`**
  ([LocalizableTestCase.swift:54](../../../Sources/FOSTesting/LocalizableTestCase.swift)),
  which works on macOS (`Contents/Resources/Resources` exists for SPM test bundles) but
  throws `.noResourcePaths` on iOS's **flat** bundles. `""` recurses and is correct on
  **both** platforms.

### Testing reality: run client-VM-framework tests on the iOS Simulator

`xcodebuild build-for-testing` on **macOS** fails at link time (`Ld <framework>`) when a
framework target links the SPM package products: with test targets in the graph, the FOS
products build as separate dynamic `PackageFrameworks/*.framework`s, `SPMLibraries` no
longer *contains* the FOS symbols, and the framework can't resolve them (undefined FOS
symbols). This is a **shared Xcode limitation** — it reproduces identically across multiple
independent FOSMVVM projects, so do not debug it as a project bug. The **iOS Simulator**
builds, links, loads, and passes cleanly (including `expectTranslations`); the macOS **app**
still builds — only *build-for-testing* is affected.

**Default the test plans/schemes for client-VM frameworks to an iOS Simulator destination**
and note why in the scheme or test docs.

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

## The Xcode project is the scaffolder's job, not this skill's

`fosmvvm-bootstrap` emits the `project.yml`, the target graph, the SPMLibraries umbrella, the
signing settings, and the test-target wiring for all three project shapes. It is the source of
truth for project structure; this skill does not restate it.

- **Creating a project** — `swift run fosmvvm-bootstrap new`. See the
  [Creating a Project](../../../Sources/FOSMVVM/FOSMVVM.docc/CreatingAProject.md) article.
- **Auditing an existing one** — `swift package fosmvvm-doctor`, which checks the settings this
  section used to list (`SWIFT_VERSION`, `BUILD_LIBRARY_FOR_DISTRIBUTION`, `TEST_HOST`,
  `DEVELOPMENT_TEAM`, `CODE_SIGN_STYLE`, the hardened runtime, the link and embed graph,
  deployment floors).
- **Why the umbrella exists** — [FOSMVVM Architecture → The SPMLibraries umbrella](../../docs/FOSMVVMArchitecture.md).

The scaffolder generates a project once and does not maintain it: after the finishing checklist
converts the groups to synchronized folders, the `.xcodeproj` is hand-maintained. Everything below
is about that phase — the app's whole life after generation.

## Naming Conventions

| Concept | Convention | Example |
|---------|------------|---------|
| App struct | `{Name}App` | `MyApp`, `StoreApp` |
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
| 1.7 | 2026-07-02 | Fold in the build-verified `fosmvvm-app-project-template.md` (since removed) (copied into this repo): Option-A source inclusion, singular `BUILD_LIBRARY_FOR_DISTRIBUTION` (fixed the plural no-op typo throughout), `{Base}UnitTests`/`{Base}UITests` naming, `TEST_HOST` pin, app-hosted tests, `supportedDestinations`, `.xctestplan` caveat (C3). `.testHost()` no-arg baseline + `underTest` detection via `launchEnvironment` (`__FOS_ViewModel`) not `arguments.count` — verified against `ViewModelViewTestCase.presentView` (C4). "Lifecycle: scaffolds not maintains" — synchronized folders, commit the `.xcodeproj`, keep strict-concurrency (C5). Reinforced `SystemVersion+<App>.swift` naming (C6). |
| 1.8 | 2026-07-02 | Add "Seed the App's `CLAUDE.md`": recommend the scaffolded app repo adopt a "SOLID Is the Foundation" project-conventions entry (drop-in template) so downstream apps inherit FOSMVVM's SOLID discipline and point future sessions at the `fosmvvm-*` skills. |
| 1.9 | 2026-07-03 | Wire in the FOSUtilities API catalog: pointer to `../shared/api-catalog/FOSMVVM.md` (§ SwiftUI Support, § Versioning) near the top, and an "API Discovery" drop-in for the seeded app `CLAUDE.md` referencing the `fosutilities-api-catalog` skill by name only (never a filesystem path — the catalog lives in the installed plugin). |
| 1.10 | 2026-07-23 | Add "Client-Hosted Localization" (field feedback from standing up a first `.clientHostedFactory` VM in an overlay-based Xcode app): encode-time vs bind-time localization concept + `missingLocalizationStore`/`noResourcePaths` symptoms; the resource-carrying framework pattern for overlay projects; the five framework-target settings (`DEVELOPMENT_TEAM`, `BUILD_LIBRARY_FOR_DISTRIBUTION`, deployment targets, `SWIFT_VERSION`, SPMLibraries-only linking); the Xcode resource-flattening gotcha (`resourceDirectoryName` nil ⇒ `""` recurses; tests must pass `""`, not the `"Resources"` default); client-VM-framework tests default to the iOS Simulator (macOS build-for-testing PackageFrameworks link failure); `localizationBundle` naming (never `clientLocalizationStore`). All claims verified against `MVVMEnvironment.swift` / `YamlLocalizationStore.swift` / `URL+Files.swift` / `LocalizableTestCase.swift` / `ViewModelView.swift`. |
| 2.0 | 2026-08-24 | **Re-cut around the app's life, not its creation.** `fosmvvm-bootstrap` (shipped 0.14.0) now emits the App struct, `MVVMEnvironment`, test infrastructure, seeded `CLAUDE.md` and memory files for all three shapes, so this skill's project-creation half was superseded and had begun to drift — its `project.yml` table still read `ENABLE_HARDENED_RUNTIME: YES` for app and tests, while the templates set Debug `NO` / Release `YES` because YES in Debug kills macOS UI testing. Removed: the XcodeGen section, the project file tree, the code-signing section, the file-template list, and the seeded-`CLAUDE.md` instructions — all now the scaffolder's, and audited by `fosmvvm-doctor`. Kept and re-parented: `MVVMEnvironment`, test-view registration, the resource wiring, Client-Hosted Localization (including the hand-added-framework checklist and the `resourceDirectoryName` flattening gotcha), server-hosted contract wiring, deployment configuration. The SPMLibraries type-identity doctrine moved to `.claude/docs/FOSMVVMArchitecture.md`, discharging the never-done item from the bootstrap design §6.7 — it had lived only in this skill and in a template that ships out to customers. |
