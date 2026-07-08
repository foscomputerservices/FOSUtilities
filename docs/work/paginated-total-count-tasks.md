# Paginated total-count — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a factory the size of the authorized set a `PaginatedQuery` window is a view into, so a client can render window position ("showing 40–65 of 1,204,882").

**Architecture:** One new public symbol — `ProjectionContext.totalCount(for:)`, a sibling of `records(_:)`. Internally: a `count` closure on `ContainmentRelation` runs a `.count()` query (no window fetch); the executor deposits per-tuple counts into a new `containerRecordCountCache`; `serve` snapshots them into `ProjectionContext.countsByTuple`; the accessor reads them by the same handle `records(_:)` uses. Design is gated in `docs/work/paginated-total-count-plan.md` — read it first.

**Tech Stack:** Swift 6, Vapor, FluentKit, Swift Testing. Test harness: `withFluentTestApp` + the Harbor→Dock→{Berth,CrewMember} fixtures (`FOSTestingVapor`).

**Conventions:** Commit messages follow the repo's trailer convention. Granular local commits are fine; the branch is squashed to a few logical commits before any PR (do not open a PR — that gate is David's).

**TDD note:** the count is only observable end-to-end once all plumbing lands. So the *unit* seam (`ContainmentRelation.memberCount`) is driven test-first (Task 1); the interior plumbing (Tasks 2–4) compiles green per commit but is exercised by the end-to-end contract tests in Task 5. This is deliberate — do not fabricate per-file "observability" that does not exist.

---

## File Structure

**Modify (production):**
- `Sources/FOSMVVMVapor/Containment/ContainmentRelation.swift` — add a `count` closure + `memberCount(of:on:)`.
- `Sources/FOSMVVMVapor/Containment/ContainerRecordCache.swift` — add `containerRecordCountCache` storage; invalidate it too.
- `Sources/FOSMVVMVapor/Extensions/Request+ContainerLoad.swift` — compute+cache the count in `authorizedRecords(…sortedBy:pagination:)` when a window is present.
- `Sources/FOSMVVM/Protocols/ProjectionContext.swift` — add `countsByTuple` field + init param.
- `Sources/FOSMVVMVapor/Vapor Support/ServeRequest.swift` — add `countsByTuple()`; pass it into the context.
- `Sources/FOSMVVMVapor/Containment/ProjectionContext+Records.swift` — add `totalCount(for:)` + DocC.

**Create (tests):**
- `Tests/FOSMVVMVaporTests/Containment/MemberCountTests.swift` — the `memberCount` unit seam.
- `Tests/FOSMVVMVaporTests/Composition/TotalCountTests.swift` — the end-to-end contract tests.

---

## Task 1: `ContainmentRelation.memberCount` — count without fetching the window

**Files:**
- Modify: `Sources/FOSMVVMVapor/Containment/ContainmentRelation.swift`
- Test: `Tests/FOSMVVMVaporTests/Containment/MemberCountTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/FOSMVVMVaporTests/Containment/MemberCountTests.swift`:

```swift
// MemberCountTests.swift
//
// Copyright 2026 FOS Computer Services, LLC
//
// Licensed under the Apache License, Version 2.0 (the  License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Test-taxonomy discipline: the memberCount seam is internal (below C8's public surface),
// exercised via `@testable import FOSMVVMVapor`. Behavior only — no representation.

import FluentKit
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing

@Suite("Containment member counts")
struct MemberCountTests {
    /// The full member count of a to-many relation — the whole set, independent of any window.
    @Test func childrenMemberCountIsTheFullSet() async throws {
        let count = try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let (dock1, _) = try await seedHarbor(on: db) // dock1 has 3 berths
            return try await ContainmentRelation.children(\Dock.$berths).memberCount(of: dock1, on: db)
        }
        #expect(count == 3)
    }

    /// Siblings (pivot) count the whole set the same way.
    @Test func siblingsMemberCountIsTheFullSet() async throws {
        let count = try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let (dock1, _) = try await seedHarbor(on: db) // dock1 has 2 crew
            return try await ContainmentRelation.siblings(\Dock.$crew).memberCount(of: dock1, on: db)
        }
        #expect(count == 2)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter MemberCountTests`
Expected: FAIL to compile — `value of type 'ContainmentRelation' has no member 'memberCount'`.

- [ ] **Step 3: Add the `count` closure and `memberCount` to `ContainmentRelation`**

In `ContainmentRelation.swift`, add a stored `count` closure beside `load` (after the `load` property, ~line 45):

```swift
    /// The count twin of `load`: the size of the full authorized member set, run as a `.count()`
    /// query — never a fetch. Ignores sort and window (neither changes a count). When a filter axis
    /// is added to the refinement, apply it here too, in lockstep with `load`.
    private let count: @Sendable (any DataModel, any Database) async throws -> Int
```

Add it to the private `init` (after `load`):

```swift
    private init(
        containerType: any DataModel.Type,
        containedType: any DataModel.Type,
        load: @escaping @Sendable (any DataModel, any Database, ContainmentQueryRefinement) async throws -> [any DataModel],
        count: @escaping @Sendable (any DataModel, any Database) async throws -> Int,
        create: (@Sendable (any DataModel, any DataModel, any Database) async throws -> Void)?
    ) {
        self.containerType = containerType
        self.containedType = containedType
        self.load = load
        self.count = count
        self.create = create
    }
```

Supply `count` in all three factories:

`children(_:)` — add after its `load:` closure:
```swift
            count: { container, db in
                try await container.cast(to: From.self)[keyPath: keyPath].query(on: db).count()
            },
```

`siblings(_:)` — add after its `load:` closure:
```swift
            count: { container, db in
                try await container.cast(to: From.self)[keyPath: keyPath].query(on: db).count()
            },
```

`parent(_:)` — a to-one; add after its `load:` closure:
```swift
            count: { container, db in
                try await container.cast(to: From.self)[keyPath: keyPath].query(on: db).count()
            },
```

Add the wrapper in the `extension ContainmentRelation` block (beside `members`):
```swift
    /// The count of the full authorized member set — the total the window is a view into. Runs a
    /// `.count()` query; never fetches the rows. Same fetched-container PRECONDITION as `members`.
    func memberCount(of container: any DataModel, on db: any Database) async throws -> Int {
        try await count(container, db)
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter MemberCountTests`
Expected: PASS (both cases).

- [ ] **Step 5: Commit**

```bash
git add Sources/FOSMVVMVapor/Containment/ContainmentRelation.swift Tests/FOSMVVMVaporTests/Containment/MemberCountTests.swift
git commit -m "feat(FOSMVVMVapor): add ContainmentRelation.memberCount (count without fetch)"
```

---

## Task 2: The count cache

**Files:**
- Modify: `Sources/FOSMVVMVapor/Containment/ContainerRecordCache.swift`

No standalone test — this storage is exercised by Task 5's end-to-end tests. It compiles green on its own.

- [ ] **Step 1: Add the count cache storage**

In `ContainerRecordCache.swift`, in `extension Vapor.Request`, add beside `containerRecordCache` (after ~line 85):

```swift
    /// Per-window totals, keyed exactly as `containerRecordCache`: the size of the authorized set a
    /// windowed load is a view into. Written only when a load carries a window (unpaginated loads
    /// need no entry — their total equals the records they already returned). Same single-writer /
    /// snapshot-sharing contract as `containerRecordCache`.
    var containerRecordCountCache: [ContainerRecordCacheKey: Int] {
        get { storage[ContainerRecordCountCacheStore.self] ?? [:] }
        set { storage[ContainerRecordCountCacheStore.self] = newValue }
    }
```

- [ ] **Step 2: Invalidate it alongside the records**

Extend `invalidateContainerRecords(of:)` (~line 89) so a mutation drops the counts too:

```swift
    func invalidateContainerRecords(of container: ModelIdentity) {
        containerRecordCache = containerRecordCache.filter { $0.key.container != container }
        containerRecordCountCache = containerRecordCountCache.filter { $0.key.container != container }
    }
```

- [ ] **Step 3: Add the storage key**

Beside `MaxRecordsWarningThresholdStore` (~line 116):

```swift
private struct ContainerRecordCountCacheStore: StorageKey {
    typealias Value = [ContainerRecordCacheKey: Int]
}
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/FOSMVVMVapor/Containment/ContainerRecordCache.swift
git commit -m "feat(FOSMVVMVapor): add containerRecordCountCache keyed like the record cache"
```

---

## Task 3: Compute the count in the authorized engine

**Files:**
- Modify: `Sources/FOSMVVMVapor/Extensions/Request+ContainerLoad.swift`

Exercised by Task 5. The rule: the count runs **inside** the authorized path, after the grant check, so it can never count rows the caller is not authorized to see.

- [ ] **Step 1: Cache the count when a window is present**

In `authorizedRecords(via:of:containing:for:authorizedAs:sortedBy:pagination:)` (the 6-param overload, ~line 96), after the records loop caches `records` (currently `containerRecordCache[cacheKey] = records; return records` at ~line 151), insert the count computation *before* the cache write + return:

```swift
        // Total the window is a view into: only when a window is present (an unpaginated load's
        // total IS records.count — no query needed). Runs inside the authorized path, after the
        // grant check above, so it never counts rows the caller cannot see. Mirrors the records
        // loop's relation match.
        if refinement.pagination != nil {
            var total = 0
            for relation in descriptor.containment
                where ObjectIdentifier(relation.containedType) == ObjectIdentifier(containedType) {
                total += try await relation.memberCount(of: containerRecord, on: db)
            }
            containerRecordCountCache[cacheKey] = total
        }

        containerRecordCache[cacheKey] = records
        return records
```

> Note: the two early-return unauthorized branches (`containerRecordCache[cacheKey] = []; return []` at ~lines 126-128 and 136-138) deliberately write **no** count entry — an unauthorized load's total falls back to its (empty) record count. Leave them unchanged.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/FOSMVVMVapor/Extensions/Request+ContainerLoad.swift
git commit -m "feat(FOSMVVMVapor): cache the authorized window total inside authorizedRecords"
```

---

## Task 4: Thread counts through `ProjectionContext`

**Files:**
- Modify: `Sources/FOSMVVM/Protocols/ProjectionContext.swift`
- Modify: `Sources/FOSMVVMVapor/Vapor Support/ServeRequest.swift`

- [ ] **Step 1: Add `countsByTuple` to `ProjectionContext`**

In `ProjectionContext.swift`, add the field beside `recordsByTuple` (~line 50):

```swift
    package let recordsByTuple: [RecordLoadPlan.Tuple: [any Model]]
    // Per-tuple total the window is a view into; empty for a zero-data context. Read via
    // FOSMVVMVapor's `totalCount(for:)`, never as raw storage.
    package let countsByTuple: [RecordLoadPlan.Tuple: Int]
```

Update the data-bearing init to accept and store it (add the param after `recordsByTuple`, default `[:]` so existing call sites and tests keep compiling):

```swift
    package init(
        vmRequest: Request,
        appState: AppState,
        plan: RecordLoadPlan,
        recordsByTuple: [RecordLoadPlan.Tuple: [any Model]],
        countsByTuple: [RecordLoadPlan.Tuple: Int] = [:]
    ) {
        self.vmRequest = vmRequest
        self.appState = appState
        self.plan = plan
        self.recordsByTuple = recordsByTuple
        self.countsByTuple = countsByTuple
    }
```

Update the zero-data init to set `countsByTuple = [:]`:

```swift
    package init(
        vmRequest: Request,
        appState: AppState
    ) {
        self.vmRequest = vmRequest
        self.appState = appState
        self.plan = nil
        self.recordsByTuple = [:]
        self.countsByTuple = [:]
    }
```

- [ ] **Step 2: Snapshot the counts in `serve`**

In `ServeRequest.swift`, add a sibling of `recordsByTuple()` (after ~line 58):

```swift
    /// Flattens the count cache into the plan-tuple → total snapshot the ``ProjectionContext``
    /// carries. A tuple with a window entry uses the cached total; a tuple without one (unpaginated)
    /// falls back to the size of the records it deposited — so a non-windowed load's total is its
    /// record count, at no extra query. `package` so the test harness builds a context like `serve`.
    package func countsByTuple() -> [RecordLoadPlan.Tuple: Int] {
        var result: [RecordLoadPlan.Tuple: Int] = [:]
        for (tuple, keys) in tupleCacheKeys {
            result[tuple] = keys.reduce(0) { running, key in
                running + (containerRecordCountCache[key] ?? (containerRecordCache[key]?.count ?? 0))
            }
        }
        return result
    }
```

Pass it into the data-bearing context in `serve` (~line 41):

```swift
            context = .init(vmRequest: vmRequest, appState: appState, plan: plan, recordsByTuple: recordsByTuple(), countsByTuple: countsByTuple())
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: builds clean (the `= [:]` default keeps the existing `makeContext` test helper and any other call sites compiling).

- [ ] **Step 4: Commit**

```bash
git add Sources/FOSMVVM/Protocols/ProjectionContext.swift "Sources/FOSMVVMVapor/Vapor Support/ServeRequest.swift"
git commit -m "feat(FOSMVVM): carry per-tuple window totals on ProjectionContext"
```

---

## Task 5: The `totalCount(for:)` accessor + end-to-end contract tests

**Files:**
- Modify: `Sources/FOSMVVMVapor/Containment/ProjectionContext+Records.swift`
- Test: `Tests/FOSMVVMVaporTests/Composition/TotalCountTests.swift`

- [ ] **Step 1: Write the failing contract tests**

Create `Tests/FOSMVVMVaporTests/Composition/TotalCountTests.swift`. It mirrors `ProjectionContextTests.swift`'s harness (a paginated, refined-by-request Berth fixture) — copy that file's private `configureContainers`, `GrantProvider`/`GrantsKey`, `makeRequest`, `requestURL`, `grantDockReads`, and `DockRootedQuery` helpers, and add the paginated fixture below. The distinguishing wiring: the Query conforms to `PaginatedQuery`, and the Berth requirement is `.refinedByRequest`.

```swift
// TotalCountTests.swift
//
// Copyright 2026 FOS Computer Services, LLC
//
// Licensed under the Apache License, Version 2.0 (the  License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Test-taxonomy discipline: totalCount(for:) reads the executor's count snapshot back by declared
// handle, via `@testable import FOSMVVMVapor`. Behavior only — no encoded shape asserted.

import Fluent
import FluentKit
import FOSFoundation
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing
import Vapor

private struct GrantsKey: StorageKey { typealias Value = [TestGrant] }

private struct GrantProvider: ContainerAuthorizationProvider {
    func containerAuthorizations(for request: Request) async throws -> [TestGrant] {
        request.application.storage[GrantsKey.self] ?? []
    }
}

private func configureContainers(_ app: Application) throws {
    app.migrations.add(CreatePier())
    try app.register(Harbor.self, migration: CreateHarbor())
    try app.register(Dock.self, migration: CreateDock())
    app.migrations.add(CreateBerth())
    app.migrations.add(CreateCrewMember())
    app.migrations.add(CreateDockCrew())
    try app.useContainerAuthorizationProvider(GrantProvider())
}

private func makeRequest(on app: Application, url: URL? = nil) -> Vapor.Request {
    Request(application: app, method: .GET, url: URI(string: url?.absoluteString ?? "/"), on: app.eventLoopGroup.next())
}

private func requestURL(for request: some ServerRequest) throws -> URL {
    let base = try #require(URL(string: "http://localhost"))
    return try #require(try base.appending(serverRequest: request))
}

private func grantDockReadsBerths(_ app: Application, dock: Dock) throws {
    app.storage[GrantsKey.self] = try [
        TestGrant(
            authorizedContainer: dock.modelIdentity,
            operations: [.readRecords],
            recordTypes: [Berth.modelIdentityNamespace]
        )
    ]
}

/// A rooted query that ALSO carries a window — the search-window shape.
private struct PagedDockQuery: RootedQuery, PaginatedQuery {
    let rootIdentity: ModelIdentity
    let pagination: Pagination
}

/// A windowed Berth page: its Berth requirement is `.refinedByRequest`, so the query's window
/// binds to it. `body` reads records (windowed) AND the total.
private struct PagedDockVM: RequestableViewModel, ComposableFactory, VaporResponseBodyFactory {
    typealias Request = PagedDockRequest

    static let berths = LoadRequirement.read(Berth.self, in: .parentRoot).refinedByRequest
    static var dataRequirements: [any DataRequirement] { [berths] }

    var vmId = ViewModelId()
    init() {}
    func propertyNames() -> [LocalizableId: String] { [:] }
    static func stub() -> Self { .init() }

    static func body<R: ServerRequest>(context: ProjectionContext<R, Void>) throws -> Self where R.ResponseBody == Self {
        .init()
    }
}

private final class PagedDockRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = PagedDockQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: PagedDockQuery?
    var responseBody: PagedDockVM?

    init(query: PagedDockQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: PagedDockVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

/// Builds the context the way `serve` does — WITH the count snapshot.
private func makeContext(for vmRequest: PagedDockRequest, on req: Vapor.Request) -> ProjectionContext<PagedDockRequest, Void> {
    guard let plan = req.application.recordLoadPlan(for: PagedDockRequest.self) else {
        return .init(vmRequest: vmRequest, appState: ())
    }
    return .init(vmRequest: vmRequest, appState: (), plan: plan, recordsByTuple: req.recordsByTuple(), countsByTuple: req.countsByTuple())
}

@Suite("Paginated total-count")
struct TotalCountTests {
    /// The window returns a slice; the total is the whole authorized set.
    @Test func totalCountIsFullSetWhileRecordsAreWindowed() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: PagedDockRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db) // dock1 has 3 berths
            try grantDockReadsBerths(app, dock: dock1)

            let vmRequest = PagedDockRequest(query: .init(rootIdentity: dock1.modelIdentity, pagination: .init(startIndex: 0, maxResults: 1)))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            try await req.executeRecordLoadPlan(for: vmRequest)
            let context = makeContext(for: vmRequest, on: req)

            #expect(try context.records(PagedDockVM.berths).count == 1)   // windowed
            #expect(try context.totalCount(for: PagedDockVM.berths) == 3) // full set
        }
    }

    /// The total is the AUTHORIZED set — no grant, no count leak (0, not 3).
    @Test func totalCountRespectsAuthorization() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: PagedDockRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            app.storage[GrantsKey.self] = [] // no grant

            let vmRequest = PagedDockRequest(query: .init(rootIdentity: dock1.modelIdentity, pagination: .init(startIndex: 0, maxResults: 1)))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            try await req.executeRecordLoadPlan(for: vmRequest)
            let context = makeContext(for: vmRequest, on: req)

            #expect(try context.records(PagedDockVM.berths).isEmpty)
            #expect(try context.totalCount(for: PagedDockVM.berths) == 0)
        }
    }

    /// An unplanned handle throws — never returns 0 (mirrors records(_:)).
    @Test func unplannedHandleThrows() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: PagedDockRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            try grantDockReadsBerths(app, dock: dock1)

            let vmRequest = PagedDockRequest(query: .init(rootIdentity: dock1.modelIdentity, pagination: .init(startIndex: 0, maxResults: 1)))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            try await req.executeRecordLoadPlan(for: vmRequest)
            let context = makeContext(for: vmRequest, on: req)

            let undeclared = LoadRequirement.read(Pier.self, in: .parentRoot)
            do {
                _ = try context.totalCount(for: undeclared)
                Issue.record("expected a throw for an unplanned requirement, not 0")
            } catch let error as ContainmentError {
                guard case .unplannedRequirement = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
        }
    }
}
```

> If, on running, the window fixture's requirement does not bind the query's pagination (the tuple isn't marked refined-by-request as expected), verify against `PlanRegistration.swift:168-174` (`declaresWindow`) and `DataRequirement.swift:198` (`refinedByRequest`) — those pin how a windowed requirement is declared. Do not weaken an assertion to make it pass.

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter TotalCountTests`
Expected: FAIL to compile — `no member 'totalCount'` and `no member 'countsByTuple'` on Request (the latter lands in Task 4; if Task 4 is committed, only `totalCount` is missing).

- [ ] **Step 3: Add the accessor + DocC**

In `ProjectionContext+Records.swift`, inside the existing `public extension ProjectionContext`, add after `records(_:)`:

```swift
    /// The total number of records the window pages through — read by the SAME handle the factory
    /// declared, alongside ``records(_:)``.
    ///
    /// A ``PaginatedQuery`` returns only a window; the View needs the full set's size to render
    /// position — a scroll bar over 1.2M rows, or "showing 40–65 of 1,204,882". Pre-compute it in
    /// the factory and store it (a computed property would not survive the JSON round trip):
    ///
    /// ```swift
    /// static func model(context: Context) throws -> BerthSearchViewModel {
    ///     .init(
    ///         berths: try context.records(Self.berths).map(BerthRowViewModel.init),
    ///         totalMatches: try context.totalCount(for: Self.berths)
    ///     )
    /// }
    /// ```
    ///
    /// The count is the **authorized** set the window is a view into — the same records
    /// ``records(_:)`` would return without the window. For a non-paginated load it equals
    /// `records(_:).count`.
    ///
    /// Throws exactly as ``records(_:)`` does: an unplanned handle throws (never returns 0 — a
    /// misconfiguration is not a genuine "no matches"); a handle matching more than one declared
    /// load throws.
    func totalCount<Record: FOSMVVM.Model>(for handle: LoadRequirement<Record>) throws -> Int {
        let requestName = String(describing: Request.self)
        let recordName = String(describing: Record.self)

        guard let plan else {
            throw ContainmentError.unplannedRequirement(recordType: recordName, request: requestName)
        }

        let candidates = plan.tuples(matching: handle)
        guard let tuple = candidates.first else {
            throw ContainmentError.unplannedRequirement(recordType: recordName, request: requestName)
        }
        guard candidates.count == 1 else {
            throw ContainmentError.ambiguousRequirement(
                recordType: recordName,
                request: requestName,
                matchCount: candidates.count
            )
        }

        return countsByTuple[tuple] ?? 0
    }
```

> The handle-resolution prologue is identical to `records(_:)` by design — same throws, same handle. If a shared private helper feels warranted, DO NOT extract it in this task (keeps the diff reviewable); note it for a follow-up simplification pass.

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter TotalCountTests`
Expected: PASS (all three cases).

- [ ] **Step 5: Commit**

```bash
git add Sources/FOSMVVMVapor/Containment/ProjectionContext+Records.swift Tests/FOSMVVMVaporTests/Composition/TotalCountTests.swift
git commit -m "feat(FOSMVVMVapor): add ProjectionContext.totalCount(for:) with contract tests"
```

---

## Task 6: Round-trip pin + full verification

**Files:**
- Test: `Tests/FOSMVVMVaporTests/Composition/TotalCountTests.swift` (add one case)

- [ ] **Step 1: Add a round-trip contract test**

A ViewModel that stores a total round-trips it intact (behavior, not encoded shape). Add to `TotalCountTests` — a tiny local ViewModel storing `totalMatches: Int`:

```swift
    /// A ViewModel storing a window total round-trips it intact — contract, not encoded shape.
    @Test func storedTotalRoundTrips() throws {
        struct BerthSearchVM: Codable, Hashable {
            let totalMatches: Int
        }
        let vm = BerthSearchVM(totalMatches: 1_204_882)
        let restored = try vm.toJSON().fromJSON() as BerthSearchVM
        #expect(restored.totalMatches == vm.totalMatches)
    }
```

- [ ] **Step 2: Run the whole suite**

Run: `swift test`
Expected: PASS, no regressions (the `= [:]` default kept every existing `ProjectionContext` construction green).

- [ ] **Step 3: Format + lint**

Run: `swiftformat . && swiftlint`
Expected: no changes needed / 0 violations.

- [ ] **Step 4: Commit**

```bash
git add Tests/FOSMVVMVaporTests/Composition/TotalCountTests.swift
git commit -m "test(FOSMVVMVapor): pin stored-total round-trip"
```

---

## Done criteria

- `swift test` green; `swiftlint` 0; `swiftformat` clean.
- `ProjectionContext.totalCount(for:)` returns the authorized full-set size; records stay windowed.
- No public surface beyond the one accessor; the `= [:]` init default kept all existing call sites compiling.
- Branch NOT pushed and NO PR opened — hand back to David for review (per the PR-review gate).
