# fosmvvm-bootstrap Plan 3 — client-server Template

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The `fosmvvm-bootstrap` CLI generates a **client-server** FOSMVVM
project (FOSShowcase-shaped: a root `Package.swift` with a shared `ViewModels`
contract library + a Vapor `WebServer` executable, **plus** a SwiftUI app
xcodeproj that source-includes the same `ViewModels` folder) whose walking
skeleton verifies **headlessly** — the server boots in-process and serves the
localized ViewModel route, and the app project builds.

**Architecture:** Extends Plan 2's machine. Config/TokenSet already carry the
app-shape fields (`bundleIdRoot`, `teamId`, `MACOS_DEPLOYMENT`) from Plan 2 —
client-server reuses them unchanged. A `client-server` template tree lands
(Package.swift + shared ViewModels + WebServer + server YAML + app + tests);
`Verifier.steps(for: .clientServer)` becomes the four-step door
`[.swiftBuild, .swiftTest, .xcodegenGenerate, .xcodebuildBuild]`. The Emitter
shape-guard (Plan 2 Task 1) auto-passes the moment `Templates/client-server/`
exists.

**Tech Stack:** Swift 6 / Swift Testing; Vapor 4; FOSMVVMVapor + FOSTestingVapor
(headless boot-and-fetch); XcodeGen + `xcodebuild build … CODE_SIGNING_ALLOWED=NO`.

**Spec:** FOSUtilities `docs/superpowers/specs/2026-07-24-fosmvvm-project-bootstrap-design.md`
(§5 client-server witness, §6.4 server door).

---

## Fact-sheet decisions (2026-07-25 witness survey — `FOS/FOSShowcase` — plus a live API-drift audit against FOSUtilities `main` @ 0.10.0)

**The witness is STALE on the server factory API. Template the current API, not FOSShowcase's.**

- **CS1 — server factory + route registration (DRIFTED; do not copy the witness).**
  FOSShowcase's `LandingPageViewModel+Factory.swift` conforms to
  `VaporViewModelFactory` and `routes.swift` calls `register(viewModel:)`.
  **Both are gone from FOSUtilities 0.10.0.** The current contract, verified in
  source:
  - Server factory: `VaporResponseBodyFactory`
    (`Sources/FOSMVVMVapor/Protocols/VaporResponseBodyFactory.swift:47`), whose
    only requirement is `ResponseBodyFactory.body(context:)`
    (`Sources/FOSMVVM/Protocols/ResponseBodyFactory.swift:38`). A **zero-data**
    body supplies just:
    ```swift
    static func body<R: ServerRequest>(context: ProjectionContext<R, Void>) throws -> Self
        where R.ResponseBody == Self { .init() }
    ```
    No `encodeResponse` override — the protocol extension
    (`VaporResponseBodyFactory.swift:65`) provides it (delegates to the shared
    `buildResponse`, the single localization-on-serve point). Emitting an
    `encodeResponse` would be the red flag that localization leaked its owner.
  - Route registration: `RoutesBuilder.register(request:app:)`
    (`Sources/FOSMVVMVapor/Vapor Support/ViewModelRequest.swift:61`), called as
    `try app.register(request: WelcomeRequest.self, app: app)`.

- **CS2 — no SPMLibraries umbrella (unlike local-only).**
  The app target links `FOSFoundation` + `FOSMVVM` **directly** (SPM package
  product deps in `project.yml`) and **source-includes** the shared
  `Sources/ViewModels` folder (the witness carries it as a
  `PBXFileSystemSynchronizedRootGroup` on the app target — verified in
  `FOSShowcase.xcodeproj/project.pbxproj`). **Why no umbrella here when
  local-only needs one:** local-only has *two* Xcode framework targets
  (`SPMLibraries`, `ViewModels`) + the app, so FOS types cross a target
  boundary → the umbrella gives one canonical type identity. Client-server has
  *one* app target that both links FOS and compiles the contract source
  in-line — nothing crosses a target boundary, so there is no identity problem
  to solve and an umbrella would be dead weight. (The **contract folder is
  compiled twice** — once by the SPM `ViewModels` library for the server, once
  in-line by the app — which is correct and intended; the source is the single
  source of truth, the two builds are two consumers of it.)

- **CS3 — the shared contract is Vapor-free (DIP).**
  `Sources/ViewModels/` imports **only** `FOSFoundation` + `FOSMVVM`. The
  `VaporResponseBodyFactory` conformance (which imports `FOSMVVMVapor` + `Vapor`)
  lives in `Sources/WebServer/ViewModelFactories/`, server-only. The client app
  source-includes `ViewModels` and must never transitively pull in Vapor — the
  ViewModel module never imports the wire/server module; the server adapts.

- **CS4 — server-hosted localization.**
  YAML at `Sources/Resources/ViewModels/*.yml`; the server loads it with
  `try app.initYamlLocalization(bundle: Bundle.module, resourceDirectoryName: "Resources")`.
  The client's `MVVMEnvironment` has **no `resourceBundles`** — the server
  hosts the strings, the client fetches them over the wire. This is the
  client/server tell (spec §6.2 "derived, never asked").

- **CS5 — client `MVVMEnvironment` (server-hosted form).**
  ```swift
  MVVMEnvironment(
      currentVersion: .currentApplicationVersion,
      appBundle: Bundle.main,
      deploymentURLs: [.debug: URL(string: "http://localhost:8080")!]
  )
  ```
  The `[Deployment: URL]` convenience init
  (`Sources/FOSMVVM/SwiftUI Support/MVVMEnvironment.swift:292`). The walking
  skeleton **hardcodes `.debug: http://localhost:8080`** (where the generated
  `WebServer` boots). Production/staging URLs are a finishing-checklist step,
  not a Plan-3 config field — do not invent placeholder prod URLs.

- **CS6 — two-door verify.** `steps(for: .clientServer)` =
  `[.swiftBuild, .swiftTest, .xcodegenGenerate, .xcodebuildBuild]`.
  - Server door is **fully headless**: `swift build` compiles the package
    (contract + server + factory + tests); `swift test` runs the server boot
    tests below. This closes the "app shapes ship CI-unverified test files"
    gap the Plan 2 review flagged for the server half.
  - App door: `xcodegen generate` + `xcodebuild build` (macOS, unsigned) — the
    same leg as local-only. `build-for-testing` is **not** run (same known
    macOS-Ld limitation; app-side test *execution* is a human/Xcode step).

- **CS7 — no Fluent in the skeleton.**
  FOSShowcase carries Fluent/Postgres for its webhook feature; the spec's
  server door (§6.4) needs **no persistence**. The generated `configure.swift`
  wires `SystemVersion` + `initYamlLocalization` + `routes` and nothing else —
  the server boots with no database. Persistence + `.live` invalidation is
  Plan 4's (hybrid) concern. Keeping Fluent out means `swift test` boots the
  real server with zero external services.

- **CS8 — the boot test imports the executable target.**
  `WebServerTests` does `@testable import WebServer` (to bring the
  `VaporResponseBodyFactory` conformance into scope — it is declared in
  `WebServer`, and `WelcomeRequest.ResponseBody == WelcomeViewModel`) plus
  `import FOSTestingVapor`. Importing a Vapor `@main` executable target into a
  test target is supported by SwiftPM (it is the standard modern-Vapor test
  shape). FOSShowcase declares this dependency but ships an **empty**
  `WebServerTests` — so this path is *unproven in the witness*; Task 6's
  integration run is its first real exercise. If the toolchain balks at
  linking the executable into the test, the fallback (documented in Task 6) is
  to split a thin `WebServerCore` library target that both the executable and
  the test import — but attempt the single-executable shape first.

**Walking-skeleton domain:** `Welcome` / `WelcomeViewModel` — the same
FOSShowcase-flavored placeholder as Plan 2 (no customer refs), so the three
shapes stay legible side-by-side.

**Working directory:** `/Users/david/Repository/FOS/fosmvvm-bootstrap`.

**Finish line (scoreboard units):** `fosmvvm-bootstrap new` with a
`clientServer` config produces a project where `swift build` + `swift test`
(server boots + serves the localized route, headless) **and**
`xcodegen generate` + `xcodebuild build` (app) all succeed, and the bootstrap
repo's integration test proves it. **After this plan: 2 of 3 project types
generatable.**

---

### Task 1: Config / TokenSet / Verifier — turn client-server on

Small extension task; no new config fields (Plan 2's `bundleIdRoot` / `teamId`
already apply to every non-`sharedLibrary` shape).

**Files:**
- Modify: `Sources/BootstrapKit/BootstrapConfig.swift`
- Modify: `Sources/BootstrapKit/Verifier.swift`
- Test: `Tests/BootstrapKitTests/BootstrapConfigTests.swift`,
  `Tests/BootstrapKitTests/TokenSetTests.swift`,
  `Tests/BootstrapKitTests/VerifierTests.swift`

**1a. `validate()` — require macOS for client-server too.** The current guard
is `if shape == .localOnly, platforms[.macOS] == nil { throw missingPlatform(.macOS) }`.
Generalize to both app shapes that this repo emits a macOS project for:
```swift
if shape == .localOnly || shape == .clientServer, platforms[.macOS] == nil {
    throw BootstrapConfigError.missingPlatform(.macOS)
}
```
(TokenSet.derive already covers client-server — its `shape != .sharedLibrary`
branch derives `BUNDLE_ID_ROOT` / `TEAM_ID` / `MACOS_DEPLOYMENT`. No change.)

**1b. `Verifier.steps(for:)`** — split client-server off from hybrid:
```swift
case .clientServer: [.swiftBuild, .swiftTest, .xcodegenGenerate, .xcodebuildBuild]
case .hybrid:       [.swiftBuild, .swiftTest] // extended in Plan 4
```

- [ ] **Step 1: failing tests** — add:
```swift
    // BootstrapConfigTests
    @Test func clientServerRequiresMacOSPlatform() throws {
        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .clientServer,
            platforms: [.iOS: "17.0"],
            bundleIdRoot: "com.example.palettepress",
            teamId: "ABCDE12345"
        )
        #expect(throws: BootstrapConfigError.missingPlatform(.macOS)) {
            try config.validate()
        }
    }

    @Test func validClientServerConfigPasses() throws {
        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .clientServer,
            platforms: [.macOS: "14.0"],
            bundleIdRoot: "com.example.palettepress",
            teamId: "ABCDE12345"
        )
        try config.validate()
    }

    // TokenSetTests
    @Test func derivesClientServerTokens() throws {
        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .clientServer,
            platforms: [.macOS: "14.0"],
            bundleIdRoot: "com.example.palettepress",
            teamId: "ABCDE12345"
        )
        let tokens = try TokenSet.derive(from: config)
        #expect(tokens["BUNDLE_ID_ROOT"] == "com.example.palettepress")
        #expect(tokens["TEAM_ID"] == "ABCDE12345")
        #expect(tokens["MACOS_DEPLOYMENT"] == "14.0")
    }

    // VerifierTests
    @Test func clientServerStepsAreTheFourDoorSteps() {
        #expect(Verifier.steps(for: .clientServer)
            == [.swiftBuild, .swiftTest, .xcodegenGenerate, .xcodebuildBuild])
    }
```
- [ ] **Step 2: RED**, **Step 3: implement**, **Step 4: full fast suite GREEN.**
- [ ] **Step 5: commit** — `feat: turn on client-server shape (validate + steps)`

---

### Task 2: shared `ViewModels` contract module

Data-entry (proven by Tasks 6–7). All under
`Sources/BootstrapKit/Templates/client-server/Sources/ViewModels/`.
**Imports only `FOSFoundation` + `FOSMVVM` — no Vapor (CS3).**

**2a. `WelcomeViewModel.swift.tmpl`** — the server-fetched RequestableViewModel:
```swift
// WelcomeViewModel.swift
{{LICENSE_HEADER}}
import FOSFoundation
import FOSMVVM
import Foundation

@ViewModel
public struct WelcomeViewModel: RequestableViewModel {
    public typealias Request = WelcomeRequest

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

**2b. `WelcomeRequest.swift.tmpl`** — the read request. **NB (execution-caught
drift):** FOSShowcase's `LandingPageRequest` is stale — it omits `id` and the
`sort:` init parameter. The FOSShowcase package pins FOSUtilities `branch: main`
(ahead of the floor), where later defaults let the shorter form conform; the
**pinned 0.10.0 floor** requires two things the witness lacks, verified against
the authoritative test conformer `Tests/FOSMVVMVaporTests/TestViewModel.swift`:
- a stored `let id: String` (`ServerRequest: Identifiable`, no `id` default at
  0.10.0), seeded `.random(length: 10)` (a `FOSFoundation` `String` helper);
- the **5-arg designated init** `init(query:sort:fragment:requestBody:responseBody:)`
  (the `sort:`-less 4-arg is only an extension default that *calls* the 5-arg —
  providing only it does NOT satisfy the requirement).
```swift
// WelcomeRequest.swift
{{LICENSE_HEADER}}
import FOSFoundation
import FOSMVVM
import Foundation

public final class WelcomeRequest: ViewModelRequest, @unchecked Sendable {
    public typealias Query = EmptyQuery
    public typealias Fragment = EmptyFragment
    public typealias RequestBody = EmptyBody
    public typealias ResponseError = EmptyError

    public let id: String
    public var responseBody: WelcomeViewModel?

    public init(
        query: EmptyQuery? = nil,
        sort: EmptySort? = nil,
        fragment: EmptyFragment? = nil,
        requestBody: EmptyBody? = nil,
        responseBody: WelcomeViewModel? = nil
    ) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }
}
```

**2c. `SystemVersion+App.swift.tmpl`** — same as Plan 2 (client + server share
the version line; the server calls `SystemVersion.setCurrentVersion(...)`, the
client passes it to `MVVMEnvironment`):
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

**2d. `Sources/Resources/ViewModels/WelcomeViewModel.yml`** — server-hosted,
two locales (en + es), `locale → TypeName → property`:
```yaml
en:
  WelcomeViewModel:
    welcomeTitle: "Welcome"
    welcomeMessage: "Your FOSMVVM client-server app is running."

es:
  WelcomeViewModel:
    welcomeTitle: "Bienvenido"
    welcomeMessage: "Tu aplicación cliente-servidor FOSMVVM está funcionando."
```
(Path note: `Resources` is a **sibling** of `ViewModels` under `Sources/` —
`Sources/Resources/ViewModels/WelcomeViewModel.yml` — matching the witness so
the `.copy("../Resources")` relative paths in Package.swift resolve.)

- [ ] Write 2a–2d. No build yet (needs the Package.swift from Task 4).
- [ ] **Commit** — `feat: client-server shared ViewModels contract + server YAML`

---

### Task 3: `WebServer` Vapor executable

All under `Sources/BootstrapKit/Templates/client-server/Sources/WebServer/`.
**No Fluent (CS7).**

**3a. `entrypoint.swift.tmpl`** — the standard modern-Vapor `@main` (verbatim
from the witness, license-tokenized):
```swift
// entrypoint.swift
{{LICENSE_HEADER}}
import Logging
import NIOCore
import NIOPosix
import Vapor

@main
enum Entrypoint {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)

        let app = try await Application.make(env)

        let executorTakeoverSuccess =
            NIOSingletons.unsafeTryInstallSingletonPosixEventLoopGroupAsConcurrencyGlobalExecutor()
        app.logger.debug(
            "Tried to install SwiftNIO's EventLoopGroup as Swift's global concurrency executor",
            metadata: ["success": .stringConvertible(executorTakeoverSuccess)]
        )

        do {
            try await configure(app)
        } catch {
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            throw error
        }
        try await app.execute()
        try await app.asyncShutdown()
    }
}
```

**3b. `configure.swift.tmpl`** — version + localization + routes, no DB:
```swift
// configure.swift
{{LICENSE_HEADER}}
import FOSFoundation
import FOSMVVM
import Foundation
import Vapor

/// Boots the walking-skeleton server: pins the version, loads the
/// server-hosted localization, and registers the routes. No database —
/// this skeleton has no persistence (add Fluent when you add a model).
public func configure(_ app: Application) async throws {
    SystemVersion.setCurrentVersion(.currentApplicationVersion)

    try app.initYamlLocalization(
        bundle: Bundle.module,
        resourceDirectoryName: "Resources"
    )

    try routes(app)
}
```

**3c. `routes.swift.tmpl`** — the public route via the current API (CS1):
```swift
// routes.swift
{{LICENSE_HEADER}}
import FOSFoundation
import FOSMVVM
import Vapor
import ViewModels

func routes(_ app: Application) throws {
    app.get { _ async in "It works!" }

    // Public (unauthenticated) read route. The served path is derived from
    // the request type — never hand-mount a path prefix (clients derive the
    // same URL from the type; a prefix would desync them and is rejected at
    // boot). Guard privileged routes by registering on a middleware group.
    try app.register(request: WelcomeRequest.self, app: app)
}
```

**3d. `ViewModelFactories/WelcomeViewModel+Factory.swift.tmpl`** — the
server-only projection (CS1 zero-data body):
```swift
// WelcomeViewModel+Factory.swift
{{LICENSE_HEADER}}
import FOSFoundation
import FOSMVVM
import FOSMVVMVapor
import Foundation
import Vapor
import ViewModels

extension WelcomeViewModel: VaporResponseBodyFactory {
    public static func body<R: ServerRequest>(
        context: ProjectionContext<R, Void>
    ) throws -> Self where R.ResponseBody == Self {
        // Zero-data body: no records, no plan — just the constructed value.
        // Its localized strings are applied on serve by the shared
        // buildResponse (via the VaporResponseBodyFactory default), never here.
        .init()
    }
}
```

- [ ] Write 3a–3d. No build yet.
- [ ] **Commit** — `feat: client-server WebServer target (configure, routes, factory)`

---

### Task 4: `Package.swift` template

`Sources/BootstrapKit/Templates/client-server/Package.swift.tmpl`. Derived from
the witness, **stripped to the walking skeleton** (no Ignite, no Leaf app, no
Fluent, no SwiftLint plugin — keep the generated package dependency-lean and
CI-fast):

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "{{PROJECT_NAME}}",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ViewModels", targets: ["ViewModels"]),
        .executable(name: "WebServer", targets: ["WebServer"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/foscomputerservices/FOSUtilities.git",
            from: "{{FOS_VERSION}}"
        ),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.102.0")
    ],
    targets: [
        // Shared contract — client + server both compile this. FOS only;
        // NO Vapor (the client app source-includes this folder).
        .target(
            name: "ViewModels",
            dependencies: [
                .product(name: "FOSFoundation", package: "FOSUtilities"),
                .product(name: "FOSMVVM", package: "FOSUtilities")
            ]
        ),
        .executableTarget(
            name: "WebServer",
            dependencies: [
                .byName(name: "ViewModels"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "FOSFoundation", package: "FOSUtilities"),
                .product(name: "FOSMVVM", package: "FOSUtilities"),
                .product(name: "FOSMVVMVapor", package: "FOSUtilities")
            ],
            resources: [
                .copy("../Resources")
            ]
        ),
        .testTarget(
            name: "ViewModelTests",
            dependencies: [
                .target(name: "ViewModels"),
                .product(name: "FOSFoundation", package: "FOSUtilities"),
                .product(name: "FOSMVVM", package: "FOSUtilities"),
                .product(name: "FOSTesting", package: "FOSUtilities")
            ],
            resources: [
                .copy("../../Sources/Resources")
            ]
        ),
        .testTarget(
            name: "WebServerTests",
            dependencies: [
                .target(name: "WebServer"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "FOSFoundation", package: "FOSUtilities"),
                .product(name: "FOSMVVM", package: "FOSUtilities"),
                .product(name: "FOSMVVMVapor", package: "FOSUtilities"),
                .product(name: "FOSTesting", package: "FOSUtilities"),
                .product(name: "FOSTestingVapor", package: "FOSUtilities")
            ],
            resources: [
                .copy("../../Sources/Resources")
            ]
        )
    ]
)
```

**IMPLEMENTER notes:**
- `swift-tools-version: 6.0` (the witness says 6.2 — pin to the FOS floor's
  6.0 for the widest toolchain, matching Plan 1/2's generated packages).
- The undeclared `Sources/{{PROJECT_NAME}}` (app) and `Sources/Resources`
  directories under `Sources/` are **not** SPM targets — SwiftPM tolerates
  them (the witness does exactly this). The `../Resources` and
  `../../Sources/Resources` `.copy` paths are the witness's proven relative
  reaches; keep them verbatim.
- Confirm `FOSTestingVapor` is a real product of FOSUtilities 0.10.0 during the
  Task 7 run (it is — `Sources/FOSTestingVapor/`); if the product name differs,
  match the shipped `Package.swift` and report the divergence.

- [ ] Write the template. **Do not** `swift build` yet — needs Task 5's app
  files present for a clean tree, but the *package* alone should already
  resolve; a `swift build` here is optional smoke.
- [ ] **Commit** — `feat: client-server Package.swift (lean skeleton, no Fluent)`

---

### Task 5: SwiftUI client app + `project.yml`

All under `Sources/BootstrapKit/Templates/client-server/`.

**5a. `Sources/{{PROJECT_NAME}}/App/{{PROJECT_NAME}}App.swift.tmpl`** — server-hosted
client (CS5); stored `@State` env (same trap-avoidance as Plan 2):
```swift
// {{PROJECT_NAME}}App.swift
{{LICENSE_HEADER}}
import FOSFoundation
import FOSMVVM
import SwiftUI

@main
struct {{PROJECT_NAME}}App: App {
    @State private var mvvmEnv = makeMVVMEnvironment()

    var body: some Scene {
        WindowGroup {
            WelcomeView.bind()
        }
        .environment(mvvmEnv)
    }
}

private extension {{PROJECT_NAME}}App {
    @MainActor static func makeMVVMEnvironment() -> MVVMEnvironment {
        // Server-hosted localization: NO resourceBundles — the server hosts
        // the strings and the client fetches them. `.debug` points at the
        // local WebServer; add .production / .staging when you deploy.
        MVVMEnvironment(
            currentVersion: .currentApplicationVersion,
            appBundle: Bundle.main,
            deploymentURLs: [
                .debug: URL(string: "http://localhost:8080")!
            ]
        )
    }
}
```
(IMPLEMENTER: `WelcomeView.bind()` — the no-argument `.bind()` — is what a
server-fetched `RequestableViewModel` view uses, matching the witness's
`LandingPageView.bind()`. Confirm the `bind()` overload against FOS 0.10.0
during the app build; the `.clientHostedFactory`'s `.bind(appState:)` is a
DIFFERENT overload — do not cross them.)

**5b. `Sources/{{PROJECT_NAME}}/Views/WelcomeView.swift.tmpl`** —
**NB (execution-caught):** the app files must **NOT** `import ViewModels`. The
app *source-includes* the shared contract folder (CS2), so those types are in
the app's **own** module — an `import ViewModels` fails with "no such module".
(Contrast local-only, where `ViewModels` is a separate framework the app *does*
import; and the server's `WebServer` target, which *does* import it.)
```swift
// WelcomeView.swift
{{LICENSE_HEADER}}
import FOSMVVM
import SwiftUI

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
    WelcomeView(viewModel: .stub())
}
```

**5c. `Sources/{{PROJECT_NAME}}/Info.plist`** and
**5d. `{{PROJECT_NAME}}.entitlements`** — identical to Plan 2's local-only
(macOS app; sandbox on; **plus** the network-client entitlement so the app can
reach the server):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```
(The `network.client` entitlement is the shape's real need — a client-server
app talks to a server. It is **not** the `disable-library-validation` symptom
memo warns about; that one is about embedded dylibs, which this shape has none
of.)

**5e. `project.yml.tmpl`** — the app project (**no umbrella**, CS2; app
source-includes both its own sources and the shared `ViewModels` folder; links
FOS directly):
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
  {{PROJECT_NAME}}:
    type: application
    platform: macOS
    sources:
      # The app compiles its own sources AND the shared contract folder
      # in-line (compiled twice — the server compiles the same folder via
      # the SPM ViewModels target). No umbrella: a single app target links
      # FOS directly, so no type crosses a target boundary.
      - path: Sources/{{PROJECT_NAME}}
        excludes:
          - "Info.plist"
          - "{{PROJECT_NAME}}.entitlements"
      - path: Sources/{{PROJECT_NAME}}/Info.plist
        buildPhase: none
      - path: Sources/{{PROJECT_NAME}}/{{PROJECT_NAME}}.entitlements
        buildPhase: none
      - path: Sources/ViewModels
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
      - package: FOSUtilities
        product: FOSFoundation
      - package: FOSUtilities
        product: FOSMVVM

schemes:
  {{PROJECT_NAME}}:
    build:
      targets:
        {{PROJECT_NAME}}: all
    run:
      config: Debug
    archive:
      config: Release
```

**IMPLEMENTER notes:**
- The app scheme lists **no test targets** — the client-server app's automated
  tests are the *server-side* `swift test` (headless); the app project is
  build-verified only (same posture as local-only's app, minus the app-side
  unit/UI test targets which this shape doesn't ship in v1). A human adds SwiftUI
  view tests via the `fosmvvm-ui-tests-generator` skill later; state this in the
  README.
- `Sources/Resources` is **excluded from the app** — the client does not host
  YAML (server-hosted). Do not add it to the app's `sources`.
- The app source-includes `Sources/ViewModels`, which imports `FOSMVVM`. That is
  satisfied by the app's direct `FOSMVVM` product dep. It must **not** pull
  `FOSMVVMVapor` — the factory lives in `Sources/WebServer` (excluded from the
  app), so the app tree stays Vapor-free (CS3).

- [ ] Write 5a–5e.
- [ ] **Commit** — `feat: client-server SwiftUI app + project.yml (no umbrella, source-included contract)`

---

### Task 6: Tests — server boot + fetch (headless) and ViewModel contract

All under
`Sources/BootstrapKit/Templates/client-server/Tests/`.

**6a. `ViewModelTests/WelcomeViewModelTests.swift.tmpl`** — codable + translations,
package-hosted bundle (`Bundle.module`, the test target's copied Resources):
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
        self.locStore = try Self.loadLocalizationStore(
            bundle: Bundle.module,
            resourceDirectoryName: "Resources"
        )
    }
}
```
(IMPLEMENTER: `@LocalizedString` ViewModels need the localizing encoder —
`encoder(locale:)` — in `expectCodable`, exactly as the Plan 2 template does;
this is the gotcha the Plan 2 review baked in. `resourceDirectoryName: "Resources"`
matches the server's `initYamlLocalization` and the `.copy("../../Sources/Resources")`
bundling.)

**6b. `WebServerTests/WelcomeServerTests.swift.tmpl`** — the headless
boot-and-fetch proof, the heart of this plan's server-door verify:
```swift
// WelcomeServerTests.swift
{{LICENSE_HEADER}}
import FOSFoundation
import FOSMVVM
import FOSTesting
import FOSTestingVapor
import Foundation
import Testing
import Vapor
@testable import WebServer
import ViewModels

/// Boots a real Vapor application, serves `WelcomeRequest` through its actual
/// route + server-hosted localization pipeline, and asserts the localized
/// ViewModel comes back — fully headless (no database, no simulator).
@Suite("WelcomeServer", .serialized)
struct WelcomeServerTests {
    @Test func servesLocalizedWelcome_en() async throws {
        let harness = try await VaporServerRequestTest(
            for: WelcomeRequest.self,
            bundle: Bundle.module,
            resourceDirectoryName: "Resources"
        )
        let body = try await harness.test(request: .init(), locale: Self.en)
        #expect(!body.welcomeTitle.isEmpty)
    }

    @Test func servesLocalizedWelcome_es() async throws {
        let harness = try await VaporServerRequestTest(
            for: WelcomeRequest.self,
            bundle: Bundle.module,
            resourceDirectoryName: "Resources"
        )
        let bodyEn = try await harness.test(request: .init(), locale: Self.en)
        let bodyEs = try await harness.test(request: .init(), locale: Self.es)
        // Localization actually varies by Accept-Language.
        #expect(bodyEn.welcomeTitle != bodyEs.welcomeTitle)
    }

    /// The generated `configure`/`routes` register cleanly at boot — proves the
    /// `register(request:)` wiring the CS1 API demands, which `VaporServerRequestTest`
    /// (it mounts its own route) does not exercise.
    @Test func generatedConfigureBoots() async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try await app.asyncBoot()
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    private static let en = Locale(identifier: "en")
    private static let es = Locale(identifier: "es")
}
```

**IMPLEMENTER notes (this task carries the most live-API risk — verify against
0.10.0 during Task 7, fix the *template* on any mismatch, never weaken a test):**
- `VaporServerRequestTest(for:bundle:resourceDirectoryName:)` is the blessed
  headless harness (`Sources/FOSTestingVapor/VaporServerTestCase.swift`). It
  boots with `asyncBoot()` (the async-boot gotcha — sync `app.test()` would skip
  the localization lifecycle). It requires
  `Request.ResponseBody: VaporResponseBodyFactory`; that conformance lives in
  `WebServer`, hence `@testable import WebServer`.
- `Bundle.module` here is **WebServerTests'** bundle (its `.copy` of
  `Sources/Resources`). Confirm the served strings resolve; if the harness wants
  the *server* bundle instead, the fix is the `bundle:` argument, not the YAML.
- `generatedConfigureBoots` imports the executable target (CS8). If the toolchain
  refuses to link `@main WebServer` into the test, apply the CS8 fallback (thin
  `WebServerCore` library) and keep the test — do not delete it; booting the
  generated wiring is the point.
- `Application.make(.testing)` / `.testing` environment: confirm the label; the
  witness uses `Application.make(env)` with a detected env. `.testing` is the
  standard test env — match whatever 0.10.0's FOSTestingVapor harnesses use.

- [ ] Write 6a–6b.
- [ ] **Commit** — `feat: client-server tests — headless server boot + fetch, VM contract`

---

### Task 7: Emitter file-set assertions

**Files:** `Tests/BootstrapKitTests/EmitterTests.swift`

- [ ] **Step 1: failing test** — emit a `clientServer` config (valid, Task-1
  fixture) and assert the full expected relative-path set:
  `Package.swift`, `project.yml`, `README.md`,
  `Sources/ViewModels/WelcomeViewModel.swift`,
  `Sources/ViewModels/WelcomeRequest.swift`,
  `Sources/ViewModels/SystemVersion+App.swift`,
  `Sources/Resources/ViewModels/WelcomeViewModel.yml`,
  `Sources/WebServer/entrypoint.swift`,
  `Sources/WebServer/configure.swift`,
  `Sources/WebServer/routes.swift`,
  `Sources/WebServer/ViewModelFactories/WelcomeViewModel+Factory.swift`,
  `Sources/PalettePress/App/PalettePressApp.swift`,
  `Sources/PalettePress/Views/WelcomeView.swift`,
  `Sources/PalettePress/Info.plist`,
  `Sources/PalettePress/PalettePress.entitlements`,
  `Tests/ViewModelTests/WelcomeViewModelTests.swift`,
  `Tests/WebServerTests/WelcomeServerTests.swift`,
  plus the shared doctrine set (CLAUDE.md + memory/*). Extend the
  token-cleanliness assertion to loop the client-server emitted tree too.
- [ ] **Step 2:** should go GREEN immediately if Tasks 2–5 are complete; any
  missing/misnamed file IS the defect list — fix the templates.
- [ ] **Step 3:** full fast suite green.
- [ ] **Step 4: commit** — `test: client-server emission file-set + token-clean assertions`

---

### Task 8: Integration — the client-server walking skeleton, headless

**Files:** `Tests/BootstrapKitTests/IntegrationTests.swift`

- [ ] **Step 1: add the integration test:**
```swift
    /// Client-server walking-skeleton proof: emit → the four-step door
    /// (swift build + swift test boot the server headless and serve the
    /// localized route; xcodegen + xcodebuild build the app).
    /// Skips cleanly (typed toolMissing) when xcodegen is absent.
    @Test(.timeLimit(.minutes(20)))
    func clientServerWalkingSkeletonBuilds() throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("cs-skeleton-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }

        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .clientServer,
            platforms: [.macOS: "14.0"],
            bundleIdRoot: "com.example.palettepress",
            teamId: "ABCDE12345"
        )
        try Emitter.emit(config: config, into: out)
        try Verifier.verify(
            projectDir: out,
            steps: Verifier.steps(for: .clientServer),
            projectName: "PalettePress"
        )
    }
```
  Notes for the implementer:
  - The first `swift build` inside `out` does a full SPM resolve of FOSUtilities
    + Vapor — the first run can take several minutes. The `.timeLimit` is 20 min.
  - `swift test` runs BOTH package test targets (ViewModelTests + WebServerTests).
    A failure there is a template/API-fact defect — read the captured output in
    the `stepFailed` description and fix the template.
  - `xcodegen`/`xcodebuild` build the app exactly as the local-only leg does.
  - ANY failure is a template defect (or a wrong fact in this plan) — fix the
    template; never weaken the verify.
- [ ] **Step 2: run** — `swift test --filter IntegrationTests` (all skeletons).
- [ ] **Step 3:** the CI workflow already `brew install xcodegen`s before the
  integration leg (Plan 2 Task 7); confirm it covers this test too.
- [ ] **Step 4: full `swift test` green.**
- [ ] **Step 5: commit** — `feat: client-server end-to-end walking-skeleton integration`

---

### Task 9: HandoffChecklist + README status

**Files:**
- Modify: `Sources/BootstrapKit/HandoffChecklist.swift`
- Modify: repo `README.md`

`HandoffChecklist.text(for: .clientServer, projectName:)`:
```
Next steps (things tooling structurally cannot do):
1. git init && git add -A && git commit
2. Server:
   a. swift run WebServer   (boots on http://localhost:8080)
   b. It has NO database — add Fluent + a model when you need persistence.
   c. Set real production / staging deployment URLs in {Name}App.swift.
3. App — open {Name}.xcodeproj in Xcode:
   a. Convert the enumerated source groups to synchronized folders
      (XcodeGen cannot emit PBXFileSystemSynchronizedRootGroup). The
      shared "ViewModels" group is compiled INTO the app on purpose.
   b. Confirm signing: your real DEVELOPMENT_TEAM.
   c. Run the app (it fetches WelcomeViewModel from the local server).
   d. Add iOS/iPadOS destinations if wanted.
4. Delete project.yml; commit the .xcodeproj. Hand-maintained from here.
5. Read CLAUDE.md and memory/ — settled doctrine ships with the project.
6. Add screens via the fosmvvm-viewmodel-generator +
   fosmvvm-serverrequest-generator + fosmvvm-swiftui-view-generator skills;
   add server-side view tests via fosmvvm-ui-tests-generator.
```

- [ ] Implement; fast suite green (absorb any signature fallout).
- [ ] Update repo `README.md`: shapes supported = shared-library, local-only,
  **client-server**; remaining = hybrid, doctor, skill, release CI.
- [ ] **Commit** — `feat: client-server handoff checklist + README status (2 of 3 shapes)`

---

## Out of scope (later plans)

- **hybrid** template (Plan 4) — the two-door overlay + `.live` invalidation +
  Fluent + the correlation seam.
- Auth/credential-grouped route registration — the skeleton ships the public
  `register(request:)`; the credential-group form is a documented next step, not
  generated in v1.
- App-side unit/UI test *execution* in CI (needs simulator boot management —
  deferred with local-only).
- `doctor`, the plugin skill, release CI, example-repo publishing,
  `FOSMVVMArchitecture.md` SPMLibraries section (Plan 5).
