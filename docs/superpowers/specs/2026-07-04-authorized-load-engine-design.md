# Layer 1 · C6 — The Authorized Load Engine, C6a Sort Mapping & the Request-Scoped Cache (Design Spec)

**Status:** Reviewed — spec-document + FOSMVVM-discipline reviewers (2026-07-04); both reviews'
blockers/majors folded in (see §Review reconciliation). Decisions D-C6-1…3 **RESOLVED by David
(2026-07-04)**.
**Date:** 2026-07-04
**Layer:** 1, component **C6 (+C6a)** of `2026-07-03-authorized-container-data-loading-architecture.md`.
**Targets:** FOSMVVMVapor (engine, C6a, cache, refinement). **Shared FOSMVVM additions:** the
`ContainerAuthorization` protocol (C3's shared core, pulled forward — D-C6-1), a small
`ContainerOperation` collection helper (misuse-resistance, C6.1), and the C2 pickups on `ServerRequest`
(sort-at-init + URL round-trip).
**Depends on:** L0 + C1 + C2 (shipped) + C4 (shipped: registry, `ContainmentRelation`, `package` seams).
**Blocks:** C8 (factory — the engine's first in-package consumer), L2.

> **The problem C6 solves** — *one authorized read path, computed once, shared by everything that
> renders.* After C4, the server can get from a sealed `ModelIdentity` to a container's raw members —
> but that load is unrefined (no auth, no sort, no window) and `package`-gated precisely so nobody ships
> on it. C6 wraps it into the **single, non-bypassable authorization boundary** (arch seam invariant #1):
> for each request, the engine produces the auth-scoped, sorted, paginated record set **once**, caches it
> request-scoped, and every downstream projection (C8 factory, post-write pass #2, L2 live) reads that
> one snapshot. Authorization is **data-scoping, not route-guarding**: routes gate only authentication;
> a brute-forced request simply projects an empty set.

## Reconciliation with the architecture doc (supersedes its C6 pipeline text)

The arch's C6 section (§5) predates the C4 spec and still describes the prior-art pipeline:
*member-id query → `~~` id filter → re-sort to member-id order*. C4 eliminated that shape — Fluent's own
relationship query returns a `QueryBuilder<To>`, so sort and pagination **push down into the query**
(OQ-L1-6's chosen direction; filter push-down itself is deferred, D-C6-3) and the re-sort wart never
exists. This spec is the source of truth for the C6 pipeline; the arch doc gets a one-line reconciliation
note on approval.

## The unit of load (resolves the review blocker)

**One engine call loads one (container, contained-type) pair** — "the authorized `Berth`s of Dock #5,
sorted, windowed." This is the unit a projection binds, the unit the sort vocabulary types against, the
unit a pagination window is coherent over, and exactly the unit the cache key names. A whole-container
sweep is just iteration over `containedRecordTypes` by the caller (C8) — it is **not** an engine entry
(a single refinement cannot be meaningful across heterogeneous record types).

If a container declares **two relations vending the same contained type** (arch: legal), one call loads
both: the refinement applies **per relation** and results concatenate in `containment` declaration order —
so the window is per-relation in that (rare) case. Documented limitation; revisit when a real consumer
has two same-type containment relations.

## The refined flow (what C6 adds to C4's steps 1–5)

1. **Authorizations in hand** — the caller supplies the subject's authorizations (`some Sequence<A>`,
   `A: ContainerAuthorization`). Acquisition — *who fetches these per request* — is C3's provider seam.
2. **Instance scope** — keep only authorizations whose `authorizedContainer` **is** the requested
   container (`ModelIdentity` equality — L0's load-bearing `==`).
3. **Operation × type scope** — load only if some in-scope authorization
   `authorizes(operation, ofType: containedType, in: container)`.
4. **Refined load (the D1 seam)** — the engine selects the container's relation(s) vending
   `containedType` and hands each a `ContainmentQueryRefinement` (erased sort terms + pagination); the
   relation — which alone knows the concrete `To` — applies C6a sort mappings and the window **onto the
   `QueryBuilder` before `.all()`**.
5. **Guard + cache** — the call's record count is checked against `maxRecordsWarningThreshold` (log
   warning, never truncate); the records land in the **request-scoped cache**; subsequent identical
   calls in the same request return the cached result (compute-once / read-many — empty results are
   cached too). Pass #2 re-runs via explicit invalidation (C6.5).

## Scope (what ships in this spec)

1. **`ContainerAuthorization`** (FOSMVVM, **public**) — C3's shared core, verbatim from the arch §C3
   snippet: `authorizedContainer: ModelIdentity` + `authorizes(_:ofType:in:)`. Ships now because the
   engine cannot be specified without it and its shape is arch-fixed (D-C6-1 — RESOLVED yes).
   Plus a small C1 misuse-resistance helper: `Sequence<ContainerOperation>.authorizes(_:)` — honors the
   wildcard, so app `authorizes` implementations don't drift to raw `contains`/`==` (C1 discipline).
2. **C6a: `SortableDataModel` + `SortMapping`** (FOSMVVMVapor, **public**) — the one place a `.number`
   *meaning* becomes a Fluent order-by. `SortMapping.keyPath(...)` factories capture the concrete field
   generics (same closure-erasure pattern as `ContainmentRelation`); a `SortKey` may expand to several
   mappings, applied in order. Constraints verified against FluentKit: `QueryBuilder.sort(_:_:)` requires
   exactly `Field: QueryableProperty, Field.Model == M`; `range(lower:upper:)` maps `Pagination`
   (upper = start + max − 1).
3. **`AnySortTerm`** (FOSMVVMVapor, `package`) — the erased sort term (key meaning + direction) that
   crosses the engine/refinement/cache seams. Defined in C6.3 (manual `Hashable` — an existential key is
   not Hashable for free); constructed ONLY from a typed `SortTerm` (factory captures the concrete key);
   `SortCriteria` gains a Vapor-side `erasedTerms` bridge (the sanctioned eraser — C8 and tests use it).
4. **`ContainmentQueryRefinement`** (FOSMVVMVapor, `package`, **`Hashable`**) — sort terms + pagination,
   and the **refined `members` overload on `ContainmentRelation`** (`members(of:on:applying:)`) that
   applies it inside the relation's typed closure. Resolves deferred **D1**. `.parent` (to-one) ignores
   the whole refinement — sort and window alike — which is definitionally lossless for a single row
   (unlike silently unsorting a to-many, which stays a typed throw). Being `Hashable`, the refinement
   participates in the cache key **as a value**, so future additive fields (filter, eager-loads) cannot
   miss the key.
5. **The engine** (FOSMVVMVapor, `package`) — `Request.authorizedRecords(of:containing:authorizedBy:for:sortedBy:pagination:)`:
   one (container, contained-type) unit per call; generic over the app's auth-record type (no existential
   array); drives registry→find→scope→refined-members→cache. `package` until C8 consumes it ("Defer API
   Until Client Exists").
6. **Request-scoped record cache** (FOSMVVMVapor, `package`) — `StorageKey`-backed on `Request`. Key:
   (container `ModelIdentity`, `ObjectIdentifier(containedType)`, `ContainerOperation`,
   `ContainmentQueryRefinement`) — all `Hashable`. **Closes OQ-L1-4 under a stated contract:** the cache
   assumes **one authorization set per `Request`** (C3's provider makes that structural; until then it is
   a documented seam contract + maintainer note — differing auth sets across calls in one request are
   unsupported). The engine is the cache's only writer (arch seam).
7. **`maxRecordsWarningThreshold`** (FOSMVVMVapor, `package`, default **1000**) — deliberately
   default-only for now: in-package tests set it; there is no app-facing knob until a consumer needs one
   (`public` promotion is additive). Exceeded ⇒ one `logger.warning` naming the registered container
   *type* (via `String(describing:)` — diagnostic, not identity; `ModelNamespace` contents stay sealed),
   the contained type, and the count. Never truncates.
8. **C2 pickups** (FOSMVVM + FOSMVVMVapor, **public**; D-C6-2 — RESOLVED yes):
   - `ServerRequest.init` gains `sort:` as **the canonical requirement**
     (`init(query:sort:fragment:requestBody:responseBody:)`). Swift protocol requirements cannot take
     defaulted parameters, so a **protocol-extension convenience** (defined once, not per-conformer)
     `init(query:fragment:requestBody:responseBody:)` = canonical with `sort: nil` is the compatibility
     bridge — sugar over one canonical init, not a second way.
   - **Wire placement (specified, not "same machinery"):** the shipped encoding puts the query JSON in a
     single item *name* and the shipped parse JSON-decodes the whole `url.query` string — sort cannot
     ride that blob. So: **the query item stays byte-for-byte as shipped** (old URLs parse by
     construction), and a non-nil, non-`EmptySort` sort travels as one additional **reserved named item**
     (`sort=<json>`), omitted otherwise; the server-side parse strips the reserved item before query
     decoding. Exact item name + stripping pinned in an internal `//` comment and an internal
     compatibility test — never in public DocC (representation stays unpublished).
   - **`Request.serverRequestSort(ofType:)`** (FOSMVVMVapor, public — mirrors `serverRequestQuery`): the
     named server-side parse surface C8 and test 9 call.
9. Contract tests for all of the above (Fluent SQLite harness — `withFluentTestApp`, harbor fixtures).

## Non-goals (explicitly deferred)

- **Query→predicate filter push-down** (D-C6-3 — RESOLVED: defer). The engine applies *sort +
  pagination*; a Query-mapping trait (the C6a pattern again) lands when a filtering consumer appears.
  `ContainmentQueryRefinement` being the cache-key value means the future field is additive and
  collision-safe by construction.
- **A whole-container engine entry.** C8 iterates `containedRecordTypes`; a single-refinement sweep over
  heterogeneous types is incoherent (review B-1) and CRUD "is my target in scope" checks are an auth
  question for C3/C8, not a load shape.
- **`ContainerAuthorizationProvider`** (per-request acquisition) and the app-side concrete auth
  record/role model → **C3** (OQ-L1-2 unchanged).
- **Eager-load composition and requirement aggregation** → **C7/C8** (additive refinement fields).
- **Public engine surface** → C8 decides what the factory exposes; the engine stays `package`.
- **UI→sort binding** (OQ-L1-7, View layer) and **L2** emit/dispatch.

## Types & placement

### C6.1 `ContainerAuthorization` + operation-set helper (`FOSMVVM/Protocols/ContainerAuthorization.swift`, public)

**Customer DocC (drafted first):**

```swift
/// Declares that your authorization value can answer "may this subject touch these records?" —
/// conform a value type your persisted grant row projects, so the framework can scope every container
/// load with it.
///
/// ```swift
/// // A Sendable snapshot of one grant row (persisted Fluent classes aren't Sendable — project a value):
/// struct DockGrant: ContainerAuthorization {
///     let authorizedContainer: ModelIdentity   // decoded from the stored identity column
///     let operations: [ContainerOperation]
///     let recordTypes: [ModelNamespace]        // the stored, decodable form of "which record types"
///
///     func authorizes(_ operation: ContainerOperation,
///                     ofType recordType: any FOSMVVM.Model.Type,   // qualify: FluentKit also declares `Model`
///                     in container: ModelIdentity) -> Bool {
///         container == authorizedContainer
///             && operations.authorizes(operation)                   // honors the wildcard — never `contains`
///             && recordTypes.contains(recordType.modelIdentityNamespace)
///     }
/// }
/// ```
///
/// The framework never sees your role or user types — it only asks each authorization whether it covers
/// the requested container, operation, and record type. A subject with no covering authorization simply
/// loads an empty set; routes are never the place to enforce data access.
public protocol ContainerAuthorization: Sendable {
    /// The container this authorization grants access within (persist it as a stored ``ModelIdentity``).
    var authorizedContainer: ModelIdentity { get }
    /// Whether `operation` on records of `recordType` inside `container` is granted.
    func authorizes(_ operation: ContainerOperation,
                    ofType recordType: any Model.Type,
                    in container: ModelIdentity) -> Bool
}
```

**The C1 helper** (same file or `ContainerOperation.swift` — plan decides):

```swift
public extension Sequence where Element == ContainerOperation {
    /// Whether this granted set covers `operation` — including via the wildcard. Use this instead of
    /// `contains(_:)`, which silently ignores the wildcard grant:
    ///
    /// ```swift
    /// grantedOperations.authorizes(.read)
    /// ```
    func authorizes(_ operation: ContainerOperation) -> Bool
}
```

Notes: shared (references only L0/C1 vocabulary — no Vapor, no Fluent); `Sendable` required (crosses into
the engine's async load) — hence the value-snapshot conformance pattern in the example. A model may
publish exactly **one** sort vocabulary (see C6.2) — deliberate, stated there.

### C6.2 C6a — `SortableDataModel` + `SortMapping` (`FOSMVVMVapor/Containment/SortableDataModel.swift`, public)

**Customer DocC (drafted first):**

```swift
/// Declares how your model's published sort *meanings* become database ordering — one declaration,
/// applied everywhere the framework sorts this model.
///
/// ```swift
/// extension Berth: SortableDataModel {
///     static func sortMappings(for key: BerthSortKey) -> [SortMapping<Berth>] {
///         switch key {
///         case .number:   [.keyPath(\Berth.$number)]
///         case .dockName: [.keyPath(\Berth.$dockName), .keyPath(\Berth.$number)]  // stable tiebreak
///         }
///     }
/// }
/// ```
///
/// Clients only ever send the ``SortKey`` meaning; column names never reach the wire, so renaming a
/// field is invisible to every client. `RequestSortKey` is your model's **one** published sort
/// vocabulary — every request that sorts this model shares it (that's what makes it a vocabulary).
public protocol SortableDataModel: DataModel {
    /// The request-vocabulary key this model sorts by (the shared ``SortKey`` enum your requests use).
    associatedtype RequestSortKey: SortKey
    /// The ordered database mappings for one key — several entries make composite/tiebreak ordering.
    static func sortMappings(for key: RequestSortKey) -> [SortMapping<Self>]
}

/// One database ordering for a ``SortableDataModel`` — build it from a Fluent field KeyPath.
public struct SortMapping<M: SortableDataModel> {
    /// Order by this Fluent field (direction comes from the request's ``SortTerm``).
    public static func keyPath<Field>(_ keyPath: KeyPath<M, Field> & Sendable) -> SortMapping<M>
        where Field: QueryableProperty, Field.Model == M
}
```

Internally `SortMapping` stores an erased `@Sendable (QueryBuilder<M>, SortDirection) -> QueryBuilder<M>`
apply closure captured at the factory (identical discipline to `ContainmentRelation` — the factory is the
only construction path; no column strings anywhere). `Field.Model == M` means a mapping **cannot** target
another model's field (compile-time misuse resistance); joined-parent sorts are out of scope for v1
(denormalize or wait for the eager-load slice).

### C6.3 `AnySortTerm` + `ContainmentQueryRefinement` + refined members (D1) (`FOSMVVMVapor/Containment/ContainmentQueryRefinement.swift`, `package`)

```swift
// The erased sort term crossing the engine/refinement/cache seams. `Any` prefix per Swift's
// meaning-preserving erased-wrapper convention (AnyHashable/AnyView). Constructed ONLY from a typed
// SortTerm — the factory captures the concrete key for the downcast inside the relation's closure.
// Hashable is MANUAL: `any SortKey` is not Hashable; equality/hash go through AnyHashable(key).
package struct AnySortTerm: Hashable, Sendable {
    package let key: any SortKey & Sendable   // downcast to To.RequestSortKey inside the typed closure
    package let direction: SortDirection
    package init(_ term: SortTerm<some SortKey>)
}

// The sanctioned eraser — C8 and tests bridge a request's typed criteria with this; the engine never
// sees SortCriteria<Key> directly.
package extension SortCriteria {
    var erasedTerms: [AnySortTerm] { get }
}

// The erased load instructions the engine hands a ContainmentRelation (which alone knows `To`).
// Hashable so the CACHE KEYS ON THE WHOLE VALUE — additive future fields (filter, eager-loads) join
// the key automatically and can never resurrect the OQ-L1-4 collision.
package struct ContainmentQueryRefinement: Hashable, Sendable {
    package var sortTerms: [AnySortTerm]
    package var pagination: Pagination?
    package static let none: ContainmentQueryRefinement   // empty — the unrefined path's value
}

package extension ContainmentRelation {
    // Refined containment load: applies the refinement INSIDE the typed closure (push-down: sort via
    // To's SortableDataModel mappings, window via QueryBuilder.range) before `.all()`. `.parent`
    // ignores the whole refinement (sort AND window — lossless for one row). Sort terms whose key type
    // ≠ To.RequestSortKey, or a To that is not SortableDataModel while terms are present, throw
    // ContainmentError.unsortableContainedType — fail-fast, never a silently unsorted result.
    func members(of container: any DataModel, on db: any Database,
                 applying refinement: ContainmentQueryRefinement) async throws -> [any DataModel]
}
```

Implementation note: one private load closure parameterized by refinement; C4's unrefined
`members(of:on:)` forwards with `.none` (one code path, two entries — no drift). C4's fetched-container
precondition applies unchanged to the refined overload. `ContainmentError` gains **two** cases (package,
diagnostic payloads): `unsortableContainedType(modelType:keyType:)`, and
`unregisteredNamespace(identity: String)` — the payload is the requested identity's debug summary, since
no registered type name exists to report. C4 shipped no lookup error; the engine adds this one
(misconfiguration must not hide as empty, C4's silent-`[]` lesson).

### C6.4 The engine (`FOSMVVMVapor/Extensions/Request+ContainerLoad.swift`, `package`)

```swift
package extension Request {
    // THE authorized read path (arch seam invariant #1) — everything that projects reads through this.
    // ONE call = ONE (container, containedType) set — the unit a projection binds, the sort vocabulary
    // types against, the window applies to, and the cache key names. Compute-once per
    // (container, type, operation, refinement) within a Request; cached thereafter (empty results too).
    // Generic over the app's auth record — no existential arrays cross this seam.
    func authorizedRecords<A: ContainerAuthorization>(
        of container: ModelIdentity,
        containing containedType: any DataModel.Type,
        authorizedBy authorizations: some Sequence<A> & Sendable,
        for operation: ContainerOperation,
        sortedBy sortTerms: [AnySortTerm] = [],
        pagination: Pagination? = nil
    ) async throws -> [any DataModel]
}
```

Pipeline (internal): cache probe → registry lookup (`modelTypeRegistry.registered(for:)`; unregistered
namespace ⇒ **throw `.unregisteredNamespace`** — configuration bug, not data) → `find` the container
(missing row ⇒ **empty result** — data condition, indistinguishable from unauthorized by design) →
instance-scope authorizations (`ModelIdentity ==`) → operation×type check for `containedType` → refined
`members` on each relation vending `containedType` (declaration order) → threshold check + cache write →
return.

### C6.5 Cache + threshold (`FOSMVVMVapor/Containment/ContainerRecordCache.swift`, `package`)

- `Request.containerRecordCache` — `StorageKey`-backed, request-scoped (parallel-test-safe by
  construction: one cache per `Request`). Key: `ContainerRecordCacheKey`
  (identity + `ObjectIdentifier(containedType)` + operation + `ContainmentQueryRefinement`).
  **Contract (maintainer note at the cache):** one authorization set per `Request` — C3's provider makes
  this structural; until then, passing differing sets across calls in one request is unsupported.
- **Snapshot sharing contract:** cached elements are shared class references — readers (projections)
  **must not mutate** them; only the write path mutates records, and after commit it calls
  `invalidateContainerRecords`. Stated as a `//` maintainer note + the pass-#2 contract below.
- **Pass #2 support:** `package func invalidateContainerRecords(of container: ModelIdentity)` on
  `Request` drops that identity's entries (all types/refinements) so a post-write re-run recomputes.
  The engine remains the only *writer*.
- `maxRecordsWarningThreshold` (`package var` on `Application` storage; default **1000**; deliberately
  no app-facing knob yet): a call's result count > threshold ⇒ one `logger.warning` naming the
  registered container type (`String(describing:)` — diagnostic only), the contained type, and the
  count. Load proceeds — observability, not truncation. Checked per engine call (= per cached unit).

### C6.6 C2 pickups (`FOSMVVM/Protocols/ServerRequest.swift` + `FOSMVVMVapor/Extensions/Request+FOS.swift`)

- **Sort-at-init (D-C6-2 — RESOLVED yes):** canonical requirement
  `init(query: Query?, sort: Sort?, fragment: Fragment?, requestBody: RequestBody?, responseBody: ResponseBody?)`;
  protocol-extension convenience without `sort:` (= `sort: nil`), defined once. Pre-1.0 breaking; all
  conformers + macro-generated inits update mechanically.
- **Encode (`URL.appending(serverRequest:)`):** query item unchanged byte-for-byte; non-nil,
  non-`EmptySort` sort adds one reserved named item (`sort=<json>`), omitted otherwise — so every
  pre-C6 URL round-trips unchanged, by construction. Reserved name + stripping order pinned in an
  internal `//` comment + internal compatibility test, never public DocC.
- **Parse:** `Request.serverRequestQuery` strips the reserved sort item before query decoding (existing
  whole-string decode then proceeds as shipped); new public
  `Request.serverRequestSort(ofType:)` (FOSMVVMVapor) mirrors `serverRequestQuery` — DocC with example;
  returns `nil` when the item is absent.

## Testing (contract tests — obligations verified through the APIs that carry them, representation never asserted; `withFluentTestApp` + harbor fixtures)

Fixture additions: `BerthSortKey` (`number`, `dockName`) + `Berth: SortableDataModel`; `Berth` gains a
denormalized `dockName` `@Field` (+ migration + seed update — FluentKit's `Field.Model == M` rules out
joined-parent sorts in v1); a `TestGrant: ContainerAuthorization` **value type** (container identity +
operations + record types). Engine tests mint a real `Request` via Vapor's public
`Request(application:method:url:on:)` (or a one-line harness helper — plan decides placement).

1. **Auth instance-scoping** — grants for dock1 only ⇒ `authorizedRecords(of: dock1Identity, containing:
   Berth.self, …)` returns dock1's berths; the same call against dock2's identity ⇒ empty; **empty
   authorizations ⇒ empty** (brute-force projects empty — the data-scoping invariant).
2. **Operation × type scoping** — a grant covering `.read` on `Berth` but not `CrewMember` ⇒ the Berth
   call loads, the CrewMember call returns empty; the Berth call `for: .create` ⇒ empty.
3. **C6a sort applied in-DB** — `sortedBy: SortCriteria<BerthSortKey>(…number desc…).erasedTerms` ⇒
   `[3,2,1]` (seed order differs from result order — push-down asserted via order); the multi-mapping
   key (`dockName` → dockName then number) yields the composite order.
4. **Pagination window** — over the sorted single-type call, `Pagination(startIndex: 1, maxResults: 1)`
   ⇒ exactly the middle record; `nil` ⇒ full set.
5. **Unsortable fail-fast** — sort terms against `CrewMember` (no `SortableDataModel` conformance) ⇒
   throws `.unsortableContainedType`; wrong key *type* against `Berth` ⇒ same throw. Never a silently
   unsorted array.
6. **Compute-once cache** — two identical calls return the **same element instances** (assertion basis:
   `===`/`ObjectIdentifier` on elements, as C4's tests pinned equality bases); a call differing only in
   sort or pagination recomputes (the OQ-L1-4 collision test); an *empty* result is also cached (second
   call after deleting rows in between still returns the cached empty — then
   `invalidateContainerRecords` ⇒ recompute observes reality).
7. **Missing vs unregistered** — a valid-namespace identity whose row is deleted ⇒ `[]` (not a throw);
   an unregistered namespace ⇒ throws `.unregisteredNamespace` (misconfiguration ≠ unauthorized).
8. **Threshold** — threshold 2, load 3 berths ⇒ result intact (3 records) — the non-truncation
   contract. (Warning emission is observability — covered by an internal logger-capture assertion if
   Vapor's test logger permits, else documented; not a public contract.)
9. **`ServerRequest` sort round-trip (C2 pickup; lives in `Tests/FOSMVVMVaporTests`)** — a request with
   a real `SortCriteria` builds its URL and `serverRequestSort(ofType:)` recovers an equal value while
   `serverRequestQuery` still decodes the query; an `EmptySort`/nil request produces **today's exact URL
   shape** and old URLs parse unchanged (compatibility assertion, no representation assertion).
10. **Refined members directly (D1 seam)** — `members(of:on:applying:)` honors sort + window; `.parent`
    ignores both; C4's unrefined overload behaves exactly as before (C4's tests stay green untouched).

## Risks & mitigations

- **Two `members` entries drift.** Mitigation: single private closure parameterized by refinement;
  unrefined = `.none`. One code path.
- **Erased key casting** (`any SortKey` → `To.RequestSortKey`) fails at runtime on vocabulary mismatch.
  Mitigation: typed throw (test 5); C8 — the only eventual caller — pins key types at compile time when
  it lands; the erased seam stays package-internal.
- **Cache staleness after a write** (pass #2). Mitigation: explicit `invalidateContainerRecords` by the
  mutating caller; request-scoped storage dies with the request; snapshot-sharing contract forbids
  reader mutation.
- **Authorization-set variance within a request** would collide cache entries. Mitigation: stated
  contract (one set per request) + maintainer note; C3's provider makes it structural.
- **`ServerRequest.init` breaking change** ripples to conformers/macros. Mitigation: protocol-extension
  convenience keeps call sites compiling; pre-1.0 is the window.
- **Threshold as log-only** may hide runaway loads. Accepted for v1; a hard-limit mode is additive.

## Definition of done

- All 10 test groups green (SQLite harness) on macOS/Linux; full suite green; swiftformat/swiftlint clean.
- Customer DocC with examples on `ContainerAuthorization`, `Sequence<ContainerOperation>.authorizes`,
  `SortableDataModel`, `SortMapping.keyPath`, `Request.serverRequestSort(ofType:)`, and the changed
  `ServerRequest.init`; `package` symbols carry maintainer notes only.
- No Fluent/Vapor types on the shared surface (grep-verified as in C4); pre-C6 request URLs round-trip
  byte-identically (compatibility test).
- The engine is the cache's only writer; no public load path exists (engine + refined members stay
  `package`).
- Arch doc §5 C6 gets the one-line supersession note (pipeline text → this spec).
- CHANGELOG: public symbols + the `ServerRequest.init` breaking change.

## Design rationale (why-this-way — kept out of the DocC)

- **Why one (container, type) per call.** A single refinement over heterogeneous types is incoherent:
  sort vocabularies are per-model, windows are per-set, and the cache names one contained type. The
  whole-container sweep is the caller's loop, not an engine shape (review B-1).
- **Why `ContainerAuthorization` ships in C6, not C3** (D-C6-1). The engine's signature *is* its
  contract; the protocol is the arch-frozen shared core. C3 keeps everything with open questions
  (provider seam, OQ-L1-2, app patterns). Rejected: an opaque scoping closure — loses the typed
  vocabulary and makes C3 a breaking change instead of an addition.
- **Why the engine is generic over the auth record.** Apps have one concrete grant type;
  `[any ContainerAuthorization]` is an existential array with no flexibility gain (governance smell).
- **Why sort mappings are values built by factories.** A mapping is *data* — ordered, composable — and
  the factory captures the field generic so no column string exists; `Field.Model == M` makes
  cross-model mappings uncompilable. Same construction discipline as `ContainmentRelation`.
- **Why `AnySortTerm` (not "ErasedSortTerm").** `Any` is Swift's meaning-preserving erased-wrapper
  prefix (`AnyHashable`, `AnyView`); "Erased" names the mechanism. Manual `Hashable` via
  `AnyHashable(key)` — the typed factory is the only construction path, mirroring the repo's
  sealed-value discipline.
- **Why missing-container is empty but unregistered-namespace throws.** Deleted row = data — no
  existence oracle for brute-forcers. Unregistered namespace = configuration bug C4's boot checks should
  have caught — hiding it as empty buries it (C4's silent-`[]` lesson).
- **Why the cache keys on the refinement value.** "Additive" is only true if a future field *cannot*
  miss the key; keying on exploded fields resurrects OQ-L1-4 the day `filter` lands. The value is the
  key.
- **Why warn-not-truncate.** Truncation is silent data loss at the auth boundary; pagination is the
  first-class fix.
- **Rejected:** post-load Swift sorting (prior art's self-flagged gap; OQ-L1-6 direction + C4's
  QueryBuilder seam make push-down free); a public engine entry (no consumer until C8); a
  whole-container engine entry (B-1); cache keyed by type alone (OQ-L1-4); a second sort wire format
  (reserved named item beside the untouched query blob is the minimal correct multiplex); truncating
  threshold; joined-parent sort mappings in v1.

## Decisions (RESOLVED by David, 2026-07-04)

- **D-C6-1 — `ContainerAuthorization` ships now (shared, public); provider stays C3.** **RESOLVED: yes.**
- **D-C6-2 — `ServerRequest.init` gains `sort:` as the canonical initializer** (+ protocol-extension
  compatibility convenience — structurally the only bridge Swift allows; requirements can't default
  parameters). **RESOLVED: yes.**
- **D-C6-3 — Query→predicate filter push-down deferred** until a filtering consumer appears; the
  refinement-as-cache-key makes the future field collision-safe by construction. **RESOLVED: defer.**

## Review reconciliation (2026-07-04; spec-document + FOSMVVM-discipline reviewers)

Initial draft verdicts: Blockers / Request-changes — all folded in:

- **Unit of load (both reviewers' blocker):** engine call now scoped to one (container, containedType)
  pair — `containing:` parameter; whole-container sweep demoted to an explicit non-goal; multi-relation
  same-type semantics documented (per-relation refinement, declaration order).
- **`AnySortTerm` defined** (was an undefined "ErasedSortTerm" at three seams): package struct, manual
  `Hashable` via `AnyHashable`, typed-factory-only construction, `SortCriteria.erasedTerms` bridge.
- **Sort URL wire respecified against the shipped machinery** (the "same queryItems path" claim was
  unimplementable — shipped code decodes the whole `url.query` as the query JSON): query blob untouched,
  reserved named `sort=` item, parse strips before query decode, old URLs round-trip by construction;
  public `Request.serverRequestSort(ofType:)` added as the named parse surface.
- **`.unregisteredNamespace` is a NEW `ContainmentError` case** (the draft mis-cited it as existing C4
  API); `unsortableContainedType` payloads specified.
- **`ContainerAuthorization` example is a value snapshot** (a persisted Fluent grant *class* can't be
  `Sendable`), with `any FOSMVVM.Model.Type` disambiguation; added the
  `Sequence<ContainerOperation>.authorizes(_:)` helper so wildcard-dropping `contains` isn't the easy
  path.
- **Cache:** keys on `ContainmentQueryRefinement` as a `Hashable` value (additive fields can't miss the
  key); one-authorization-set-per-Request contract stated (OQ-L1-4 closed *under that contract*);
  snapshot-sharing/no-reader-mutation contract stated; empty results cached.
**Implementation finding (2026-07-04, Task 2 review):** the example's original storage shape
(`recordTypes: [any Model.Type]`) makes every `Sendable` conformer warn under Swift 6 (non-Sendable
existential metatype in stored state) — and was architecturally wrong anyway: a grant row cannot decode
a live metatype, and metatype `==` bypasses `modelIdentityNamespace` overrides. Canonical shape (above):
store `[ModelNamespace]` and compare via `recordType.modelIdentityNamespace` — persistence-true,
identity-consistent, warning-free. The protocol requirement (`ofType recordType: any Model.Type`) is
unchanged (engines pass concrete metatypes, which are Sendable).

- Minors: threshold logs the type name (`ModelNamespace` stays sealed) and is deliberately default-only;
  `Berth` gains denormalized `dockName` (joined-parent sorts out of v1 — `Field.Model == M`); `.parent`
  ignores sort *and* window with the lossless rationale; test 6's assertion basis pinned to element
  identity; test-Request minting specified; line-level wording fixes (filter out of the OQ-L1-6 claim;
  C6a FluentKit constraints discharged against the checkout).
