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

**`.testHost { }` modifier:**
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
                        underTest = ProcessInfo.processInfo.arguments.count > 1
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
- The default case detects test mode via process arguments
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
        underTest = ProcessInfo.processInfo.arguments.count > 1
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
                underTest = ProcessInfo.processInfo.arguments.count > 1
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
| SPMLibraries umbrella | Optional `Sources/SPMLibraries/SPMLibraries.swift` umbrella to keep SPM dependency wiring out of the app target | N/A |

Default to **Xcode project** for app projects unless there is a specific reason to use SPM at the top level. The Xcode layout sidesteps the PackageFrameworks signing trap and gives natural homes for `Info.plist`, `Assets.xcassets`, and `.entitlements`.

### Sources/ tree (canonical app layout)

```
{ProjectName}/
├── {ProjectName}.xcodeproj          # Xcode project (no Package.swift)
│
├── Sources/
│   ├── ViewModels/                  # SHARED MODULE (framework target)
│   │   ├── ViewModels/              # @ViewModel structs
│   │   ├── Operations/              # Op protocols + StubOps (no live impls)
│   │   ├── Fields/                  # Fields protocols + FieldsMessages
│   │   ├── Errors/                  # ServerRequestError types
│   │   ├── Versioning/
│   │   │   └── SystemVersion+App.swift
│   │   ├── Resources/ViewModels/    # *.yml localization
│   │   └── ViewModelsResourceAccess.swift   # exposes localizationBundle
│   │
│   ├── Models/                      # OPTIONAL framework — @Model classes
│   │
│   ├── SPMLibraries/                # OPTIONAL umbrella — keeps SPM wiring
│   │   └── SPMLibraries.swift       #   out of the app target (Xcode only)
│   │
│   └── {AppTarget}/                 # APP TARGET
│       ├── App/
│       │   ├── {AppName}App.swift   # @main — the file this skill generates
│       │   ├── TestConfiguration.swift   # if .testHost uses typed configs
│       │   └── Assets.xcassets
│       ├── Views/
│       ├── Operations/              # Live op implementations
│       ├── AppState/                # @Observable session state
│       ├── Info.plist
│       └── {AppName}.entitlements
│
└── Tests/
    ├── UnitTests/
    │   └── TestYAML/                # FOSMVVM test fixtures
    └── UITests/
```

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

## Generating the Xcode Project (XcodeGen)

The Xcode-project layout has many easy-to-forget settings that must be set on **every** target: `SWIFT_VERSION = 6.0`, `BUILD_LIBRARIES_FOR_DISTRIBUTION = NO`, embed-and-sign vs. link-only on the app target, `SPMLibraries` umbrella wiring, signing identity, deployment targets, entitlements path, Info.plist path. Configuring these by hand is repetitive and drifts.

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

### The SPMLibraries umbrella, declaratively

`SPMLibraries` exists to keep external SPM dependency wiring out of the app target — it's a thin framework that depends on FOSFoundation/FOSMVVM/etc. and re-vends them. In XcodeGen this is one stanza: `SPMLibraries` is a framework target whose dependencies list every external package product, and the app target depends on `SPMLibraries` (plus `ViewModels` and `Models`).

### What `project.yml` settles in one place

| Setting | Applied to | Why |
|---|---|---|
| `SWIFT_VERSION: 6.0` | All targets via `settings.base` | Must match across the project |
| `BUILD_LIBRARIES_FOR_DISTRIBUTION: NO` | All targets | App is not a library; setting YES bloats build & breaks `@_spi` |
| `ENABLE_HARDENED_RUNTIME: YES` | App + tests | macOS notarization |
| `GENERATE_INFOPLIST_FILE: YES` | Frameworks + tests | Saves writing empty Info.plists |
| `INFOPLIST_FILE: Sources/{App}/Info.plist` | App target only | Carries `FOS-DEPLOYMENT`, `NS*UsageDescription` |
| `CODE_SIGN_ENTITLEMENTS: Sources/{App}/{App}.entitlements` | App target only | CloudKit, audio background, etc. |
| `DEVELOPMENT_TEAM` | All targets via `settings.base` | Avoids the SPM ad-hoc-signing trap |
| Package dependencies on `SPMLibraries` only | App imports just `import {AppModule}` shape | One place to add/remove SPM deps |

See [reference.md](reference.md) Template 7 for the complete `project.yml`.

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
| 1.4 | 2026-05-03 | Add "Generating the Xcode Project (XcodeGen)" section with declarative project setup (`SWIFT_VERSION`, `BUILD_LIBRARIES_FOR_DISTRIBUTION = NO`, signing, `SPMLibraries` umbrella wiring) so the `.xcodeproj` is regenerable from a committed `project.yml`. Add Template 7 to reference.md with a complete `project.yml`. |
