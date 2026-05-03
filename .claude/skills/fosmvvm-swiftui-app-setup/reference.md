# FOSMVVM SwiftUI App Setup - Reference Templates

Complete file templates for setting up a FOSMVVM SwiftUI application.

> **Conceptual context:** See [SKILL.md](SKILL.md) for when and why to use this skill.
> **Architecture context:** See [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md) for full FOSMVVM understanding.

## Placeholders

| Placeholder | Replace With | Example |
|-------------|--------------|---------|
| `{AppName}` | Your app name (without "App" suffix) | `MyApp`, `Accel` |
| `{AppTarget}` | Main app target name | `App` |
| `{ResourceBundle1}`, `{ResourceBundle2}` | Module names containing localization | `MyAppViewModels`, `SharedResources` |
| `{ProductionURL}` | Production server URL | `https://api.example.com` |
| `{DebugURL}` | Debug/local server URL | `http://localhost:8080` |

---

# Template 1: Basic App Setup (No Test Infrastructure)

For simple apps that don't need UI testing support.

**Location:** `Sources/{AppTarget}/{AppName}App.swift`

```swift
// {AppName}App.swift
//
// Copyright (c) 2026 Your Organization. All rights reserved.
// License: Your License

import {ResourceBundle1}
import FOSFoundation
import FOSMVVM
import SwiftUI

/// Entry point for the application
@main
struct {AppName}App: App {
    var body: some Scene {
        WindowGroup {
            LandingPageView()
        }
        .environment(mvvmEnv)
    }
}

private extension {AppName}App {
    var mvvmEnv: MVVMEnvironment {
        MVVMEnvironment(
            appBundle: Bundle.main,
            resourceBundles: [
                {ResourceBundle1}ResourceAccess.localizationBundle
                // Add additional resource bundles here
            ],
            deploymentURLs: [
                .production: .init(serverBaseURL: URL(string: "{ProductionURL}")!),
                .debug: .init(serverBaseURL: URL(string: "{DebugURL}")!)
            ]
        )
    }
}
```

---

# Template 2: Full App Setup (With Test Infrastructure)

For apps that need comprehensive UI testing support.

**Location:** `Sources/{AppTarget}/{AppName}App.swift`

```swift
// {AppName}App.swift
//
// Copyright (c) 2026 Your Organization. All rights reserved.
// License: Your License

import {ResourceBundle1}
import FOSFoundation
import FOSMVVM
import SwiftUI

// Deployment Notes:
//
// For release builds, the deployment environment is configured via Info.plist:
//
//  1. The CI pipeline sets the FOS_DEPLOYMENT build setting (e.g., "staging" or "production")
//  2. Info.plist contains: FOS-DEPLOYMENT = $(FOS_DEPLOYMENT)
//  3. FOSUtilities reads this value at runtime via Bundle.main.infoDictionary
//
// Expected CI configuration:
//   - Develop branch => deployment: staging
//   - Main branch => deployment: production
//
// The FOSMVVM.Deployment.current property automatically detects the deployment from Info.plist.
// No manual override or #if blocks are needed - detection is automatic.
//
// For local development, you can override via Xcode scheme:
//   Edit Scheme → Run → Arguments → Environment Variables → FOS-DEPLOYMENT = staging

/// Entry point for the application
@main
struct {AppName}App: App {
    #if DEBUG
    @State private var underTest = false
    #endif

    var body: some Scene {
        WindowGroup {
            ZStack {
                LandingPageView()
            }
            #if DEBUG
            .testHost { testConfiguration, testView in
                // Handle specific test configurations if needed
                // switch try? testConfiguration.fromJSON() as MyTestConfiguration {
                // case .specificScenario(let data):
                //     testView.environment(MyState.stub(data: data))
                //         .onAppear { underTest = true }
                //
                // default:
                //     testView.onAppear {
                //         underTest = ProcessInfo.processInfo.arguments.count > 1
                //     }
                // }

                // Default case - always needed
                default:
                    testView
                        .onAppear {
                            // Right now there's no other way to detect if the app is under test.
                            // This is only debug code, so we can
                            // proceed for now.
                            underTest = ProcessInfo.processInfo.arguments.count > 1
                        }
            }
            #endif
        }
        .environment(mvvmEnv)
    }

    init() {
        #if DEBUG
        registerTestingViews()
        #endif
    }
}

private extension {AppName}App {
    var mvvmEnv: MVVMEnvironment {
        MVVMEnvironment(
            appBundle: Bundle.main,
            resourceBundles: [
                {ResourceBundle1}ResourceAccess.localizationBundle
                // Add additional resource bundles here
            ],
            deploymentURLs: [
                .production: .init(serverBaseURL: URL(string: "{ProductionURL}")!),
                .debug: .init(serverBaseURL: URL(string: "{DebugURL}")!)
            ]
        )
    }
}

#if DEBUG
private extension {AppName}App {
    // Every ViewModelView is listed here to enable individualized
    // testing of each view
    @MainActor func registerTestingViews() {
        // Landing Page
        mvvmEnv.registerTestView(LandingPageView.self)

        // Add all your ViewModelViews here
        // Example:
        // mvvmEnv.registerTestView(SettingsView.self)
        // mvvmEnv.registerTestView(DashboardView.self)
    }
}
#endif
```

---

# Template 3: App with Custom Environment Values

For apps that inject additional environment values beyond MVVMEnvironment.

**Location:** `Sources/{AppTarget}/{AppName}App.swift`

```swift
// {AppName}App.swift
//
// Copyright (c) 2026 Your Organization. All rights reserved.
// License: Your License

import {ResourceBundle1}
import FOSFoundation
import FOSMVVM
import SwiftUI

/// Entry point for the application
@main
struct {AppName}App: App {
    @Environment(\.scenePhase) var scenePhase
    @State private var appState: AppState

    #if DEBUG
    @State private var underTest = false
    #endif

    var body: some Scene {
        WindowGroup {
            ZStack {
                LandingPageView()
            }
            #if DEBUG
            .testHost { testConfiguration, testView in
                default:
                    testView
                        .onAppear {
                            underTest = ProcessInfo.processInfo.arguments.count > 1
                        }
            }
            #endif
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .background:
                appState.appEnteredBackground()
            case .inactive:
                break
            case .active:
                appState.appEnteredForeground()
            @unknown default:
                break
            }
        }
        .environment(mvvmEnv)
        .environment(appState)
        .environment(\.colorScheme, .dark)  // Example: Force dark mode
    }

    init() {
        self.appState = AppState()

        #if DEBUG
        registerTestingViews()
        #endif
    }
}

private extension {AppName}App {
    var mvvmEnv: MVVMEnvironment {
        MVVMEnvironment(
            appBundle: Bundle.main,
            resourceBundles: [
                {ResourceBundle1}ResourceAccess.localizationBundle
            ],
            deploymentURLs: [
                .production: .init(serverBaseURL: URL(string: "{ProductionURL}")!),
                .debug: .init(serverBaseURL: URL(string: "{DebugURL}")!)
            ]
        )
    }
}

#if DEBUG
private extension {AppName}App {
    @MainActor func registerTestingViews() {
        mvvmEnv.registerTestView(LandingPageView.self)
    }
}
#endif
```

---

# Template 4: App with Multiple Deployment Environments

For apps that need staging, QA, and production environments.

**Location:** `Sources/{AppTarget}/{AppName}App.swift`

```swift
// {AppName}App.swift
//
// Copyright (c) 2026 Your Organization. All rights reserved.
// License: Your License

import {ResourceBundle1}
import FOSFoundation
import FOSMVVM
import SwiftUI

/// Entry point for the application
@main
struct {AppName}App: App {
    var body: some Scene {
        WindowGroup {
            LandingPageView()
        }
        .environment(mvvmEnv)
    }
}

private extension {AppName}App {
    var mvvmEnv: MVVMEnvironment {
        MVVMEnvironment(
            appBundle: Bundle.main,
            resourceBundles: [
                {ResourceBundle1}ResourceAccess.localizationBundle
            ],
            deploymentURLs: [
                .production: .init(serverBaseURL: URL(string: "https://api.example.com")!),
                .custom("staging"): .init(serverBaseURL: URL(string: "https://staging.api.example.com")!),
                .custom("qa"): .init(serverBaseURL: URL(string: "https://qa.api.example.com")!),
                .debug: .init(serverBaseURL: URL(string: "http://localhost:8080")!)
            ]
        )
    }
}
```

---

# Template 5: Complete Example with Advanced Features

A comprehensive example showing all features together.

**Location:** `Sources/App/MyApp.swift`

```swift
// MyApp.swift
//
// Copyright (c) 2026 Your Organization. All rights reserved.
// License: Your License

import FOSFoundation
import FOSMVVM
import MyAppViewModels
import MyAppViews
import SharedViewModels
import SharedViews
import SwiftUI
import ViewModels

/// Entry point for the application
@main
struct MyApp: App {
    #if DEBUG
    @State private var underTest = false
    #endif
    @Environment(\.scenePhase) var scenePhase
    @State private var appState: MyAppState

    var body: some Scene {
        WindowGroup {
            LandingPageView.bind(
                appState: .init(
                    bindingState: appState.bindingState.modelBindingState
                    // Add other appState properties as needed
                )
            )
            #if DEBUG
            .testHost { testConfiguration, testView in
                switch try? testConfiguration.fromJSON() as TestConfiguration {
                case .scenario1(let data):
                    testView.environment(
                        MyAppState.stub(data: data)
                    )
                    .onAppear {
                        underTest = true
                    }

                case .scenario2(let data):
                    testView.environment(
                        MyAppState.stub(data: data)
                    )
                    .onAppear {
                        underTest = true
                    }

                default:
                    testView
                        .onAppear {
                            underTest = ProcessInfo.processInfo.arguments.count > 1
                        }
                }
            }
            #endif
            .preferredColorScheme(ColorScheme.dark)
            .onAppear {
                loadAppState()
            }
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .background:
                appState.appEnteredBackground()
            case .inactive:
                break
            case .active:
                appState.appEnteredForeground()
            @unknown default:
                break
            }
        }
        .environment(\.colorScheme, .dark)
        .environment(appState)
        .environment(mvvmEnv)
    }

    init() {
        self.appState = MyAppState()

        #if DEBUG
        registerTestingViews()
        #endif
    }

    private func loadAppState() {
        appState.restoreState()
    }
}

private extension MyApp {
    var mvvmEnv: MVVMEnvironment {
        let env = MVVMEnvironment(
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

        #if DEBUG
        env.registerTestingViews()
        #endif

        return env
    }
}

#if DEBUG
private extension MyApp {
    // Every ViewModelView is listed here to enable individualized
    // testing of each view
    @MainActor func registerTestingViews() {
        // Landing Page
        mvvmEnv.registerTestView(LandingPageView.self)

        // Dashboard
        mvvmEnv.registerTestView(DashboardView.self)
        mvvmEnv.registerTestView(CardView.self)

        // Settings
        mvvmEnv.registerTestView(SettingsView.self)
        mvvmEnv.registerTestView(ProfileView.self)
    }
}
#endif
```

---

# Template 6: Wholly Client-Hosted Xcode-Project App

For an app with no project server — every ViewModel uses `@ViewModel(options: [.clientHostedFactory])`. Layout is an Xcode project (not SPM), so `ResourceAccess` uses `Bundle(for:)` and the `disable-library-validation` entitlement is **not** required.

**Layout:**
```
{ProjectName}/
├── {ProjectName}.xcodeproj
├── Sources/
│   ├── ViewModels/                              # framework target
│   │   ├── ViewModelsResourceAccess.swift
│   │   ├── Resources/ViewModels/*.yml
│   │   └── Versioning/SystemVersion+App.swift
│   └── {AppTarget}/
│       ├── App/{AppName}App.swift               # this template
│       ├── App/TestConfiguration.swift          # optional
│       ├── Info.plist
│       └── {AppName}.entitlements
```

**`Sources/ViewModels/ViewModelsResourceAccess.swift`:**
```swift
import Foundation

public enum ViewModelsResourceAccess {
    private final class ResourceAccessClass {}
    public static var localizationBundle: Bundle {
        Bundle(for: ResourceAccessClass.self)
    }
}
```

**`Sources/{AppTarget}/App/{AppName}App.swift`:**
```swift
// {AppName}App.swift
//
// Copyright (c) 2026 Your Organization. All rights reserved.

import FOSFoundation
import FOSMVVM
import SwiftUI
import ViewModels

@main
struct {AppName}App: App {
    #if DEBUG
    @State private var underTest = false
    #endif

    init() {
        #if DEBUG
        registerTestingViews()
        #endif
    }

    private var mvvmEnv: MVVMEnvironment {
        MVVMEnvironment(
            appBundle: Bundle.main,
            resourceBundles: [
                ViewModelsResourceAccess.localizationBundle
            ],
            // Wholly client-hosted: no server. Empty is correct.
            deploymentURLs: [Deployment: MVVMEnvironment.URLPackage]()
        )
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
            }
            #if DEBUG
            .testHost { testConfiguration, testView in
                switch try? testConfiguration.fromJSON() as TestConfiguration {
                // Add one case per scenario that needs container seeding.
                // Each case ends with `.onAppear { underTest = true }`.

                default:
                    testView
                        .onAppear {
                            underTest = ProcessInfo.processInfo.arguments.count > 1
                        }
                }
            }
            #endif
        }
        .environment(mvvmEnv)
    }
}

#if DEBUG
private extension {AppName}App {
    @MainActor func registerTestingViews() {
        // Register every ViewModelView as it is added.
        // mvvmEnv.registerTestView(LandingPageView.self)
    }
}
#endif
```

**`Sources/{AppTarget}/{AppName}.entitlements`** — typical client-hosted contents (CloudKit + push for own-data sync only; **no** `disable-library-validation`):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>aps-environment</key>
    <string>development</string>
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudKit</string>
    </array>
</dict>
</plist>
```

**Notes:**
- No `Package.swift` at the top level — Xcode-managed framework target.
- `ViewModels` framework signs with the app's Team ID, so the SPM `PackageFrameworks` ad-hoc-signing trap does not apply. Do **not** add `com.apple.security.cs.disable-library-validation` unless an `SPMLibraries.framework` umbrella is in use.
- `deploymentURLs` is intentionally empty. Do not invent placeholder production/debug URLs for an app with no project server.
- App-target imports stay minimal: `FOSFoundation`, `FOSMVVM`, `SwiftUI`, `ViewModels`.

---

# Template 7: project.yml (XcodeGen)

A complete XcodeGen spec for a wholly client-hosted FOSMVVM Xcode-project app with three product targets (`ViewModels`, `Models`, `{AppName}`) plus an `SPMLibraries` umbrella and unit/UI test bundles. Modeled on a working FOSMVVM project (ConversationPractice).

**Location:** `project.yml` at repo root.

**Generate:** `xcodegen generate` (commit `project.yml`; treat `.xcodeproj` as derived).

**Placeholders:**

| Placeholder | Replace With | Example |
|---|---|---|
| `{ProjectName}` | Project + app name | `MyApp` |
| `{AppName}` | App target name (often = ProjectName) | `MyApp` |
| `{BundleIdRoot}` | Reverse-DNS bundle id root | `com.example.myapp` |
| `{TeamId}` | Apple developer Team ID | `ABCDE12345` |
| `{iOSDeployment}` | iOS deployment target | `17.0` |
| `{macOSDeployment}` | macOS deployment target | `14.0` |
| `{FOSUtilitiesVersion}` | Tag/branch of FOSUtilities | `from: "1.0.0"` or `branch: main` |

```yaml
name: {ProjectName}
options:
  deploymentTarget:
    iOS: "{iOSDeployment}"
    macOS: "{macOSDeployment}"
  generateEmptyDirectories: true
  createIntermediateGroups: true
  groupSortPosition: top

settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    BUILD_LIBRARIES_FOR_DISTRIBUTION: NO
    DEVELOPMENT_TEAM: {TeamId}
    ENABLE_USER_SCRIPT_SANDBOXING: YES
    SWIFT_TREAT_WARNINGS_AS_ERRORS: YES
    GCC_TREAT_WARNINGS_AS_ERRORS: YES

packages:
  FOSUtilities:
    url: https://github.com/foscomputerservices/FOSUtilities.git
    {FOSUtilitiesVersion}    # e.g. branch: main  OR  from: "1.0.0"

targets:
  # ───────────────────────────── Frameworks ─────────────────────────────

  ViewModels:
    type: framework
    platform: [iOS, macOS]
    sources:
      - path: Sources/ViewModels
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: {BundleIdRoot}.view-models
        GENERATE_INFOPLIST_FILE: YES
    dependencies:
      - target: SPMLibraries
        embed: false           # umbrella is embedded by the app target

  Models:
    type: framework
    platform: [iOS, macOS]
    sources:
      - path: Sources/Models
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: {BundleIdRoot}.models
        GENERATE_INFOPLIST_FILE: YES
    dependencies:
      - target: ViewModels
        embed: false
      - target: SPMLibraries
        embed: false

  # SPMLibraries — the umbrella that holds all external SPM dependencies.
  # The app target embeds-and-signs SPMLibraries; ViewModels/Models only link it.
  SPMLibraries:
    type: framework
    platform: [iOS, macOS]
    sources:
      - path: Sources/SPMLibraries
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: {BundleIdRoot}.spm-libraries
        GENERATE_INFOPLIST_FILE: YES
    dependencies:
      - package: FOSUtilities
        product: FOSFoundation
      - package: FOSUtilities
        product: FOSMVVM
      # Add other external SPM dependencies here ONCE.

  # ───────────────────────────── App ─────────────────────────────

  {AppName}:
    type: application
    platform: [iOS, macOS]
    sources:
      - path: Sources/{AppName}
        excludes:
          - "Info.plist"
          - "{AppName}.entitlements"
      - path: Sources/{AppName}/Info.plist
        buildPhase: none
      - path: Sources/{AppName}/{AppName}.entitlements
        buildPhase: none
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: {BundleIdRoot}
        PRODUCT_NAME: {AppName}
        INFOPLIST_FILE: Sources/{AppName}/Info.plist
        CODE_SIGN_ENTITLEMENTS: Sources/{AppName}/{AppName}.entitlements
        ENABLE_HARDENED_RUNTIME: YES
        MARKETING_VERSION: "1.0"
        CURRENT_PROJECT_VERSION: 1
        TARGETED_DEVICE_FAMILY: "1,2"
    dependencies:
      - target: ViewModels
        embed: true
        codeSign: true
      - target: Models
        embed: true
        codeSign: true
      - target: SPMLibraries
        embed: true
        codeSign: true

  # ───────────────────────────── Tests ─────────────────────────────

  {AppName}Tests:
    type: bundle.unit-test
    platform: [iOS, macOS]
    sources:
      - path: Tests/UnitTests
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: {BundleIdRoot}.unit-tests
        GENERATE_INFOPLIST_FILE: YES
    dependencies:
      - target: {AppName}
      - target: ViewModels
      - target: Models
      - package: FOSUtilities
        product: FOSTesting

  {AppName}UITests:
    type: bundle.ui-testing
    platform: [iOS, macOS]
    sources:
      - path: Tests/UITests
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: {BundleIdRoot}.ui-tests
        GENERATE_INFOPLIST_FILE: YES
        TEST_TARGET_NAME: {AppName}
    dependencies:
      - target: {AppName}
      - package: FOSUtilities
        product: FOSTestingUI

schemes:
  {AppName}:
    build:
      targets:
        {AppName}: all
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - {AppName}Tests
        - {AppName}UITests
    archive:
      config: Release
```

**Notes:**
- **`embed: true` on the app target only.** Frameworks must be embedded-and-signed by exactly one consumer (the app); intermediate frameworks (`ViewModels` linking `SPMLibraries`, `Models` linking `ViewModels`) use `embed: false` to link without re-embedding.
- **`SPMLibraries` is the only target that lists external `package:` dependencies.** Add a new SPM dep here once; downstream targets just `import` from `SPMLibraries`.
- **`BUILD_LIBRARIES_FOR_DISTRIBUTION: NO`** is in `settings.base` so it applies to all targets — setting YES enables module stability you don't need for an in-tree app and breaks `@_spi`/`package` access modifiers.
- **Hardened runtime + Team ID** flow from `settings.base` to all targets, so the SPM `PackageFrameworks` ad-hoc-signing trap (see SKILL.md) does not arise here. Do **not** add `com.apple.security.cs.disable-library-validation` to entitlements unless you specifically need it.
- **Two-platform builds** (`platform: [iOS, macOS]`) generate one target per platform under the hood; XcodeGen handles the multiplexing. Drop `iOS` or `macOS` if you only ship one.

**Regenerate after every edit:**
```bash
xcodegen generate
```

Add to `.gitignore` if you want to exclude the generated project (optional — many teams commit it for IDE-only contributors):
```
{ProjectName}.xcodeproj/
```

---

# Quick Reference: Key Components

## MVVMEnvironment Parameters

```swift
MVVMEnvironment(
    appBundle: Bundle,           // Usually Bundle.main
    resourceBundles: [Bundle],   // Localization bundles from modules
    deploymentURLs: [Deployment: DeploymentURLs]  // URLs per environment
)
```

## Deployment Types

| Deployment | When to Use | Example |
|------------|-------------|---------|
| `.production` | Production environment | Live server |
| `.debug` | Local development | `http://localhost:8080` |
| `.custom("name")` | Custom environments | Staging, QA, etc. |

## Test Infrastructure Components

| Component | Type | Purpose |
|-----------|------|---------|
| `@State private var underTest` | Property | Flag for test mode |
| `.testHost { }` | Modifier | Test configuration handler |
| `registerTestingViews()` | Method | Register views for testing |
| `mvvmEnv.registerTestView()` | Method | Register individual view |

**Important:** The `.testHost { }` modifier must be applied to the **top-level view** in your WindowGroup (the outermost view in the hierarchy). This ensures it wraps the entire view hierarchy and can properly intercept test configurations. Commonly this is a ZStack, VStack, or your root navigation view.

## Resource Bundle Accessors

Each module that contains localization resources should provide a bundle accessor:

```swift
// In your ViewModels module (e.g., MyAppViewModels/ResourceAccess.swift)
public enum MyAppViewModelsResourceAccess {
    public static var localizationBundle: Bundle { Bundle.module }
}
```

Then use it in the App's `resourceBundles` array:

```swift
resourceBundles: [
    MyAppViewModelsResourceAccess.localizationBundle,
    SharedResourceAccess.localizationBundle
]
```

## Common Customizations

### Additional Resource Bundles

```swift
resourceBundles: [
    Module1ResourceAccess.localizationBundle,
    Module2ResourceAccess.localizationBundle,
    Module3ResourceAccess.localizationBundle
]
```

### Multiple Deployment URLs

```swift
deploymentURLs: [
    .production: .init(serverBaseURL: URL(string: "https://api.example.com")!),
    .custom("staging"): .init(serverBaseURL: URL(string: "https://staging.api.example.com")!),
    .custom("qa"): .init(serverBaseURL: URL(string: "https://qa.api.example.com")!),
    .debug: .init(serverBaseURL: URL(string: "http://localhost:8080")!)
]
```

### Group Test View Registration

```swift
@MainActor func registerTestingViews() {
    // Landing
    mvvmEnv.registerTestView(LandingPageView.self)

    // Dashboard
    mvvmEnv.registerTestView(DashboardView.self)
    mvvmEnv.registerTestView(DashboardCardView.self)
    mvvmEnv.registerTestView(DashboardHeaderView.self)

    // Settings
    mvvmEnv.registerTestView(SettingsView.self)
    mvvmEnv.registerTestView(SettingsRowView.self)
}
```

---

# Checklists

## Basic App Setup:
- [ ] `@main` attribute on App struct
- [ ] `var body: some Scene` with WindowGroup
- [ ] Computed `var mvvmEnv: MVVMEnvironment`
- [ ] `.environment(mvvmEnv)` on WindowGroup
- [ ] `appBundle: Bundle.main` configured
- [ ] Resource bundles array populated
- [ ] Deployment URLs configured

## With Test Infrastructure:
- [ ] `@State private var underTest = false` in DEBUG
- [ ] `.testHost { }` modifier on main view
- [ ] Default case with `underTest` detection
- [ ] `init()` method created
- [ ] `registerTestingViews()` extension created
- [ ] `registerTestingViews()` called from `init()`
- [ ] All ViewModelViews registered

## Deployment Configuration:
- [ ] Info.plist contains `FOS-DEPLOYMENT = $(FOS_DEPLOYMENT)`
- [ ] CI pipeline sets `FOS_DEPLOYMENT` build setting
- [ ] Develop branch → staging
- [ ] Main branch → production
- [ ] Local development override documented

---

# Common Patterns

## Pattern 1: Initialize in App.init()

Custom initialization logic goes in `init()`:

```swift
init() {
    // Custom setup
    UserDefaults.standard.set(versionString, forKey: "app-version")

    // Initialize state
    self.appState = MyAppState()

    #if DEBUG
    registerTestingViews()
    #endif
}
```

## Pattern 2: Scene Phase Handling

React to app lifecycle events:

```swift
.onChange(of: scenePhase) {
    switch scenePhase {
    case .background:
        appState.appEnteredBackground()
        Task {
            await performBackgroundTasks()
        }
    case .active:
        appState.appEnteredForeground()
    case .inactive:
        break
    @unknown default:
        break
    }
}
```

## Pattern 3: Conditional Environment Configuration

Customize MVVMEnvironment based on build configuration:

```swift
var mvvmEnv: MVVMEnvironment {
    let env = MVVMEnvironment(
        appBundle: Bundle.main,
        resourceBundles: [...],
        deploymentURLs: [...]
    )

    #if DEBUG
    env.registerTestingViews()
    #endif

    return env
}
```
