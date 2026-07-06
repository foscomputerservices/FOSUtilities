# C8 — VaporResponseBodyFactory: the unified server factory + the write path

**Date:** 2026-07-05
**Status:** Approved by David (live session 2026-07-04/05); dual-reviewed and
reconciled (§11) with David's post-review rulings D-C8-7..9
**Companion:** `2026-07-05-c8-surface-sketch.swift` (rev 3) — signature-normative;
on any prose/sketch conflict the sketch wins.
**Parent:** `2026-07-03-authorized-container-data-loading-architecture.md` §C8
**Depends on:** C6 (engine+cache), C3 (provider auth), C7 (trait+plan+executor)

## 1. Problem

Everything below the author is built — the engine loads auth-scoped records into a
request cache (C6), authorization is provider-driven (C3), the load plan derives
from the composition graph at boot (C7) — but none of it has an author-facing
front door:

- The executor (`Request.executeRecordLoadPlan(for:)`) has **no production
  caller** (deliberate; the C7 final review recorded wiring it as C8's job).
- The shipped server factory hands the projection the **raw `Vapor.Request`** —
  which carries `req.db`. The projection can load: the exact crash-class
  (forgotten load, unscoped query) this architecture exists to kill survives at
  the last step.
- There are **no write routes at all** (`VaporServerRequestHost` registers only
  `GET`), so the post-write refresh ("pass #2") and the write-cycle security
  properties have nowhere to live.
- Non-ViewModel `ResponseBody`s (CLI/report consumers of `ServerRequest`) have
  **no factory path** — `register(viewModel:)` is the only door and it demands
  `RequestableViewModel`.

C8 is the keystone: one author-facing declaration per screen/body, execution
stays load-then-project, and the 8 obligations recorded during C7 land here.

## 2. The two patterns, collapsed (David's framing)

The old factory and the new one are the same job — *server data →
`ResponseBody` → response* — done two ways:

1. **Hand-rolled:** load inside the projection with the whole request in hand.
   Nothing checks, scopes, caches, or re-runs it.
2. **Declared:** the plan loads (auth-scoped, cached, boot-validated,
   refreshed after writes); the projection is a pure function that *couldn't*
   load if it wanted to.

C8 ships pattern 2 as **the** pattern, under the existing name's corrected
form. There is no parallel protocol and no legacy tier.

## 3. Components

### 3.1 `VaporResponseBodyFactory` (FOSMVVMVapor) — replaces `VaporViewModelFactory` (BREAKING)

```swift
public protocol VaporResponseBodyFactory: ServerRequestBody, Vapor.AsyncResponseEncodable {
    associatedtype Request: ServerRequest where Request.ResponseBody == Self
    associatedtype AppState: Sendable = Void
    static func body(context: ProjectionContext<Request, AppState>) throws -> Self
}
```

- **Renamed** because not every `ResponseBody` is a ViewModel
  (`ServerRequest.ResponseBody: ServerRequestBody`; the VM case is the
  `ViewModelRequest` refinement). The factory produces the request's body,
  whatever it is (D-C8-1, D-C8-4).
- **Leaves the `ViewModelFactory` hierarchy** — that shared root requires
  `Self: ViewModel`. `ClientHostedViewModelFactory` stays where it is.
- **`body(context:)`** (OPEN-1 resolved): "model" read naturally only when
  ViewModels were the only product.
- **Synchronous projection** (OPEN-2 resolved): `throws`, never `async`.
  Loading belongs to the load phase (declared requirements, or
  `SupplementalRecordLoading`); an awaitable projection is the hole this type
  closes. This also enforces C7's D-C7-8 (no async down projection)
  structurally.
- Serving is unchanged: the default `AsyncResponseEncodable` conformance
  delegates to the shared `ServerRequestBody.buildResponse(_:)` —
  localization + `SystemVersion` header keep their single home.
- A **zero-data screen** conforms to the factory alone (no trait): no plan,
  no boot guard involved. The C7 adopt-and-declare-nothing fail-fast is
  unchanged (it fires only on trait adopters).

### 3.2 `ProjectionContext` (FOSMVVMVapor, new) — discharges the "ProjectionState" obligation

```swift
public struct ProjectionContext<Request: ServerRequest, AppState: Sendable>: ViewModelFactoryContext {
    public let vmRequest: Request
    public let appState: AppState
    public var appVersion: SystemVersion { get throws }
    public func records<Record: Model>(_ handle: LoadRequirement<Record>) throws -> [Record]
}
```

- **Merged type** (slate 3A): C7's promised separate `ProjectionState` inside a
  context wrapper was a Russian doll with one doll; the context *is* the
  projection state. The C7 obligation is discharged under the merged name; the
  rename is recorded here because C7 documents promised "ProjectionState".
- `records(_:)` reads by the **same static handle the factory declared**. Any
  handle in the request's plan is readable — including a child factory's;
  that is how parents compose children (authored value construction from
  loaded records; the trait guaranteed the data, composition is plain Swift —
  there is **no framework child-projection API**).
- **Fail-fast** (obligation): a handle that never reached the plan throws —
  never `[]`. The public DocC states the *behavior* only ("throws; never
  returns `[]`; names the handle and factory"); the concrete error case is
  `ContainmentError.unplannedRequirement`, which stays **internal** and is
  pinned by an internal test (review fix: an internal type must not be named
  on a public surface). This is also the **runtime closure of the
  conforming-but-unlisted-child gap** (obligation): an unlisted child's
  handles never reach the plan, so its first read throws instead of
  rendering silently empty. The generating macro later upgrades both to
  compile-time diagnoses (unchanged future work).
- No `Vapor.Request`, no `Database`, nothing that can load.
- **Escape contract** (review fix): the context must not escape the
  projection (no capturing it in a spawned `Task`) — reads are contracted to
  the request's handler task, per `ContainerRecordCache`'s sequential-touch
  contract. Documented on the type (consenting-adults posture, as D-C8-2);
  noted beside the cache's contract comment.
- **Seal mechanics across modules** (review fix): `records(_:)` maps an
  opaque handle to its cache entry via the already-sanctioned
  `RecordLoadPlan` **package** site, which gains a handle→tuple lookup
  member; `ProjectionContext` joins that site's named-consumer statement.
  Zero new package **sites** (see §4).

### 3.3 The `AppState` slot + `useAppState` (FOSMVVMVapor, new)

```swift
public extension Vapor.Application {
    func useAppState<AppState: Sendable>(
        _ type: AppState.Type,
        builder: @escaping @Sendable (Vapor.Request) async throws -> AppState)
}
```

- The server twin of `ClientHostedModelFactoryContext.appState`: an
  app-defined value built **in the load phase** by the registered builder
  (full request power is legitimate there), handed to projection as a value.
  `Void` default = zero ceremony.
- Registry keyed by the `AppState` **type**. Boot validation: registering a
  request whose `ResponseBody.AppState != Void` with no builder registered
  fails at `register(request:)` — misconfiguration is a boot error, not a
  first-request surprise. **Double-registering the same `AppState` type is a
  boot error** (review fix: silent last-wins is a guess).
- **The capture-anything hole is accepted** per David's exploitability threat
  model: a typed `Sendable` slot has no prior-art gravity (unlike strings);
  abusing it requires deliberate intent. Escape hatches for consenting adults;
  the contract is documented, not armored (D-C8-2).

### 3.4 `ComposableFactory` (FOSMVVM) — rename + un-pin of `ComposableViewModelFactory` (BREAKING)

```swift
public protocol ComposableFactory: Sendable {
    static var dataRequirements: [any DataRequirement] { get }   // default []
    static var children: [ComposedChild] { get }                 // default []
}
```

- D-C8-4: the VM pin (`: ViewModelFactory`) made "only ViewModels declare
  data" a shipped assumption the factory rename just declared false. Any
  `ResponseBody` producer may adopt. The boot guard, walk, `ComposedChild`,
  and all C7 semantics are unchanged — this is a rename + base-clause change,
  swept through C7's docs/DocC (the word "Composable" survives everywhere).

### 3.5 `DataRequirement` sealed (FOSMVVM) — the freeze decision (BREAKING)

- D-C8-5 (obligation "DECIDE BEFORE RELEASE" resolved): the five public
  members move to an **internal walk-face protocol** (`LoadRequirement`
  conforms; the walk casts to it — same module, no `package`).
  `DataRequirement` becomes a pure public marker.
- A foreign conformance **fails fast at boot** ("unknown requirement kind") —
  the previously open direct-conformance hole closes structurally. The old
  "extension point" was fake OCP: the walk's semantics are closed, so a
  conformer the engine can't honor could never load anyway.
- Sealing is the reversible direction: opening members later is additive;
  freezing them public was forever.

### 3.6 `LoadRequirement` — write-family verbs (new) + pack-based `via:` (BREAKING)

- Verbs `.write` / `.create` / `.delete` arrive (their DocC promise from C7).
  Each **loads the candidate set** its `ContainerOperation` names
  (`.writeRecords` / `.createRecords` / `.deleteRecords`): the records the
  caller is authorized to mutate. A write request's resolved target **must
  belong to the set**. (`.destroy`/`destroyRecords` is deferred until a
  consumer distinguishes it from `.delete` — Defer-API.)
- **Ownership split (D-C8-8, review fix):** `.read` requirements belong to
  factories (`ComposableFactory.dataRequirements`); the write-family verbs
  belong to **write requests** (`WriteTargetProviding.candidates`, §3.8) and
  never enter a factory's `dataRequirements`. A plain GET therefore never
  loads a candidate set; the write route loads exactly one, by construction.
- **`.create` takes no `via:` intermediates** (review fix): a `via:` path can
  fan out to N container instances, and "which container receives the fresh
  record" must never be a guess — the root container *is* the create scope.
  The general fan-out case waits for a consumer (Defer-API).
- D-C8-6: `via:` becomes a parameter pack —
  `via intermediates: repeat (each Hop).Type`, `each Hop: Model` — on all four
  verbs. Call sites are byte-identical. Zero `any` remains on the public
  minting path; the heterogeneous-path erasure (`[any Model.Type]`) lives
  behind the sealed walk face where plumbing belongs. Hop *adjacency* stays
  boot-validated (registry data, not type data).

### 3.7 `TargetedQuery` (FOSMVVM, new) — the write-target selector

```swift
public protocol TargetedQuery: ServerRequestQuery {
    var target: ModelIdentity { get }
}
```

- OPEN-4 resolved. The selector is the **opaque L0 `ModelIdentity`** the
  client received inside a displayed ViewModel, echoed back verbatim —
  the L0 token's first wire payoff. Sibling trait of `RootedQuery` /
  `PaginatedQuery`: one trait per concern.
- **Retarget-proof property** (reinforces seam-invariant #1): the form body
  carries **no `ModelIdType`** (firm rule); the server resolves `target`
  against the candidate set *it loaded itself*. Resolution failure is
  indistinguishable from not-found (**not-yours == not-found**; no
  authorization oracle).

### 3.8 `WriteTargetProviding` + `DataModelWriter` (FOSMVVMVapor, new) — the write twin

```swift
public protocol WriteTargetProviding: Sendable {
    associatedtype Target: DataModel
    static var candidates: LoadRequirement<Target> { get }
}

public protocol DataModelWriter: WriteTargetProviding {
    func apply(to target: Target) throws
}
```

- Slate 4A + review restructure (D-C8-8/9). Adopted by the shared
  `RequestBody` **in the server target** — the mirror of `ResponseBody`
  adopting the factory. Same pattern both directions; Fluent never crosses
  the SPMLibraries boundary.
- **`candidates` — the write request's one candidate set** (D-C8-8): the
  write-verb requirement lives on the writer, not the shared factory graph.
  Exactly one per write request **by construction** — the same-type-ambiguity
  and per-verb-loading gaps close structurally. On a writer, `.parentRoot`
  anchors at the write request's own query root (there is no parent factory).
- **`apply` is sealed: synchronous, no `Database`** (D-C8-9). Pure field
  application needs no I/O; the framework owns ALL of it — loading, saving,
  FK wiring, deletion, refresh. This is the exact mirror of the synchronous
  projection: neither side of the author's code can touch the database. Per
  the exploitability threat model this hole *stays closed* (unlike the
  `AppState` slot): "load in the handler" is a worn footpath with decades of
  prior-art gravity. A db-needing `apply` waits for a named consumer.
- Named for its object (the app's `DataModel`); deliberately **not**
  `VaporRequestBody…` — `Request`/`Response` differing mid-word beside
  `VaporResponseBodyFactory` is the banned confusable pair.
  (`WriteTargetProviding`'s name remains open to David's rename on the final
  read.)
- OPEN-3 resolved: **create uses the same `apply`** — the framework
  instantiates a fresh `Target()` (Fluent's required empty init), calls
  `apply`, saves into the create scope. One authored method covers update and
  create. OPEN-5 resolved: **the framework sets the container FK on create**,
  from the candidate scope — `apply` never names a parent.
- **`DeleteRequest` bodies conform to `WriteTargetProviding` alone**: the
  candidate set is still declared (what may be deleted, from where); deletion
  itself is framework-owned — there is nothing to apply.
- **Write bodies are per-request types, never a shared empty-body type**
  (review fix): the conformance carries `candidates`, so conforming a shared
  framework type would be one global retroactive conformance colliding across
  every delete request in the app. Each write request declares its own
  (possibly empty) `RequestBody`.

### 3.9 The write route (D-C8-3 + D-C8-7) — pass #2 as the refresh request

**The typed bridge (D-C8-7, review fix).** A body type serves exactly one
request (`Request.ResponseBody == Self`), so a write request cannot reuse a
read screen's body directly — "fall through to GET" needs a typed input.
Each write CRUD protocol (`CreateRequest`, `UpdateRequest`, `DeleteRequest`)
gains:

```swift
associatedtype RefreshRequest: ServerRequest
    // constrained: ResponseBody == RefreshRequest.ResponseBody
func refreshRequest() -> RefreshRequest
```

The authored bridge is a pure value mapping in the shared module (~2 lines:
`DockPageRequest(query: .init(dock: query.dock))`). Pass #2 **executes the
refresh request for real** through the genuine GET pipeline — its own plan,
its own refinement axes (which also settles *which* Sort/Pagination the
refreshed body renders under: whatever the authored bridge puts there).

For a request speaking a supported write protocol, the host runs (nothing
authored beyond `apply` + the bridge):

1. middleware binds the typed request (exists)
2. `RequestBody.validate()` — **structural**: `apply` is unreachable otherwise
3. load the writer's `candidates` tuple through the authorized engine —
   the candidate set lands in the cache (the page's read plan is NOT loaded)
4. resolve `Query.target` against the candidate set (not-yours == not-found);
   create needs no target — its candidate scope *is* the destination, **and is
   gated on the grant directly** (AMENDED 2026-07-05, implementation review):
   membership-in-a-loaded-set cannot gate create (a denied `.createRecords`
   load and an authorized-but-empty scope are both `[]` — correctly
   indistinguishable to callers, so the framework must ask the grant question
   itself). An internal grant-verdict check (reusing the per-Request C3 memo;
   no records loaded, no cache write, no new public API) runs before the
   fresh `Target()` is minted; denial throws the same not-found shape as a
   nonexistent destination container — no authorization oracle
5. authored `apply` (update: resolved target; create: fresh `Target()`) —
   or framework delete (no writer method)
6. save + commit; `invalidateContainerRecords(of:)` for the mutated
   containers — the exact caller contract C6 recorded for pass #2
   (records, never grants: the C3 grant memo is per-Request and stands).
   A save/commit failure (e.g., a DB constraint violation) propagates as
   the request's error, same as any thrown step — never a silent partial
7. **serve `refreshRequest()` through the genuine GET pipeline** — execute
   its plan, project its body, `buildResponse`

Pass #2 is not a mechanism; it is step 7 being the same code the read route
runs. The forgotten-re-bind bug class has no place to exist.

HTTP mapping: `CreateRequest → POST`, `UpdateRequest → PATCH`,
`DeleteRequest → DELETE`, reads stay `GET` — derived from the request's CRUD
protocol at registration. **`ReplaceRequest` (PUT) and destroy are deferred**
(Defer-API, review fix): registering one fails fast at boot — "write
protocol not yet supported" — never a silent read-only registration.

### 3.10 Registration surface (FOSMVVMVapor)

```swift
func register<SR: ServerRequest>(request: SR.Type) throws
    where SR.ResponseBody: VaporResponseBodyFactory
```

- Slate 7A: **one door** for every request, VM-bodied or not.
  `register(viewModel:)` is **removed** (zero clients of consequence; one
  door, not two). Plan derivation + boot validation stay in the door, as C7
  built them. The door lives on a `Vapor.Application` extension — grouped/
  `Routes`-level registration is **structurally gone**, which retires the C7
  grouped-path caveat rather than carrying it (review fix: prose now matches
  the sketch).
- **The write door gates at compile time; the read door boot-rejects any
  write-protocol conformer** (review fix, iteration 2): the update/delete
  overloads require `SR.Query: TargetedQuery` and `SR.RequestBody:
  DataModelWriter` (update/create) or `: WriteTargetProviding` (delete) in
  their `where` clauses — but Swift overload resolution means a write request
  *failing* those constraints silently binds the base read overload instead
  of failing to compile. The base door therefore **boot-fails on any
  `CreateRequest`/`UpdateRequest`/`DeleteRequest` conformer** ("write request
  reached the read door — its Query/RequestBody do not satisfy the write
  overload's constraints") — the same runtime write-protocol check the
  `ReplaceRequest` deferral already requires. No silent GET-only mode exists.
- **Boot checks** (fail-fast, never silent): write-protocol conformer at the
  read door (above); unsupported write protocol (`ReplaceRequest`/destroy);
  the writer's candidate tuple's **root source validated** (query root ⇒
  `SR.Query: RootedQuery`; apex root ⇒ resolver registered — the writer-side
  twin of C7's factory-plan validation); non-`Void` `AppState` with no
  registered builder; duplicate `useAppState` type; the existing C7 plan
  validations for the refresh request's factory graph.
- The registration signatures also pin the factory/request identity
  (`SR.ResponseBody.Request == SR` on the read door;
  `SR.RefreshRequest.ResponseBody.Request == SR.RefreshRequest` on the write
  doors) — the handler must construct `ProjectionContext<Factory.Request, _>`
  from the bound or bridged request instance (review advisory; sketch
  signatures are normative).
- `useApexContainerResolver` goes **public unchanged** (slate 6A; obligation
  discharged — `.apex` roots become usable by apps).
- Boot-time **Sort-bridge warn** (obligation discharged): at plan
  registration, a `.refinedByRequest` plan whose request `Sort` is neither
  `EmptySort` nor `SortCriteria`-based logs a warning naming the request and
  the ignored `Sort` type — the silent zero-terms no-op becomes visible.
- **Fixture note** (review advisory): a shared body serving as a write
  request's `ResponseBody` must satisfy the shipped `UpdateResponseBody`/
  `CreateResponseBody` constraints on those CRUD protocols — fixtures adopt
  them alongside the factory.

### 3.11 `SupplementalRecordLoading` goes public (FOSMVVMVapor)

- Name unchanged (slate 7½); C7's internal seam publicized: the load-phase
  escape hatch for data that cannot be declared as containment tuples. Runs
  after the declarative plan (declared records readable); full request power
  (load phase, not projection).
- **Throwing hook propagates** (obligation discharged): a thrown error fails
  the request — never swallowed to an empty result. Same no-silent-guess
  discipline as the declarative path, now a documented public contract with a
  pinning test.

## 4. Access-audit resolutions (arch §6 list)

- **`authorizedBy:` engine entry — REMOVED.** C8 routes every framework
  caller through the provider-driven entry (C3); the demote-or-remove
  question closes on remove.
- **`Application.maxRecordsWarningThreshold` — stays internal.** No
  app-facing consumer appeared; promotion waits for one (Defer-API).
- **The two FOSMVVM `package` sites** (`ModelIdentity.namespace`/`.id`;
  `RecordLoadPlan` + walk) — statements **re-verified at C8**: named
  cross-module consumers unchanged (the Vapor registry/engine; the Vapor
  executor); `public` still forbidden (L0 opacity; walk is not app surface).
  The `RecordLoadPlan` site **gains a handle→tuple lookup member** (named
  consumer: `ProjectionContext.records(_:)` must map a sealed handle to its
  cache entry cross-module); the site's on-file statement is updated to name
  it (review fix — the seal made this the only lawful path).
- **Zero new `package` *sites*** in this slice (grep-enforced in the DoD);
  the two sanctioned FOSMVVM sites may gain members only with updated
  named-consumer statements.

## 5. Kept ceilings (documented, not lifted)

- **`RootedQuery` single-`.query`-root ceiling stands.** No consumer needs
  two query-vended roots in one request; lifting it without a consumer is
  speculative API. Documented in `RootedQuery`'s DocC.
- **Marked-under-guard-diamond guidance** lands as DocC on
  `refinedByRequest` (the C7 rider): a `.refinedByRequest` tuple reached
  through a `.guards` diamond applies the refinement per-anchor; the guidance
  names the declaration-order rule and points at per-relation windows.

## 6. Decisions (all with David, live, 2026-07-04/05)

- **OQ-L1-9 RESOLVED** — no framework mapping mechanism; the write-path seam
  only (committed `85fe3dd`; arch doc reconciled).
- **D-C8-1** one server factory; `Context` narrows (BREAKING); no parallel
  protocol; no legacy tier.
- **D-C8-2** context = `vmRequest` + `appVersion` + typed record reads +
  `AppState` slot (`Void` default, load-phase builder, type-keyed registry);
  hole accepted per the exploitability threat model.
- **D-C8-3** write = validate → plan-load → target-from-Query → authored
  `apply` → commit+invalidate → fall through to GET. Pass #2 is fall-through.
- **D-C8-4** `VaporResponseBodyFactory` name ("not all ResponseBodys are
  ViewModels" — David); `ComposableFactory` un-pinned from ViewModels.
- **D-C8-5** `DataRequirement` sealed: public marker + internal walk face;
  boot fail-fast on foreign conformers. ("We can always open it up later.")
- **D-C8-6** pack-based `via:` on all verbs; erasure behind the seal.
- **OPEN-1..5** resolved as sketched (rev 2 approved whole): `body(context:)`;
  synchronous projection; create-via-fresh-`Target()`+`apply`;
  `TargetedQuery`/`ModelIdentity` selector; framework sets create-FK.
- Naming slate 2A·3A·4A·5A·6A·7A·7½-keep — approved on the sketch cold read.
- **D-C8-7** (post-review, David "go") — the typed refresh bridge: write CRUD
  protocols gain `RefreshRequest` + authored `refreshRequest()`; the write
  request's `ResponseBody == RefreshRequest.ResponseBody` by constraint;
  pass #2 executes the refresh request through the genuine GET pipeline.
- **D-C8-8** (post-review, David "go") — candidate sets live on the write
  side: `WriteTargetProviding.candidates` (name open to rename), exactly one
  per write request by construction; never in a factory's `dataRequirements`;
  GETs never load them.
- **D-C8-9** (post-review, David "go") — `apply` sealed: synchronous, no
  `Database`. Framework owns all I/O on both sides. Hole stays closed per the
  exploitability threat model ("load in the handler" is a worn footpath, the
  opposite of the no-gravity `AppState` slot).

## 7. Breaking changes (pre-1.0, intentional; CHANGELOG entries)

- `VaporViewModelFactory` + `VaporModelFactoryContext` **removed**, replaced
  by `VaporResponseBodyFactory` + `ProjectionContext` (projection loses
  `Vapor.Request`/`req.db` — by design).
- `register(viewModel:)` **removed**, replaced by `register(request:)`.
- `ComposableViewModelFactory` **renamed** `ComposableFactory`; base clause
  drops `ViewModelFactory`.
- `DataRequirement`'s five members **leave the public surface** (sealed).
- `LoadRequirement.read` signature: variadic existential → parameter pack
  (call-site-identical).
- `CreateRequest` / `UpdateRequest` / `DeleteRequest` gain `RefreshRequest` +
  `refreshRequest()` (D-C8-7) — conformers must add the bridge.
- Plan-time verification item: the `@ViewModel` macro's factory-facing
  expansions (C6 showed the macro generates factory glue) must be audited for
  references to the removed/renamed symbols.

## 8. Non-goals (landing zones stated)

- **The generating macro** (compile-time closure of the two listing gaps) —
  unchanged future work; the runtime fail-fasts land now.
- **M2 eager-load collapse** — unchanged (executor optimization; landing zone
  proven in C7).
- **`.destroy` verb / `RecordOperation` tier / threshold promotion /
  multi-root queries** — Defer-API; each waits for a named consumer.
- **Client-hosted conformance of `ComposableFactory`** — the un-pin makes the
  future seam wider (any body, any host), but prefetch/offline remain L2-era
  work.
- **Leaf/HTML rendering of non-VM bodies** — out of scope; `buildResponse`
  serves JSON bodies as today.

## 9. Test groups

1. **Factory routing** — zero-data screen (no trait) serves; composable
   screen serves; non-VM body serves; localization + version header intact
   (buildResponse funnel unchanged).
2. **Executor wiring** — GET on a composable body executes the plan before
   projection; records readable by handle; legacy no-plan configuration
   errors preserved.
3. **ProjectionContext fail-fast** — unplanned handle throws
   `unplannedRequirement`; unlisted-child first read throws; planned handles
   (own + child) read back exactly the cached records.
4. **AppState** — builder runs per request (load phase); `Void` needs no
   registration; non-`Void` without builder fails at `register(request:)`;
   value visible in projection.
5. **Write route: update** — happy path (validate→load candidates→resolve→
   apply→commit→refresh served); the response IS `refreshRequest()`'s body,
   reflecting post-write state, under the refresh request's own refinement
   axes; the page's read plan is NOT loaded pre-apply (candidates only);
   cache invalidated (stale read impossible); grant memo NOT invalidated;
   a save-time DB constraint violation propagates as the request's error.
6. **Write route: create** — fresh `Target()` + same `apply`; framework sets
   the container FK from the candidate scope; created record present in the
   refresh body; `.create` accepts no intermediates (compile-audit).
7. **Write route: delete** — `WriteTargetProviding` alone (no `apply`);
   target gone from the refresh body.
8. **Validation gate** — failing `validate()` never reaches `apply`; error
   propagates through the response path.
9. **Retarget-proofing** — target outside the candidate set ⇒ not-found
   semantics (indistinguishable from missing row); body-borne identity
   impossible by construction (compile-audit: no `ModelIdType` in fixtures'
   RequestBodies); candidate set honors the write verb's operation in
   grant checks; a write request whose writer's candidate tuple is missing
   from the derived write plan fails fast (never resolves against nothing).
10. **Sealed DataRequirement** — foreign conformer rejected at boot with
    "unknown requirement kind"; `LoadRequirement` still walks (behavior
    pinned via plan, not representation).
11. **Pack `via:`** — multi-hop declarations produce identical plans to C7's
    (byte-equal tuples); call sites compile unchanged.
12. **Supplemental hook (public)** — conformer runs post-declarative in walk
    order; thrown error fails the request (never empty).
13. **Sort-bridge boot warn** — foreign `Sort` conformance on a
    `.refinedByRequest` plan logs the warning at registration; `EmptySort`/
    `SortCriteria` stay silent.
14. **Apex publicization** — `.apex`-rooted plan usable through the public
    registration; unresolved apex fails the request (existing semantics
    through the public door).
15. **Boot fail-fasts (registration)** — a write-protocol conformer reaching
    the base read door ⇒ boot error (the overload fall-through is caught,
    never a silent GET-only registration); `ReplaceRequest`/destroy conformer
    ⇒ "write protocol not yet supported"; candidate root-source validation
    (query root without `RootedQuery`; apex root without resolver) ⇒ boot
    error; non-`Void` `AppState` with no builder ⇒ boot error; duplicate
    `useAppState` type ⇒ boot error; overload selection pinned (a
    fully-constrained write request binds the write door); write bodies are
    per-request types (compile/boot audit — no shared empty-body
    conformance).
16. **Refresh bridge typing** — `ResponseBody == RefreshRequest.ResponseBody`
    holds by constraint (compile-audit); the authored bridge's output routes
    through the same code path as a direct GET (pinned by comparing
    responses).

## 10. Definition of done

- All 8 recorded C8 obligations discharged (hook surface; throw-propagate;
  plan-absent-handle fail-fast; unlisted-child runtime closure;
  `ProjectionContext`; Sort-bridge warn; apex publicization; executor wired)
  + the freeze decision executed (sealed).
- Test groups 1–16 green; full suite green; swiftformat/swiftlint clean.
- DocC with examples on every public symbol (customer-framed, written before
  implementation per the planning gate); no internal type named on any public
  surface (incl. the `records(_:)` error — behavior-stated only); no sealed
  representation stated anywhere public; the sketch's obligation labels,
  future-macro notes, and decision-ID citations (D-C8-n) relocated to prose
  (implementer-leak sweep).
- Greps clean: no Fluent/Vapor types (incl. `$`-projections) in FOSMVVM
  sources or comments; zero new `package` *sites* (the two sanctioned FOSMVVM
  sites carry updated named-consumer statements for any new members); no
  `ModelIdType` in any fixture `RequestBody`.
- `VaporViewModelFactory`, `VaporModelFactoryContext`, `register(viewModel:)`,
  and the internal `authorizedBy:` engine entry deleted; no dangling
  references (grep).
- Arch doc §C8: DIRECTION → SPECIFIED (this doc); obligations annotated
  discharged; §6 audit list updated (removed entry, threshold stays,
  package statements re-verified); CHANGELOG carries §7.
- C7 docs swept for the `ComposableFactory` rename; the C7 sketch gains a
  superseded-by note (per the C1/C2 supersession precedent).

## 11. Review reconciliation (2026-07-05, dual review of the initial draft)

Both reviewers ran against the shipped C6/C7 code. Spec-document reviewer:
Issues Found (3); FOSMVVM-discipline reviewer: Sound-with-fixes (6 Important,
3 Minor). All findings folded; the three design-level findings were ruled by
David ("go"):

- **Pass-#2 typing conflict** (both reviewers, the centerpiece finding): a
  body serves one request, so the write route had no typed input for "fall
  through to GET" → **D-C8-7** typed refresh bridge.
- **Candidate-set plan entry** (both): the sketch's write requirement never
  reached a plan; listing it would make GETs load it → **D-C8-8**
  writer-owned candidates (`WriteTargetProviding`), exactly one by
  construction; delete conforms to the base alone (writer-discovery +
  same-type-ambiguity + delete-tuple findings close together).
- **`any Database` in `apply` unjustified** → **D-C8-9** sealed: sync, no db
  (footpath-gravity rationale recorded; contrast with D-C8-2).
- Mechanical folds: internal error type un-named in public DocC (§3.2);
  `RecordLoadPlan` package-site member + "zero new package *sites*" DoD
  wording (§4); `.create` zero-intermediates rule (§3.6); `ReplaceRequest`/
  destroy boot fail-fast (§3.9); compile-time write-overload `where` clauses
  + boot-check list + fixture `UpdateResponseBody` note (§3.10);
  Application-only registration wording aligned to the sketch (§3.10);
  `useAppState` duplicate = boot error (§3.3); `ProjectionContext` escape
  contract (§3.2); authored child-composition annotation (sketch MARK 2);
  implementer-leak DocC sweep named in the DoD (§10); test groups 5–7/9
  updated + 15–16 added (§9).

**Implementation-time amendments (2026-07-05, recorded as found).**
- **§3.9 step 4 amended — the create gate.** The drafted step list gated
  update/delete by candidate-set membership but left create ungated; the T6
  escalated review demonstrated an unauthorized create proceeding (the root
  identity is client-supplied). Amended as marked in §3.9; implementation adds
  an internal grant-verdict primitive beside the engine's memo. Also hardened
  in the same review cycle: `.siblings` create is transactional (no committed
  orphan on a failed pivot attach); candidate verb↔door coherence, `.create`
  path-emptiness, and no-`.refinedByRequest`-on-candidates are boot-validated.
- **Discovered out-of-spec surface:** the pre-existing public
  `ServerRequestController`/`UpdateController` family (raw per-action closures,
  incl. PUT) is a second write door this spec was drafted without knowledge of.
  Zero in-repo consumers. Disposition is David's call (recorded when ruled);
  not modified by C8 tasks.
- **C8a composition correction (David's three rulings, 2026-07-05).** The
  out-of-spec surface above was ruled the keeper: `ServerRequestController` is
  the general dispatch layer, and C8's parallel routing scaffold —
  `VaporServerRequestHost` plus the write doors' inline route registrations —
  is replaced by processors composed onto it (an internal
  `GuardedRequestController` carries `serve`/`serveUpdate`/`serveCreate`/
  `serveDelete` as its `actions`; the register-door signatures and boot-check
  batteries are unchanged). The rulings: (1) `ActionProcessor` is two-arg —
  `@Sendable (Vapor.Request, TRequest) async throws -> TRequest.ResponseBody`,
  the bound instance carrying the middleware-parsed query + sort and, on a
  body verb, the decoded `requestBody`. Note the shift this makes visible: the
  bound instance's `requestBody` is now *populated* on write verbs — identical
  to the explicit `body:` parameter the guarded pipelines receive (previously
  the bound instance carried `requestBody: nil` and the body arrived only as
  the separate argument). (2) All six `ServerRequestAction`s map to HTTP
  methods (`.show` GET, `.create` POST, `.replace` PUT, `.update` PATCH,
  `.delete`/`.destroy` DELETE); `invalidAction` is repurposed from
  "unsupported verb" to the one-URL/one-method boot guard (a controller
  listing both `.delete` and `.destroy` fails fast at boot). (3) The file
  rename `UpdateController.swift` → `ServerRequestController.swift`. Full
  record: docs/superpowers/plans/2026-07-05-c8a-controller-composition.md.

**Iteration 2 (same reviewers, re-dispatched on the reconciled text).**
Spec-document: **Approved** (3 advisories, folded: same-type identity
constraints on the register signatures; bespoke delete `RequestBody` in the
sketch; save-failure surfacing sentence + test pins). Discipline:
**Sound-with-fixes** — all nine priors verified closed and the D-C8-7 bridge
confirmed against DIP/LSP/C6-cache/C3-memo; one new Important + three Minors,
folded: the **overload fall-through** (a write request missing the write
door's constraints binds the read door — closed by boot-failing any
write-CRUD conformer at the base door, §3.10; compile-time claim reworded;
test 15 pins overload selection + rejection); candidate root-source boot
validation (§3.10); per-request write bodies, never a shared empty-body type
(§3.8, sketch MARK 4); decision-ID citations added to the DoD DocC sweep
(§10).
