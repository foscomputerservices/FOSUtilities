# C8 — VaporResponseBodyFactory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Model economy (David's directive):** implementer + routine per-task review subagents run on **Opus**; escalate to the session default only where a step's reasoning is genuinely subtle (noted inline).

**Goal:** Ship the unified server factory (`VaporResponseBodyFactory` + `ProjectionContext`), the write path (candidates → apply → refresh), and every recorded C8 obligation, per the approved spec.

**Architecture:** One server factory replaces `VaporViewModelFactory` (BREAKING, narrowed no-`Database` context); `ComposableFactory` (renamed, un-pinned) declares read data; write requests carry their own candidate set (`WriteTargetProviding`) and a typed refresh bridge; pass #2 is the genuine GET pipeline run on `refreshRequest()`.

**Tech Stack:** Swift 6 / Swift Testing (XCTest only for macro tests), Vapor + FluentKit (FOSMVVMVapor), fluent-sqlite-driver test harness (`withFluentTestApp`).

---

## Normative sources (read before ANY task)

- **Spec:** `docs/superpowers/specs/2026-07-05-vapor-response-body-factory-design.md`
  (decisions D-C8-1..9; §3 components; §9 test groups 1–16; §10 DoD; §11 reconciliation)
- **Sketch (signature-normative, prose defers to it):**
  `docs/superpowers/specs/2026-07-05-c8-surface-sketch.swift`
  **All public DocC text comes from the sketch/spec — copy, then strip decision-ID
  citations (D-C8-n), obligation labels, and future-macro notes into `//` internal
  comments or drop them (DoD implementer-leak sweep). Every public symbol keeps a
  call-site example.**
- **Disciplines:** repo `CLAUDE.md` (SOLID + encapsulation + DocC); zero new `package`
  *sites*; no Fluent/Vapor (incl. `$`-projections) in FOSMVVM sources or comments;
  no `ModelIdType` in any fixture `RequestBody`; contract tests via public paths,
  `@testable` only for coverage below the public surface.

## Worktree / suite facts

- Work in `/Users/david/Repository/FOS/FOSUtilities-model-identity`
  (branch `spec/model-identity-live-invalidation`). Baseline: suite 478 green
  (2 pre-existing known issues). Run: `swift test` (full), `swift test --filter <Suite>`.
- `swiftformat . && swiftlint` before each commit.

## Key shipped facts (scouted 2026-07-05 — trust these, verify only if a step fails)

- CRUD protocols (`Sources/FOSMVVM/Protocols/`): `CreateRequest`/`UpdateRequest`/
  `ReplaceRequest` require `RequestBody: ValidatableModel, ResponseBody: <Verb>ResponseBody`;
  `DeleteRequest`/`DestroyRequest` are unconstrained; `ServerRequestAction`
  (`ServerRequest.swift:231`) already maps show=GET, create=POST, update=PATCH,
  delete/destroy=DELETE, replace=PUT. `EmptyBody` (`ServerRequest.swift:380`)
  conforms to the `*ResponseBody` markers.
- `RootedQuery` requires `var rootIdentity: ModelIdentity` (`RootedQuery.swift:31-34`).
- `VaporServerRequestMiddleware` parses ONLY the URL query; `requestBody` is
  hardcoded `nil` — **write routes must decode the HTTP body themselves**.
- Rename touchpoints for `VaporViewModelFactory`/`VaporModelFactoryContext`/
  `register(viewModel:)`: `Sources/FOSMVVMVapor/Protocols/ViewModelFactory.swift`,
  `Vapor Support/VaporServerRequestHost.swift:28`, `Vapor Support/ViewModelRequest.swift:51`,
  `Containment/PlanExecutor.swift:32,41` (error strings),
  `Sources/FOSTestingVapor/VaporServerTestCase.swift:24`,
  `Sources/FOSMVVM/FOSMVVM.docc/ViewModelandViewModelRequest.md:108-118`,
  `Tests/FOSMVVMVaporTests/TestViewModel.swift:83-86`,
  `Tests/FOSMVVMVaporTests/Composition/PlanRegistrationTests.swift` +
  `PlanExecutorTests.swift`, `Tests/FOSMacrosTests/ViewModelFactoryMacroTests.swift:93-150`
  (expected-expansion strings only — **macro sources are clean, no macro change**).
- `RecordLoadPlan` (`Sources/FOSMVVM/RecordLoadPlan.swift`): `package` site with
  on-file statement (L19-22); `Tuple` stores root/path/recordType/operation/anchor/
  isRefinedByRequest; `walk` at L146. Plan storage: `Containment/PlanRegistration.swift`
  (`registerRecordLoadPlan` L36, `recordLoadPlan(for:)` L64, apex resolver L195).
- Cache: `Containment/ContainerRecordCache.swift` — `containerRecordCache` computed
  storage, `invalidateContainerRecords(of:)` L69, sequential-touch contract L84-87.
- Engine entries: `Extensions/Request+ContainerLoad.swift` — provider-driven
  `authorizedRecords(of:containing:for:authorizedAs:sortedBy:pagination:)` L112
  (KEEP; the executor calls it); internal `authorizedBy:` entry L40-48 (REMOVE, Task 7).
- Harbor fixtures: `Tests/FOSMVVMVaporTests/Containment/ContainmentFixtures.swift`
  (Pier/Dock/Berth/CrewMember/DockCrew); composition test request/VM fixtures in
  `Composition/PlanRegistrationTests.swift:141-176`.

## File structure (created/modified, by responsibility)

```
Sources/FOSMVVM/
  Protocols/TargetedQuery.swift                 CREATE  (T1)
  Protocols/DataRequirement.swift               MODIFY  (T1: seal + verbs + packs)
  RecordLoadPlan.swift                          MODIFY  (T1: walk-face cast, unknown-kind
                                                         error, handle→tuple lookup)
  Protocols/ComposableFactory.swift             RENAME from ComposableViewModelFactory.swift (T2)
  Protocols/{Create,Update,Delete}Request.swift MODIFY  (T3: refresh bridge)
Sources/FOSMVVMVapor/
  Protocols/VaporResponseBodyFactory.swift      RENAME from ViewModelFactory.swift (T4)
  Containment/ProjectionContext.swift           CREATE  (T4; AppState wiring T5)
  Vapor Support/VaporServerRequestHost.swift    MODIFY  (T4 GET wiring; T6 write routes)
  Vapor Support/ViewModelRequest.swift          MODIFY  (T4: register(request:); delete
                                                         register(viewModel:))
  Containment/AppStateRegistry.swift            CREATE  (T5)
  Protocols/WriteTargetProviding.swift          CREATE  (T6; includes DataModelWriter)
  Containment/WriteRoute.swift                  CREATE  (T6: decode→validate→candidates→
                                                         resolve→apply→save→invalidate→refresh)
  Containment/ContainmentRelation.swift         MODIFY  (T6: internal additive createMember)
  Containment/PlanRegistration.swift            MODIFY  (T6 boot checks; T7 apex public +
                                                         sort-bridge warn)
  Containment/PlanExecutor.swift                MODIFY  (T2 rename; T4 error strings;
                                                         T7 SupplementalRecordLoading public)
  Extensions/Request+ContainerLoad.swift        MODIFY  (T7: remove authorizedBy: entry)
Sources/FOSTestingVapor/VaporServerTestCase.swift MODIFY (T4: new constraint)
Tests/  (per-task test files named in tasks)
CHANGELOG.md, arch doc, C7 docs                 MODIFY  (T8)
```

Task order keeps the package compiling at every commit: shared vocabulary first
(T1–T3), Vapor replacement (T4), AppState (T5), write path (T6), audit/publicize
(T7), docs (T8).

---

### Task 1: Seal `DataRequirement`, add write verbs + pack `via:`, `TargetedQuery`, handle lookup

**Spec:** §3.5, §3.6, §3.7; sketch sections `DataRequirement`, `LoadRequirement`, `TargetedQuery`. Test groups 10, 11 (+ walk regression).

**Files:**
- Modify: `Sources/FOSMVVM/Protocols/DataRequirement.swift`
- Modify: `Sources/FOSMVVM/RecordLoadPlan.swift`
- Create: `Sources/FOSMVVM/Protocols/TargetedQuery.swift`
- Test: `Tests/FOSMVVMTests/Composition/SealedRequirementTests.swift` (create);
  existing walk tests in `Tests/FOSMVVMTests/Composition/` (locate with
  `grep -rl "RecordLoadPlan.walk" Tests/FOSMVVMTests/`) must stay green unmodified
  where they use `.read` factories (pack call sites are byte-identical).

- [ ] **Step 1: Failing tests — sealed marker + unknown-kind rejection + pack parity + verbs**

```swift
// Tests/FOSMVVMTests/Composition/SealedRequirementTests.swift
import FOSMVVM
import Testing

@Suite("Sealed DataRequirement")
struct SealedRequirementTests {
    struct ForeignRequirement: DataRequirement {} // compiles — marker is public

    @Test func foreignConformerIsRejectedByWalk() {
        // factory fixture whose dataRequirements returns [ForeignRequirement()]
        #expect(throws: RecordLoadPlan.WalkError.self) {
            _ = try RecordLoadPlan.walk(from: ForeignFactoryFixture.self)
        }
        // assert the error case is .unknownRequirementKind(factory:) and its
        // message names the factory — behavior via thrown error, not internals
    }

    @Test func packViaProducesIdenticalTuples() throws {
        // fixture declaring .read(SlipFixture.self, in: .parentRoot, via: BerthFixture.self)
        // walk it; assert tuple path == [BerthFixture.self] identity, record == Slip —
        // byte-equal to the C7 baseline expectations already asserted in walk tests
    }

    @Test func writeVerbsCarryTheirOperations() throws {
        // .write → .writeRecords, .create → .createRecords, .delete → .deleteRecords
        // asserted THROUGH the walk (plan tuples), never by reading members —
        // the members are sealed now
    }
}
```

Note: `.create` has **no** `via:` parameter at all (spec §3.6) — add a
does-not-compile assertion as a commented compile-audit line, per repo precedent
for compile-audits (grep `"compile-audit"` in Tests/ to copy the idiom).

- [ ] **Step 2: Run — verify fails** (`swift test --filter SealedRequirementTests`; expect: `ForeignRequirement` currently REQUIRES five members → compile error proves the seal is absent; walk has no unknown-kind path)

- [ ] **Step 3: Implement**

`DataRequirement.swift`:
- `public protocol DataRequirement: Sendable {}` — marker only, DocC from sketch.
- `protocol DataRequirementWalkFace { var recordType: any Model.Type { get };
  var rootScope: RootScope { get }; var intermediates: [any Model.Type] { get };
  var operation: ContainerOperation { get }; var isRefinedByRequest: Bool { get } }`
  (internal; `LoadRequirement: DataRequirement, DataRequirementWalkFace` with the
  five members now **internal** — move the existing bodies, do not rewrite them).
- Verb factories, all pack-based (copy signatures from sketch):
  `read/write/delete<each Hop: Model>(_:in:via: repeat (each Hop).Type)`,
  `create(_:in:)` (no pack). Bodies build
  `let hops: [any Model.Type] = [repeat (each intermediates)]` and call the
  existing private init with `.readRecords`/`.writeRecords`/`.createRecords`/
  `.deleteRecords`.
- Delete the old variadic `read(_:in:via: any Model.Type...)`.

`RecordLoadPlan.swift`:
- In `walk`, where requirements are consumed:
  `guard let face = requirement as? any DataRequirementWalkFace else {
  throw WalkError.unknownRequirementKind(factory: ...) }` — add the case to
  `WalkError` with a message naming factory + the foreign type.
- Add the handle lookup (named consumer: `ProjectionContext.records(_:)`, T4):
  `package func tuple(matching requirement: any DataRequirement) -> Tuple?`
  — cast to the walk face inside FOSMVVM, match on
  (recordType identity, rootScope→root, intermediates→path prefix, operation,
  isRefinedByRequest). **Update the on-file package statement comment** (L19-22)
  to name the new member + `ProjectionContext` consumer.

`TargetedQuery.swift` (new): copy protocol + DocC from sketch
(`var target: ModelIdentity { get }`, `: ServerRequestQuery`).

**Spec §5 DocC deliverables (assigned HERE — both live in files this task edits):**
- `RootedQuery` DocC gains the single-`.query`-root **ceiling note** (one query-vended
  root per request; lifting it waits for a consumer) —
  `Sources/FOSMVVM/Protocols/RootedQuery.swift`.
- `refinedByRequest` DocC gains the **marked-under-guard-diamond guidance**: a
  `.refinedByRequest` tuple reached through a `.guards` diamond applies the
  refinement per-anchor; name the declaration-order rule and point at per-relation
  windows (spec §5 wording) — `DataRequirement.swift`.

- [ ] **Step 4: Run — verify passes** (`swift test --filter SealedRequirementTests`, then full FOSMVVMTests; C7 walk tests green unmodified except any that read the five members directly — re-point those through the walk/plan, never widen access)

- [ ] **Step 5: Commit** — `feat(FOSMVVM)!: seal DataRequirement behind an internal walk face; pack-based via:; write-family verbs; TargetedQuery (C8 T1)`

---

### Task 2: Rename `ComposableViewModelFactory` → `ComposableFactory`, drop the VM pin

**Spec:** §3.4. Whole-repo mechanical rename + one base-clause change; no behavior change.

**Files:**
- Rename: `Sources/FOSMVVM/Protocols/ComposableViewModelFactory.swift` →
  `ComposableFactory.swift`
- Modify: every reference — find with
  `grep -rln "ComposableViewModelFactory" Sources/ Tests/`
  (includes `RecordLoadPlan.swift`, `ComposedChild`, `PlanExecutor.swift`,
  `PlanRegistration.swift`, FOSMVVM + Vapor tests). Docs sweep waits for T8.

- [ ] **Step 1: Failing test** — add to `SealedRequirementTests` (or a tiny new suite): a **non-ViewModel** `ServerRequestBody` fixture adopting `ComposableFactory` with one `.read` requirement; assert `RecordLoadPlan.walk` derives its plan (this cannot compile today: the trait requires `ViewModelFactory where Self: ViewModel`).
- [ ] **Step 2: Run — verify it does not compile** (expected: conformance error).
- [ ] **Step 3: Implement** — rename file + symbol everywhere;
  `public protocol ComposableFactory: Sendable { ... }` (base clause change only —
  keep `dataRequirements`/`children` + defaults + DocC, updating the DocC's
  protocol name and keeping its example). `ComposedChild`'s stored factory type and
  the executor's casts (`as? any ComposableFactory.Type`) follow mechanically.
- [ ] **Step 4: Run full suite** — `swift test` (rename must not change behavior; the new non-VM test passes).
- [ ] **Step 5: Commit** — `feat(FOSMVVM)!: ComposableFactory — un-pin the composable trait from ViewModels (C8 T2)`

---

### Task 3: Refresh bridge on the write CRUD protocols

**Spec:** §3.9 (D-C8-7); sketch "write CRUD protocols gain the refresh bridge". Test group 16 (typing half).

**Files:**
- Modify: `Sources/FOSMVVM/Protocols/CreateRequest.swift`, `UpdateRequest.swift`,
  `DeleteRequest.swift` (NOT Replace/Destroy — they stay unbridged and are
  boot-rejected in T6)
- Test: `Tests/FOSMVVMTests/Protocols/RefreshBridgeTests.swift` (create)

- [ ] **Step 1: Failing test** — shared-module fixture pair: a `ShowRequest` (`FixtureShowRequest`, ResponseBody `FixturePageBody`) + an `UpdateRequest` whose `RefreshRequest == FixtureShowRequest`; assert `refreshRequest()` returns a value carrying the write query's root (pure value mapping — construct via public inits, round-trip nothing). Add commented compile-audit: an `UpdateRequest` whose `ResponseBody != RefreshRequest.ResponseBody` does not compile.
- [ ] **Step 2: Run — verify fails** (no such associatedtype yet).
- [ ] **Step 3: Implement** — to each of the three protocols add (DocC from sketch, adjusted per protocol):

```swift
associatedtype RefreshRequest: ServerRequest
// and to the where clause:  ResponseBody == RefreshRequest.ResponseBody
/// Builds the read request pass #2 re-serves after this write commits.
func refreshRequest() -> RefreshRequest
```

  Sweep existing conformers: `grep -rln "UpdateRequest\|CreateRequest\|DeleteRequest" Tests/ Sources/ | xargs grep -l ": UpdateRequest\|: CreateRequest\|: DeleteRequest"` — each test fixture gains a `RefreshRequest` typealias + 2-line bridge (use an existing Show/ViewModelRequest fixture as the refresh target; where none exists, mint a minimal `ShowRequest` fixture beside it). (Scouted: no write-CRUD conformers exist today, so this sweep should find only fixtures this task creates.)
  **Fixture reminder** (reviewer advisory): the new constraint composes with the
  shipped `ResponseBody: UpdateResponseBody`/`CreateResponseBody`, so the refresh
  target's body must ALSO adopt those markers —
  `extension FixturePageBody: UpdateResponseBody {}` etc. — or the conformance
  fails with a confusing constraint error.
- [ ] **Step 4: Run full suite.**
- [ ] **Step 5: Commit** — `feat(FOSMVVM)!: write CRUD protocols carry the typed refresh bridge (C8 T3)`

---

### Task 4: `VaporResponseBodyFactory` + `ProjectionContext` + GET wiring + `register(request:)`

**The keystone task — escalate its review to the session-default model.**
**Spec:** §3.1, §3.2, §3.10 (read door); sketch factory/context/read-door sections. Test groups 1, 2, 3 (+ obligation: executor wired).

**Files:**
- Rename+rewrite: `Sources/FOSMVVMVapor/Protocols/ViewModelFactory.swift` →
  `VaporResponseBodyFactory.swift` (delete `VaporModelFactoryContext` +
  `VaporViewModelFactory`)
- Create: `Sources/FOSMVVMVapor/Containment/ProjectionContext.swift`
- Modify: `Vapor Support/VaporServerRequestHost.swift` (GET handler),
  `Vapor Support/ViewModelRequest.swift` (`register(request:)`, delete
  `register(viewModel:)`), `Containment/PlanExecutor.swift` (error-string text
  `register(viewModel:)` → `register(request:)`),
  `Sources/FOSTestingVapor/VaporServerTestCase.swift:24` (constraint →
  `VaporResponseBodyFactory`)
- Modify (rename fallout): `Tests/FOSMVVMVaporTests/TestViewModel.swift`,
  `Composition/PlanRegistrationTests.swift`, `Composition/PlanExecutorTests.swift`,
  `Tests/FOSMacrosTests/ViewModelFactoryMacroTests.swift` (expected-expansion
  strings only)
- **NOT mechanical rename — delete/rewrite (reviewer flag):** the grouped-
  registration tests exercise a seam §3.10 removes:
  `PlanRegistrationTests.swift:626` and `PlanExecutorTests.swift:783` call
  `.grouped("api").register(viewModel:)` (fixtures `GroupedPageVM`, grouped
  `DockPageVM`) and assert the C7 grouped-path config error. Under C8 there is
  NO `RoutesBuilder` registration at all — `register(request:)` exists only on
  `Vapor.Application`. **Delete these tests + their fixtures** and replace with
  one compile-audit comment line pinning "registration is Application-only".
  Do NOT add a grouped overload to make them pass — that contradicts §3.10.
- Test: `Tests/FOSMVVMVaporTests/Protocols/VaporResponseBodyFactoryTests.swift`
  (create; grow from `VaporServerRequestHostTests.swift` patterns),
  `Tests/FOSMVVMVaporTests/Composition/ProjectionContextTests.swift` (create)

- [ ] **Step 1: Failing tests** (write all four, expect compile failures):

```swift
// ProjectionContextTests — withFluentTestApp; Harbor fixtures
@Test func plannedHandleReadsBackCachedRecords()   // group 3: own handle + a child's
@Test func unplannedHandleThrows()                  // never [] — assert throws; message
                                                    // names handle + factory (behavior only)
@Test func zeroDataScreenServesWithoutTrait()       // group 1: LandingPage-like fixture,
                                                    // GET through register(request:) →
                                                    // localized body + version header
@Test func composableScreenLoadsThenProjects()      // group 2: executor runs BEFORE body();
                                                    // records visible; legacy no-plan
                                                    // config error preserved
```

- [ ] **Step 2: Run — verify fails.**
- [ ] **Step 3: Implement** (signatures verbatim from sketch):
  - `VaporResponseBodyFactory` — `ServerRequestBody & Vapor.AsyncResponseEncodable`;
    `associatedtype Request: ServerRequest where Request.ResponseBody == Self`;
    `associatedtype AppState: Sendable = Void`;
    `static func body(context: ProjectionContext<Request, AppState>) throws -> Self`;
    default `encodeResponse` → `buildResponse(request)` (keep the existing
    SRP/OCP DocC block from the old file).
  - `ProjectionContext` — `vmRequest`, `appState`, `appVersion { get throws }`
    (from the stored `Vapor.Request`'s `applicationVersion()`? NO — the context
    must not hold the request. Capture the resolved `SystemVersion` **value**
    at construction, surface it via the throwing getter). Internal init takes
    `(vmRequest:, appState:, appVersion:, plan: RecordLoadPlan?, cache: [ContainerRecordCacheKey: [any DataModel]])`
    — a **value snapshot**; `records(_:)`:
    `plan?.tuple(matching: handle)` (T1's package member) → rebuild the cache key
    (container root + anchor + operation + refinement — mirror how the executor
    deposited it; read `PlanExecutor.load` for the exact key construction) →
    entries as `[Record]` (cast; a cast failure is a framework bug → throw).
    Missing tuple → throw `ContainmentError.unplannedRequirement(handle:factory:)`
    (new internal case; public DocC states behavior only).
  - Host GET handler becomes:
    `try await req.executeRecordLoadPlan(for: Request.self)` →
    build context (AppState = `()` until T5) → `Request.ResponseBody.body(context:)`
    → return (encodeResponse localizes). **This is the executor-wiring obligation.**
  - `register(request:)` per sketch (read door, identity constraint
    `SR.ResponseBody.Request == SR`); keep the C7 plan-derivation seam;
    delete `register(viewModel:)` entirely. **Also retire the stale
    grouped-path caveat wording** (reviewer flag): the doc comment at
    `PlanExecutor.swift:31`, the error `reason:` at `:41`, and the comment at
    `PlanRegistration.swift:60` all say "grouped/app.routes registration
    cannot reach boot derivation" — under C8 registration is Application-only
    by construction, so rewrite those to say that (don't just swap the
    method name inside otherwise-stale sentences).
  - Mechanical rename fallout across the listed files (macro-test expectation
    strings included).
- [ ] **Step 4: Run full suite** — expect broad green after fallout sweep; groups 1–3 pass.
- [ ] **Step 5: Commit** — `feat(FOSMVVMVapor)!: VaporResponseBodyFactory + ProjectionContext replace the raw-request factory; register(request:) wires the executor (C8 T4)`

---

### Task 5: `AppState` slot + `useAppState`

**Spec:** §3.3; sketch `useAppState`. Test group 4.

**Files:**
- Create: `Sources/FOSMVVMVapor/Containment/AppStateRegistry.swift`
- Modify: `ProjectionContext` construction site (host handler), `register(request:)`
  boot check
- Test: `Tests/FOSMVVMVaporTests/Containment/AppStateTests.swift` (create)

- [ ] **Step 1: Failing tests** — group 4 verbatim: builder runs per request (load phase — assert it can read the `Vapor.Request`); `Void` needs no registration; non-`Void` factory registered without builder → `register(request:)` throws (boot error, message names the AppState type); duplicate `useAppState` for the same type → throws; value visible in projection (`context.appState`).
- [ ] **Step 2: Run — verify fails.**
- [ ] **Step 3: Implement** — Application storage keyed by `ObjectIdentifier(AppState.self)` holding `@Sendable (Vapor.Request) async throws -> any Sendable` type-erased builders (erasure internal; recover via opened generic at build time, mirroring `resolveRecordLoadPlan`'s idiom); `useAppState` public per sketch (`throws` on duplicate); host handler: if `AppState.self != Void.self`, look up builder (missing = already boot-rejected), `try await` it, cast; `register(request:)` boot check via `SR.ResponseBody.AppState.self != Void.self && builder-absent → ContainmentError` (new internal case).
- [ ] **Step 4: Run — group 4 + full suite.**
- [ ] **Step 5: Commit** — `feat(FOSMVVMVapor): useAppState — typed load-phase app state for projections (C8 T5)`

---

### Task 6: Write path — `WriteTargetProviding`/`DataModelWriter`, write routes, boot checks

**The other keystone — escalate its review to the session-default model.**
**Spec:** §3.6 (ownership split), §3.8, §3.9, §3.10; sketch writer/write-door/MARK 3/MARK 4. Test groups 5, 6, 7, 8, 9, 15, 16.

**Files:**
- Create: `Sources/FOSMVVMVapor/Protocols/WriteTargetProviding.swift`
  (both protocols, DocC from sketch)
- Create: `Sources/FOSMVVMVapor/Containment/WriteRoute.swift` (the 7-step flow)
- Modify: `Vapor Support/VaporServerRequestHost.swift` (write-route registration by
  CRUD protocol), `Vapor Support/ViewModelRequest.swift` (write `register` overloads +
  base-door boot-reject), `Containment/ContainmentRelation.swift` (internal additive
  `createMember(_:in:on:)` — Fluent `ChildrenProperty.create`/`SiblingsProperty.attach`
  captured at factory time, the C6 refined-members precedent),
  `Containment/PlanRegistration.swift` (candidate-tuple derivation + root-source
  validation at write registration)
- Test: `Tests/FOSMVVMVaporTests/Containment/WriteRouteTests.swift` (create),
  fixtures extended in `ContainmentFixtures.swift` + a new
  `Tests/FOSMVVMVaporTests/Containment/WriteFixtures.swift`
  (UpdateBerthRequest/DeleteBerthRequest/CreateBerthRequest + bespoke RequestBodies —
  sketch MARK 3/4 verbatim, `rootIdentity` spelled per shipped `RootedQuery`;
  **no `ModelIdType` in any RequestBody — grep-audited in T8**)

- [ ] **Step 1: Failing tests** — groups 5–9, 15, 16 from the spec, one `@Test` per bullet. The load-bearing ones:
  - update happy path: PATCH with JSON body → response IS `refreshRequest()`'s body reflecting post-write state; page read plan NOT loaded pre-apply; cache invalidated; grant memo untouched; save-time constraint violation propagates
  - create: fresh `Target()` + same `apply`; FK set from candidate scope; record in refresh body
  - delete: `WriteTargetProviding` alone; gone from refresh body
  - validate() failure never reaches `apply`
  - retarget-proofing: target outside candidate set ⇒ not-found semantics; missing candidate tuple ⇒ fail-fast
  - boot fail-fasts: write-CRUD conformer at the base read door ⇒ boot error; `ReplaceRequest` ⇒ "write protocol not yet supported"; candidate root-source (query root without `RootedQuery` / apex without resolver) ⇒ boot error; fully-constrained write request binds the write door (positive overload-selection pin)
  - refresh bridge: bridge output routes through the same path as a direct GET (compare responses byte-wise)
- [ ] **Step 2: Run — verify fails.**
- [ ] **Step 3: Implement**, in this order:
  1. The two protocols (sketch-verbatim; `WriteTargetProviding.candidates`,
     `DataModelWriter.apply(to:) throws` — sync, no `Database`).
  2. Candidate-plan derivation at write registration: derive a one-tuple
     `RecordLoadPlan` from `candidates` (via the T1 walk face, inside FOSMVVM?
     NO — build the tuple Vapor-side through `RecordLoadPlan.tuple(matching:)`'s
     match data is not constructible there; instead add the candidate plan
     derivation next to `registerRecordLoadPlan` reusing the same walk on a
     synthesized single-requirement factory — simplest: an internal generic
     `CandidateFactory<Writer>` conforming to `ComposableFactory` whose
     `dataRequirements = [Writer.candidates]`, walked by the existing
     `RecordLoadPlan.walk`. Zero new package surface.) Store keyed by the write
     request type. Validate root source here (RootedQuery / apex resolver).
  3. `WriteRoute.swift` — the handler steps: decode body
     (`req.content.decode(SR.RequestBody.self)`), `validate()` (throw →
     propagate), execute the candidate plan (same executor path), resolve
     `Query.target` by `ModelIdentity` equality against the loaded set
     (miss ⇒ the registry's existing not-found error — behavior
     indistinguishable from missing row), `apply` / fresh `Target()` + apply +
     `createMember` FK / `target.delete(on: req.db)`, save,
     `invalidateContainerRecords(of:)` for the candidate root (and anchor
     containers touched), then `refreshRequest()` → run the **same generic GET
     handler body** (factor the T4 GET handler into an internal
     `serve<SR>(_ request: SR, on req:)` both routes call — pass #2 is
     fall-through by construction).
  4. Write `register` overloads (sketch-verbatim `where` clauses incl. identity
     constraints) registering the HTTP method from the CRUD protocol
     (PATCH/POST/DELETE per `ServerRequestAction`); base door gains the
     boot-reject (`SR.self is any CreateRequest/UpdateRequest/DeleteRequest/
     ReplaceRequest/DestroyRequest` type-checks → throw with the spec's message).
- [ ] **Step 4: Run — groups 5–9, 15, 16 + full suite.**
- [ ] **Step 5: Commit** — `feat(FOSMVVMVapor): the write path — candidates, sealed apply, refresh fall-through (C8 T6)`

---

### Task 7: Publicize + audit — apex resolver, `SupplementalRecordLoading`, Sort-bridge warn, remove `authorizedBy:`

**Spec:** §3.10, §3.11, §4. Test groups 12, 13, 14.

**Files:**
- Modify: `Containment/PlanRegistration.swift` (`useApexContainerResolver` → `public`,
  DocC from sketch; Sort-bridge boot warn at plan registration — detect
  `.refinedByRequest` plan whose `SR.Sort` is neither `EmptySort` nor
  `SortCriteria`-based via the existing `ErasedSortTermsProviding` check, log via
  `app.logger.warning` naming request + Sort type)
- Modify: `Containment/PlanExecutor.swift` (`SupplementalRecordLoading` → `public`
  with sketch DocC; keep walk-order runner internal)
- Modify: `Extensions/Request+ContainerLoad.swift` — delete the internal
  `authorizedBy:` entry (L40-48); fold its body into the opened-generic provider
  core (it is the only cache writer — the fold must preserve write-once semantics);
  re-point every test that called it (grep `authorizedBy:` in Tests/) through a
  minimal test `ContainerAuthorizationProvider` fixture — **never widen access**
- Modify: `Containment/ContainerRecordCache.swift` — update the L55-60 contract
  comment (the "until the C8 audit" sentence resolves to: removed)
- Test: `Tests/FOSMVVMVaporTests/Composition/SupplementalHookTests.swift`
  (group 12 — conformer runs post-declarative in walk order; thrown error fails
  the request, never empty), Sort-warn test (group 13 — assert via a captured
  logger), apex-through-public-door test (group 14)

- [ ] **Step 1: Failing tests** (groups 12–14).
- [ ] **Step 2: Run — verify fails.**
- [ ] **Step 3: Implement** (order: publicize → warn → removal+re-point, committing suite-green between if the removal sweep grows).
- [ ] **Step 4: Run full suite.**
- [ ] **Step 5: Commit** — `feat(FOSMVVMVapor): publicize apex resolver + supplemental hook; sort-bridge boot warn; remove the authorizedBy engine entry (C8 T7)`

---

### Task 8: Docs sweep, CHANGELOG, arch reconciliation, DoD greps

**Spec:** §7, §10.

**Files:**
- Modify: `CHANGELOG.md` (every §7 breaking change + the new public surface),
  `docs/superpowers/specs/2026-07-03-authorized-container-data-loading-architecture.md`
  (§C8 DIRECTION → SPECIFIED pointing at the spec; 8 obligations annotated
  discharged; §6 audit list: `authorizedBy:` removed, threshold stays internal,
  package statements re-verified incl. the `RecordLoadPlan` member addition),
  C7 spec + `2026-07-04-c7-surface-sketch.swift` (superseded-by note + rename
  mentions), `Sources/FOSMVVM/FOSMVVM.docc/ViewModelandViewModelRequest.md`
  (rename), skills/api-catalog if it names renamed symbols
  (`grep -rl "VaporViewModelFactory\|ComposableViewModelFactory\|register(viewModel"
  .claude/ docs/ Sources/*/\*.docc`)

- [ ] **Step 1: DocC implementer-leak sweep** — over every public symbol added/touched in T1–T7: no obligation labels, no future-macro notes, no D-C8-n citations, every symbol has a call-site example (grep `D-C8` in Sources/ must return nothing).
- [ ] **Step 2: DoD greps** (all must be clean):

```bash
grep -rn '\$[a-zA-Z]' Sources/FOSMVVM/ | grep -v '.build'      # no $-projections in FOSMVVM
grep -rn 'package ' Sources/FOSMVVMVapor/                       # zero package in Vapor
grep -rn 'VaporViewModelFactory\|VaporModelFactoryContext\|register(viewModel' Sources/ Tests/
grep -rn 'ModelIdType' Tests/FOSMVVMVaporTests/Containment/WriteFixtures.swift
```

- [ ] **Step 3: CHANGELOG + arch edits** (content per spec §7/§10).
- [ ] **Step 4: Full suite + swiftformat + swiftlint.** Expected: green (baseline 478 + new tests), clean.
- [ ] **Step 5: Commit** — `docs: C8 recorded — arch SPECIFIED, CHANGELOG, rename sweep, DoD greps (C8 T8)`

---

## Plan prose — rationale & gotchas (implementer notes; NOT DocC material)

- **Why the context snapshots instead of holding `Vapor.Request`:** the whole point
  is no reachable loader; a stored request would reintroduce `req.db` one property
  away. Snapshot cost is a dictionary copy of references — the cache entries are the
  same live Fluent objects (do not mutate them in projection; the cache's
  snapshot-sharing contract, `ContainerRecordCache.swift:52-61`, now also serves
  the context).
- **Why `serve<SR>` is factored (T6.3):** pass #2's whole guarantee is "same code
  path as GET". If the write route re-implements projection/serving, drift returns.
  Byte-compare test (group 16) pins it.
- **Why the candidate plan is a synthesized one-requirement factory:** reuses the
  walk, its validation, and the executor unchanged — no second plan format
  (one-serialization discipline applied to plans), no new package surface.
- **Why `authorizedBy:` removal folds INTO the provider core:** it is the only
  cache writer; moving rather than duplicating preserves the single-writer
  invariant the sequential-touch contract depends on.
- **Overload fall-through (T6.4):** Swift will route a constraint-missing write
  request to the base door silently — the boot-reject there is load-bearing, not
  belt-and-braces. Test both directions (reject at base door; positive selection
  at write door).
- **Middleware body decode:** the shipped middleware binds query-only with
  `requestBody: nil` — decode in the write handler (`req.content.decode`), NOT in
  middleware, so read routes stay untouched and the decode error propagates as the
  request's error.
- **`RootedQuery.rootIdentity`** is the shipped property name — fixtures use it
  (the sketch's `let dock:` was illustrative; satisfy the protocol with
  `var rootIdentity: ModelIdentity { dock }` or name the stored property
  `rootIdentity` outright).
- **Fixture bodies must be bespoke types** (never `EmptyBody`) — the
  `WriteTargetProviding` conformance would otherwise be a single global retroactive
  conformance (spec §3.8).
- **Rejected alternatives** live in spec §11 and the arch doc — do not re-litigate
  in code comments.

## Execution deviations (recorded)

Recorded during implementation; each was reviewer-accepted at the task it surfaced in.

1. **Group-16 byte-compare realized as field-compare.** The pass-#2 "same code path as
   GET" pin was drafted as a byte-equal comparison of the two responses. A ViewModel
   carries a random `vmId` (SwiftUI rendering identity), so two independent renders can
   never be byte-equal by construction. The test instead compares the response *fields*
   that carry post-write state — the guarantee the pin exists to protect. Reviewer-accepted.

2. **T7 fold made provider-fetch lazy.** Folding the `authorizedBy:` engine entry into the
   provider-driven core made the candidate/record load consult the authorization provider
   only when a container is present: a missing container now returns `[]` *without*
   consulting the provider. This is more correct per the pipeline order (no container ⇒
   nothing to authorize ⇒ empty, indistinguishable from an authorized-but-empty scope —
   the not-yours-is-not-found property already relies on that indistinguishability).
   Acknowledged here as a behavior note.

3. **T4/T6 fix cycles.** The create-gate amendment (an internal grant-verdict check before
   a fresh `Target()` is minted) and the `.siblings` transactionality / verb-door coherence
   hardening landed as review-cycle fixes — see spec §11 (Implementation-time amendments)
   and the §3.9 step-4 amendment for the full record.

4. **Post-review composition refactor (C8a).** The routing scaffold this plan shipped
   (`VaporServerRequestHost` + the write doors' inline route registrations) was refactored
   after review into the general `ServerRequestController` layer per David's composition
   ruling — see docs/superpowers/plans/2026-07-05-c8a-controller-composition.md.
