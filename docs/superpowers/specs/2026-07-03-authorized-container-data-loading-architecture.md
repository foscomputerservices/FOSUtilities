# Authorized Container Data Loading — Architecture (Layer 1)

**Status:** Architecture / reconciliation. Not yet implemented. **Draft for review.**
**Date:** 2026-07-03
**Layer:** 1 of 3 — the container / authorized-data-loading subsystem.
**Targets:** FOSMVVM (shared vocabulary) + FOSMVVMVapor (Fluent-coupled mechanism).
**Depends on:** Layer 0 (`2026-07-03-model-identity-foundation-design.md`).
**Consumed by:** Layer 2 (live invalidation).
**Sits under:** `2026-07-03-live-viewmodel-invalidation-architecture.md` (the 0→1→2 north star). That
doc frames the whole arc around *live invalidation*; this doc is the truth for L1's world, which is
large enough (≈9 interacting components, three of them absent from the north-star's §4 sketch) to
earn its own architecture.

> **This is an "Architecture is Truth" artifact.** Its job is **not** to specify every internal now.
> Its job is to **lock the seams between components** so each component's internals can mature — or
> stay explicitly TBD ("a miracle occurs here") — *without reopening the frame*. The recurring cost
> this prevents: relitigating the whole system every time one piece is detailed. Detailed per-component
> specs (and plans) are spawned *from* this document; some components stay TBD until a consumer forces
> them.

---

## How to read this

Each component carries a **maturity marker**:

- **SPECIFIED** — designed and (for L0) planned/committed; the contract is fixed.
- **PARTIAL** — the shape and seams are known; internals need a detailed spec.
- **DIRECTION** — the intended approach is chosen; the mechanism is sketched, not proven.
- **TBD** — a genuine open problem; the *seam* is fixed here, the *internals* are marked "miracle here."

Where a component maps to a proven prior-art pattern, that is noted generically as **[prior art]** —
this subsystem is a *refinement of a production-proven design*, re-rooted on stronger foundations
(§2). No prior-art system, client, or proprietary type is named anywhere in this document.

Running example throughout (from the north star): a **`Dock`** *contains* **`Berth`s** and carries
per-dock **access grants**. "All docks in the system" is an *unbounded* container view.

---

## 1. Purpose — and the failure it exists to prevent

FOSMVVM can resolve a single ViewModel from a request, but it has **no formalized way for *any*
`ServerRequest` to load the authorized, filtered, sorted *set* of records it must act on**, and no
request-scoped record cache — today the package contains *zero* Fluent queries and no record loading
of any kind. Layer 1 introduces that machinery.

**This spans every `ServerRequest` semantic, not just reads.** The same auth-scoped load serves the
whole CRUD family: a `ViewModelRequest` (read) *projects* the set into a ViewModel; a create needs the
scope to know the subject may create in the container and that the new record lands in an authorized one;
an update/replace/delete/destroy needs its target to be *in* the loaded set. The ViewModel projection is
merely the read path's consumer of that set (and pass #2's re-projection after a write). This is exactly
why the load is a request-level boundary, not a projection detail — seam-invariant #1 (§4).

The design is governed by one hard-won failure the prior art hit and never cleanly solved: **the
knowledge of "what data do I need loaded" lived with the composable ViewModel piece, but the
*declaration* of what to load lived far away at the top-level request.** Nothing tied the two together,
so composition was not actually compositional — dropping a child ViewModel in silently required editing
a distant load list, and forgetting to was **a runtime crash at composition time**, not a compile
error. Component 7 (Composition & data-requirements aggregation) exists to make that failure
*structurally impossible*, and several other components are shaped by that goal.

## 2. This is a refinement, not an invention

The container / record / authorization / load model distilled here is a **production-proven** pattern
for authorized, filtered, sorted collection loading behind an MVVM projection. FOSUtilities' contribution
is to re-root it on stronger foundations:

- **Sealed, opaque identity** (`ModelIdentity`, L0) replaces a type-erased `(id + Type)` reference whose
  `Codable` needed a **process-global** string→Type registry. Here the registry is **injected** (§ C4).
- **KeyPath sorting** replaces stringly-typed order-by columns — a limitation the prior art itself
  had flagged as needing to change.
- **First-class, client-chosen sort** on the request (§ C3) — an opportunity the prior art missed
  (sort was hard-coded server-side).
- **DIP-clean framework/app boundary** (§3): the framework depends on an authorization *abstraction*,
  never a concrete role/subject table.
- **Injected dependencies over globals** throughout (registry, authorization provider, invalidation
  channel), preserving parallel-test isolation.
- **SPMLibraries boundary respected**: Fluent/persistence types never cross onto the shared `Model` /
  `ServerRequest` surface.

## 3. The organizing cut — framework vs application

The single most important structural decision, because it governs every component: **FOSUtilities ships
the generic loading/authorization *machinery and vocabulary*; the application owns the concrete
authorization record, the subject (user), and the role/permission model.** The prior-art principle
tags make the line for us — the loading engine, operation vocabulary, type registry, and
request-materialization are *broadly transferable* infrastructure; the concrete role/subject
authorization model is *app-flavored*.

| Concern | Home | Why |
|---|---|---|
| `Container`, `containedRecordTypes`, `ContainerOperation` + `authorizesXXX` | **FOSMVVM** | generic vocabulary |
| `ServerRequestSort` / `SortCriteria` / filter / pagination | **FOSMVVM** | wire contract |
| `ContainerAuthorization` **protocol** + the DI seam for "current authorizations" | **FOSMVVM(+Vapor)** | the abstraction the engine depends on |
| Fluent-derived `containment` (cardinality), the injected `ModelNamespace→Model.Type` registry, the load engine, request-scoped cache, the unified factory | **FOSMVVMVapor** | Fluent-coupled |
| The concrete authorization **record**, the subject/user, the role→grant model, how "current authorizations" are fetched | **the application** | irreducibly domain-specific |

This honors DIP (the engine never imports a concrete role table) and "defer API until a client exists"
(FOSUtilities does not invent a role system it has no consumer for). **[DECISION — PROPOSED, pending
confirmation]** — the alternative (ship a concrete/default authorization record apps adopt-or-replace)
is recorded in the TBD register as OQ-L1-2.

---

## 4. How it hangs together (the seams)

**Read path** (resolve a container ViewModel):

```
ServerRequest  ──decode──▶  [auth-scoped LOAD ENGINE] ──▶  request-scoped RECORD CACHE  ──▶  UNIFIED FACTORY (projection) ──▶ localized Response
   │ Query(filter)              │  needs:                         (compute once,                │ reads cache only,
   │ Sort(SortCriteria)         │   • Container.Type  ◀── REGISTRY (namespace→Type)             │ NO Database handle
   │ pagination                 │   • member query    ◀── CONTAINMENT (Fluent-derived; C4)      │ aggregates child
   └────────────────────────────┤   • authorizations ◀── ContainerAuthorization (app) via DI   │ requirements (C7)
                                 │   • Sort→KeyPath    ◀── Key→KeyPath mapping (Vapor)           │
                                 └──▶ member-id query → re-sort to id order → eager-load → cache
```

**Write path** (pass #2 — post-write refresh, and the L2 emit seam):

```
ServerRequest(write) ─▶ validate ─▶ mutate ─▶ [commit] ─▶ re-bind (re-run LOAD ENGINE) ─▶ re-project fresh VM to caller
                                        └─▶ (L2) post-commit invalidation nudge on the container's ModelIdentity
```

The **seam invariants** (the things this document fixes so components can move independently):

1. **The auth-scoped record set is produced once, before projection, and is the authorization boundary.**
   Projection never queries; it only reads the cache. This is what lets one load serve read + write and
   makes "forget to authorize" impossible.
2. **Identity is the universal key.** `ModelIdentity` is simultaneously the container reference, the
   persisted auth-scope stored in a column, the registry key, and (L2) the invalidation routing key.
3. **Wire carries meaning; Vapor owns Fluent mechanism.** `Sort` and the registry split this way — a
   Codable vocabulary on the shared side, a KeyPath/SQL mapping on the Vapor side. (Containment/cardinality
   lives wholly Vapor-side, derived from Fluent relationships — it never crosses the wire.)
4. **The projection has no `Database` handle.** (C7) A composable piece *cannot* trigger a load, so a
   missing requirement fails to compile rather than crashing at composition time.

---

## 5. Components

### C1 — Container model & operation vocabulary  ·  FOSMVVM  ·  **PARTIAL**  ·  [proven prior art]

**Responsibility.** Declare what a container owns, and the shared verb space for authorizing operations
on a container's records.

```swift
// A container is a Model that owns/authorizes other records.
public protocol Container: Model {
    static var containedRecordTypes: [any Model.Type] { get }   // default: []
}

// The authorization verb space. authorizesXXX helpers, never raw == (OCP: new ops + .anyOperation
// wildcard extend in one place). Ships with its RecordOperation companion + the bridge between them.
public enum ContainerOperation: Hashable, CaseIterable, Sendable {   // runtime metadata only — NOT Codable
    case readRecords, writeRecords, createRecords, deleteRecords, destroyRecords, anyOperation
    // var authorizesReadRecords/…/authorizesDestroyRecords: Bool  (+ Sequence overloads)
}
// Runtime metadata only (David, 2026-07-03): it is NOT serialized anywhere, so it is deliberately NOT
// Codable — add serialization only if a consumer appears, and then as a sealed token (no String raw
// value: a security vocabulary must not expose a public rawValue). RecordOperation is deferred (OQ-L1-3):
// Model is the record tier; container-scoped checks need only ContainerOperation for now.
```

**Seam.** `containedRecordTypes` names the types the load engine (C6) and requirement aggregation (C7)
walk; `ContainerOperation` is the verb shared by requests, authorizations (C3), and the engine.
**Open:** whether the `Record → Container → DataModel` refinement chain is worth introducing a distinct
`Record` tier in FOSMVVM, or whether `Model` is already that tier (lean: reuse `Model`; the L0 spec
already made `Model` the identity root). Whether `RecordOperation` ships or `ContainerOperation` suffices.
Registered as OQ-L1-3.

### C2 — Query · Sort · Pagination on `ServerRequest`  ·  FOSMVVM (wire)  ·  **PARTIAL**  ·  [new]

**Responsibility.** Let a client specify *which* population (filter), *what order* (sort), and *how much*
(pagination) — as first-class, wire-carried, type-safe request concerns.

`ServerRequest` already has `associatedtype Query: ServerRequestQuery` (filter/population). L1 adds sort
as a **separate** associated type (SRP: filter selects the population; sort orders any population;
pagination bounds it), defaulting like `Query` does so existing requests are unaffected:

```swift
public protocol ServerRequest /* … */ {
    associatedtype Sort: ServerRequestSort = EmptySort     // NEW, defaulted
    var sort: Sort? { get }
}

// Ordered, per-key direction (multi-key: "dock name, then berth number desc"). Key is a
// container-declared Codable enum of *published sortable dimensions* — meanings, not columns.
public struct SortCriteria<Key: SortKey>: ServerRequestSort { /* [(Key, SortDirection)] */ }
public protocol SortKey: Codable, Hashable, Sendable {}      // e.g. enum BerthSortKey { case number, name, updatedAt }
```

**Seam.** `Sort` crosses the wire as meaning; the Vapor `Key→KeyPath` mapping (C6a) turns it into a
Fluent order-by. A `Key` case may expand to *several* KeyPaths (`.name → \.$dockName, \.$number`),
so composable field-sorting and named-orders are the same primitive. Validity is enforced by the enum
(an undeclared key can't decode). **Non-goal:** the UI→`SortCriteria` binding (column-header taps) is
View-layer, deferred (OQ-L1-7).

**Encapsulation note.** Unlike `ContainerOperation` (a sealed *security/persistence* token), `SortKey` is
an ordinary request-parameter vocabulary — validated by decode, never persisted or frozen — so its
case-name `Codable` form is fine and it does **not** carry the sealed-token discipline. Don't over-seal it.

**Pagination.** Pagination is a *standard* concern (start + limit) — identical for every request, unlike
population-specific `Query` or container-specific `Sort`. **Resolved (OQ-L1-10, David 2026-07-03):** it is
an **optional protocol conformance on `Query`** — a `PaginatedQuery` trait a query opts into, carrying a
standard `Pagination` value — *not* a new field on `ServerRequest` (keeps the core request surface minimal;
trait-overlay pattern). The load engine applies the window when the query conforms, else returns the full
authorized set (subject to `maxRecordsWarningThreshold`).

### C3 — Authorization model & the framework/app boundary  ·  FOSMVVM(+Vapor)  ·  **PARTIAL + DECISION**  ·  [proven prior art]

**Responsibility.** Express "subject *S* may {operation} the records in container *C*" as a check the
load engine applies while scoping, and define the seam by which the app supplies concrete authorizations.

Authorization is **two-axis**: (1) **instance scope** — `ModelIdentity` equality between the requested
container and the one an authorization grants (this is why L0 kept `==`/`== some Model` load-bearing);
(2) **operation × record-type** — the app's role grants a `ContainerOperation` on a record type. The
framework owns axis 1 and the vocabulary of axis 2; the app owns axis 2's data.

```swift
// The abstraction the engine depends on. The app's concrete Fluent authorization record conforms.
public protocol ContainerAuthorization {
    var authorizedContainer: ModelIdentity { get }                      // stored in a DB column (L0 frozen Codable)
    func authorizes(_ operation: ContainerOperation,
                    ofType recordType: any Model.Type,
                    in container: ModelIdentity) -> Bool
}

// DI seam: how the engine obtains the current subject's authorizations. App-provided, injected — the
// generic replacement for a bespoke "load the user's role-authorizations" middleware.
public protocol ContainerAuthorizationProvider: Sendable {
    associatedtype Authorization: ContainerAuthorization
    func containerAuthorizations(for request: Request) async throws -> [Authorization]
}
```

**Shipped shape (C3, 2026-07-04) — full-set-per-request, not per-(type, operation).** The sketch above
originally read `authorizations(for: request, type:, operation:)`; C3 ships the complete set instead —
per-call narrowing would re-invoke app code on every load (mid-request grant drift) and defeat
memoization, so the engine fetches once per `Request` and memoizes. See
`2026-07-04-authorization-provider-design.md` for the full rationale and shipped design.

**Placement split (boundary-critical).** `ContainerAuthorization` is **shared (FOSMVVM)** — it references
only `ModelIdentity`/`ContainerOperation`/`any Model.Type`, no Vapor type. `ContainerAuthorizationProvider`
takes a Vapor `Request`, so it lives in **FOSMVVMVapor** (the engine is already Vapor-side — never drag
`Request` onto the shared surface).

**Seam.** The engine (C6) consumes `[some ContainerAuthorization]` from the provider and scopes the load;
it never sees a role or user type. **Authorization by data-scoping, not route-guarding** (foundational
discipline): routes are gated only by *authentication*; a brute-forced request simply loads an empty
projection. **[DECISION — RESOLVED (thin), confirmed by David 2026-07-04; see
C3 spec D-C3-1]:** thin framework (protocol + DI seam only; app owns the concrete record). Alternative =
ship a default authorization record → OQ-L1-2.

### C4 — Cardinality & the injected type registry  ·  FOSMVVMVapor  ·  **DIRECTION (cardinality) / PARTIAL (registry)**  ·  [proven prior art]

**Responsibility.** Know how to find a container's members of a given type, and recover a `Model.Type`
from a stored `ModelIdentity`.

**Cardinality — derive from Fluent, don't re-specify it.** Fluent's `@Children` / `@Siblings` /
`@Parent` property wrappers *already* encode cardinality + key + foreign key + pivot schema. Requiring a
separate hand-written `.toMany(keyName, fk, pivotSchema)` re-states that truth and drifts from it. The
intended design: a container declares *which* of its Fluent relationships are authorization-bearing
containment (a set of relationship KeyPaths — it must, since not every relationship is containment and a
container may have two relationships to the same type), and the engine reads cardinality + keys **off the
property wrapper** — driving the member query through Fluent's own relationship query where possible
rather than reconstructing SQL.

```swift
extension Dock {
    static var containment: [ContainmentRelation] {           // WHICH relationships are containment…
        [.children(\Dock.$berths), .siblings(\Dock.$crew)]    // …the HOW (keys/pivot) comes from Fluent
    }
}
```

This removes the re-specification redundancy that "always seemed off." **Open (OQ-L1-8):** generic
introspection of Fluent relationship metadata; disambiguating multiple relationships to the same
contained type; and how much of the id-set / re-sort-to-id-order / skipLimit logic survives when leaning
on Fluent's query builder instead of a raw member-id `SELECT`. **Convergence:** these same containment
KeyPaths are candidates to also express C7's scope inheritance (M1) and eager-load composition (M2) —
one relationship primitive potentially serving cardinality, containment scope, and eager loading.

**Two invariants to pin (detailed spec):** (a) the Vapor `containment` relations' target types must equal
the shared `containedRecordTypes` (C1) — declared in two places across the boundary, they must not drift;
guard with a registration-time check/test. (b) any `ContainerCardinality` value is a *derived view*
computed from a `ContainmentRelation` (read off the Fluent wrapper), never hand-authored — there is no
separately-specified cardinality to keep in sync.

The registry recovers a queryable type from a persisted namespace — its **concrete consumer**: the load
engine, given a stored `ModelIdentity`, must get the `Container.Type` to look up cardinality and
`containedRecordTypes`. The prior art did this through a **process-global** string→Type service; L1
**injects** it into the Vapor `Application`/`Request` context and **populates it as a side-effect of
migration registration** (declaring the migration *is* registering the type — no drift, no
forgot-to-register). Server-only; never linked into the client.

```swift
public struct ModelTypeRegistry: Sendable { /* ModelNamespace → any Model.Type ; injected, not global */ }
```

**Seam.** `Cardinality` is consumed only by the engine's member-id query; the registry is consumed
wherever a stored identity must become a type. **Open:** cache key collisions when two containers hold
the same record type in one request → the request-scoped cache key is (container `ModelIdentity` + type),
not type alone (OQ-L1-4). Naming: avoid confusion with the existing internal `ModelRegistry` used by
localization (OQ-L1-5).

### C5 — Injected type registry
*(folded into C4 above; kept as a named seam for L2, which also resolves namespaces for nudge routing.)*

### C6 — The authorized load engine + request-scoped record cache  ·  FOSMVVMVapor  ·  **SPECIFIED** — see `2026-07-04-authorized-load-engine-design.md`  ·  [proven prior art]

> **SUPERSEDED PIPELINE NOTE (2026-07-04).** The pipeline text below predates the C4 spec: C4's
> Fluent-relationship `QueryBuilder` seam eliminated the member-id query and the re-sort wart, so sort
> and pagination push down into the query. The C6 detailed spec is the source of truth for the pipeline;
> this section remains for the responsibility statement and seams.

**Responsibility.** Produce, once per request, the auth-scoped, filtered, sorted, paginated,
eager-loaded set of a container's records, cached for all downstream projection.

Pipeline *(superseded — see note above)*: for each authorization in scope → member-id query driven by `Cardinality` (C4) → apply
`Sort→KeyPath` (C6a) + filter + pagination → **re-sort results to the member-id order** (the `~~` id
filter returns DB order, not the requested order) → apply eager-loads (opt-in `EagerBindable`) →
accumulate into the **request-scoped record cache**, guarded by `maxRecordsWarningThreshold`.

- **C6a — Sort `Key → [KeyPath]` mapping** (Vapor protocol on the DataModel). The one place a `.number`
  becomes `.sort(\.$number)`. Fluent-coupled, so it cannot live on the shared `SortKey`. **PARTIAL.**
- **Cache** — `req`-scoped, `StorageKey`-backed, keyed by (container identity + type). Compute-once /
  read-many; a `bind(to:)`-style re-run supports pass #2. This is net-new to FOSUtilities.
- **Known refinements over prior art** (both were self-flagged gaps there): KeyPath sort (done via C6a)
  and **push filter/pagination down into the id query** rather than post-filtering in Swift (efficiency;
  DIRECTION — OQ-L1-6, overlaps OQ-L1-8).

**Seam.** Consumes C1/C3/C4/C6a + the aggregated requirements from C7; the *only* writer of the cache
the projection reads.

### C7 — Composition & data-requirements aggregation  ·  FOSMVVM(+Vapor)  ·  **SPECIFIED** — see `2026-07-04-composable-factory-data-requirements-design.md`  ·  [new; partial prior art]

**Responsibility.** Make "a composable ViewModel declares the data it needs" true and automatic, so the
load plan is *derived from the composition*, not hand-maintained — eliminating the forgotten-load crash
(§1).

**Direction (shipped).** The `ComposableFactory` trait[^c8-rename] is the single site where a piece declares
(a) its record/relationship needs (`dataRequirements: [any DataRequirement]`), (b) the **child factory
types** it composes (`children: [ComposedChild]`), and (c) its projection (C8). The framework computes the
**transitive closure of requirements over the static child-factory-type graph** via the pure
`RecordLoadPlan.walk` — composing a child automatically pulls in its requirements. The engine (C6)
loads the aggregate once; projection reads the cache.

**Why data-dependent composition doesn't break it.** The child *types and relationships* are static
(all the load plan needs); only the *instance count* is dynamic (e.g. N berth cells from already-loaded
data), and iterating loaded data triggers no new load. The crash becomes impossible because projection
is handed a **read-only cached view with no `Database` handle** — a forgotten requirement can't be
reached, so it fails to compile instead of faulting at runtime.

**M1–M3 — resolved (2026-07-04; full rationale in the C7 spec).**
- **M1 — scope inheritance,** resolved as a **placement grammar**: `RootScope` (`.parentRoot` shares the
  declaring factory's scope; `.newRoot(RootSource)` starts a fresh tree) + `RootSource` (`.query` — the
  request's `RootedQuery` vends the identity; `.apex` — a boot-registered resolver vends it) name WHERE a
  requirement or composed child roots; `via:` intermediates on `LoadRequirement`/`ComposedChild` carry the
  containment hops between that root and the declared type (the terminal hop is always implicit — a
  cold-read grammar bug caught the opposite spelling, see the spec's Constraint ledger). `RecordLoadPlan.walk`
  substitutes every child-relative declaration into an absolute path at boot.
- **M2 — type-safe eager-load composition,** DEFERRED, with the landing zone proven rather than merely
  sketched: `RecordLoadPlan.collapseRuns` already computes, as pure data, the maximal runs of consecutive
  tuples sharing root, anchor, and operation — exactly the legality map a future `.with {}`-applying
  executor optimization needs (a same-anchor+operation run may collapse into one eager-loaded query; a
  `.guards` anchor always starts a new boundary). Landing it is a pure executor optimization via the
  refinement's additive-field seam + a `.with`-applying capability on `ContainmentRelation` — zero API
  movement.
- **M3 — the aggregation surface,** resolved as **declared values walked by the framework**: the
  `ComposableFactory` trait's `dataRequirements`/`children` static properties, aggregated by the
  pure, `package`-scoped `RecordLoadPlan.walk` (FOSMVVM) and bound/executed by the internal Vapor executor.
  A generating macro remains explicit future work — it closes two residual gaps today's compile-time check
  cannot catch (a conforming-but-unlisted child; a declared-but-unlisted requirement handle) — layered on
  top of the same declared-value surface, never a replacement for it.

**Seam (now the shipped contract).** Requirements are co-located with access, aggregated over the
composition graph by a boot-time, pure walk, satisfied by a single pre-projection load (C6), and
projection cannot load — it reads only the request-scoped cache. Downstream components (C8) depend only
on that contract.

[^c8-rename]: Renamed `ComposableViewModelFactory` → `ComposableFactory` and un-pinned from
    `ViewModelFactory` in C8 (D-C8-4): any `ServerRequestBody` may declare its data, not only ViewModels.
    The trait's members, walk, and C7 semantics are unchanged.

### C8 — Unified server-hosted container factory (+ pass #2 refresh)  ·  FOSMVVMVapor  ·  **SPECIFIED** — see `2026-07-05-vapor-response-body-factory-design.md`  ·  [proven prior art]

**Responsibility.** One author-facing declaration — the server analogue of `ClientHostedViewModelFactory`
— that collapses the prior art's *two* parallel, kept-in-sync protocols (load-spec vs projection) into a
single type per screen/body. Execution stays **load-then-project**: the load runs ahead, once, auth-scoped,
cached (C6); the projection reads the cache and cannot load. Collapsing that separation would destroy the
shared read/write boundary and the non-bypassable authorization.

**Direction (shipped).** `VaporResponseBodyFactory` produces any request's `ResponseBody` (ViewModel or
not — the ViewModel pin is gone), through a **synchronous** `body(context:)` handed a `ProjectionContext`
that carries the typed request, the app-declared `AppState`, and typed record reads — never a
`Vapor.Request` or `Database`. The write path is the mirror: `WriteTargetProviding`/`DataModelWriter`
declare an auth-scoped `candidates` set and a sealed synchronous `apply`; a `TargetedQuery` selector
(the opaque `ModelIdentity`, never a `ModelIdType` in the body) resolves against the set the server
loaded itself (not-yours == not-found; create is gated on the grant directly). **Pass #2 is not a
mechanism:** each write CRUD protocol carries a `RefreshRequest` + authored `refreshRequest()`, and after
commit + `invalidateContainerRecords(of:)` the server re-serves that refresh request through the *genuine
GET pipeline* — the same code the read route runs, so the forgotten-re-bind class has no place to exist.
Registration is Application-only (`register(request:)`); form↔DataModel mapping stays authored app code
(OQ-L1-9). Everything funnels through the existing centralized `buildResponse` (localization + version
header). Full contract, decisions (D-C8-1..9), and the review reconciliation are in the C8 spec.

**Seam.** The one surface that ties C1–C6 together for a screen; its output localizes through the
existing response builder.

**Accumulated C8 obligations (recorded during C7, 2026-07-04) — all discharged in C8:**

- **The supplemental hook's public surface** *(discharged — C8)* — `SupplementalRecordLoading` is now
  public (C8 spec §3.11).
- **Throwing hook ⇒ propagate** *(discharged — C8)* — a thrown hook fails the request, never swallowed to
  empty; pinned by test (§3.11 / test group 12).
- **Plan-absent-handle fail-fast** *(discharged — C8)* — `ProjectionContext.records(_:)` throws on a
  handle that never reached the plan, never returns `[]` (§3.2 / test group 3).
- **Conforming-but-unlisted-child closure** *(discharged — C8)* — an unlisted child's handles never reach
  the plan, so its first read throws (the runtime closure; compile-time upgrade is the future macro, §3.2).
- **`ProjectionState`** *(discharged — C8)* — merged into `ProjectionContext` (the context *is* the
  projection state; the C7-promised separate type was a one-doll Russian doll, §3.2).
- **Boot-warn on an unbridgeable `.refinedByRequest` `Sort`** *(discharged — C8)* — registration warns
  when the marked plan's `Sort` is neither `EmptySort` nor `SortCriteria`-based (§3.10 / test group 13).
- **Public apex-resolver registration** *(discharged — C8)* — `useApexContainerResolver` is now public;
  `.apex` roots are usable by apps (§3.10 / test group 14).
- **Wire the executor** *(discharged — C8)* — `Request.executeRecordLoadPlan(for:)` runs inside
  `VaporServerRequestHost` on the GET path (§3.1 / test group 2).
- **The freeze decision (was "DECIDE BEFORE THE NEXT TAGGED RELEASE")** *(discharged — C8)* —
  `DataRequirement` sealed: pure public marker + internal walk face; foreign conformers boot-reject
  (D-C8-5, §3.5). Opening members later is additive; freezing them public was forever.

### C9 — Live invalidation  ·  Layer 2  ·  **SPECIFIED@arc-level, detail DEFERRED**  ·  [proven prior art; L0 freshness]

Slotted here only to fix its seams to this layer: the L2 emit fires on the container's `ModelIdentity`
after commit (C8 write path); the dispatcher routes by `ModelIdentity` (exact) or `ModelNamespace`
(unbounded), resolving types through the same injected registry (C4); the monotonic gate uses L0's
`ViewModelId.Freshness`. No L1 work beyond exposing those seams. Full design: north star §5.

### Cross-cutting

- **Migration-as-registration** — a migration `struct` nested in its model, its stable `name` the
  DB identity; registering the migration populates the type registry (C4). No separate registration step.
- **DEF-7 — fail-fast namespace guard**  ·  **TBD/small.** A boot/`DEBUG` assertion (piggybacking the
  registry) that every persisted-identity `Model` overrode the L0 reflection-default namespace, elevating
  the L0 "SHOULD anchor to a stable marker type" from doc guidance to an enforced guard — because L1 is
  where identities first get persisted (in authorization columns).
- **Centralized response builder** — reused, not rebuilt; every L1 read/refresh path funnels
  through it.

---

## 6. Layering, placement & build order

**Placement:** shared vocabulary (C1, C2, C3's `ContainerAuthorization` protocol) in **FOSMVVM**; Fluent
mechanism (C4, C6, C6a, C8, C3's `ContainerAuthorizationProvider`) + the registry + cache in
**FOSMVVMVapor**; the concrete authorization/role/subject in the **app**. C7 spans both (the requirement
*declaration* is shared; the *aggregation/execution* is Vapor-side); C9 is Layer 2. No Fluent type crosses
onto shared `Model`/`ServerRequest` (SPMLibraries/DIP boundary).

**Suggested detailed-spec sequence** (each spawns its own spec → plan, per the north star's layer
discipline and the `fosmvvm-planning` gate):

1. **C1 + C2** (shared vocabulary: `Container`, `ContainerOperation`, `ServerRequestSort`/`SortCriteria`)
   — no Fluent; unblocks everything; independently testable.
2. **C4** (cardinality + injected registry + migration-as-registration) — the first Fluent-facing spec.
3. **C6/C6a** (load engine + KeyPath sort + request-scoped cache) — depends on C1/C4.
4. **C3** (authorization protocol + DI provider seam) — can proceed in parallel with C4/C6; the engine
   integrates it.
5. **C8** (unified factory + pass #2) — depends on C6; needs C7's contract (not its internals).

   **C8 package audit (accumulating).** Every `package` symbol must carry a named cross-target consumer
   no other access level serves, or it demotes to `internal` — "tests can see it" counts for nothing.

   *Demotions executed early (2026-07-04, David's order, pre-Task-5 of C7):* every `package` symbol in
   FOSMVVMVapor — `ContainmentError`, `ContainmentRelation`'s erased types + `members` entries,
   `ModelTypeRegistry`/`RegisteredModel`, the registry accessors, `AnySortTerm`/refinement/`erasedTerms`,
   `SortMapping.apply`, the `authorizedBy:` engine entry, and the cache (key, accessors, invalidate,
   threshold) — is now `internal`. Consuming tests use `@testable` (coverage tests below C8's public
   surface; no access widened for tests).

   C8 audit resolutions (executed 2026-07-05):
   - The (now-internal) `authorizedBy:` engine entry — **REMOVED** (T7): C8 routes every framework
     caller through the provider-driven entry (C3), so the demote-or-remove question closed on remove;
     the removal folded *into* the provider core (the single cache-writer invariant preserved).
   - `Application.maxRecordsWarningThreshold` — **stays internal** (unchanged): no app-facing consumer
     appeared; promote only when a definitive one does (Defer-API).
   - The two FOSMVVM `package` sites (`ModelIdentity.namespace`/`.id`; `RecordLoadPlan` + walk) —
     on-file statements **re-verified at C8**: named cross-module consumers unchanged (the Vapor
     registry/engine; the Vapor executor), `public` still forbidden (L0 opacity; the walk is not app
     surface). The `RecordLoadPlan` site **gained members** — `tuples(matching:)` (consumer:
     `ProjectionContext.records(_:)`, resolving a sealed handle's token to its tuple) and
     `requirementTokensAreStable(for:)` (consumer: boot registration's token-stability lint, reading a
     Bool verdict only, never a token value) — each named in its on-file statement. **Zero new
     `package` *sites*** in the slice (grep-enforced in the DoD).

   C8 forward notes (recorded, not scheduled):
   - **A public authorized-engine entry for `SupplementalRecordLoading` conformers** is a named future
     publicization. Today the hook has raw request power (full load-phase authority per the load-phase
     contract, §C8 obligation "supplemental hook's public surface"); a narrowed, provider-scoped engine
     entry the hook could call *instead of* raw `req.db` would close the last raw-power surface — waits
     for a consumer that needs the narrowing (Defer-API).
   - **The `ServerRequestController` family is the general dispatch layer — RESOLVED (David,
     2026-07-05; C8a).** The C8 review recorded this family as "a second write door, disposition
     pending" (deprecate-now was the recommendation); the ruling went the other way: the controller
     protocol is the *one* general mechanism, and C8's read/write doors are framework-specialized
     controllers — `register(request:)` and the write overloads instantiate an internal
     `GuardedRequestController` whose `actions` are the guarded pipelines
     (`serve`/`serveUpdate`/`serveCreate`/`serveDelete`). Hand-written processors through the same
     mechanism are the sanctioned home for operations the guarded verbs don't cover yet (Replace,
     destroy, multi-record operations) — a set that shrinks as future slices add guarded verbs.
     See docs/superpowers/plans/2026-07-05-c8a-controller-composition.md.
   - **Pre-existing incoherence, recorded (not C8a work):** `ControllerRouting.path(for:)` builds
     client URLs with `/create`, `/delete`, `/destroy` suffixes, while the controller's `boot`
     registers every verb at `baseURL` itself. Predates C8; left standing.
6. **C7** (composition aggregation) — the pillar; its *seam* is fixed now, its internals (M1–M3) are a
   dedicated design pass, likely last and possibly macro-assisted.
7. **DEF-7 guard** — small, rides on C4's registry.

C9 (live) is Layer 2 and follows the whole of L1.

## 7. Decisions locked this session

- **Scope of L1** = §4 core **+** pass #2 request-level refresh **+** DEF-7 guard.
- **Sort is a first-class, client-chosen request concern** — separate `Sort` associated type carrying
  `SortCriteria<Key>` (ordered, per-key direction, meanings-not-columns), Vapor maps `Key→KeyPath`.
- **Framework/app boundary** = thin framework (vocabulary + `Container`/cardinality + engine +
  `ContainerAuthorization` protocol + DI provider seam); app owns concrete auth/role/subject. *(pending
  final confirmation — OQ-L1-2.)*
- **"Unified factory" preserves the load/use separation** — one declaration site, still load-then-project,
  projection has no `Database` handle.
- **Composition-requirements aggregation is a design pillar of L1** — its seam is fixed; internals TBD.

## 8. Open questions / TBD register

- **OQ-L1-1 — north-star relationship.** Dedicated doc (this) vs. rewrite the north star. *Proposed:
  dedicated.* Pending confirmation.
- **OQ-L1-2 — authorization boundary — [DECISION — RESOLVED (thin), confirmed by David 2026-07-04;
  see C3 spec D-C3-1].** Thin (protocol only) vs. ship a default authorization record.
  *Resolved: thin.*
- **OQ-L1-3 — `Record` tier & `RecordOperation` — RESOLVED (David, 2026-07-03).** No distinct `Record`
  tier (`Model` is it); ship `ContainerOperation` **only** for now — defer `RecordOperation` until a
  record-vs-container-granularity consumer appears.
- **OQ-L1-4 — cache key.** (container identity + type), confirmed direction; verify no other collision axis.
- **OQ-L1-5 — registry naming.** Disambiguate the new `ModelTypeRegistry` from the existing internal
  localization `ModelRegistry`.
- **OQ-L1-6 — filter push-down.** Push filter/pagination into the member-id SQL rather than post-filter in
  Swift (chosen DIRECTION; overlaps OQ-L1-8's id-query rework).
- **OQ-L1-7 — UI→sort binding.** Deferred to the View layer (non-goal here).
- **OQ-L1-8 — cardinality from Fluent.** Derive cardinality/keys/pivot from declared `@Children`/
  `@Siblings`/`@Parent` relationships (container declares *which* relationships are containment via
  KeyPaths) instead of hand-specifying them; possibly drive the member query through Fluent's own
  relationship query. Open: generic relationship-metadata introspection, same-type ambiguity, and how
  much id-set/re-sort/skipLimit logic survives. Converges with C7-M1/M2.
- **OQ-L1-9 — bidirectional form binding — RESOLVED (David, 2026-07-04): no framework mapping
  mechanism.** The `ResponseBody` contract already decouples the concrete source type — the framework
  needs *an instance conforming to `Request.ResponseBody`* and never learns what produced it, so
  model↔form mapping is authored app code (an app that conforms its `DataModel` to its own app-side
  form-contract protocol self-serves a once-per-contract `apply(from:)` via a plain protocol
  extension; the framework cannot enumerate properties of a protocol it has never seen). No macro;
  revisit only if a real consumer demonstrates the need (Defer-API). What survives into C8 is the
  write-path *seam*, which is pipeline business, not mapping business: a defined place for the
  authored apply/mutate handed the auth-scoped loaded target; `ValidatableModel.validate()` invoked
  structurally before the mutation is reachable; the retarget-proof property (form body carries no
  `ModelIdType` — the write target resolves from the request's `Query` against the auth-scoped
  loaded set); pass #2 refresh after commit.
- **OQ-L1-10 — pagination's wire carrier — RESOLVED (David, 2026-07-03).** An optional `PaginatedQuery`
  trait conformance on `Query` carrying a standard `Pagination` value — not a `ServerRequest` field.
- **M1–M3 (C7) — RESOLVED (2026-07-04); see `2026-07-04-composable-factory-data-requirements-design.md`.**
  M1 (scope inheritance) = the `RootScope`/`RootSource` + `via:` placement grammar; M2 (type-safe
  eager-load composition) = deferred, landing zone proven (`RecordLoadPlan.collapseRuns` as the
  eager-load collapse-legality map, consumed later by a `.with {}`-applying executor optimization); M3
  (the aggregation surface) = declared values (`ComposableFactory.dataRequirements`/`children`)
  walked by the pure `RecordLoadPlan.walk`, with a generating macro layered on later.

## 9. Non-goals / deferred

- Layer 2 detail (SSE, dispatcher, `ModelMiddleware` emit, freshness producer/gate, `.live` macro).
- A role/permission system, a concrete subject/user, a concrete authorization record (app-owned).
- The UI→`SortCriteria` binding.
- Any client-linked type registry (the registry is server-only).
