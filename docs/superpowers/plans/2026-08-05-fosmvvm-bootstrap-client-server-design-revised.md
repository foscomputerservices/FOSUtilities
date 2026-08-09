# Client-server (= hybrid) scaffold — REVISED design

**Status:** design for review. No code until approved. Supersedes the design in
`2026-07-25-fosmvvm-bootstrap-plan3-client-server.md` (which came from
FOSShowcase, out of date).

**client-server ≡ hybrid** (David, 2026-08-05): one shape, full feature-set.

**Provenance of this design:**
- **Structure** (umbrella, targets, on-disk, test-target set): the client-server witness app's
  the witness Xcode project, as David corrected it 2026-08-05.
- **The Fluent-backed live + write PATTERN**: FOSUtilities' own API catalog +
  framework + tests — **not** the witness's `.live`-from-in-memory-actor code, which
  David flagged as WIP/over-compensated, not the rule. A Fluent-persisted model
  **auto-emits** live invalidation; the witness's manual projection-key marker exists
  only because its state isn't in Fluent.

---

## 1. The whole shape at a glance

**Two doors over one display-agnostic contract**, plus persistence:

- **Server-fetched door** — a `@ViewModel(options: [.live])` that a
  `ComposableFactory` projects from **Fluent records**; a **write request**
  (`DataModelWriter`) mutates a record and the framework **auto-refreshes** every
  live client through the same body. Localization served on-serve.
- **Client-hosted door** — `.clientHostedFactory` VMs in their own framework,
  localized on-device from the framework bundle.
- **Correlation seam** — a client-hosted VM and a server VM share a key; the
  **view** joins them; never one VM on both doors.
- **The contract stays FOS-only** (no SwiftUI/Vapor/Fluent) so renderers are
  pluggable (§11).

**Placeholder domain:** `Board` (container) → `Card` (record). Obviously a
placeholder to rename. One container, one record, one live read, one write.

---

## 2. Target inventory

### SPM package — `Package.swift`

- **`{{PROJECT_NAME}}ViewModels`** — library. Deps: `FOSFoundation` + `FOSMVVM`
  only. Display-agnostic; no Vapor, no Fluent, no bundled YAML. Holds: the
  ViewModels, the read `Request`, and the write `Request` **type** (its
  `DataModelWriter` conformance is server-side).
- **`{{PROJECT_NAME}}Server`** — executable. Deps: `{{PROJECT_NAME}}ViewModels`
  + `Vapor` + `FOSMVVMVapor` + `Fluent` + `FluentSQLiteDriver` + FOS. Holds: the
  Fluent DataModels + migrations, the `ComposableFactory`/`VaporResponseBodyFactory`
  conformances, the `DataModelWriter` conformance, `configure`/`routes`, and the
  server-hosted YAML (`.copy("../Resources")`).
- **`{{PROJECT_NAME}}ViewModelsTests`** — SPM; contract round-trip/translations.
- **`{{PROJECT_NAME}}ServerTests`** — SPM; **headless** Fluent boot + write +
  live-refresh, via `withFluentTestApp` (SQLite in-memory).

### xcodeproj — `project.yml` → convert to synchronized folders

Mirrors the witness's corrected Xcode project:

- **`SPMLibraries`** — framework; the one FOS doorway (FOSFoundation, FOSMVVM,
  FOSTesting). Nothing else links FOS directly (except UITests → `FOSTestingUI`).
- **`{{PROJECT_NAME}}ClientViewModels`** — framework; the client-hosted door.
  Links+embeds `SPMLibraries.framework`. Holds the `.clientHostedFactory` VMs +
  `Resources/ViewModels/*.yml` + the bundle-access class.
- **`{{PROJECT_NAME}}`** (app) — links+embeds `SPMLibraries.framework` +
  `{{PROJECT_NAME}}ClientViewModels.framework` (both CodeSignOnCopy); **no direct
  FOS**; source-includes `{{PROJECT_NAME}}ViewModels` + the views.
- **`{{PROJECT_NAME}}UnitTests`** — app-hosted (`TEST_HOST` → app); links+embeds umbrella.
- **`{{PROJECT_NAME}}ClientViewModelsTests`** — app-hosted; links+embeds the
  client framework + umbrella; loads its bundle with `resourceDirectoryName: ""` (§7).
- **`{{PROJECT_NAME}}UITests`** — targets the app; links umbrella + `FOSTestingUI`.
- scheme (build all; test the three xcodeproj test targets) + `{{PROJECT_NAME}}.xctestplan`.

**The DataModels live in the SERVER target, never the contract** — `DataModel`
imports Fluent. The contract holds only the display-agnostic VMs + request types.

---

## 3. The server-fetched live+write door (canonical FOSUtilities pattern)

### Contract side (`{{PROJECT_NAME}}ViewModels`, FOS-only)

```swift
@ViewModel(options: [.live])
public struct BoardViewModel: RequestableViewModel {
    public typealias Request = BoardRequest
    @LocalizedString public var title
    public let cards: [CardViewModel]
    public var vmId = ViewModelId()
    public init(cards: [CardViewModel]) { self.cards = cards }
}
```
plus `CardViewModel`, `BoardRequest` (read), and `UpdateCardRequest` (write) with
its `RequestBody` (a `ServerRequestBody` + `ValidatableModel`) and a
`Query: TargetedQuery` naming the target card.

### Server side (`{{PROJECT_NAME}}Server`, imports Fluent + FOSMVVMVapor)

**Models** — a container + a record:
```swift
final class Board: ContainerDataModel, @unchecked Sendable {
    static let schema = "boards"
    @ID(key: .id) var id: ModelIdType?
    @Children(for: \Card.$board) var cards: [Card]
    static var containedRecordTypes: [any FOSMVVM.Model.Type] { [Card.self] }
    static var containment: [ContainmentRelation] { [.children(\Board.$cards)] }
    init() {}
}
final class Card: DataModel, CardFields, Hashable, @unchecked Sendable {
    static let schema = "cards"
    @ID(key: .id) var id: ModelIdType?
    @Parent(key: "board_id") var board: Board
    @Field(key: "title") var title: String
    // init()s, validation messages
}
```
+ their `AsyncMigration`s (`Board.Initial`, `Card.Initial`).

**The live read** — a server-side conformance (keeps the VM Vapor-free):
```swift
extension BoardViewModel: ComposableFactory, VaporResponseBodyFactory {
    static let cards = LoadRequirement.read(Card.self, in: .parentRoot)
    static var dataRequirements: [any DataRequirement] { [cards] }   // stored, never computed
    static func body<R: ServerRequest>(context: ProjectionContext<R, Void>) throws -> Self
        where R.ResponseBody == Self {
        .init(cards: try context.records(Self.cards).map(CardViewModel.init(card:)))
    }
}
```
Plan-loaded Fluent records **auto-register** their live dependency — no manual key.

**The write** — a server-side `DataModelWriter` (field-assignment only):
```swift
extension UpdateCardRequest.RequestBody: DataModelWriter {
    static let candidates = LoadRequirement.write(Card.self, in: .parentRoot)
    func apply(to card: Card) throws { card.title = title }   // no fetch/save/FK here
}
```

**Boot** (`configure`) + **routes**:
```swift
try app.register(Board.self, migration: Board.Initial())
try app.register(Card.self,  migration: Card.Initial())
try app.useContainerAuthorizationProvider(SkeletonAuthProvider())
try app.useLiveInvalidation(on: app)          // walking skeleton: public group
// routes:
try app.register(request: BoardRequest.self,      app: app)   // GET  (live read)
try app.register(request: UpdateCardRequest.self, app: app)   // PATCH (write door, Swift-picked)
```

**The refresh is automatic:** the `DataModelWriter` commit → `InvalidationEmitMiddleware`
emits the containment-derived staleness set (the Card + its owning Board) → live
`BoardViewModel` clients are nudged → they re-fetch through the same `body(context:)`.
No manual `invalidateProjections` on the Fluent path.

**Auth in the skeleton:** a trivial `useContainerAuthorizationProvider` that grants
read+write (the walking skeleton isn't demonstrating auth; the credential-middleware
group is a documented next step). Registration is on the public `app` group.

---

## 4. The client-hosted door

`{{PROJECT_NAME}}ClientViewModels` framework:
- **`AboutViewModel`** — `@ViewModel(options: [.clientHostedFactory])`; a couple of
  `@LocalizedString`s (app name/version blurb). No server round-trip.
- **`Resources/ViewModels/AboutViewModel.yml`** — bundled, client-hosted, two locales.
- **bundle-access class** — `public final class {{PROJECT_NAME}}ClientViewModels`
  with `static var localizationBundle: Bundle { Bundle(for: Self.self) }`.

---

## 5. The correlation seam (documented in place, per spec §6.4)

The seam's rule, wired minimally: a server VM exposes a plain-`String?` key on its
wire shape; a client-hosted VM carries the same key; **the View joins by matching**;
never one VM on both doors.

**Skeleton instance:** `CardViewModel` exposes `ownerTag: String?`; `AboutViewModel`
carries `localOwnerTag: String?`; a view helper highlights "my" cards
(`card.ownerTag == about.localOwnerTag`), with a unit test on the pure join.
DocC on both VMs states the seam contract.

*(Judgment call — see §14: this is the spec's "documented in place" bar with a
minimal wired join. Tell me if you want it richer or lighter.)*

---

## 6. Two localization trees

- **Server** — `Sources/Resources/ViewModels/*.yml`; `.copy`d into the server +
  the SPM tests; loaded `initYamlLocalization(bundle: .module, resourceDirectoryName: "Resources")`;
  resolved **on-serve**.
- **Client** — `Sources/{{PROJECT_NAME}}ClientViewModels/Resources/ViewModels/*.yml`;
  bundled into the framework; resolved **on-device** via `Bundle(for:)`.

## 7. The `resourceDirectoryName: ""` gotcha

The client framework's test loads its bundle with **`""`, not `"ViewModels"`** —
Xcode's CopyBundle flattens the framework's grouped resources to the bundle root
(same flattening as local-only D2). the witness's bundle-access-class DocC still says
`"ViewModels"` — that's stale; `""` is authoritative. The scaffold ships `""`.

## 8. The umbrella wiring

FOS enters through `SPMLibraries.framework` **only**, embedded once (CodeSignOnCopy);
the app + every test bundle link that same framework → one FOS type identity across
them. (My original design linked FOS directly — the core error.)

---

## 9. On-disk layout (everything under `Sources/`, as the witness does)

```
{{PROJECT_NAME}}/
├── Package.swift
├── {{PROJECT_NAME}}.xcodeproj            (from project.yml → convert → delete project.yml)
├── {{PROJECT_NAME}}.xctestplan
├── Sources/
│   ├── {{PROJECT_NAME}}ViewModels/        SHARED contract (SPM lib + source-included); FOS-only
│   │   ├── ViewModels/{Board,Card,About? no}…            (Board/Card VMs)
│   │   └── Requests/{BoardRequest, UpdateCardRequest}
│   ├── Resources/ViewModels/*.yml          SERVER-hosted YAML
│   ├── {{PROJECT_NAME}}Server/             Vapor exe
│   │   ├── entrypoint.swift · configure.swift · routes.swift
│   │   ├── DataModels/{Board,Card}.swift
│   │   ├── Migrations/{Board,Card}+Schema.swift
│   │   ├── Factories/BoardViewModel+Factory.swift        (ComposableFactory + VaporResponseBodyFactory)
│   │   ├── Writers/UpdateCardRequest+Writer.swift        (DataModelWriter)
│   │   └── Auth/SkeletonAuthProvider.swift
│   ├── SPMLibraries/SPMLibraries.swift     umbrella framework (Xcode-only)
│   ├── {{PROJECT_NAME}}ClientViewModels/   client-hosted framework (Xcode-only)
│   │   ├── {{PROJECT_NAME}}ClientViewModels.swift        (bundle-access class)
│   │   ├── AboutViewModel.swift                          (.clientHostedFactory)
│   │   └── Resources/ViewModels/AboutViewModel.yml
│   └── {{PROJECT_NAME}}/                    app (Xcode-only): App, Views, Info.plist, entitlements, assets
└── Tests/
    ├── {{PROJECT_NAME}}ViewModelsTests/     SPM — contract
    ├── {{PROJECT_NAME}}ServerTests/         SPM — headless Fluent boot + write + refresh
    ├── {{PROJECT_NAME}}UnitTests/           Xcode app-hosted
    ├── {{PROJECT_NAME}}ClientViewModelsTests/  Xcode app-hosted (resourceDirectoryName "")
    └── {{PROJECT_NAME}}UITests/             Xcode
```

---

## 10. Headless verification

- **`{{PROJECT_NAME}}ServerTests`** uses FOSTestingVapor's `withFluentTestApp`
  (SQLite `.memory`, `autoMigrate`, `asyncBoot`) — proven headless in FOSUtilities'
  own `WriteRouteTests`/`EmitMiddlewareTests`. The skeleton test: seed a Board+Card,
  PATCH `UpdateCardRequest` through the real pipeline, assert the refreshed
  `BoardViewModel` reflects the write; optionally subscribe to `app.invalidationHub`
  and assert the emitted staleness set.
- **Verifier steps** for the shape:
  `[.swiftBuild, .swiftTest, .xcodegenGenerate, .xcodebuildBuild]` — server side fully
  headless; app side builds via xcodegen+xcodebuild.
- **No headless blockers** — SQLite-only (no Postgres), `asyncBoot` (not `startup()`).

## 11. Display-agnostic contract — forward-looking, NOT scaffolded

`{{PROJECT_NAME}}ViewModels` stays FOS-only + a first-class SPM library — the seam a
future renderer (Leaf/Ignite/React) plugs into. Named as an extension point in the
generated README; **no** extra renderer targets scaffolded.

## 12. What survives / what's rebuilt

- **Survives** (renamed `{{PROJECT_NAME}}`-prefixed): the SPM package skeleton
  (ViewModels lib + Server exe + two SPM test targets), entrypoint/configure/routes
  shape, server-hosted YAML loading, the headless boot test approach.
- **Rebuilt / new:** the entire `project.yml` (umbrella + client framework + app +
  three app-side test targets + testplan); the Fluent models + migrations + container
  registration; the `ComposableFactory` live read; the `DataModelWriter` write; the
  client-hosted door; the correlation seam. The old `WelcomeViewModel` server-fetched
  VM is replaced by the `Board`/`Card` live+writable example.

## 13. A maintenance finding (separate from this work)

The `fosmvvm-serverrequest-generator` skill (through v2.10) still teaches the
**hand-rolled `ServerRequestController` + manual query/save/project**. The API catalog
documents and prefers the newer `register(request:app:)` + `DataModelWriter.apply`
seam. The scaffold uses the **catalog seam**; the skill looks due for an update.

---

## 14. Open items / judgment calls

1. **Correlation-seam depth** (§5) — I've set it at the spec's "documented in place"
   bar plus a minimal wired join + unit test. Richer, lighter, or as-is?
2. **Write verb** — I chose **Update** (`UpdateCardRequest`, `apply(to: existing)`) as
   the simplest `DataModelWriter`. Create (adds a card, framework sets the FK) shows the
   live list *grow* more vividly but adds FK machinery. Update, or Create, or both?
3. **Placeholder domain** — `Board`/`Card`. Rename to your taste (it's the visible
   example every generated project starts from).
4. **Auth** — skeleton ships a trivial grant-all `ContainerAuthorizationProvider` on the
   public group; the credential-middleware group is a documented next step. OK?
