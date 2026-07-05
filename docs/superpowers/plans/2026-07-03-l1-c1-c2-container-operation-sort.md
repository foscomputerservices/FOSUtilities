# L1 · C1 + C2 — Container, Operation Vocabulary & Client-Chosen Sort — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the shared, Fluent-free container vocabulary — `Container`, `ContainerOperation`, client-chosen `SortCriteria`, and opt-in `Pagination` — to FOSMVVM, with contract tests.

**Architecture:** Pure FOSMVVM protocol/value types (`Sources/FOSMVVM/Protocols/`). `Container: Model`; `ContainerOperation` is runtime metadata (not `Codable`); sort is a new **defaulted** associated type on `ServerRequest` (additive, existing requests untouched); pagination is an opt-in `PaginatedQuery` trait on `Query`. No Fluent, no Vapor, no macros.

**Tech Stack:** Swift 6, Swift Testing, `swiftformat`, `swiftlint`. Round-trip via repo `toJSON()`/`fromJSON()` helpers.

**Spec:** `docs/superpowers/specs/2026-07-03-container-operation-sort-design.md`
**Frame:** `docs/superpowers/specs/2026-07-03-authorized-container-data-loading-architecture.md` (C1, C2).

**Scope note (refined during planning):** the end-to-end **sort URL encode↔parse round-trip** and the **"how a request receives a sort at its designated init"** decision are **deferred to the C6 Vapor materialization spec** (where the server actually parses+constructs a request from a sort). This plan ships the vocabulary + the additive `ServerRequest.Sort` surface + Codable round-trip tests only. All changes are source-compatible.

---

## File Structure

**Create (Sources):**
- `Sources/FOSMVVM/Protocols/Container.swift` — `Container: Model` protocol + `containedRecordTypes` default.
- `Sources/FOSMVVM/Protocols/ContainerOperation.swift` — `ContainerOperation` enum + `authorizes…` accessors (enum + `Sequence`).
- `Sources/FOSMVVM/Protocols/ServerRequestSort.swift` — `ServerRequestSort`, `SortKey`, `SortDirection`, `SortTerm`, `SortCriteria`, `EmptySort`.
- `Sources/FOSMVVM/Protocols/PaginatedQuery.swift` — `Pagination` + `PaginatedQuery`.

**Modify (Sources):**
- `Sources/FOSMVVM/Protocols/ServerRequest.swift` — add `associatedtype Sort: ServerRequestSort = EmptySort`, `var sort: Sort? { get }`, and the `where Sort == EmptySort` nil convenience.

**Create (Tests):**
- `Tests/FOSMVVMTests/Protocols/ContainerOperationTests.swift`
- `Tests/FOSMVVMTests/Protocols/ContainerTests.swift`
- `Tests/FOSMVVMTests/Protocols/ServerRequestSortTests.swift`
- `Tests/FOSMVVMTests/Protocols/PaginationTests.swift`

Every new file gets the Apache 2.0 header (`Copyright 2026 FOS Computer Services, LLC`) — `swiftformat .` inserts it. DocC on every public symbol is copied verbatim from the spec (already customer-first with examples).

---

## Task 1: `ContainerOperation` + intent accessors

**Files:**
- Create: `Sources/FOSMVVM/Protocols/ContainerOperation.swift`
- Test: `Tests/FOSMVVMTests/Protocols/ContainerOperationTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import FOSMVVM
import Foundation
import Testing

@Suite("ContainerOperation")
struct ContainerOperationTests {
    @Test("Single op authorizes only its own intent (+ anyOperation, except destroy)")
    func singleOpIntent() {
        #expect(ContainerOperation.readRecords.authorizesReadRecords)
        #expect(!ContainerOperation.readRecords.authorizesWriteRecords)

        // anyOperation grants everything EXCEPT destroy
        #expect(ContainerOperation.anyOperation.authorizesReadRecords)
        #expect(ContainerOperation.anyOperation.authorizesWriteRecords)
        #expect(ContainerOperation.anyOperation.authorizesCreateRecords)
        #expect(ContainerOperation.anyOperation.authorizesDeleteRecords)
        #expect(!ContainerOperation.anyOperation.authorizesDestroyRecords)

        // destroy is explicit-only
        #expect(ContainerOperation.destroyRecords.authorizesDestroyRecords)
        #expect(!ContainerOperation.destroyRecords.authorizesReadRecords)
    }

    @Test("A set authorizes an intent iff any element does")
    func sequenceIntent() {
        let ops: [ContainerOperation] = [.readRecords, .createRecords]
        #expect(ops.authorizesReadRecords)
        #expect(ops.authorizesCreateRecords)
        #expect(!ops.authorizesWriteRecords)
        #expect(![ContainerOperation]().authorizesReadRecords) // empty grants nothing

        let anyOps: [ContainerOperation] = [.anyOperation]
        #expect(anyOps.authorizesDeleteRecords)
        #expect(!anyOps.authorizesDestroyRecords)
    }

    @Test("Usable as Set metadata (Hashable, no Codable needed)")
    func hashableSet() {
        let set: Set<ContainerOperation> = [.readRecords, .readRecords, .writeRecords]
        #expect(set.count == 2)
        #expect(set.contains(.readRecords))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ContainerOperationTests`
Expected: FAIL to compile — `ContainerOperation` not found.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

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

public extension ContainerOperation {
    /// `true` if this operation authorizes reading the container's records.
    var authorizesReadRecords: Bool { self == .anyOperation || self == .readRecords }
    /// `true` if this operation authorizes modifying the container's records.
    var authorizesWriteRecords: Bool { self == .anyOperation || self == .writeRecords }
    /// `true` if this operation authorizes creating records in the container.
    var authorizesCreateRecords: Bool { self == .anyOperation || self == .createRecords }
    /// `true` if this operation authorizes (recoverably) deleting the container's records.
    var authorizesDeleteRecords: Bool { self == .anyOperation || self == .deleteRecords }
    /// `true` only for ``destroyRecords`` — the wildcard deliberately does **not** grant destroy.
    var authorizesDestroyRecords: Bool { self == .destroyRecords }
}

public extension Sequence where Element == ContainerOperation {
    /// `true` if **any** operation in the set authorizes reading the container's records.
    var authorizesReadRecords: Bool { contains(where: \.authorizesReadRecords) }
    /// `true` if **any** operation in the set authorizes modifying the container's records.
    var authorizesWriteRecords: Bool { contains(where: \.authorizesWriteRecords) }
    /// `true` if **any** operation in the set authorizes creating records in the container.
    var authorizesCreateRecords: Bool { contains(where: \.authorizesCreateRecords) }
    /// `true` if **any** operation in the set authorizes (recoverably) deleting the container's records.
    var authorizesDeleteRecords: Bool { contains(where: \.authorizesDeleteRecords) }
    /// `true` if **any** operation in the set authorizes destroying the container's records.
    var authorizesDestroyRecords: Bool { contains(where: \.authorizesDestroyRecords) }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter ContainerOperationTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
swiftformat . && swiftlint
git add Sources/FOSMVVM/Protocols/ContainerOperation.swift Tests/FOSMVVMTests/Protocols/ContainerOperationTests.swift
git commit -m "feat(fosmvvm): add ContainerOperation authorization vocabulary"
```

---

## Task 2: `Container` protocol + default

**Files:**
- Create: `Sources/FOSMVVM/Protocols/Container.swift`
- Test: `Tests/FOSMVVMTests/Protocols/ContainerTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import FOSFoundation
import FOSMVVM
import Foundation
import Testing

@Suite("Container")
struct ContainerTests {
    // A container that owns Berths.
    struct Dock: Container {
        var id: ModelIdType?
        static var containedRecordTypes: [any Model.Type] { [Berth.self] }
        init(id: ModelIdType? = nil) { self.id = id }
    }
    // A leaf model that owns nothing — inherits the empty default.
    struct Berth: Container {
        var id: ModelIdType?
        init(id: ModelIdType? = nil) { self.id = id }
    }

    @Test("Override returns declared contained types (dispatched through Container.self)")
    func override() {
        func containedTypes(of type: some Container.Type) -> [any Model.Type] { type.containedRecordTypes }
        #expect(containedTypes(of: Dock.self).count == 1)
        #expect(containedTypes(of: Dock.self).first is Berth.Type)
    }

    @Test("A model that owns nothing inherits the empty default")
    func emptyDefault() {
        #expect(Berth.containedRecordTypes.isEmpty)
    }
}
```

> Note: `Container` requires the `Model` members (`id`, `requireId()`, `modelIdentityNamespace`). If L0's `Model` is not yet implemented in this branch, the test `Dock`/`Berth` provide `id` and rely on `Model`'s defaults; adjust the minimal conformance to whatever `Model` currently requires. Verify against `Sources/FOSMVVM/Protocols/Model.swift` before writing.

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ContainerTests`
Expected: FAIL to compile — `Container` not found.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// A ``Model`` that owns and authorizes other records.
///
/// Conform a model that contains others — a `Dock` owns its `Berth`s — and list what it contains:
///
/// ```swift
/// struct Dock: Container {
///     static var containedRecordTypes: [any Model.Type] { [Berth.self] }
///     // ...Model requirements (id, requireId(), …)...
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
    static var containedRecordTypes: [any Model.Type] { [] }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter ContainerTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
swiftformat . && swiftlint
git add Sources/FOSMVVM/Protocols/Container.swift Tests/FOSMVVMTests/Protocols/ContainerTests.swift
git commit -m "feat(fosmvvm): add Container protocol with containedRecordTypes"
```

---

## Task 3: Sort vocabulary (`SortKey`, `SortDirection`, `SortTerm`, `SortCriteria`, `ServerRequestSort`)

**Files:**
- Create: `Sources/FOSMVVM/Protocols/ServerRequestSort.swift`
- Test: `Tests/FOSMVVMTests/Protocols/ServerRequestSortTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import FOSFoundation
import FOSMVVM
import Foundation
import Testing

@Suite("ServerRequestSort")
struct ServerRequestSortTests {
    enum BerthSortKey: String, SortKey { case number, dockName, updatedAt }

    @Test("SortCriteria preserves term order")
    func order() {
        let sort = SortCriteria<BerthSortKey>([
            .init(key: .dockName, direction: .ascending),
            .init(key: .number, direction: .descending),
        ])
        #expect(sort.terms.map(\.key) == [.dockName, .number])
        #expect(sort.terms.map(\.direction) == [.ascending, .descending])
    }

    @Test("SortCriteria round-trips through JSON, value-preserving")
    func roundTrip() throws {
        let sort = SortCriteria<BerthSortKey>([
            .init(key: .number, direction: .ascending),
            .init(key: .updatedAt, direction: .descending),
        ])
        let back: SortCriteria<BerthSortKey> = try sort.toJSON().fromJSON()
        #expect(back == sort)
    }

    @Test("SortTerm & SortDirection equality")
    func terms() {
        #expect(SortTerm(key: BerthSortKey.number, direction: .ascending)
            == SortTerm(key: BerthSortKey.number, direction: .ascending))
        #expect(SortTerm(key: BerthSortKey.number, direction: .ascending)
            != SortTerm(key: BerthSortKey.number, direction: .descending))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ServerRequestSortTests`
Expected: FAIL to compile — sort types not found.

- [ ] **Step 3: Write the implementation** (copy DocC from the spec)

```swift
import Foundation

/// The wire contract for a request's sort. See ``SortCriteria`` for the standard implementation.
public protocol ServerRequestSort: Codable, Hashable, Sendable {}

/// The sortable dimensions a container publishes to clients — *meanings*, never storage columns.
///
/// ```swift
/// enum BerthSortKey: String, SortKey { case number, dockName, updatedAt }
/// ```
///
/// The server maps each dimension to one or more sort keypaths; the client only ever names a dimension,
/// so renaming a column never reaches the wire.
public protocol SortKey: Codable, Hashable, Sendable {}

/// Ascending or descending order for a ``SortTerm``.
public enum SortDirection: Codable, Hashable, Sendable {
    case ascending
    case descending
}

/// One ordering term: a published ``SortKey`` dimension and its direction.
public struct SortTerm<Key: SortKey>: Codable, Hashable, Sendable {
    public let key: Key
    public let direction: SortDirection
    public init(key: Key, direction: SortDirection) {
        self.key = key
        self.direction = direction
    }
}

/// A client's chosen ordering for a container's records: an ordered list of ``SortTerm``s.
///
/// ```swift
/// // Sort berths by dock name, then by number descending:
/// let sort = SortCriteria<BerthSortKey>([
///     .init(key: .dockName, direction: .ascending),
///     .init(key: .number, direction: .descending),
/// ])
/// ```
///
/// Terms apply in order (primary, secondary, …).
public struct SortCriteria<Key: SortKey>: ServerRequestSort {
    public let terms: [SortTerm<Key>]
    public init(_ terms: [SortTerm<Key>]) { self.terms = terms }
}

/// The used-but-empty default sort for a request that exposes no ordering (mirrors `EmptyQuery`).
public struct EmptySort: ServerRequestSort {
    public init() {}
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter ServerRequestSortTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
swiftformat . && swiftlint
git add Sources/FOSMVVM/Protocols/ServerRequestSort.swift Tests/FOSMVVMTests/Protocols/ServerRequestSortTests.swift
git commit -m "feat(fosmvvm): add client-chosen sort vocabulary (SortCriteria/SortKey)"
```

---

## Task 4: `Sort` on `ServerRequest` (additive associated type + convenience)

**Files:**
- Modify: `Sources/FOSMVVM/Protocols/ServerRequest.swift`
- Test: `Tests/FOSMVVMTests/Protocols/ServerRequestSortTests.swift` (extend)

- [ ] **Step 1: Write the failing tests** (append to the suite)

```swift
    // A request with no sort — Sort defaults to EmptySort; `sort` comes from the convenience.
    // `@unchecked Sendable` matches every real ServerRequest class conformer; `responseBody` and
    // `id` are supplied by the existing `where ResponseBody == EmptyBody` + AnyObject defaults.
    final class UnsortedRequest: ServerRequest, @unchecked Sendable {
        typealias Query = EmptyQuery
        typealias Fragment = EmptyFragment
        typealias RequestBody = EmptyBody
        typealias ResponseBody = EmptyBody
        typealias ResponseError = EmptyError
        let action: ServerRequestAction = .show
        init(query: EmptyQuery?, fragment: EmptyFragment?, requestBody: EmptyBody?, responseBody: EmptyBody?) {}
    }

    // A request that carries a real sort via its own stored property + init.
    final class SortedRequest: ServerRequest, @unchecked Sendable {
        typealias Query = EmptyQuery
        typealias Fragment = EmptyFragment
        typealias RequestBody = EmptyBody
        typealias ResponseBody = EmptyBody
        typealias ResponseError = EmptyError
        typealias Sort = SortCriteria<BerthSortKey>
        let action: ServerRequestAction = .show
        let sort: SortCriteria<BerthSortKey>?
        init(query: EmptyQuery?, fragment: EmptyFragment?, requestBody: EmptyBody?, responseBody: EmptyBody?) { sort = nil }
        init(sort: SortCriteria<BerthSortKey>?) { self.sort = sort }
    }

    @Test("Unsorted request has nil sort via the EmptySort convenience")
    func unsortedDefault() {
        let req = UnsortedRequest(query: nil, fragment: nil, requestBody: nil, responseBody: nil)
        #expect(req.sort == nil)
    }

    @Test("Sorted request carries its sort")
    func sortedCarries() {
        let sort = SortCriteria<BerthSortKey>([.init(key: .number, direction: .ascending)])
        let req = SortedRequest(sort: sort)
        #expect(req.sort == sort)
    }
```

> Verify the minimal `ServerRequest` conformance against the current protocol before writing — the exact stored members (`id`, `action`, `responseBody`) must satisfy `Identifiable`/`Hashable`/`Codable`. If `Codable`/`Identifiable` synthesis needs more, mirror an existing test conformer (e.g. `Tests/FOSMVVMTests/ReplaceRequestTests.swift`).

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ServerRequestSortTests`
Expected: FAIL — `sort` is not a member of `ServerRequest`.

- [ ] **Step 3: Modify `ServerRequest.swift`** — add the associated type + property to the protocol, and the convenience. In `public protocol ServerRequest`, after the `ResponseError` associated type and after `var responseBody`:

```swift
    associatedtype Sort: ServerRequestSort = EmptySort
    // ...
    var sort: Sort? { get }
```

And add a convenience extension next to the existing `where Query == EmptyQuery` one:

```swift
public extension ServerRequest where Sort == EmptySort {
    var sort: EmptySort? {
        nil
    }
}
```

> Do **not** add `sort` to the designated `init(query:fragment:requestBody:responseBody:)` and do **not** touch `queryItems(from:)` — the generic sort-at-init and URL wiring are deferred to the C6 Vapor spec (see plan header scope note). Existing conformers keep `Sort == EmptySort` by default and are unaffected.

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter ServerRequestSortTests` then `swift build`
Expected: PASS (5 tests); build green (proves existing requests still compile with the defaulted `Sort`).

- [ ] **Step 5: Commit**

```bash
swiftformat . && swiftlint
git add Sources/FOSMVVM/Protocols/ServerRequest.swift Tests/FOSMVVMTests/Protocols/ServerRequestSortTests.swift
git commit -m "feat(fosmvvm): add defaulted Sort associated type to ServerRequest"
```

---

## Task 5: `Pagination` + `PaginatedQuery`

**Files:**
- Create: `Sources/FOSMVVM/Protocols/PaginatedQuery.swift`
- Test: `Tests/FOSMVVMTests/Protocols/PaginationTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import FOSFoundation
import FOSMVVM
import Foundation
import Testing

@Suite("Pagination")
struct PaginationTests {
    struct PagedQuery: PaginatedQuery {
        var pagination: Pagination { .init(startIndex: 0, maxResults: 25) }
    }
    struct PlainQuery: ServerRequestQuery {}

    @Test("A conforming query exposes its window")
    func exposes() {
        #expect(PagedQuery().pagination.startIndex == 0)
        #expect(PagedQuery().pagination.maxResults == 25)
    }

    @Test("Pagination on a query is opt-in — a plain query is not a PaginatedQuery")
    func optIn() {
        let paged: any ServerRequestQuery = PagedQuery()
        let plain: any ServerRequestQuery = PlainQuery()
        #expect((paged as? any PaginatedQuery) != nil)
        #expect((plain as? any PaginatedQuery) == nil)
    }

    @Test("Pagination round-trips, value-preserving")
    func roundTrip() throws {
        let page = Pagination(startIndex: 50, maxResults: 25)
        let back: Pagination = try page.toJSON().fromJSON()
        #expect(back == page)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter PaginationTests`
Expected: FAIL to compile — `Pagination`/`PaginatedQuery` not found.

- [ ] **Step 3: Write the implementation** (copy DocC from the spec)

```swift
import Foundation

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
    public init(startIndex: Int? = nil, maxResults: Int? = nil) {
        self.startIndex = startIndex
        self.maxResults = maxResults
    }
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

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter PaginationTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
swiftformat . && swiftlint
git add Sources/FOSMVVM/Protocols/PaginatedQuery.swift Tests/FOSMVVMTests/Protocols/PaginationTests.swift
git commit -m "feat(fosmvvm): add opt-in PaginatedQuery pagination trait"
```

---

## Task 6: Full gate

- [ ] **Step 1:** `swift build` — Expected: green across FOSMVVM and dependents (proves the additive `Sort` associated type didn't break any conformer).
- [ ] **Step 2:** `swift test` — Expected: all suites pass, including the four new ones.
- [ ] **Step 3:** `swiftformat .` then `swiftlint` — Expected: no diffs, no violations. Confirm each new file carries the Apache 2.0 header.
- [ ] **Step 4:** `grep -rn "import Fluent\|import Vapor\|FluentKit" Sources/FOSMVVM/Protocols/Container.swift Sources/FOSMVVM/Protocols/ContainerOperation.swift Sources/FOSMVVM/Protocols/ServerRequestSort.swift Sources/FOSMVVM/Protocols/PaginatedQuery.swift` — Expected: **no output** (no Fluent/Vapor leaked into shared FOSMVVM).
- [ ] **Step 5:** Draft the CHANGELOG entry: "Added `Container`, `ContainerOperation`, client-chosen `SortCriteria`/`SortKey`, and opt-in `PaginatedQuery` pagination to FOSMVVM. `ServerRequest` gains a defaulted `Sort` associated type (additive)."
- [ ] **Step 6: Commit** any gate fixes.

---

## Definition of done (mirrors the spec)

- All new public API compiles across FOSMVVM (+ dependents); `swift test` green; `swiftformat`/`swiftlint` clean.
- The four contract-test suites pass — no `@testable`, no representation/byte-shape assertions.
- Every new public symbol has customer-facing DocC with an example.
- No new file imports Fluent/Vapor (Task 6 Step 4).
- CHANGELOG entry drafted.

## Deferred (not this plan)

- Sort URL **encode↔parse** round-trip and the **sort-at-designated-init** decision → C6 Vapor materialization spec.
- Serializing `ContainerOperation` → only if/when a consumer needs it (then as a sealed token).
- `SortKey → [KeyPath]` mapping, cardinality, registry, load engine → later L1 specs.
