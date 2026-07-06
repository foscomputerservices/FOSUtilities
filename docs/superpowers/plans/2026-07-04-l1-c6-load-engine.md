# L1 C6 — Authorized Load Engine, C6a Sort Mapping & Request Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the reviewed C6 spec — `ContainerAuthorization` + operation-set helper, C6a `SortableDataModel`/`SortMapping`, `AnySortTerm` + `ContainmentQueryRefinement` + refined `members`, the `package` engine + request-scoped cache + threshold, and the C2 pickups (`ServerRequest` sort-at-init, reserved `sort=` URL item, `Request.serverRequestSort`).

**Architecture:** One engine call = one (container, containedType) set. Erasure by closure capture throughout (C4's discipline): `SortMapping.keyPath` captures the concrete field; `AnySortTerm`'s typed factory captures the concrete key; the refined `members` applies both inside the relation's typed closure, pushing sort + window onto the `QueryBuilder` before `.all()`. Cache keys on the refinement *value*. Public surface: `ContainerAuthorization` + `Sequence.authorizes(_:)` (FOSMVVM), `SortableDataModel`/`SortMapping` + `Request.serverRequestSort` (FOSMVVMVapor), the `ServerRequest.init` change. Everything else `package`.

**Tech Stack:** Swift 6 strict concurrency, Vapor 4, FluentKit (`QueryBuilder.sort/range`), SQLite test harness (`withFluentTestApp`), Swift Testing.

**Spec (normative):** `docs/superpowers/specs/2026-07-04-authorized-load-engine-design.md` — read fully first; its DocC drafts and 10 test groups are the contract. Decisions D-C6-1/2/3 are RESOLVED — do not reopen.

---

## Plan prose — rationale & gotchas (implementer-facing; keep OUT of DocC)

- **Real `ContainerOperation` case names** are `.readRecords`/`.writeRecords`/`.createRecords`/`.deleteRecords`/`.destroyRecords`/`.anyOperation` (the spec's test sketches abbreviate; use the real names). The new `Sequence.authorizes(_:)` composes the EXISTING per-verb helpers (`authorizesReadRecords` etc., `ContainerOperation.swift:71-96`) via a `switch` — it must preserve the wildcard-excludes-destroy rule for free by delegating, never re-encoding it.
- **`ServerRequest.init` ripple is bounded and mechanical.** No macro generates the init (verified: `grep -rn "init(query" Sources/FOSMacros/` is empty). The required init changes in `ServerRequest.swift:65`; a protocol-extension convenience (4-param, `sort: nil`) keeps call sites compiling. Conformers that *define* the required init and must add the `sort:` parameter: `Tests/FOSMVVMVaporTests/TestViewModel.swift:77`, `Tests/FOSMVVMTests/TestViewModel.swift:80`, `Tests/FOSMVVMTests/TestCreateViewModel.swift:50`, `Tests/FOSMVVMTests/Versioning/VersionedViewModel.swift:153`, `Tests/FOSMVVMTests/Protocols/ServerRequestSortTests.swift:64,77`, plus the DocC article `Sources/FOSMVVM/FOSMVVM.docc/ViewModelandViewModelRequest.md`. Those test conformers declare the init with `= nil` defaulted params — keep `sort:` defaulted there too so zero-arg call sites keep compiling. `ViewModelView.swift` and `ViewModelFactoryMacroTests.swift` contain only 4-param *call sites*/pass-through fixture strings — the convenience covers them with zero edits (touch the macro-test strings only if a build error proves otherwise). For `Sort == EmptySort` conformers the parameter is simply unused (no stored property needed; the `sort` getter comes from the existing constrained extension).
- **URL multiplexing is safe on raw `&` split.** The shipped encode puts the query JSON in a `URLQueryItem` *name* (`ServerRequest.swift:118`) — `URLQueryItem` percent-encodes `&` and `=` inside names/values, so unencoded `&` in `url.query` only ever separates items. Parse therefore: split `url.query` on `"&"`, components with prefix `"sort="` are the reserved item; the remainder re-joins for the legacy whole-string query decode (`Request+FOS.swift:31-47`). Pin the reserved name + split rule in a `//` comment + the compatibility test — never in DocC.
- **`EmptySort` needs no special-case on encode:** the constrained extension (`ServerRequest.swift:147-151`) makes `sort` nil for `EmptySort` conformers, so `if let sort = serverRequest.sort` alone implements "omitted when nil/EmptySort".
- **`AnySortTerm.Hashable` is manual** — `any SortKey` is not `Hashable`; equality/hash via `AnyHashable(key)`. The typed factory `init(_ term: SortTerm<some SortKey>)` also stores the key for the downcast inside the relation's closure (`key as? To.RequestSortKey`, throw `.unsortableContainedType` on failure).
- **One private load closure in `ContainmentRelation`** parameterized by `ContainmentQueryRefinement`; the shipped unrefined `members(of:on:)` forwards `.none`. C4's tests must stay green UNTOUCHED — if a C4 test changes, the refactor is wrong.
- **FluentKit verified:** `QueryBuilder.sort(_ field: KeyPath, _ direction:)` requires `Field: QueryableProperty, Field.Model == Model`; `range(lower..<upper)` (or `.range(lower:upper:)`) — `Pagination(startIndex: s, maxResults: m)` maps to `range(s ..< s+m)`; `startIndex` nil = 0, `maxResults` nil = no upper bound (apply `.range(s...)`-equivalent via offset only... FluentKit's `range` takes `Range<Int>`/`PartialRangeFrom` variants — use `query.range(lower:)` shape per checkout; the implementer verifies the exact overload at compile time).
- **Threshold check is per engine call** (= per cached unit). Log via `req.logger.warning`; the message names the registered container type + contained type + count via `String(describing:)` (diagnostic only — `ModelNamespace` stays sealed).
- **Engine tests mint a real `Request`:** `Request(application: app, method: .GET, url: URI(string: "/"), on: app.eventLoopGroup.next())` — Vapor-public. Two calls on the SAME `Request` instance share the cache; a fresh `Request` gets a fresh cache (assert both).
- **`Berth.dockName` is denormalized** (a plain `@Field` seeded with the dock's name) because `Field.Model == M` rules out joined-parent sorts in v1.
- **Registration in engine tests:** remember FK order (CreatePier before `register(Dock…)`) and that `register` adds `CreateDock` itself — copy the configure blocks from `ModelTypeRegistryTests`.
- **swiftformat gotchas** (established this branch): `docComments` forces `///` on pre-declaration comments (tool-overridden, acceptable); `redundantSendable` is DISABLED in `.swiftformat` (do not remove); swiftlint directives must not carry trailing prose.
- **Do not add:** any public engine/cache surface, a whole-container engine entry, filter push-down, eager-loads, the C3 provider, `RecordOperation`. All explicitly out of scope.

## File structure

| File | Responsibility |
|---|---|
| `Sources/FOSMVVM/Protocols/ContainerOperation.swift` (modify) | + `Sequence.authorizes(_:)` intent helper |
| `Sources/FOSMVVM/Protocols/ContainerAuthorization.swift` (create) | The shared auth contract (spec C6.1 DocC verbatim) |
| `Sources/FOSMVVM/Protocols/ServerRequest.swift` (modify) | init gains `sort:` (canonical) + 4-param convenience; encode adds reserved `sort=` item |
| `Sources/FOSMVVMVapor/Extensions/Request+FOS.swift` (modify) | strip reserved item before query decode; + public `serverRequestSort(ofType:)` |
| `Sources/FOSMVVMVapor/Containment/SortableDataModel.swift` (create) | C6a protocol + `SortMapping` (public factories, `package` apply) |
| `Sources/FOSMVVMVapor/Containment/ContainmentQueryRefinement.swift` (create) | `AnySortTerm` + refinement value + `SortCriteria.erasedTerms` bridge |
| `Sources/FOSMVVMVapor/Containment/ContainmentRelation.swift` (modify) | refined `members(of:on:applying:)`; single private load closure |
| `Sources/FOSMVVMVapor/Containment/ContainmentError.swift` (modify) | + `.unsortableContainedType`, `.unregisteredNamespace` |
| `Sources/FOSMVVMVapor/Containment/ContainerRecordCache.swift` (create) | cache key/value + `Request.containerRecordCache` + `invalidateContainerRecords` + threshold storage |
| `Sources/FOSMVVMVapor/Extensions/Request+ContainerLoad.swift` (create) | the `package` engine |
| `Tests/FOSMVVMTests/Protocols/ContainerOperationTests.swift` (modify or create) | helper tests |
| `Tests/FOSMVVMTests/Protocols/ContainerAuthorizationTests.swift` (create) | protocol contract tests (no DB) |
| `Tests/FOSMVVMVaporTests/Containment/ContainmentFixtures.swift` (modify) | `dockName` field + migration/seed; `BerthSortKey`; `Berth: SortableDataModel`; `TestGrant` |
| `Tests/FOSMVVMVaporTests/Containment/SortMappingTests.swift` (create) | C6a mapping application |
| `Tests/FOSMVVMVaporTests/Containment/RefinedMembersTests.swift` (create) | spec groups 5 + 10 |
| `Tests/FOSMVVMVaporTests/Containment/AuthorizedLoadEngineTests.swift` (create) | spec groups 1–4, 6–8 |
| `Tests/FOSMVVMVaporTests/Protocols/ServerRequestSortURLTests.swift` (create) | spec group 9 (round-trip + compat) |
| `CHANGELOG.md` (modify) | public symbols + breaking init |

---

### Task 1: `Sequence<ContainerOperation>.authorizes(_:)` (FOSMVVM)

**Files:** Modify `Sources/FOSMVVM/Protocols/ContainerOperation.swift`; Test `Tests/FOSMVVMTests/Protocols/ContainerOperationTests.swift` (extend the existing suite if present, else create).

- [ ] **Step 1: Failing tests** — wildcard grants read/write/create/delete but NOT destroy; explicit destroy grants destroy; empty set grants nothing; mixed set answers by any-member:

```swift
@Test func operationSetAuthorizesByIntent() {
    let wildcard: [ContainerOperation] = [.anyOperation]
    #expect(wildcard.authorizes(.readRecords))
    #expect(wildcard.authorizes(.deleteRecords))
    #expect(!wildcard.authorizes(.destroyRecords))   // wildcard never grants destroy
    #expect([ContainerOperation]().authorizes(.readRecords) == false)
    #expect([.destroyRecords].authorizes(.destroyRecords))
    #expect([.writeRecords, .readRecords].authorizes(.readRecords))
    #expect(![.writeRecords].authorizes(.readRecords))
}
```

- [ ] **Step 2:** `swift test --filter ContainerOperationTests` → compile FAIL (`no member 'authorizes'`).
- [ ] **Step 3: Implement** in the existing `Sequence<ContainerOperation>` extension (DocC from spec C6.1, example `grantedOperations.authorizes(.readRecords)`):

```swift
    /// Whether this granted set covers `operation` — including via the wildcard. Use this instead of
    /// `contains(_:)`, which silently ignores the wildcard grant:
    ///
    /// ```swift
    /// grantedOperations.authorizes(.readRecords)
    /// ```
    func authorizes(_ operation: ContainerOperation) -> Bool {
        switch operation {
        case .readRecords: authorizesReadRecords
        case .writeRecords: authorizesWriteRecords
        case .createRecords: authorizesCreateRecords
        case .deleteRecords: authorizesDeleteRecords
        case .destroyRecords: authorizesDestroyRecords
        case .anyOperation: contains(.anyOperation)
        }
    }
```

- [ ] **Step 4:** Tests PASS; full suite green (375 + new).
- [ ] **Step 5:** `git commit -m "feat(FOSMVVM): add operation-set authorizes(_:) intent helper"`

### Task 2: `ContainerAuthorization` (FOSMVVM)

**Files:** Create `Sources/FOSMVVM/Protocols/ContainerAuthorization.swift`; Test `Tests/FOSMVVMTests/Protocols/ContainerAuthorizationTests.swift`.

- [ ] **Step 1: Failing tests** — pure-logic contract, no DB. Fixture: a `struct TestAuthorization: ContainerAuthorization` (value type) with stored identity/operations/types, `authorizes` composed exactly as the spec's DocC example. Tests: covering grant answers true; wrong container (different `ModelIdentity`) false; wildcard-excludes-destroy flows through; record-type mismatch false. Mint identities via `model.modelIdentity` on small `Model` fixtures (the intended path — NOT internal inits).
- [ ] **Step 2:** compile FAIL. **Step 3:** implement protocol with the spec C6.1 DocC **verbatim** (value-snapshot example, `any FOSMVVM.Model.Type` qualification note, `operations.authorizes(operation)` in the example). **Step 4:** PASS + full suite. 
- [ ] **Step 5:** `git commit -m "feat(FOSMVVM): add ContainerAuthorization — the shared auth contract (C6/C3 core)"`

### Task 3: `ServerRequest` sort-at-init (FOSMVVM, breaking)

**Files:** Modify `Sources/FOSMVVM/Protocols/ServerRequest.swift:65` + the 7 conformer files + DocC article (list in plan prose).

- [ ] **Step 1:** Change the requirement to `init(query: Query?, sort: Sort?, fragment: Fragment?, requestBody: RequestBody?, responseBody: ResponseBody?)` and add the convenience in `public extension ServerRequest`:

```swift
    /// Creates the request with no sort (see ``init(query:sort:fragment:requestBody:responseBody:)``).
    init(query: Query?, fragment: Fragment?, requestBody: RequestBody?, responseBody: ResponseBody?) {
        self.init(query: query, sort: nil, fragment: fragment, requestBody: requestBody, responseBody: responseBody)
    }
```

- [ ] **Step 2:** `swift build 2>&1 | grep error` — fix each conformer mechanically (add `sort: Sort? = ...` NO: add the `sort:` parameter to their required-init definitions; `EmptySort` conformers ignore it). Update `ViewModelFactoryMacroTests` expected strings ONLY if the macro emits the init (it doesn't — verify; if its expected output merely *calls* the 4-param form, the convenience covers it). Update the DocC article's example.
- [ ] **Step 3:** Full suite green (behavior unchanged — this task adds no new tests; the compile IS the test). Conformers with a real Sort (`ServerRequestSortTests`) now store/receive sort through init — extend that test to construct via the canonical init and read `sort` back (one assertion).
- [ ] **Step 4:** `git commit -m "feat(FOSMVVM)!: ServerRequest.init gains sort — canonical initializer + compatibility convenience"`

### Task 4: Sort URL wire + `Request.serverRequestSort` (FOSMVVM + FOSMVVMVapor)

**Files:** Modify `Sources/FOSMVVM/Protocols/ServerRequest.swift:98-120` (encode), `Sources/FOSMVVMVapor/Extensions/Request+FOS.swift` (parse); Test `Tests/FOSMVVMVaporTests/Protocols/ServerRequestSortURLTests.swift` (spec group 9).

- [ ] **Step 1: Failing tests** (build a real request type with `SortCriteria<TestSortKey>`):
  - encode+parse round-trip: `URL.appending(serverRequest:)` → mint a Vapor `Request` with that URL → `serverRequestSort(ofType:)` returns an equal `SortCriteria` AND `serverRequestQuery(ofType:)` still returns the query.
  - compatibility: a nil-sort request produces a URL with NO `sort=` component and byte-identical `url.query` to the pre-C6 encoding (construct the legacy expectation with the query-JSON-as-name rule, asserting *equality of the two URLs*, not the JSON shape); a legacy URL (query blob only) parses: query decodes, sort is nil.
  - `EmptySort` request → no sort item (via the nil path).
- [ ] **Step 2:** FAIL (`no member 'serverRequestSort'`). 
- [ ] **Step 3: Implement.** Encode — in `queryItems(from:)`, return query item (as shipped, untouched) plus, `if let sort = serverRequest.sort`, `.init(name: "sort", value: try sort.toJSON())`. (Reserved name `"sort"`; `//` comment: reserved item, stripped server-side before whole-string query decode — see Request+FOS.swift.) Handle the query-nil-but-sort-present case (items array built from both optionals). Parse — in `Request+FOS.swift`: private helper `serverRequestRawQueryString` that splits `url.query` on `"&"`, partitions components by the `sort=` prefix, and rejoins the rest; `serverRequestQuery` uses it in place of raw `url.query`; new public `serverRequestSort(ofType:)` (DocC + example, mirrors `serverRequestQuery`; `EmptySort.self` short-circuits nil; percent-decode the value then `fromJSON`).
- [ ] **Step 4:** Group-9 tests PASS; existing `VaporServerRequestTest`-based suites still green (legacy path untouched for sortless requests).
- [ ] **Step 5:** `git commit -m "feat: sort rides the request URL as a reserved item; add Request.serverRequestSort"`

### Task 5: C6a `SortableDataModel` + `SortMapping` (+ fixtures)

**Files:** Create `Sources/FOSMVVMVapor/Containment/SortableDataModel.swift`; Modify `Tests/FOSMVVMVaporTests/Containment/ContainmentFixtures.swift` (Berth `dockName` `@Field` + migration column + seed passes the dock name; `enum BerthSortKey: String, SortKey { case number, dockName }`; `Berth: SortableDataModel` per the spec DocC example; `TestGrant: ContainerAuthorization` value fixture); Test `Tests/FOSMVVMVaporTests/Containment/SortMappingTests.swift`.

- [ ] **Step 1: Failing tests** — seed harbor; apply mappings directly to `Berth.query(on: db)` via the `package` apply (`mapping.apply(to:direction:)`): `.number` desc → `[3,2,1]` for dock1's berths (filter by dock in the test query); `dockName` mapping list applies in order (composite: name then number).
- [ ] **Step 2:** FAIL. **Step 3:** implement per spec C6.2 (public protocol + `SortMapping` with public `keyPath` factory; the erased `@Sendable (QueryBuilder<M>, SortDirection) -> QueryBuilder<M>` closure stays **`private`** with a **`package` `apply(to:direction:)` method** as the seam — a package-visible stored closure would make the synthesized memberwise init package-reachable and reopen the only-the-factory-constructs hole. Same split applies to Task 6/7's erased closures. DocC verbatim incl. the one-vocabulary sentence). **Step 4:** PASS + prior Containment suites green (fixture migration change ripples — update `CreateBerth` and `seedHarbor`).
- [ ] **Step 5:** `git commit -m "feat(FOSMVVMVapor): add C6a SortableDataModel + SortMapping (meaning→order-by)"`

### Task 6: `AnySortTerm` + refinement + refined `members` (D1)

**Files:** Create `Sources/FOSMVVMVapor/Containment/ContainmentQueryRefinement.swift`; Modify `ContainmentRelation.swift` (single private load closure + refined overload), `ContainmentError.swift` (+ `.unsortableContainedType(modelType:keyType:)`); Test `Tests/FOSMVVMVaporTests/Containment/RefinedMembersTests.swift` (spec groups 5 + 10).

- [ ] **Step 1: Failing tests** — refined children honors sort (`AnySortTerm(SortTerm(key: BerthSortKey.number, direction: .descending))`) + window (`Pagination(startIndex: 1, maxResults: 1)` → middle berth of the sorted order); `.parent` ignores sort AND window (returns the single Pier regardless); unsortable: terms against CrewMember relation → `.unsortableContainedType`; wrong key type against Berth → same; unrefined `members(of:on:)` unchanged (C4's `ContainmentRelationTests` MUST pass untouched — run them).
- [ ] **Step 2:** FAIL. **Step 3:** implement per spec C6.3 — `AnySortTerm` (manual `Hashable` via `AnyHashable`; `Sendable`), `SortCriteria.erasedTerms` (FOSMVVMVapor extension), `ContainmentQueryRefinement: Hashable, Sendable` with `static let none`; rework the three factories' closures to take `(container, db, refinement)`: cast container (existing backstop), build the relationship query, then if `To: SortableDataModel` and terms cast to `To.RequestSortKey` apply each key's `sortMappings` in term order with the term's direction; terms present but To not sortable / cast fails → throw; then apply `range` for pagination; `.parent` closure ignores the refinement. **Step 4:** PASS; ContainmentRelationTests + ErasedBridgeTests untouched-green. 
- [ ] **Step 5:** `git commit -m "feat(FOSMVVMVapor): refined containment load — AnySortTerm + ContainmentQueryRefinement (D1)"`

### Task 7: Engine + cache + threshold

**Files:** Create `Sources/FOSMVVMVapor/Containment/ContainerRecordCache.swift`, `Sources/FOSMVVMVapor/Extensions/Request+ContainerLoad.swift`; Modify `ContainmentError.swift` (+ `.unregisteredNamespace(identity: String)`); Test `Tests/FOSMVVMVaporTests/Containment/AuthorizedLoadEngineTests.swift` (spec groups 1–4, 6–8).

- [ ] **Step 1: Failing tests** (mint `Request(application:method:url:on:)` inside `withFluentTestApp`'s body; grants via `TestGrant`):
  1. instance-scoping (dock1 grant → dock1 berths; dock2 identity → empty; `[]` auths → empty)
  2. operation×type (`.readRecords` on Berth only → Berth call loads, CrewMember call empty; Berth call `for: .createRecords` → empty)
  3. sort in-DB (erased `SortCriteria<BerthSortKey>` desc → `[3,2,1]`; composite `dockName`)
  4. pagination (middle record; nil → full)
  6. cache (same `Request`: identical calls → same ELEMENT instances via `ObjectIdentifier`; differing sort → different instances; empty result cached — delete rows between two identical calls, second still returns cached; `invalidateContainerRecords` → recompute observes reality; fresh `Request` → fresh cache)
  7. missing row → `[]`; unregistered namespace (identity of an unregistered fixture type) → `.unregisteredNamespace`
  8. threshold 2 vs 3 berths → all 3 returned (set `app` threshold via the package var)
- [ ] **Step 2:** FAIL. **Step 3:** implement per spec C6.4/C6.5 — cache key struct, `Request.containerRecordCache` (StorageKey, get/modify), engine pipeline (cache probe → registry → find → scope → refined members per matching relation, declaration order → threshold warn → cache write incl. empty → return), `invalidateContainerRecords(of:)`, `Application.maxRecordsWarningThreshold` (package var, default 1000, storage-backed). Maintainer notes: one-auth-set-per-Request; readers must not mutate the shared snapshot. **Step 4:** all engine tests PASS; full suite green. 
- [ ] **Step 5:** `git commit -m "feat(FOSMVVMVapor): add the authorized container load engine + request-scoped cache"`

### Task 8: DoD sweep + CHANGELOG

- [ ] **Step 1: Greps** — no Fluent/Vapor import in FOSMVVM/FOSFoundation; `ContainerAuthorization.swift` imports only FOSFoundation/Foundation; no `public` engine/cache/members surface (`grep -n "public" Sources/FOSMVVMVapor/Containment/ContainmentQueryRefinement.swift Sources/FOSMVVMVapor/Extensions/Request+ContainerLoad.swift Sources/FOSMVVMVapor/Containment/ContainerRecordCache.swift` → only comments); `ModelIdentity` opacity grep unchanged.
- [ ] **Step 2:** `swiftformat . && swiftlint --quiet` (only the pre-existing WASI force_cast), `swift test` full suite green.
- [ ] **Step 3: CHANGELOG** — under Unreleased: Added `ContainerAuthorization` + `Sequence<ContainerOperation>.authorizes(_:)`, `SortableDataModel`/`SortMapping`, `Request.serverRequestSort(ofType:)`; **Changed (breaking)**: `ServerRequest.init` now takes `sort:` (compatibility convenience provided); sort criteria now travel in request URLs. Contract-level wording only.
- [ ] **Step 4:** `git commit -m "docs(CHANGELOG): record C6 authorized load engine + sort wiring"`

---

## Final verification (spec Definition of done)

- [ ] All 10 spec test groups mapped: 1–4, 6–8 (`AuthorizedLoadEngineTests`), 5+10 (`RefinedMembersTests` + `SortMappingTests`), 9 (`ServerRequestSortURLTests`); threshold logging is observability (internal if logger capturable).
- [ ] DocC + examples on every public symbol; package symbols maintainer-notes only.
- [ ] Pre-C6 URLs round-trip byte-identically (compat test green).
- [ ] Engine is the cache's only writer; no public load path.
- [ ] Arch supersession note: already committed (6bd1486).
- [ ] CHANGELOG records the breaking init change.
