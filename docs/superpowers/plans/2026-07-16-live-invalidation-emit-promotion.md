# Live-Invalidation Emit Promotion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give non-Fluent server-side sources (Application-hosted actors, computed aggregates) a public, typed entry into live invalidation: `invalidateProjections(of:)` on the write side, `registerDependency(on:)` on the read side.

**Architecture:** The `.live` layer is abstracted transport with Fluent-only ignition — the hub → SSE → client pipeline speaks only `Set<ModelIdentity>`, but the only emit point is the Fluent `InvalidationEmitMiddleware` and the only registration writer is `PlanExecutor.depositRegistrationSet`. This plan opens both halves as one paired public contract, composing onto the existing collector/hub/header machinery with **no new protocol and no new mechanism**.

**Tech Stack:** Swift 6 / Swift Testing, Vapor, FluentKit (test fixtures only — the new API itself is Fluent-free).

---

## Design & Rationale (the fosmvvm-planning gate output)

### The ratified paired contract

Naming ratified by David 2026-07-16. The teaching sentence:
*register a dependency on what you read; invalidate projections of what you changed.*

```swift
// factory (read side) — ProjectionContext, FOSMVVMVapor extension:
try context.registerDependency(on: status)

// source (write side) — Vapor.Application (+ Request forwarding):
try await app.invalidateProjections(of: status)
```

Both halves are REQUIRED — the symmetry invariant is pinned at
`Sources/FOSMVVMVapor/Containment/PlanExecutor.swift` (`touchedContainers(of:)` doc):
*"the live-invalidation contract holds only while a client registers on exactly what a
write invalidates."* Emit without registration nudges nobody; registration without
emit refreshes never.

### Why the design is thin

- `FOSMVVM.Model` (`Sources/FOSMVVM/Protocols/Model.swift:26`) is already Fluent-free
  (`Codable + Hashable + id: ModelIdType?`) and mints unforgeable `ModelIdentity`
  (internal init — nobody hand-forges one). Identity needs zero new work.
- The routing discriminator is already ambient, not Fluent-attached:
  `LiveTransactionState.$collector` (task-local,
  `Sources/FOSMVVMVapor/LiveInvalidation/LiveTransaction.swift:97`). The public write-side
  call consults the same task-local: inside `liveTransaction { }` the nudge joins the
  transaction's collector and flushes only on commit; outside, it emits immediately
  (an actor mutation is its own commit). Hub absent (live invalidation not enabled) → no-op,
  matching `liveTransaction`'s degradation.
- **No `InvalidationSource` protocol.** Cut as speculative (defer-API-until-client-exists):
  nothing would require conformance; sources just call the two functions.

### The one structural change: the dependency sink

`ProjectionContext` (`Sources/FOSMVVM/Protocols/ProjectionContext.swift:32`) is a pure
value struct — it holds no `Vapor.Request`, by design ("Everything a projection may
see… Nothing else"). `registerDependency(on:)` therefore needs a conduit to
`req.registrationSet`. Decision: a **package-level closure field installed at
construction** —

```swift
package let dependencySink: (ModelIdentity) -> Void
```

- **Required (non-optional, no default).** A defaulted `{ _ in }` would be a silently-
  dropping no-op — the misconfiguration's invisible mode this repo's `records(_:)`
  throw-never-empty philosophy exists to forbid. Every constructor names its sink.
- **Why a field, not a task-local:** the context is the factory's *entire* sanctioned
  window; giving it the deposit capability at construction keeps the capability visible
  in the type and testable by handing a capturing closure. A task-local would hide a
  second ambient channel behind a surface whose whole point is "nothing else."
- Non-Sendable closure inside the existing `@unchecked Sendable` struct is sound under
  the already-documented contract: the context never escapes the projection; reads (and
  now the sink call) happen only on the request's handler task.
- Blast radius: the construction sites are
  `Sources/FOSMVVMVapor/Vapor Support/ServeRequest.swift:40` and `:42`, plus the test
  helpers in `Tests/FOSMVVMVaporTests/Composition/ProjectionContextTests.swift:89-97`
  and `Tests/FOSMVVMVaporTests/Composition/TotalCountTests.swift:116-118` (both init
  spellings in each). Task 2's grep is the authority — trust it over this list.

### Sequencing is already safe (verified)

`serve(_:)` (`Sources/FOSMVVMVapor/Vapor Support/ServeRequest.swift:30-45`) runs
`executeRecordLoadPlan` — which **assigns** `registrationSet` — *before* constructing
the context and calling `body(context:)`. The factory's `registerDependency` **inserts**
into the already-deposited set, so plan-derived registrations and factory-added ones
merge; nothing clobbers. The header attachment (`Response+FOS.swift:77`,
`addRegistrations(from:)`) reads the union later in `buildResponse` and needs no change.

`body(context:)` is **synchronous** (`ServeRequest.swift:44` — `try`, no `await`), so
`registerDependency(on:)` is `throws`, not `async throws`. Actor state reaches the
factory as a *value* via the `useAppState(_:builder:)` builder (which runs async, with
full request power, at `ServeRequest.swift:37` — *before* the factory). DocC examples
must show the snapshot taken in the builder, read synchronously in the factory.

### Semantics pinned for DocC and tests

- **Fluent-persisted models never need `invalidateProjections(of:)`** — their writes
  already emit via middleware. Calling it anyway double-nudges (harmless refresh, not a
  correctness break); the DocC says "never need," not "must not."
- **v1 derives no containment for non-Fluent models** — the emitted set is the model's
  own identity only. Sufficient for the hybrid case because `registerDependency`
  registered that same identity. Containment declarations for non-Fluent sources in
  `ModelTypeRegistry` are a separate future feature.
- **Bare `database.transaction { }` around a mixed SQL+actor write is undetectable**
  from `invalidateProjections` (no `db` handle crosses it) — the call would emit before
  commit. The remedy is the same one the middleware's suppression warning already
  teaches: use `liveTransaction`. Goes in DocC.
- **Actor-held identity needs only process-lifetime stability**
  (`let statusId = ModelIdType()` at actor init): a server restart is covered by the
  client transport's `.connected` event → refresh-every-live-screen sweep
  (`Sources/FOSMVVM/Protocols/InvalidationChannel.swift` DocC). Goes in the write-side
  function's DocC.
- Throws: both functions throw only `ModelError.missingId` (via `model.modelIdentity`).

### Contract-test discipline

All new tests exercise the **public** surface: identities are minted via
`model.modelIdentity` / compared via the public `ModelIdentity == some Model` operator
or `Set` equality; the header is decoded whole-value with `fromJSON()` — never parsed.
Emission-absence uses the existing sentinel discipline (see the header comment of
`Tests/FOSMVVMVaporTests/LiveInvalidation/LiveTransactionTests.swift:17-20`).
New fixtures use neutral vocabulary (`StatusSnapshot`, `StatusDashboardVM`) — existing
harbor-named *harness* helpers may be reused as plumbing, but no new harbor vocabulary
is introduced. Reuse caveat: `withFluentTestApp` (public) and `seedHarbor`
(module-internal) are callable from a new file, but `configureLiveHarbor` is
**file-private and duplicated per test file with differing signatures** — COPY the
single-arg version from `LiveTransactionTests.swift:189` into the new file; do not
expect to call it across files.

### Rejected alternatives (do not re-propose)

Names: `invalidate(_:)` (bare verb, no context), `registerLive(_:)`, `register(live:)`,
`register(_:)` (collides with boot `app.register(request:)`), `dependsOn(_:)`,
`registerInterest(in:)`, `announceChanged(_:)`, `emitInvalidation(for:)`,
`modelDidChange(_:)`, `notifyLiveClients(changed:)`, `invalidateLiveViews(of:)`.
Mechanisms: `InvalidationSource` protocol (speculative), optional/defaulted sink
(invisible no-op), task-local registration channel (hidden second window),
`Set<ModelIdentity>`-taking emit (two spellings; the mutation site holds the model).

---

## File Structure

- **Modify:** `Sources/FOSMVVM/Protocols/ProjectionContext.swift`
  — add `package let dependencySink`, thread through both package inits.
- **Modify:** `Sources/FOSMVVMVapor/Vapor Support/ServeRequest.swift:39-43`
  — install the real sink (insert into `registrationSet`) in both context branches.
- **Create:** `Sources/FOSMVVMVapor/LiveInvalidation/InvalidateProjections.swift`
  — write-side pair (`Application` + `Request`) + shared routing core.
- **Create:** `Sources/FOSMVVMVapor/LiveInvalidation/ProjectionContext+Dependencies.swift`
  — read-side `registerDependency(on:)` (server capability, sited like
  `ProjectionContext+Records.swift`).
- **Modify:** `Tests/FOSMVVMVaporTests/Composition/ProjectionContextTests.swift:89-97`
  — test helper passes a sink.
- **Create:** `Tests/FOSMVVMVaporTests/LiveInvalidation/InvalidateProjectionsTests.swift`
- **Create:** `Tests/FOSMVVMVaporTests/LiveInvalidation/RegisterDependencyTests.swift`
- **Modify:** `CHANGELOG.md`, `.claude/docs/FOSMVVMArchitecture.md`,
  api-catalog entries (via the `fosutilities-api-catalog-update` skill).

---

### Task 0: Branch

- [ ] **Step 1: Create the feature branch (repo is on `main`)**

```bash
cd /Users/david/Repository/FOS/FOSUtilities
git checkout -b feature/live-invalidation-emit-promotion
```

---

### Task 1: Write side — `invalidateProjections(of:)`

**Files:**
- Create: `Tests/FOSMVVMVaporTests/LiveInvalidation/InvalidateProjectionsTests.swift`
- Create: `Sources/FOSMVVMVapor/LiveInvalidation/InvalidateProjections.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/FOSMVVMVaporTests/LiveInvalidation/InvalidateProjectionsTests.swift`.
Copy the license header from any sibling file. Mirror the harness idioms of
`LiveTransactionTests.swift` in the same directory (`withFluentTestApp`,
`configureLiveHarbor`, hub subscribe, sentinel discipline — read that file first).

```swift
import Fluent
import FluentKit
import FOSFoundation
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing
import Vapor

// The internal hub subscribe is block coverage of an internal seam (same note as
// LiveTransactionTests); every asserted identity is minted/compared via public API.

/// Neutral non-Fluent fixture: an Application-hosted source's state snapshot.
/// FOSMVVM.Model only — deliberately NOT a FluentKit.Model.
private struct StatusSnapshot: FOSMVVM.Model {
    let id: ModelIdType?
    var activeSessions: Int = 0
}

@Suite("invalidateProjections(of:) — public write-side entry for non-Fluent sources")
struct InvalidateProjectionsTests {
    /// Outside any transaction, the call emits exactly the model's own identity.
    @Test func emitsOwnIdentityImmediately() async throws {
        try await withFluentTestApp { app in
            try configureLiveHarbor(app)
        } _: { app, _ in
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            let status = StatusSnapshot(id: .init(), activeSessions: 3)
            try await app.invalidateProjections(of: status)

            let expected = try Set([status.modelIdentity])
            #expect(await events.next() == expected)
        }
    }

    /// Inside liveTransaction, the nudge joins the collector: ONE union event after
    /// commit, containing the actor identity AND the SQL write's derived set.
    @Test func joinsLiveTransactionUnionOnCommit() async throws {
        try await withFluentTestApp { app in
            try configureLiveHarbor(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            let status = StatusSnapshot(id: .init(), activeSessions: 1)
            try await app.liveTransaction { tx in
                let berth = try Berth(number: 70, dockName: dock1.name, dockId: dock1.requireId())
                try await berth.save(on: tx)
                try await app.invalidateProjections(of: status)
            }

            let union = try #require(await events.next())
            #expect(union.contains(try status.modelIdentity))
            #expect(union.contains(try dock1.modelIdentity)) // berth's container, via middleware
        }
    }

    /// A thrown liveTransaction discards the collected nudge — sentinel-first.
    @Test func rolledBackTransactionEmitsNothing() async throws {
        try await withFluentTestApp { app in
            try configureLiveHarbor(app)
        } _: { app, db in
            _ = try await seedHarbor(on: db)
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            let status = StatusSnapshot(id: .init(), activeSessions: 1)
            struct Rollback: Error {}
            await #expect(throws: Rollback.self) {
                try await app.liveTransaction { _ in
                    try await app.invalidateProjections(of: status)
                    throw Rollback()
                }
            }

            let sentinelSource = StatusSnapshot(id: .init())
            let sentinel = try Set([sentinelSource.modelIdentity])
            await hub.emit(sentinel)
            #expect(await events.next() == sentinel)
        }
    }

    /// With live invalidation not enabled, the call is a no-op — no throw, no trap.
    @Test func disabledIsNoOp() async throws {
        try await withFluentTestApp { _ in
            // no configureLiveHarbor / useLiveInvalidation
        } _: { app, _ in
            let status = StatusSnapshot(id: .init())
            try await app.invalidateProjections(of: status)
            #expect(app.invalidationHub == nil)
        }
    }

    /// An unpersisted model (nil id) throws ModelError.missingId — never a silent skip.
    @Test func nilIdThrowsMissingId() async throws {
        try await withFluentTestApp { app in
            try configureLiveHarbor(app)
        } _: { app, _ in
            await #expect(throws: ModelError.self) {
                try await app.invalidateProjections(of: StatusSnapshot(id: nil))
            }
        }
    }

    /// Request forwarding reaches the same hub (exercised through the routing core:
    /// identical observable behavior to the Application call).
    @Test func requestForwardingEmits() async throws {
        try await withFluentTestApp { app in
            try configureLiveHarbor(app)
            app.get("poke") { req async throws -> HTTPStatus in
                try await req.invalidateProjections(of: StatusSnapshot(id: pokeId))
                return .ok
            }
        } _: { app, _ in
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            try await app.test(.GET, "poke") { res async in
                #expect(res.status == .ok)
            }

            let expected = try Set([StatusSnapshot(id: pokeId).modelIdentity])
            #expect(await events.next() == expected)
        }
    }
}

/// Stable across the route closure and the assertion.
private let pokeId = ModelIdType()
```

Adjust harness/fixture call shapes to what `LiveTransactionTests.swift` actually uses
(e.g. `Berth.init` signature) — the assertions above are the contract; the plumbing
must match the existing suite. For `requestForwardingEmits`, prefer the
`app.responder.respond(to:).get()` idiom the LiveInvalidation suite already uses
(`RegistrationHeaderTests.swift`) over `app.test(...)`: `app.test` runs only the sync
`boot()` (the repo's known async-boot gotcha), and staying on one idiom keeps the
suite uniform. Rewrite that test's serving plumbing accordingly.

- [ ] **Step 2: Run to verify failure**

```bash
swift test --filter InvalidateProjectionsTests
```
Expected: COMPILE FAILURE — `invalidateProjections` does not exist yet.

- [ ] **Step 3: Implement**

Create `Sources/FOSMVVMVapor/LiveInvalidation/InvalidateProjections.swift`
(license header from a sibling):

```swift
import FOSMVVM
import Foundation
import Vapor

public extension Vapor.Application {
    /// Nudges live clients to refresh every projection built from `model`
    ///
    /// Call it at each point a non-Fluent source commits a change — an
    /// `Application`-hosted actor mutating its state, a computed aggregate
    /// going stale:
    ///
    /// ```swift
    /// actor StatusMonitor {
    ///     // Minted once — the identity of "the status" for this process's
    ///     // lifetime. A restart is covered: reconnecting clients refresh
    ///     // every live screen.
    ///     private let statusId = ModelIdType()
    ///     private var activeSessions = 0
    ///
    ///     func sessionOpened(app: Application) async throws {
    ///         activeSessions += 1
    ///         try await app.invalidateProjections(of: snapshot())
    ///     }
    ///
    ///     func snapshot() -> StatusSnapshot {
    ///         .init(id: statusId, activeSessions: activeSessions)
    ///     }
    /// }
    /// ```
    ///
    /// Clients refresh the ViewModels whose factory called
    /// ``FOSMVVM/ProjectionContext/registerDependency(on:)`` for this model.
    /// Fluent-persisted models never need this call — their saves already
    /// notify live clients. When the change ships together with Fluent writes,
    /// make the call inside ``liveTransaction(_:)`` and it reaches clients
    /// only if the transaction commits. With live invalidation not enabled
    /// (no `useLiveInvalidation(on:)` at boot) it is a no-op.
    ///
    /// - Throws: `ModelError.missingId` when `model.id` is `nil`.
    func invalidateProjections(of model: some FOSMVVM.Model) async throws {
        try await routeProjectionInvalidation(of: model, hub: invalidationHub)
    }
}

public extension Vapor.Request {
    /// Nudges live clients to refresh every projection built from `model`
    ///
    /// The request-scoped spelling of
    /// ``Vapor/Application/invalidateProjections(of:)`` — same behavior, for
    /// call sites inside a route handler:
    ///
    /// ```swift
    /// try await req.invalidateProjections(of: status)
    /// ```
    func invalidateProjections(of model: some FOSMVVM.Model) async throws {
        try await application.invalidateProjections(of: model)
    }
}

/// The shared routing core, mirroring the middleware's pinned order
/// (InvalidationEmitMiddleware.route): task-local collector present → COLLECT
/// (its liveTransaction flushes on commit); else hub present → EMIT; else live
/// invalidation is not enabled → no-op. A collector is only ever installed by
/// liveTransaction, which requires a hub — so collector-first never strands a nudge.
private func routeProjectionInvalidation(
    of model: some FOSMVVM.Model,
    hub: InvalidationHub?
) async throws {
    let identity = try model.modelIdentity

    if let collector = LiveTransactionState.collector {
        await collector.collect([identity])
    } else if let hub {
        await hub.emit([identity])
    }
}
```

- [ ] **Step 4: Run to verify pass**

```bash
swift test --filter InvalidateProjectionsTests
```
Expected: all 6 tests PASS.

- [ ] **Step 5: Run the full LiveInvalidation suite (no regression)**

```bash
swift test --filter LiveTransactionTests && swift test --filter EmitMiddlewareTests
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/FOSMVVMVapor/LiveInvalidation/InvalidateProjections.swift Tests/FOSMVVMVaporTests/LiveInvalidation/InvalidateProjectionsTests.swift
git commit -m "feat: invalidateProjections(of:) — public write-side live-invalidation entry for non-Fluent sources"
```

---

### Task 2: The dependency sink (conduit only — no public API yet)

**Files:**
- Modify: `Sources/FOSMVVM/Protocols/ProjectionContext.swift`
- Modify: `Sources/FOSMVVMVapor/Vapor Support/ServeRequest.swift:39-43`
- Modify: `Tests/FOSMVVMVaporTests/Composition/ProjectionContextTests.swift:89-97`

- [ ] **Step 1: Add the field and thread it through both package inits**

In `Sources/FOSMVVM/Protocols/ProjectionContext.swift`, after the `countsByTuple`
declaration (line 53), add:

```swift
    /// Deposits one registered dependency identity into the serving request's
    /// registration set. Installed at construction — required, never defaulted: a
    /// silently-dropping sink would be a misconfiguration's invisible mode. Invoked
    /// only within the projection, on the request's handler task (the same
    /// no-escape contract the record snapshot already relies on).
    package let dependencySink: (ModelIdentity) -> Void
```

Add `dependencySink: @escaping (ModelIdentity) -> Void` as the final parameter of
**both** package inits, assigning it in each body.

- [ ] **Step 2: Fix the two construction sites in `serve(_:)`**

In `Sources/FOSMVVMVapor/Vapor Support/ServeRequest.swift`, replace lines 39-43 with:

```swift
        // The factory's dependency deposit: INSERTS into the set executeRecordLoadPlan
        // already assigned — factory-registered identities merge with the plan's, and
        // buildResponse attaches the union as X-FOS-Registrations.
        let dependencySink: (ModelIdentity) -> Void = { self.registrationSet.insert($0) }
        // A zero-data body has no derived plan; it constructs a context that carries no records.
        let context: ProjectionContext<SR, SR.ResponseBody.AppState> = if let plan = application.recordLoadPlan(for: SR.self) {
            .init(vmRequest: vmRequest, appState: appState, plan: plan, recordsByTuple: recordsByTuple(), countsByTuple: countsByTuple(), dependencySink: dependencySink)
        } else {
            .init(vmRequest: vmRequest, appState: appState, dependencySink: dependencySink)
        }
```

- [ ] **Step 3: Fix the test helper**

In `Tests/FOSMVVMVaporTests/Composition/ProjectionContextTests.swift` (helper at
lines 89-97 — check for BOTH init spellings), pass a no-op sink explicitly:
`dependencySink: { _ in }`. Grep for any other construction site:

```bash
grep -rn "init(vmRequest" Sources Tests
```
Every hit must now pass a sink.

- [ ] **Step 4: Build + full test run (behavior-neutral refactor)**

```bash
swift build && swift test
```
Expected: PASS everywhere — this task changes no observable behavior.

- [ ] **Step 5: Commit**

```bash
git add -A Sources/FOSMVVM/Protocols/ProjectionContext.swift "Sources/FOSMVVMVapor/Vapor Support/ServeRequest.swift" Tests/FOSMVVMVaporTests/Composition/ProjectionContextTests.swift
git commit -m "feat: ProjectionContext carries a required dependency sink into the request's registration set"
```

---

### Task 3: Read side — `registerDependency(on:)`

**Files:**
- Create: `Tests/FOSMVVMVaporTests/LiveInvalidation/RegisterDependencyTests.swift`
- Create: `Sources/FOSMVVMVapor/LiveInvalidation/ProjectionContext+Dependencies.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/FOSMVVMVaporTests/LiveInvalidation/RegisterDependencyTests.swift`,
patterned on `RegistrationHeaderTests.swift` (same directory): fixtures are served
through the real HTTP responder so the deposit reaches `buildResponse` on the same
request the header rides. Fixture VMs use neutral vocabulary. Cover these contracts:

1. **Factory-registered identity lands in the header.** A `VaporResponseBodyFactory`
   whose `body(context:)` calls
   `try context.registerDependency(on: StatusSnapshot(id: knownId))` (a file-private
   `let knownId = ModelIdType()`), served over HTTP. Decode the header whole-value —
   `let registered: [ModelIdentity] = try #require(res.headers.first(name: ModelIdentity.registrationsHeader)).fromJSON()`
   — and assert `Set(registered).contains(try StatusSnapshot(id: knownId).modelIdentity)`.
   *Execution note (2026-07-16): shipped as 4 tests, not 5 — review found this
   contract's path byte-identical to contract 3's with a strictly weaker assertion,
   so it is subsumed by contracts 2 (merge) + 3 (exact equality) and was dropped.*
2. **Merges with the plan's set — no clobber.** A fixture WITH a `LoadRequirement`
   (reuse the `HarborBerthsVM` shape from `RegistrationHeaderTests.swift` as plumbing)
   whose factory ALSO registers a `StatusSnapshot`: the header contains the plan's
   container identities AND the snapshot's — assert both memberships.
3. **Zero-data body registers too.** A fixture with no `dataRequirements` registering a
   snapshot: header present, contains exactly the snapshot identity (covers the
   `serve` else-branch sink).
4. **nil id throws, request fails typed.** A factory registering
   `StatusSnapshot(id: nil)` — the serve must surface an error, never a
   silently-missing registration. Depending on error-middleware wiring the failure
   arrives either as a non-`.ok` response or as a thrown error from
   `respond(to:).get()` — assert whichever the TDD run reveals; both satisfy the
   contract, silence does not.
5. **End-to-end symmetry (the invariant test).** Serve fixture (1); decode the header;
   subscribe to the hub; `try await app.invalidateProjections(of: StatusSnapshot(id: knownId))`;
   assert the emitted set equals the snapshot's identity **and** that identity is a
   member of the decoded header set — registration and emission name the same value.
   Harness note: `RegistrationHeaderTests`' `configureHarbor` does NOT enable live
   invalidation — this test's setup must compose the serving registration with
   `useLiveInvalidation(on:)` (or the copied `configureLiveHarbor`), else
   `invalidationHub` is nil and the emit is a no-op.

- [ ] **Step 2: Run to verify failure**

```bash
swift test --filter RegisterDependencyTests
```
Expected: COMPILE FAILURE — `registerDependency` does not exist yet.

- [ ] **Step 3: Implement**

Create `Sources/FOSMVVMVapor/LiveInvalidation/ProjectionContext+Dependencies.swift`:

```swift
import FOSFoundation
import FOSMVVM
import Foundation

public extension ProjectionContext {
    /// Declares that this response depends on `model`, so live clients refresh
    /// its projections when the model changes
    ///
    /// Plan-loaded records are registered automatically. Call this from your
    /// factory for data the plan can't see — state your `appState` builder
    /// snapshotted from an `Application`-hosted actor:
    ///
    /// ```swift
    /// // boot: the builder snapshots the actor (async, before the factory runs)
    /// app.useAppState(DashboardState.self) { req in
    ///     DashboardState(status: await req.application.statusMonitor.snapshot())
    /// }
    ///
    /// // factory: read the value, register the dependency
    /// static func body<R: ServerRequest>(context: ProjectionContext<R, DashboardState>) throws -> Self
    ///     where R.ResponseBody == Self {
    ///     let status = context.appState.status
    ///     try context.registerDependency(on: status)
    ///     return .init(activeSessions: status.activeSessions)
    /// }
    /// ```
    ///
    /// The registered identity rides to the client with the response; a later
    /// ``invalidateProjections(of:)`` for the same model triggers the refresh.
    /// Register and invalidate must name the same entity — that pairing IS the
    /// live contract.
    ///
    /// - Throws: `ModelError.missingId` when `model.id` is `nil`.
    func registerDependency(on model: some FOSMVVM.Model) throws {
        try dependencySink(model.modelIdentity)
    }
}
```

(Siting note, mirroring `ProjectionContext+Records.swift`'s header rationale: the
registration deposit is a server capability, so the public method lives at this layer
even though the sink field is FOSMVVM's.)

- [ ] **Step 4: Run to verify pass**

```bash
swift test --filter RegisterDependencyTests
```
Expected: all 5 tests PASS.

- [ ] **Step 5: Run the neighboring suites (no regression)**

```bash
swift test --filter RegistrationHeaderTests && swift test --filter ProjectionContextTests
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/FOSMVVMVapor/LiveInvalidation/ProjectionContext+Dependencies.swift Tests/FOSMVVMVaporTests/LiveInvalidation/RegisterDependencyTests.swift
git commit -m "feat: registerDependency(on:) — factories register non-plan data for live refresh"
```

---

### Task 4: Docs, catalog, changelog

**Files:**
- Modify: `CHANGELOG.md` (new Unreleased → Added entries)
- Modify: `.claude/docs/FOSMVVMArchitecture.md` (live-invalidation section)
- Modify: api-catalog (via skill)

- [ ] **Step 1: CHANGELOG**

Add under an `## [Unreleased]` → `### Added` section (create if absent), following the
file's existing entry style:

```markdown
- `Application.invalidateProjections(of:)` / `Request.invalidateProjections(of:)` —
  non-Fluent server-side sources (Application-hosted actors, computed aggregates)
  nudge live clients when their state changes. Composes with `liveTransaction`.
- `ProjectionContext.registerDependency(on:)` — factories register response data the
  record-load plan can't see (e.g. `appState` actor snapshots) for live refresh.
```

State the **contract only** — no encoded shapes, no internals.

- [ ] **Step 2: Architecture doc**

In `.claude/docs/FOSMVVMArchitecture.md`, extend the live-invalidation section with a
short subsection: the paired public contract, the teaching sentence (*register a
dependency on what you read; invalidate projections of what you changed*), the
Fluent-never-needs-this rule, and v1's own-identity-only scope for non-Fluent sources.

- [ ] **Step 3: API catalog**

Invoke the `fosutilities-api-catalog-update` skill — it audits the new public symbols
into `FOSMVVMVapor.md`, updates the reach-for index, and bumps the plugin version.

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md .claude/docs/FOSMVVMArchitecture.md .claude/skills
git commit -m "docs: live-invalidation emit promotion — contract docs, catalog, changelog"
```

---

### Task 5: Verification sweep

- [ ] **Step 1: Full test run**

```bash
swift test
```
Expected: PASS. (Known environment note: a cold-run intermittent exists in this repo —
rerun once before investigating; see the issue-reporting taxonomy: classify, never
"pre-existing, unrelated".)

- [ ] **Step 2: Format + lint**

```bash
swiftformat . && swiftlint
```
Expected: no violations; commit any formatting deltas as `chore: swiftformat`.

- [ ] **Step 3: Squash to logical commits**

Squash granular commits down to a few logical ones (feature write-side, feature
read-side, docs) per the repo's squash-before-PR practice.

- [ ] **STOP — review gate.** Push of the branch is fine if asked; **do NOT open a PR**
  until David has reviewed the finished work and said go.

---

## Out of Scope (deliberately)

- Containment declarations for non-Fluent sources in `ModelTypeRegistry`.
- Auto-emitting actor sugar (a `didMutate` wrapper) — cooperative calls are v1's
  honest contract.
- Multi-instance fan-out — stays behind `InvalidationHub` (DEF-L2-4), untouched.
- Client-side changes — none needed; the client already consumes the header and the
  SSE stream without knowing what produced them.
