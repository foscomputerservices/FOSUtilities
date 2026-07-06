# Layer 1 · C1 + C2 — Container, Operation Vocabulary & Client-Chosen Sort (Design Spec)

**Status:** Draft for review.
**Date:** 2026-07-03
**Layer:** 1, components **C1 + C2** of `2026-07-03-authorized-container-data-loading-architecture.md`.
**Targets:** FOSMVVM only. **No FOSMVVMVapor / FOSMacros / Fluent in this spec.**
**Depends on:** Layer 0 (`ModelIdentity`, `Model`). **Blocks:** C4/C6 (load engine), C3 (auth), C8 (factory).

> This is the first detailed spec spawned from the L1 architecture. It covers the **shared, Fluent-free
> vocabulary** two components need: C1 (`Container` + the `ContainerOperation` authorization verbs) and
> C2 (first-class, client-chosen **sort**, plus **pagination**). Everything here is pure FOSMVVM — no
> persistence, no query execution; those arrive in the Vapor-side specs that build on this vocabulary.
> Gated through `fosmvvm-planning` (design → customer-DocC → contract tests); rationale is in §"Design
> rationale", not in the DocC.

## Purpose

Give the shared module the **words** the container system speaks, before any machinery uses them:

- **What a container is** and **what it owns** (`Container` / `containedRecordTypes`).
- **The verbs** a subject can be authorized to perform on a container's records (`ContainerOperation`),
  checked by **intent** (`authorizesReadRecords`), never by case comparison.
- **How a client asks for an order** (`SortCriteria` over published `SortKey` dimensions) as a
  first-class, wire-carried request concern — an opportunity the request protocol previously lacked.
- **How a client asks for a page** (`PaginatedQuery` / `Pagination`) as an opt-in query trait.

All four are independently valuable and independently testable **without** any load engine.

## Scope (what ships in this spec)

1. `Container: Model` protocol — `containedRecordTypes` requirement **+** default `[]`.
2. `ContainerOperation` enum — 6 cases; **runtime metadata only, deliberately NOT `Codable`**;
   `authorizes…Records` accessors on the enum **and** on `Sequence` of it.
3. `ServerRequestSort` marker protocol; `SortKey`, `SortDirection`, `SortTerm<Key>`, `SortCriteria<Key>`.
4. `ServerRequest` gains `associatedtype Sort: ServerRequestSort = EmptySort` + `var sort: Sort? { get }`
   + `EmptySort`; `sort` is serialized into the request URL alongside `Query`.
5. `PaginatedQuery` trait protocol + `Pagination` value.
6. Contract tests for all of the above.

## Non-goals (explicitly deferred)

- `RecordOperation` and any distinct `Record` protocol tier — **OQ-L1-3 resolved: not now.** `Model` is
  the record tier; container-scoped checks need only `ContainerOperation`. Add `RecordOperation` + the
  bridge if a record-vs-container-granularity consumer appears.
- **Serializing `ContainerOperation`** — it is runtime metadata only; add `Codable` deliberately (as a
  sealed token) only when something must persist/transmit an operation set.
- The Vapor `SortKey → [KeyPath]` mapping (C6a), `ContainerCardinality`, the load engine, the registry,
  the request-scoped cache → later L1 specs.
- The **UI → `SortCriteria`** binding (column-header taps) → View layer (OQ-L1-7).

## Types & placement

All new types live in **FOSMVVM**. `Container` sits with `Model` (`Sources/FOSMVVM/Protocols/`); the sort
and pagination types sit with the request protocols (`Sources/FOSMVVM/Protocols/` alongside
`ServerRequest.swift`), placement to be finalized in the plan. No file in this spec imports Fluent/Vapor.

---

### C1.1 `Container` (`Protocols/Container.swift`)

**Customer DocC (drafted first):**

```swift
/// A ``Model`` that owns and authorizes other records.
///
/// Conform a model that contains others — a `Dock` owns its `Berth`s — and list what it contains:
///
/// ```swift
/// struct Dock: Container {
///     static var containedRecordTypes: [any Model.Type] { [Berth.self] }
///     // ...Model requirements (id, requireId(), modelIdentityNamespace)...
/// }
/// ```
///
/// A container's contained types drive authorized loading and live-invalidation membership. A model that
/// owns nothing needs no override — it inherits the empty default.
public protocol Container: Model {
    /// The record types this container owns.
    static var containedRecordTypes: [any Model.Type] { get }
}

public extension Container {
    static var containedRecordTypes: [any Model.Type] { [] }   // zero-config default
}
```

- **Requirement + default** (not extension-only): the default gives zero-config; a real container
  overrides. Extension-only would silently shadow rather than dispatch through `Container`.
- `Container: Model` — a container *is* a model (it has `ModelIdentity`); no separate reference type.
- `[any Model.Type]` is a **metatype list**, not existential-as-data (sanctioned).

### C1.2 `ContainerOperation` (`Protocols/ContainerOperation.swift`)

**Customer DocC (drafted first):**

```swift
/// The operations a subject can be authorized to perform on a container's records.
///
/// Check authorization by **intent**, never by comparing cases — this honors the ``anyOperation``
/// wildcard and stays correct as operations are added:
///
/// ```swift
/// if grantedOperations.authorizesReadRecords {   // grantedOperations: [ContainerOperation]
///     // ...load the records...
/// }
/// ```
public enum ContainerOperation: Hashable, CaseIterable, Sendable {
    /// Read the records the container owns.
    case readRecords
    /// Modify the records the container owns.
    case writeRecords
    /// Create new records in the container.
    case createRecords
    /// Mark the container's records deleted (recoverable).
    case deleteRecords
    /// Permanently destroy the container's records (unrecoverable).
    case destroyRecords
    /// Wildcard: authorizes every operation **except** ``destroyRecords``, which must be granted explicitly.
    case anyOperation
}
```

**Intent accessors (the sanctioned way to check — OCP):**

```swift
public extension ContainerOperation {
    /// `true` if this operation authorizes reading the container's records.
    var authorizesReadRecords: Bool { self == .anyOperation || self == .readRecords }
    var authorizesWriteRecords: Bool { self == .anyOperation || self == .writeRecords }
    var authorizesCreateRecords: Bool { self == .anyOperation || self == .createRecords }
    var authorizesDeleteRecords: Bool { self == .anyOperation || self == .deleteRecords }
    /// `true` only for ``destroyRecords`` — the wildcard deliberately does **not** grant destroy.
    var authorizesDestroyRecords: Bool { self == .destroyRecords }
}

public extension Sequence where Element == ContainerOperation {
    /// `true` if **any** operation in the set authorizes reading the container's records.
    var authorizesReadRecords: Bool { contains(where: \.authorizesReadRecords) }
    var authorizesWriteRecords: Bool { contains(where: \.authorizesWriteRecords) }
    var authorizesCreateRecords: Bool { contains(where: \.authorizesCreateRecords) }
    var authorizesDeleteRecords: Bool { contains(where: \.authorizesDeleteRecords) }
    var authorizesDestroyRecords: Bool { contains(where: \.authorizesDestroyRecords) }
}
```

- **Not `Codable`** (David): runtime metadata only. `Hashable` (usable in sets of granted operations),
  `CaseIterable` (wildcard/iteration), `Sendable` (concurrency). No `rawValue` surface.
- **`destroyRecords` is excluded from `anyOperation`** — destruction is always explicit.

---

### C2.1 Sort vocabulary (`Protocols/ServerRequestSort.swift`)

**Customer DocC (drafted first) — `SortKey`, then `SortCriteria`:**

```swift
/// The sortable dimensions a container publishes to clients — *meanings*, never storage columns.
///
/// Declare an enum of what a client may sort by:
///
/// ```swift
/// enum BerthSortKey: String, SortKey { case number, dockName, updatedAt }
/// ```
///
/// The server maps each dimension to one or more sort keypaths; the client only ever names a dimension,
/// so renaming a column never reaches the wire.
public protocol SortKey: Codable, Hashable, Sendable {}

/// Ascending or descending order for a ``SortTerm``.
public enum SortDirection: Codable, Hashable, Sendable { case ascending, descending }

/// One ordering term: a published ``SortKey`` dimension and its direction.
public struct SortTerm<Key: SortKey>: Codable, Hashable, Sendable {
    public let key: Key
    public let direction: SortDirection
    public init(key: Key, direction: SortDirection) { self.key = key; self.direction = direction }
}

/// A client's chosen ordering for a container's records: an ordered list of ``SortTerm``s.
///
/// ```swift
/// // Sort berths by dock name, then by number descending:
/// let sort = SortCriteria<BerthSortKey>([
///     .init(key: .dockName, direction: .ascending),
///     .init(key: .number, direction: .descending),
/// ])
/// let request = BerthsRequest(sort: sort)
/// ```
///
/// Terms apply in order (primary, secondary, …).
public struct SortCriteria<Key: SortKey>: ServerRequestSort {
    public let terms: [SortTerm<Key>]
    public init(_ terms: [SortTerm<Key>]) { self.terms = terms }
}

/// The wire contract for a request's sort. See ``SortCriteria`` for the standard implementation.
public protocol ServerRequestSort: Codable, Hashable, Sendable {}
```

- `SortDirection` is a **plain (non-raw-value) enum** — an ordinary request parameter, not a security
  token, so no sealed discipline (§"Design rationale" on why the wire shape is free to be synthesized).
- `SortTerm` is a **struct, not a tuple** — tuples don't synthesize `Codable`/`Hashable`.
- `SortCriteria` is **ordered**; multi-term ordering is order-sensitive.

### C2.2 `Sort` on `ServerRequest` (`Protocols/ServerRequest.swift`, `Protocols/EmptySort.swift`)

```swift
/// The used-but-empty default sort for a request that exposes no ordering (mirrors `EmptyQuery`).
public struct EmptySort: ServerRequestSort { public init() {} }

public protocol ServerRequest /* …existing… */ {
    // …existing associated types (Query, Fragment, RequestBody, ResponseBody, ResponseError)…
    associatedtype Sort: ServerRequestSort = EmptySort
    var sort: Sort? { get }
}

public extension ServerRequest where Sort == EmptySort {
    var sort: EmptySort? { nil }   // convenience: unsorted requests need not implement it
}
```

- **Defaulted associated type + convenience** exactly mirrors the existing `Query == EmptyQuery` pattern,
  so **every existing request keeps compiling unchanged** (source-compatible, additive).
- `sort` is serialized into the request URL alongside `Query` (same `queryItems(from:)` machinery); the
  plan wires this and adds a round-trip test.

### C2.3 Pagination (`Protocols/PaginatedQuery.swift`)

**Customer DocC (drafted first):**

```swift
/// A window into a result set: where to start and how many to return.
///
/// ```swift
/// let firstPage = Pagination(startIndex: 0, maxResults: 25)
/// ```
public struct Pagination: Codable, Hashable, Sendable {
    /// Zero-based index of the first record to return; `nil` starts at the beginning.
    public let startIndex: Int?
    /// Maximum records to return; `nil` is unbounded (subject to the server's max-records guard).
    public let maxResults: Int?
    public init(startIndex: Int? = nil, maxResults: Int? = nil) { self.startIndex = startIndex; self.maxResults = maxResults }
}

/// A ``ServerRequestQuery`` that pages through a large result set.
///
/// Conform your query only when it needs paging — non-paginated queries stay as they are:
///
/// ```swift
/// struct BerthsQuery: PaginatedQuery {
///     var pagination: Pagination { .init(startIndex: 0, maxResults: 25) }
///     // ...ServerRequestQuery requirements...
/// }
/// ```
///
/// The load engine applies the window when a request's query conforms, and returns the full authorized
/// set otherwise.
public protocol PaginatedQuery: ServerRequestQuery {
    var pagination: Pagination { get }
}
```

- **Opt-in trait on `Query`**, not a `ServerRequest` field — keeps the core request surface minimal; the
  engine reads it by trait inspection (`(query as? any PaginatedQuery)?.pagination`), the sanctioned
  optional-capability pattern. (Engine code is a later Vapor spec; only the vocabulary ships here.)

---

## Testing (contract tests — behavior, public path only)

Swift Testing; repo round-trip helpers (`try value.toJSON().fromJSON()`); **no `@testable`, no raw-JSON
or encoded-shape assertions.**

1. **`Container` default vs override** — a `Model` that doesn't override gets `[]`; a container declaring
   `containedRecordTypes` returns its types; dispatch **through `Container.self`**, not the concrete type.
2. **`ContainerOperation` intent** — each `authorizes…Records` is true for its own case and for
   `.anyOperation` **except** `authorizesDestroyRecords` (true only for `.destroyRecords`, false for
   `.anyOperation`); false for unrelated cases.
3. **`[ContainerOperation]` intent** — a set authorizes X iff any element does; empty set authorizes
   nothing; a set containing `.anyOperation` authorizes read/write/create/delete but **not** destroy.
4. **`ContainerOperation` in a `Set`** — `Hashable` behaves (dedupes, membership) — proves the metadata
   use-case without `Codable`.
5. **`SortCriteria` order + round-trip** — terms preserve declared order; a multi-term criteria
   `try sort.toJSON().fromJSON()` equals the original (behavior, not shape); `SortTerm`/`SortDirection`
   equality + round-trip.
6. **`Sort` on a request** — a request with `Sort == EmptySort` has `sort == nil` via the convenience; a
   request declaring a real `Sort` carries it and it survives the request's URL round-trip
   (build URL → parse back → equal sort). No representation assertion.
7. **`Pagination` / `PaginatedQuery`** — a conforming query exposes its `pagination`; a non-conforming
   query yields `nil` under `as? any PaginatedQuery` (proves opt-in); `Pagination` round-trips.

## Risks & mitigations

- **New `ServerRequest` associated type** could break an exotic conformer. Mitigation: `Sort` is defaulted
  to `EmptySort` and the `where Sort == EmptySort` convenience supplies `sort`, so existing requests are
  untouched; verify a full `swift build`/`swift test` across targets in the plan.
- **`as? any PaginatedQuery`** uses an existential. Mitigation: this is the sanctioned optional-capability
  trait check (a single self-inspection), not existential-as-data; the constrained-extension alternative
  (`where Query: PaginatedQuery`) is noted but fragments the engine — revisit only if the cast is hot.
- **`SortKey`/`SortCriteria` wire form** is a *request parameter*, re-sent each request and versioned with
  the client/server together — **not** a frozen persistence format, so its encoding may evolve; tests
  assert round-trip behavior, never a byte shape.

## Definition of done

- All new public API compiles across FOSMVVM (+ dependents compile); `swiftformat`/`swiftlint` clean.
- All 7 contract-test groups pass — no `@testable`, no representation assertions.
- Every new public symbol has customer-facing DocC **with an example** (drafted above).
- No new file imports Fluent/Vapor (grep-verified).
- CHANGELOG entry drafted (additive; `ServerRequest` gains a defaulted `Sort`).

## Design rationale (why-this-way — the implementer's notes, kept out of the DocC)

- **`ContainerOperation` is not `Codable`.** It is consumed only in-memory during authorization checks; no
  wire/persistence consumer exists (the role→grant model that *would* persist operation sets is app-domain,
  C3). Adding `Codable` now would be speculative surface *and* would freeze an encoding prematurely — so
  we defer it, and if it ever ships it ships as a sealed token (no `String` raw value: an authorization
  verb with a public `rawValue` is a stringly security handle). YAGNI applied deliberately.
- **No `RecordOperation` / `Record` tier yet.** `Model` is already the identity root (L0); container-scoped
  authorization needs only the container verbs. A record-vs-container distinction was prior-art machinery
  tied to a role model we don't ship — deferred until a consumer needs it (OQ-L1-3).
- **Sort is a separate associated type, not folded into `Query`.** SRP: `Query`'s filter selects *which*
  records form the population (container-specific); `Sort` orders *any* population (a reusable concern).
  Folding them re-mixes what should be separated and denies non-filtered requests a clean sort.
- **Named dimensions, not columns.** `SortKey` cases are published *meanings*; the client can't encode a
  key the container didn't declare (decode rejects it), and a storage-column rename never reaches the wire.
  A single dimension may expand server-side to several keypaths (C6a) — composable field-sorting and
  named-orders are the same primitive.
- **Pagination via optional `Query` conformance, not a `ServerRequest` field.** Pagination is identical in
  shape for every request, so a per-request field would be surface bloat on the core protocol; the
  trait-overlay keeps `ServerRequest` minimal and lets each query opt in. (David's call, 2026-07-03.)
- **`SortTerm` struct over a tuple; `SortDirection` plain enum.** Structs synthesize `Codable`/`Hashable`
  (tuples don't); `SortDirection` needs no sealed discipline because it is a value, not an identity/token —
  its synthesized wire form is acceptable precisely because `SortCriteria` is a transient request parameter,
  not a frozen persisted contract.
- **Rejected:** a `String`-raw `ContainerOperation` (stringly security token); `ExpressibleByStringLiteral`
  anywhere; a `Pagination` field on `ServerRequest` (surface bloat); a bespoke second serialization for
  any already-`Codable` value.
