# fosmvvm-bootstrap client-server (= hybrid) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the (wrong, FOSShowcase-derived) client-server template with the witness-derived **client-server ≡ hybrid** template: two doors (server-fetched live+writable via Fluent, and client-hosted), the SPMLibraries umbrella, the full test-target set + testplan, verified headlessly (`swift build` + `swift test` on SQLite-in-memory) and via `xcodegen` + `xcodebuild`.

**Architecture:** The scaffolder machine (Emitter, TokenSet, Verifier, TemplateRenderer, HandoffChecklist) already exists and already turns client-server on (validate + four-step Verifier door). This plan rewrites **only** `Sources/BootstrapKit/Templates/client-server/` plus the emitter/integration test assertions. Template files are data-entry (like Plan 2); correctness is proven by the emitter file-set test (structural) and the integration test (the generated project builds + tests green).

**Tech Stack:** Swift 6 · Vapor 4 · Fluent + FluentSQLiteDriver · FOSMVVM/FOSMVVMVapor/FOSTestingVapor · XcodeGen · `xcodebuild … CODE_SIGNING_ALLOWED=NO`.

**Design of record:** `docs/superpowers/plans/2026-08-05-fosmvvm-bootstrap-client-server-design-revised.md` — READ IT FIRST. Its §3–§10 carry the canonical code shapes; this plan gives file paths, task order, wiring, and verification. Where a FOSMVVM file's exact shape needs a generator skill, the task names the skill; the integration build is the arbiter.

**Working directory:** `/Users/david/Repository/FOS/fosmvvm-bootstrap`.

**Canonical-source rule (David, 2026-08-05):** the Fluent-backed live+write pattern comes from **FOSUtilities' own catalog + tests** (`.claude/skills/shared/api-catalog/FOSMVVMVapor.md`, `Tests/FOSMVVMVaporTests/Containment/WriteFixtures.swift`, `.../WriteRouteTests.swift`, `.../LiveInvalidation/EmitMiddlewareTests.swift`), **not** the witness's `.live`-from-in-memory-actor code (WIP). Fluent-persisted models auto-emit; no manual projection key.

**Settled decisions** (design §14): correlation seam = documented-in-place + a minimal wired join + unit test · write verb = **Update** · domain = **`Board`(container) → `Card`(record)** · auth = trivial grant-all `ContainerAuthorizationProvider` on the public group.

**Naming** (settled): shared contract `{{PROJECT_NAME}}ViewModels` · server exe `{{PROJECT_NAME}}Server` · client-hosted framework `{{PROJECT_NAME}}ClientViewModels` · app `{{PROJECT_NAME}}` · umbrella `SPMLibraries` (fixed).

**Finish line:** `fosmvvm-bootstrap new` with a `clientServer` config produces a project where `swift build` + `swift test` (Fluent boots on SQLite-in-memory; a write refreshes the live VM — headless) **and** `xcodegen generate` + `xcodebuild build` (app) succeed, and the bootstrap repo's integration test proves it. **After this plan: 2 of 3 project types generatable (correctly).**

---

## File structure (what the template emits)

All under `Sources/BootstrapKit/Templates/client-server/`. Tokens: `{{PROJECT_NAME}}` `{{FOS_VERSION}}` `{{LICENSE_HEADER}}` `{{BUNDLE_ID_ROOT}}` `{{TEAM_ID}}` `{{MACOS_DEPLOYMENT}}` (all already derived by TokenSet).

```
Package.swift.tmpl
project.yml.tmpl
README.md.tmpl
{{PROJECT_NAME}}.xctestplan            # committed testplan (references the 3 xcodeproj test targets)
Sources/
  {{PROJECT_NAME}}ViewModels/          # SHARED contract — SPM lib + source-included into app (FOS-only)
    ViewModels/BoardViewModel.swift.tmpl
    ViewModels/CardViewModel.swift.tmpl
    Fields/CardFields.swift.tmpl
    Requests/BoardRequest.swift.tmpl
    Requests/UpdateCardRequest.swift.tmpl
    Versioning/SystemVersion+App.swift.tmpl
  Resources/ViewModels/BoardViewModel.yml   # server-hosted YAML
  Resources/ViewModels/CardViewModel.yml
  {{PROJECT_NAME}}Server/              # Vapor exe (Fluent + FOSMVVMVapor)
    entrypoint.swift.tmpl
    configure.swift.tmpl
    routes.swift.tmpl
    DataModels/Board.swift.tmpl
    DataModels/Card.swift.tmpl
    Migrations/Board+Schema.swift.tmpl
    Migrations/Card+Schema.swift.tmpl
    Factories/BoardViewModel+Factory.swift.tmpl
    Writers/UpdateCardRequest+Writer.swift.tmpl
    Auth/SkeletonAuthProvider.swift.tmpl
  SPMLibraries/SPMLibraries.swift.tmpl # umbrella framework (Xcode-only)
  {{PROJECT_NAME}}ClientViewModels/    # client-hosted framework (Xcode-only)
    {{PROJECT_NAME}}ClientViewModels.swift.tmpl   # bundle-access class
    AboutViewModel.swift.tmpl
    Resources/ViewModels/AboutViewModel.yml
  {{PROJECT_NAME}}/                     # app (Xcode-only)
    App/{{PROJECT_NAME}}App.swift.tmpl
    Views/BoardView.swift.tmpl
    Views/AboutView.swift.tmpl
    Info.plist
    {{PROJECT_NAME}}.entitlements
Tests/
  {{PROJECT_NAME}}ViewModelsTests/WelcomeGone_BoardViewModelTests.swift.tmpl   # SPM
  {{PROJECT_NAME}}ServerTests/BoardServerTests.swift.tmpl                       # SPM (headless Fluent)
  {{PROJECT_NAME}}UnitTests/{{PROJECT_NAME}}UnitTests.swift.tmpl                # Xcode app-hosted
  {{PROJECT_NAME}}ClientViewModelsTests/AboutViewModelTests.swift.tmpl         # Xcode app-hosted
  {{PROJECT_NAME}}UITests/{{PROJECT_NAME}}UITests.swift.tmpl                    # Xcode
```

**Prior art to copy patterns from** (cite, don't reinvent):
- Umbrella `SPMLibraries.swift` + `project.yml` umbrella/app/test wiring: the **local-only** template (`Templates/local-only/`) — same umbrella discipline; adapt.
- Server boot / factory / request shapes: design §3 + FOSUtilities `Tests/FOSMVVMVaporTests/Containment/WriteFixtures.swift`.
- Fluent model + migration: `fosmvvm-fluent-datamodel-generator` skill; `CardFields`: `fosmvvm-fields-generator` skill.
- Headless server test: FOSTestingVapor `withFluentTestApp` + `Tests/FOSMVVMVaporTests/Containment/WriteRouteTests.swift`.
- Client-hosted framework + bundle-access + `resourceDirectoryName: ""`: design §4/§7 + the witness's client-hosted ViewModels framework.

---

### Task 1: Reset the old client-server template + its test assertions

The earlier FOSShowcase-derived template and its emitter/integration assertions are wrong and must go before the redesign lands. (Config/Verifier changes from `e823ba7` stay — they're correct.)

**Files:**
- Delete: `Sources/BootstrapKit/Templates/client-server/` (entire tree)
- Modify: `Tests/BootstrapKitTests/EmitterTests.swift` (remove `emitsClientServerFileSet`, `clientServerEmissionContainsNoTokens`)
- Modify: `Tests/BootstrapKitTests/IntegrationTests.swift` (remove `clientServerWalkingSkeletonBuilds`)

- [ ] **Step 1:** `git rm -r Sources/BootstrapKit/Templates/client-server`
- [ ] **Step 2:** Delete the three named test methods. Add a temporary guard test so the shape isn't silently emittable:
```swift
    @Test func clientServerHasNoTemplateYet() throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("emit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        #expect(throws: EmitterError.shapeNotImplemented("client-server")) {
            _ = try Emitter.emit(config: makeClientServerConfig(), into: out)
        }
    }
```
- [ ] **Step 3:** `swift test --skip IntegrationTests` → green (the shape now cleanly reports unimplemented).
- [ ] **Step 4: Commit** — `chore: reset client-server template for the witness-derived redesign`

---

### Task 2: `Package.swift` template

**Files:** Create `Templates/client-server/Package.swift.tmpl`

- [ ] **Step 1:** Write it — SPM: `{{PROJECT_NAME}}ViewModels` lib (FOSFoundation+FOSMVVM), `{{PROJECT_NAME}}Server` exe (+ Vapor, Fluent, FluentSQLiteDriver, FOSMVVMVapor; `resources: [.copy("../Resources")]`), `{{PROJECT_NAME}}ViewModelsTests` (FOSTesting; `.copy("../../Sources/Resources")`), `{{PROJECT_NAME}}ServerTests` (FOSTestingVapor + Fluent + FluentSQLiteDriver + Vapor; `.copy("../../Sources/Resources")`). `swift-tools-version: 6.0`; `platforms: [.macOS("{{MACOS_DEPLOYMENT}}")]`. Vapor `from: "4.102.0"`, fluent `from: "4.9.0"`, fluent-sqlite-driver `from: "4.6.0"`, FOSUtilities `from: "{{FOS_VERSION}}"`.
- [ ] **Step 2: Commit** — `feat: client-server Package.swift (Fluent + FOSMVVMVapor)`

---

### Task 3: Shared contract — Board/Card VMs, Fields, requests

Client-safe (`FOSFoundation` + `FOSMVVM` only; NO Vapor/Fluent). Shapes from design §3.

**Files (Create):**
- `Sources/{{PROJECT_NAME}}ViewModels/ViewModels/BoardViewModel.swift.tmpl` — `@ViewModel(options: [.live]) struct BoardViewModel: RequestableViewModel`, `typealias Request = BoardRequest`, `@LocalizedString title`, `let cards: [CardViewModel]`, `vmId`, init, `stub()`.
- `.../ViewModels/CardViewModel.swift.tmpl` — `@ViewModel struct CardViewModel`, `@LocalizedString`? no — `let title: String`, `let ownerTag: String?` (correlation key, design §5), `vmId`, init(card:)? no (that's server-side). Plain init + `stub()`. **CardViewModel is client-safe — no Fluent init here.**
- `.../Fields/CardFields.swift.tmpl` — minimal `CardFields` form protocol (a `title` field + messages) per `fosmvvm-fields-generator`. Card (server) and `UpdateCardRequest.RequestBody` conform.
- `.../Requests/BoardRequest.swift.tmpl` — `ViewModelRequest`, all `Empty*`, real `ResponseError` (a `reason: String`), the **5-arg `sort:` init**, `responseBody: BoardViewModel?`. (See design §3 / the witness `DocksRequest`; confirm `id` need at the pinned floor per the earlier drift lesson.)
- `.../Requests/UpdateCardRequest.swift.tmpl` — an `UpdateRequest`; `Query: TargetedQuery` naming the target card; `RequestBody` (`ServerRequestBody` + `ValidatableModel` + `CardFields`) carrying the new `title`; `ResponseBody = BoardViewModel` (write re-serves the board). Derive exact `UpdateRequest`/`TargetedQuery` shape from `fosmvvm-serverrequest-generator` **catalog seam** (NOT the controller template) + FOSUtilities `WriteFixtures.swift` (`UpdateBerthRequest`).
- `.../Versioning/SystemVersion+App.swift.tmpl` — `static let currentApplicationVersion = .init(major:0,minor:1,patch:0)`.

- [ ] **Step 1:** Write all files (tokenized, `{{LICENSE_HEADER}}` header).
- [ ] **Step 2: Commit** — `feat: client-server shared contract (Board/Card VMs, fields, requests)`

---

### Task 4: Server DataModels + migrations

Server-only (`{{PROJECT_NAME}}Server`, imports Fluent + FOSMVVMVapor). Design §3; pattern from `fosmvvm-fluent-datamodel-generator` + FOSUtilities `ContainmentFixtures.swift`.

**Files (Create):**
- `Sources/{{PROJECT_NAME}}Server/DataModels/Board.swift.tmpl` — `final class Board: ContainerDataModel, @unchecked Sendable`; `schema "boards"`; `@ID(key:.id) var id: ModelIdType?`; `@Children(for: \Card.$board) var cards`; `containedRecordTypes: [Card.self]`; `containment: [.children(\Board.$cards)]`.
- `.../DataModels/Card.swift.tmpl` — `final class Card: DataModel, CardFields, Hashable, @unchecked Sendable`; `schema "cards"`; `@ID`; `@Parent(key:"board_id") var board`; `@Field(key:"title") var title`; timestamps; the `cardValidationMessages` init-first rule; `ownerTag` as a `@Field` if it is persisted (else derive it in the factory).
- `.../Migrations/Board+Schema.swift.tmpl` — `Board.Initial: AsyncMigration` (`.id()` + timestamps).
- `.../Migrations/Card+Schema.swift.tmpl` — `Card.Initial: AsyncMigration` (`.id()`, `.field("board_id", .uuid, .required, .references("boards","id"))`, `.field("title", .string, .required)`, timestamps).

- [ ] **Step 1:** Write all files. **Step 2: Commit** — `feat: client-server Fluent DataModels + migrations (Board container, Card record)`

---

### Task 5: Server factory, writer, auth

Server-only. The DIP split: conformances live here, VMs stay in the contract.

**Files (Create):**
- `Sources/{{PROJECT_NAME}}Server/Factories/BoardViewModel+Factory.swift.tmpl` —
```swift
extension BoardViewModel: ComposableFactory, VaporResponseBodyFactory {
    static let cards = LoadRequirement.read(Card.self, in: .parentRoot)
    static var dataRequirements: [any DataRequirement] { [cards] }
    static func body<R: ServerRequest>(context: ProjectionContext<R, Void>) throws -> Self
        where R.ResponseBody == Self {
        .init(cards: try context.records(Self.cards).map { CardViewModel(title: $0.title, ownerTag: $0.ownerTag) })
    }
}
```
  (Adjust `ownerTag` source per Task 4's decision.)
- `.../Writers/UpdateCardRequest+Writer.swift.tmpl` —
```swift
extension UpdateCardRequest.RequestBody: DataModelWriter {
    static let candidates = LoadRequirement.write(Card.self, in: .parentRoot)
    func apply(to card: Card) throws { card.title = title }
}
```
- `.../Auth/SkeletonAuthProvider.swift.tmpl` — a trivial `ContainerAuthorizationProvider` granting read+write for the walking skeleton (derive the exact protocol from FOSMVVMVapor `Containment` + `WriteFixtures.swift`'s test grant helper). DocC: "grant-all skeleton auth — replace with a credential-scoped provider; see the fosmvvm-serverrequest generator + §Middleware."

- [ ] **Step 1:** Write all files. **Step 2: Commit** — `feat: client-server server factory + writer + skeleton auth`

---

### Task 6: Server boot — entrypoint, configure, routes

**Files (Create):**
- `Sources/{{PROJECT_NAME}}Server/entrypoint.swift.tmpl` — the standard modern-Vapor `@main enum Entrypoint` (copy from the earlier reset template's entrypoint — it was correct).
- `.../configure.swift.tmpl` —
```swift
public func configure(_ app: Application) async throws {
    SystemVersion.setCurrentVersion(.currentApplicationVersion)
    switch app.environment {
    case .testing: app.databases.use(.sqlite(.memory), as: .sqlite)
    default:       app.databases.use(.sqlite(.file(Environment.get("DB_PATH") ?? "db.sqlite")), as: .sqlite)
    }
    try app.register(Board.self, migration: Board.Initial())
    try app.register(Card.self,  migration: Card.Initial())
    try await app.autoMigrate()
    try app.useContainerAuthorizationProvider(SkeletonAuthProvider())
    try app.initYamlLocalization(bundle: Bundle.module, resourceDirectoryName: "Resources")
    try app.useLiveInvalidation(on: app)
    try routes(app)
}
```
  (Confirm `useContainerAuthorizationProvider` / `useLiveInvalidation(on:)` signatures against the pinned floor during Task 9.)
- `.../routes.swift.tmpl` —
```swift
func routes(_ app: Application) throws {
    app.get { _ async in "It works!" }
    try app.register(request: BoardRequest.self, app: app)      // GET (live read)
    try app.register(request: UpdateCardRequest.self, app: app)  // PATCH (write; Swift-picked)
}
```

- [ ] **Step 1:** Write all files. **Step 2: Commit** — `feat: client-server server boot (configure registers models + live invalidation, routes read+write)`

---

### Task 7: Server-hosted YAML

**Files (Create):**
- `Sources/Resources/ViewModels/BoardViewModel.yml` — en/es for `title`.
- `Sources/Resources/ViewModels/CardViewModel.yml` — en/es (only if CardViewModel has `@LocalizedString`s; if `CardViewModel` is plain data, this file is omitted — reconcile with Task 3).

- [ ] **Step 1:** Write. **Step 2: Commit** — `feat: client-server server-hosted YAML`

---

### Task 8: SPM tests — contract + headless Fluent boot/write/refresh

**Files (Create):**
- `Tests/{{PROJECT_NAME}}ViewModelsTests/BoardViewModelTests.swift.tmpl` — `LocalizableTestCase`; `expectCodable`/`expectTranslations` for `BoardViewModel` (+ `CardViewModel`), `loadLocalizationStore(bundle: .module, resourceDirectoryName: "Resources")`, locales `[en, es]`, `.serialized`.
- `Tests/{{PROJECT_NAME}}ServerTests/BoardServerTests.swift.tmpl` — `@testable import {{PROJECT_NAME}}Server` + `FOSTestingVapor`; uses `withFluentTestApp` to: configure (register models + localization + `useLiveInvalidation`), seed a Board+Card, PATCH `UpdateCardRequest` through the real pipeline, assert the refreshed `BoardViewModel` reflects the new title. Model on FOSUtilities `WriteRouteTests.swift::patchRoutesThroughRealPipeline`.

- [ ] **Step 1:** Write both. **Step 2: Commit** — `feat: client-server SPM tests (contract + headless Fluent write/refresh)`

---

### Task 9: SPM-side reality check (the hard part, headless)

Prove the SPM half compiles + tests green **before** the xcodeproj work — this is where the FOSMVVM/Fluent facts get verified. The Xcode-only files don't exist yet, so emit-via-CLI isn't possible; instead assemble the package directly.

- [ ] **Step 1:** Add a temporary `IntegrationTests` method `clientServerSPMHalfIsGreen` that emits into a temp dir **after** stub Xcode files exist — OR simpler: hand-render the SPM subset into a scratch dir and run `swift build && swift test`. (Executor's choice; the goal is a green server half.)
- [ ] **Step 2:** Run it. Fix template/API-fact defects (read captured output). Likely fixes: the `UpdateRequest`/`TargetedQuery` shape, `ContainerAuthorizationProvider` protocol name, `useLiveInvalidation(on:)` arg, the `id`/5-arg-init on requests (the pinned-floor drift lesson).
- [ ] **Step 3:** Iterate to green. **Step 4: Commit** — `test: client-server SPM half green (Fluent live+write headless)`

---

### Task 10: SPMLibraries umbrella (Xcode framework source)

**Files (Create):** `Sources/SPMLibraries/SPMLibraries.swift.tmpl` — copy the local-only umbrella file **with its full type-identity rationale comment** (design §8; the stripped form is the relapse vector). It carries no FOS imports in code; the umbrella role is the xcodeproj framework target (Task 11).

- [ ] **Step 1:** Write. **Step 2: Commit** — `feat: client-server SPMLibraries umbrella source`

---

### Task 11: Client-hosted framework — AboutViewModel + bundle access

**Files (Create):**
- `Sources/{{PROJECT_NAME}}ClientViewModels/{{PROJECT_NAME}}ClientViewModels.swift.tmpl` — the bundle-access class (design §4): `public final class {{PROJECT_NAME}}ClientViewModels { public static var localizationBundle: Bundle { Bundle(for: Self.self) } }`.
- `.../AboutViewModel.swift.tmpl` — `@ViewModel(options: [.clientHostedFactory]) struct AboutViewModel`; a couple `@LocalizedString`s (app name/version blurb); `localOwnerTag: String?` (correlation key, design §5); `stub()`.
- `.../Resources/ViewModels/AboutViewModel.yml` — en/es.

- [ ] **Step 1:** Write. **Step 2: Commit** — `feat: client-server client-hosted framework (AboutViewModel + bundle access)`

---

### Task 12: Correlation seam — join helper + unit test

**Files (Create/Modify):**
- Modify `CardViewModel` (Task 3) to carry `ownerTag: String?`; `AboutViewModel` (Task 11) carries `localOwnerTag: String?`. Add DocC on both stating the seam contract (design §5).
- Create a pure join helper (in the app or a shared view helper) `isMine(card:about:) -> Bool { card.ownerTag != nil && card.ownerTag == about.localOwnerTag }`.
- The unit test lives in the app-side `{{PROJECT_NAME}}UnitTests` (Task 16), asserting the pure join.

- [ ] **Step 1:** Wire the keys + DocC + helper. **Step 2: Commit** — `feat: client-server correlation seam (documented + pure join)`

---

### Task 13: `project.yml` — umbrella + client framework + app + 3 test targets

Adapt the **local-only** `project.yml` (same umbrella discipline) to the client-server target set (design §2, §8; the witness wiring). Targets: `SPMLibraries` (framework, links FOSFoundation/FOSMVVM/FOSTesting), `{{PROJECT_NAME}}ClientViewModels` (framework; links+embeds SPMLibraries), `{{PROJECT_NAME}}` (app; links+embeds SPMLibraries + ClientViewModels; source-includes `Sources/{{PROJECT_NAME}}ViewModels` + Views; **no direct FOS**), `{{PROJECT_NAME}}UnitTests` (app-hosted), `{{PROJECT_NAME}}ClientViewModelsTests` (app-hosted; links+embeds ClientViewModels + umbrella), `{{PROJECT_NAME}}UITests` (targets app; links umbrella + FOSTestingUI). Scheme builds all, tests the three test targets.

**Files (Create):** `Templates/client-server/project.yml.tmpl`

- [ ] **Step 1:** Write. **Step 2: Commit** — `feat: client-server project.yml (umbrella, client framework, app, 3 test targets)`

---

### Task 14: Committed `.xctestplan`

**Files (Create):** `Templates/client-server/{{PROJECT_NAME}}.xctestplan` — references the three xcodeproj test targets by NAME (XcodeGen re-mints identifiers; the plan must match by name — verify XcodeGen emits matching blueprints, else the finishing checklist notes a one-time Xcode re-add). Model on the witness's xctestplan (name-keyed testTargets).

- [ ] **Step 1:** Write. **Step 2: Commit** — `feat: client-server xctestplan`

---

### Task 15: The app — @main, views, Info.plist, entitlements

**Files (Create):**
- `Sources/{{PROJECT_NAME}}/App/{{PROJECT_NAME}}App.swift.tmpl` — stored-`@State` `MVVMEnvironment` carrying **both doors** (design §5):
```swift
MVVMEnvironment(
    currentVersion: .currentApplicationVersion,
    appBundle: Bundle.main,
    resourceBundles: [{{PROJECT_NAME}}ClientViewModels.localizationBundle],
    deploymentURLs: [.debug: URL(string: "http://localhost:8080")!]
)
```
  (The `resourceDirectoryName` for the client bundle — pin during Task 18, per §7 `""` gotcha.) `BoardView.bind()` on the window; `.testHost()` + `registerTestingViews()` in DEBUG. App files **do NOT `import {{PROJECT_NAME}}ViewModels`** (source-included → same module); they DO `import {{PROJECT_NAME}}ClientViewModels` (separate framework).
- `Sources/{{PROJECT_NAME}}/Views/BoardView.swift.tmpl` — `ViewModelView` rendering the board title + cards.
- `Sources/{{PROJECT_NAME}}/Views/AboutView.swift.tmpl` — renders `AboutViewModel`.
- `Sources/{{PROJECT_NAME}}/Info.plist` — macOS app plist (as local-only).
- `Sources/{{PROJECT_NAME}}/{{PROJECT_NAME}}.entitlements` — sandbox + `com.apple.security.network.client`.

- [ ] **Step 1:** Write. **Step 2: Commit** — `feat: client-server app (both-door MVVMEnvironment, views, plist, entitlements)`

---

### Task 16: App-side test templates

**Files (Create):**
- `Tests/{{PROJECT_NAME}}UnitTests/{{PROJECT_NAME}}UnitTests.swift.tmpl` — a minimal app-hosted unit test; include the correlation-seam pure-join assertion (Task 12).
- `Tests/{{PROJECT_NAME}}ClientViewModelsTests/AboutViewModelTests.swift.tmpl` — `LocalizableTestCase`; `expectFullViewModelTests(AboutViewModel.self)`; `loadLocalizationStore(bundle: {{PROJECT_NAME}}ClientViewModels.localizationBundle, resourceDirectoryName: "")` (§7 gotcha); a sibling `locales` extension `[en, es]`.
- `Tests/{{PROJECT_NAME}}UITests/{{PROJECT_NAME}}UITests.swift.tmpl` — minimal XCUIApplication launch + first-screen exists (as local-only).

- [ ] **Step 1:** Write. **Step 2: Commit** — `feat: client-server app-side test templates`

---

### Task 17: Emitter file-set + token-clean assertions

**Files (Modify):** `Tests/BootstrapKitTests/EmitterTests.swift` (replace the Task-1 temporary guard test).

- [ ] **Step 1:** Assert the full emitted relative-path set for a `clientServer` config (every file above, project-name-substituted, `.tmpl` dropped) + the shared doctrine set; extend token-cleanliness across the emitted tree.
- [ ] **Step 2:** `swift test --filter EmitterTests` green (fix any path/name mismatch — the failure list IS the defect list).
- [ ] **Step 3: Commit** — `test: client-server emission file-set + token-clean assertions`

---

### Task 18: Integration — the full headless+app walking skeleton

**Files (Modify):** `Tests/BootstrapKitTests/IntegrationTests.swift`

- [ ] **Step 1:** Add `clientServerWalkingSkeletonBuilds` — emit a `clientServer` config into a temp dir, then `Verifier.verify(steps: .clientServer, projectName:)` = `swift build` + `swift test` (Fluent SQLite-in-memory; the write/refresh test) + `xcodegen generate` + `xcodebuild build`. `.timeLimit(.minutes(25))`.
- [ ] **Step 2:** Run `swift test --filter clientServerWalkingSkeletonBuilds`. Debug **SPM-first** from captured output (steps run in order); ANY failure is a template defect — fix the template, never weaken the verify. Watch for: the `import {{PROJECT_NAME}}ViewModels` app-side error (source-included → remove), the request `id`/5-arg-init drift, the write/auth/live API signatures.
- [ ] **Step 3:** Confirm CI already `brew install xcodegen`s before the integration leg.
- [ ] **Step 4:** Full `swift test` green. **Commit** — `feat: client-server end-to-end walking-skeleton integration`

---

### Task 19: HandoffChecklist + README

**Files (Modify):** `Sources/BootstrapKit/HandoffChecklist.swift`; `Templates/client-server/README.md.tmpl`; repo `README.md`.

- [ ] **Step 1:** `HandoffChecklist.text(for: .clientServer, projectName:)`: git init → `swift run {{PROJECT_NAME}}Server` (SQLite file; boots on :8080) → open the xcodeproj, convert to synchronized folders, confirm signing, run the app (fetches the Board, edits a Card, watches it refresh) → delete project.yml → read CLAUDE.md/memory → extend via the fosmvvm-* generator skills → **display-tech extension point** (design §11).
- [ ] **Step 2:** `README.md.tmpl`: the two-door shape, the umbrella, server-hosted vs client-hosted localization, the live+write flow, the display-agnostic contract seam.
- [ ] **Step 3:** Repo `README.md`: shapes supported = shared-library, local-only, **client-server**; remaining = doctor, plugin skill, release CI.
- [ ] **Step 4:** Full suite green. **Commit** — `feat: client-server handoff checklist + README (2 of 3 shapes)`

---

## Out of scope

Nothing here is dropped — deferrals are **tracked** in `fosmvvm-bootstrap/docs/deferrals.md`
(reviewed before the next plan). This plan defers:

- **Genuinely deferred (future/unproven):** additional display technologies
  (Leaf/Ignite/React) — extension point documented, not scaffolded.
- **Tracked pending work** (see the ledger, not dropped): `doctor` · plugin skill
  wrapper · release CI · example-repo publishing · `FOSMVVMArchitecture.md`
  SPMLibraries section (Plan 5) · the credential-middleware auth group · updating
  the `fosmvvm-serverrequest-generator` skill to the catalog write seam.
