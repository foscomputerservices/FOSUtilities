# L2 Live Invalidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `.live` ViewModel refresh — server-pushed invalidation nudges over SSE,
per the approved spec `docs/superpowers/specs/2026-07-09-live-invalidation-l2-design.md`.

**Architecture:** One emit point (per-type Fluent `ModelMiddleware`, containment-derived
identity sets, task-local transaction collector) → in-memory hub → SSE endpoint → client
`InvalidationChannel` → `@MainActor` dispatcher + freshness gate → `.live` marker delivery
with plan-derived registration sets riding the `X-FOS-Registrations` response header.

**Tech Stack:** Swift 6 / Swift Testing (macro tests: XCTest) · Vapor + FluentKit
(`ModelMiddleware`, `Request.storage`) · `URLSession.bytes` SSE · FOSMacros.

**Read first:** the spec (§3 contract, §4 signature-normative surface, §6 frozen wire
contracts, §8 test groups). On any conflict, **the spec wins**. Spec branch:
`spec/live-invalidation-l2`. Precondition SATISFIED: `client-credential-provider` merged
as PR #113; this branch is rebased onto it — Task 6 is unblocked.

---

## fosmvvm-planning gate output

### Public surface (all names David-approved; justifications)

| Symbol | Module | Justification (caller need) |
|---|---|---|
| `ViewModelOptions.live` | FOSMVVM (`Macros.swift:19` **public** enum) | the author's one-line opt-in |
| `.live` twin case | FOSMacros (`ViewModelMacro.swift:48` **private** enum) | macro-side parsing (mirrors `clientHostedFactory`) |
| `LiveViewModel` | FOSMVVM | macro-emitted conformance; the resolver's specialization hook |
| `InvalidationEvent` | FOSMVVM | a custom channel must produce these |
| `InvalidationChannel` | FOSMVVM | the DIP transport-override seam |
| `MVVMEnvironment.invalidationChannel` / URL-package `invalidationBaseURL` | FOSMVVM | config; mirrors `resourcesBaseURL ?? serverBaseURL` |
| `Application.useLiveInvalidation(on:)` | FOSMVVMVapor | server boot switch |
| `Request.liveTransaction` / `Application.liveTransaction` | FOSMVVMVapor | the sanctioned transactional-write door (D-L2-1) |

Everything else is **internal**: hub, dispatcher, emit middleware, SSE framing/parsing,
registration token, the task-local collector, the `Request.storage` deposit key.

Gate checklist: minimal surface ✓ (every symbol above has a named consumer; nothing else
public) · encapsulation ✓ (nudges/headers carry sealed `ModelIdentity`; no raw getters) ·
no stringly-typing ✓ (the two wire literals are §6 frozen contracts, not identities) ·
one serialization ✓ (L0's frozen `ModelIdentity` Codable everywhere; no second format) ·
requirement+default n/a (marker protocol; single-requirement channel — `nil` synthesizes the
internal default, no extension-shadowing) · representation unpublished ✓ (DocC states
contracts; encoded shapes live in spec §6 + internal tests) · boundaries ✓ (FOSMVVM touches
only L0 types; all Fluent/Vapor pieces Vapor-side).

**Gate finding (spec §4 refinement):** `.live` has **three** edit sites — the public
`ViewModelOptions` (`Sources/FOSMVVM/Macros/Macros.swift:19`), the private FOSMacros twin
(`Sources/FOSMacros/ViewModelMacro.swift:48`), and the conformances list of the
`@attached(extension, …)` declaration (`Macros.swift:31`), which must gain `LiveViewModel`.

### Customer DocC (drafted first; tasks carry these verbatim, refine only for compilability)

`LiveViewModel`:
```swift
/// A ``ViewModel`` that refreshes automatically when its server data changes
///
/// Don't conform directly — opt in with the macro:
///
/// ```swift
/// @ViewModel(options: [.live])
/// public struct DocksViewModel: RequestableViewModel { ... }
/// ```
///
/// Any view bound with `.bind()` then re-fetches whenever another actor mutates
/// the data this ViewModel was served from — no polling, no manual invalidation,
/// and nothing else to write. Where no live connection is configured the
/// ViewModel behaves exactly like a non-live one (fetch once on appear), so
/// adding `.live` to a shipped screen is purely additive.
```

`InvalidationEvent`:
```swift
/// One event from the server's live-invalidation stream
///
/// You only meet this type when supplying a custom ``InvalidationChannel``;
/// the default channel produces it for you. Yield `.connected` whenever your
/// transport (re)establishes its connection — FOSMVVM responds by refreshing
/// every live screen — and `.invalidated` with each identity set the server
/// pushes.
```

`InvalidationChannel`:
```swift
/// The transport that delivers server invalidation nudges to this client
///
/// Most apps never touch this: leave ``MVVMEnvironment/invalidationChannel``
/// `nil` and FOSMVVM synthesizes the standard channel over your deployment
/// URLs. Conform your own type only to replace the transport wholesale:
///
/// ```swift
/// struct MyChannel: InvalidationChannel {
///     func events() -> AsyncStream<InvalidationEvent> { ... }
/// }
///
/// let environment = MVVMEnvironment(
///     appBundle: Bundle.main,
///     invalidationChannel: MyChannel(),
///     deploymentURLs: ...
/// )
/// ```
```

`Application.useLiveInvalidation(on:)`:
```swift
/// Turns on live invalidation for this server
///
/// Call once at boot, passing the route group your clients authenticate
/// against; every registered container model then nudges connected clients
/// after each committed change:
///
/// ```swift
/// let authed = app.grouped(MyAuthMiddleware())
/// try app.useLiveInvalidation(on: authed)
/// ```
///
/// Model registrations made before or after this call are both honored.
```

`liveTransaction`:
```swift
/// A Fluent transaction whose writes still notify live clients
///
/// Inside a bare `database.transaction { }` FOSMVVM cannot know whether your
/// writes commit, so it stays silent (and logs a warning). Use
/// `liveTransaction` instead and every write inside the closure nudges live
/// clients if — and only if — the transaction commits:
///
/// ```swift
/// try await req.liveTransaction { db in
///     dock.status = .closed
///     try await dock.save(on: db)
/// }
/// ```
```

`ViewModelOptions.live` (public enum case):
```swift
/// Refresh bound views automatically when server data changes — see ``LiveViewModel``
case live
```

### Contract-test discipline (binding for every task)

- Construct through public paths (`app.register`, door writes, `ViewModelId()`,
  `try value.toJSON().fromJSON()`); `@testable` only for block-coverage of internals
  (hub buffering, SSE parsing), never for contract assertions.
- Assert behavior — set equality of emitted identities, freshness ordering, reconnect
  sweep counts, degraded fetch-once — never encoded bytes, **except** the two §6 frozen
  wire contracts (SSE framing, header round-trip), which get representation pins by design.
- Freshness ordering comes from construction order (`ViewModelId()` twice), never forging.
- Suites touching a shared app/hub: `.serialized`. Middleware is an async lifecycle concern:
  use `app.asyncBoot()` in Vapor tests (the async-boot gotcha).
- Fixtures: the existing harbor graph (`withFluentTestApp`, Pier/Dock/Berth + Harbor apex).

### Rationale (implementer prose — none of this goes in DocC)

- **Why one emit point:** door writes are Fluent saves; middleware catches those *and*
  bypass writes. Emitting from the doors too would double-nudge (spec §3.1).
- **Why task-local:** the middleware sees only `Database`; the north star forbids
  attaching anything to it. Task-locals flow with the transaction's task tree (spec §3.1,
  §11.1). Routing order: collector present → collect; `inTransaction` → suppress+warn;
  else emit.
- **Why the header:** response-scoped metadata beside `X-FOS-Version`; VM baselines stay
  byte-identical (D-L2-4). Deposit seam: executor → `Request.storage` → `buildResponse`
  (spec §3.4; the read path derives its own set — `invalidateWrittenContainers` is
  write-path code, not reusable as-is).
- **Why re-register per response:** membership drift self-heals; no client-side bookkeeping.
- **Namespace tier may sit dormant** in v1 (spec §3.3 honesty note) — its tests assert the
  dispatcher contract, not end-to-end namespace traffic.
- **In-place swap, never teardown**, for nudge refreshes: mirrors the shipped
  `viewModelRefreshed` path (`ViewModelView.swift:432`); teardown flash is a defect for
  live screens.

---

## File structure

```
Sources/FOSMVVM/
  Protocols/LiveViewModel.swift            (new: marker)
  Protocols/InvalidationChannel.swift      (new: channel + InvalidationEvent)
  SwiftUI Support/InvalidationDispatcher.swift (new: internal dispatcher + token)
  SwiftUI Support/SSEInvalidationChannel.swift (new: internal default channel + parser)
  SwiftUI Support/MVVMEnvironment.swift    (mod: channel + invalidationBaseURL seams)
  SwiftUI Support/ViewModelView.swift      (mod: live resolver path, gate, swap)
  Macros/Macros.swift                      (mod: .live case + LiveViewModel conformance)
Sources/FOSMVVMVapor/
  LiveInvalidation/InvalidationHub.swift   (new: internal hub actor)
  LiveInvalidation/InvalidationEmitMiddleware.swift (new: internal per-type middleware
                                            + identity-set derivation)
  LiveInvalidation/LiveTransaction.swift   (new: wrappers + task-local collector)
  LiveInvalidation/InvalidationRoute.swift (new: SSE endpoint + framing)
  Extensions/Application+LiveInvalidation.swift (new: useLiveInvalidation)
  Extensions/Response+FOS.swift            (mod: attach X-FOS-Registrations)
  Containment/…executor seam…              (mod: deposit registration set in Request.storage)
Sources/FOSMacros/ViewModelMacro.swift     (mod: .live twin, conformance, diagnostic)
Tests/… mirrors sources; macro tests in Tests/FOSMacrosTests (XCTest)
```

---

### Task 1: Client vocabulary + environment seams (FOSMVVM)

**Files:** Create `Sources/FOSMVVM/Protocols/LiveViewModel.swift`,
`Sources/FOSMVVM/Protocols/InvalidationChannel.swift`;
Modify `Sources/FOSMVVM/SwiftUI Support/MVVMEnvironment.swift` (URL package
`invalidationBaseURL: URL? = nil` → stored resolved like `resourcesBaseURL` at `:81`;
`invalidationChannel: (any InvalidationChannel)? = nil` init param);
Test `Tests/FOSMVVMTests/Protocols/InvalidationChannelTests.swift`.

- [ ] Write failing tests: a test channel conforms and yields
  `.connected` / `.invalidated(Set<ModelIdentity>)` through `events()`;
  `invalidationBaseURL` defaults to `serverBaseURL` and honors an override;
  `MVVMEnvironment` accepts a channel (Swift Testing).
- [ ] Verify fail → implement (spec §4 signatures + gate DocC verbatim) → verify pass.
- [ ] `swiftformat . && swiftlint` → commit `feat(FOSMVVM): live-invalidation vocabulary + environment seams`.

### Task 2: Identity-set derivation (FOSMVVMVapor)

**Files:** Create `Sources/FOSMVVMVapor/LiveInvalidation/InvalidationEmitMiddleware.swift`
(derivation half: mutated model → `Set<ModelIdentity>` by inverting registry containment —
own identity + `.parent` refs + owning containers via relation `parentKey`, per spec §3.1);
Test `Tests/FOSMVVMVaporTests/LiveInvalidation/IdentitySetDerivationTests.swift`
(`withFluentTestApp`, harbor fixtures).

- [ ] Failing tests (spec test group 3): Berth ⇒ {Berth, owning Dock}; Dock (contained by
  Harbor apex fixture) ⇒ {Dock, Harbor}; pivot-model save covers `.siblings`; an
  uncontained model ⇒ {self} only.
- [ ] Verify fail → implement derivation (internal; no new public surface) → pass.
- [ ] Commit `feat(FOSMVVMVapor): containment-derived invalidation identity sets`.

### Task 3: Hub, emit middleware routing, liveTransaction, useLiveInvalidation (middleware half)

**Files:** Create `InvalidationHub.swift` (internal actor: `emit(Set<ModelIdentity>)`,
subscriber streams, bounded buffers; **owned by `Application.storage`** under a storage key —
mirror the `TupleCacheKeysStore` pattern, `PlanExecutor.swift:58-59`),
`LiveTransaction.swift` (public wrappers on
`Vapor.Request`/`Application` + internal task-local collector),
`Extensions/Application+LiveInvalidation.swift` (`useLiveInvalidation(on:)` — this task:
registry sweep + future-registration hook + hub creation; route mount lands in Task 4);
finish `InvalidationEmitMiddleware` routing. Modify the C4 registration path so
`app.register(type, migration:)` adds middleware when enabled.
Test `…/EmitMiddlewareTests.swift`, `…/LiveTransactionTests.swift` (`.serialized`,
`app.asyncBoot()`).

- [ ] Failing tests (groups 1–2): auto-commit door write emits post-save with the derived
  set; bare `db.transaction {}` write emits nothing + warns once; `liveTransaction` flushes
  the collected sets on commit; thrown `liveTransaction` emits nothing; enable-then-register
  and register-then-enable both wire middleware.
- [ ] Verify fail → implement (routing order: collector → `inTransaction` → emit; hub
  injected at registration, never on `Database`; gate DocC on the two public wrappers) → pass.
- [ ] Commit `feat(FOSMVVMVapor): invalidation hub + emit middleware + liveTransaction`.

### Task 4: SSE endpoint + wire framing

**Files:** Create `InvalidationRoute.swift`; extend `useLiveInvalidation(on:)` to mount
`GET <group>/invalidations` streaming from the hub (heartbeat comments; overflow closes the
stream — spec §3.2/§6). Test `…/InvalidationRouteTests.swift`.

**Test infrastructure (decided):** long-lived streams exceed `app.test(...)` — build a
**serve-on-port streaming harness in FOSTestingVapor** as part of this task (mirror
`withFluentTestApp`'s shape: boot on an ephemeral port, hand the test a base URL, drain the
stream via `URLSession.bytes` with a bounded read + timeout). The implementer is authorized
to add that file; Task 6's round-trip test reuses it.

- [ ] Failing tests (group 4 + §6 pins): connected stream receives a framed `data:` event
  whose JSON array round-trips to the emitted set via `defaultDecoder`; heartbeats flow;
  overflow closes; endpoint honors the passed `RoutesBuilder` group.
- [ ] Verify fail → implement → pass → commit `feat(FOSMVVMVapor): SSE invalidation endpoint`.

### Task 5: Registration-set deposit + X-FOS-Registrations header

**Files:** Modify the plan executor seam (deposit the resolved roots + touched containers in
`Request.storage`) and `Extensions/Response+FOS.swift` — add a **sibling of
`addSystemVersion`** (`:63`) invoked from the centralized `buildResponse` (`:33`), so the
header rides every served response the same way the version header does. Read path derives its own set
(mirror `invalidateWrittenContainers`'s shape, `WriteRoute.swift:183-193` — net-new).
Test `…/RegistrationHeaderTests.swift`.

- [ ] Failing tests (group 5): a served GET carries the executed plan's set; a write-door
  refresh carries the refreshed set; header value round-trips via
  `defaultEncoder`/`defaultDecoder` (§6 pin); a response with no plan carries no header.
- [ ] Verify fail → implement → pass → commit
  `feat(FOSMVVMVapor): plan-derived registration sets on X-FOS-Registrations`.

### Task 6: Default SSE client channel (FOSMVVM)

**Files:** Create `SwiftUI Support/SSEInvalidationChannel.swift` (internal: `URLSession.bytes`,
line parser, reconnect back-off, `.connected` on (re)open, `credentialHeaders()` at open);
wire `MVVMEnvironment` `nil`-channel synthesis. Test
`Tests/FOSMVVMTests/SwiftUI Support/SSEChannelParsingTests.swift` (parser coverage via
`@testable`) + a round-trip test in `Tests/FOSMVVMVaporTests` against the Task 4 endpoint.

- [ ] Failing tests (group 6): framing parse (data lines, comment heartbeats ignored,
  multi-line events); `.connected` emitted on open and re-open; credential headers attach.
- [ ] Verify fail → implement → pass → commit `feat(FOSMVVM): default SSE invalidation channel`.

### Task 7: Dispatcher + freshness gate (FOSMVVM)

**Files:** Create `SwiftUI Support/InvalidationDispatcher.swift` (internal `@MainActor`:
exact + namespace tiers, token, re-registration replaces, reconnect sweep; owned by
`MVVMEnvironment`, channel opens on first registration). Modify `ViewModelView.swift`:
gate at the swap point (`incoming.vmId.freshness > current.vmId.freshness`), in-place swap
for refresh arrivals, navigation (`query`/`fragment` change) bypasses the gate.
Test `…/InvalidationDispatcherTests.swift`, `…/FreshnessGateTests.swift`.

- [ ] Failing tests (groups 7–8): exact and namespace matching; token death unregisters;
  re-registration replaces; sweep fires all; older-drops/newer-swaps (construction-order
  freshness); navigation bypass; redundant self-nudge absorbed.
- [ ] Verify fail → implement → pass → commit `feat(FOSMVVM): invalidation dispatcher + freshness gate`.

### Task 8: `.live` delivery (FOSMacros + FOSMVVM resolver)

**Files:** Modify `Sources/FOSMVVM/Macros/Macros.swift` (`case live` + gate DocC;
`LiveViewModel` added to the `@attached(extension …)` conformances at `:31`),
`Sources/FOSMacros/ViewModelMacro.swift` (private twin; emit `LiveViewModel` conformance;
`.live`+`.clientHostedFactory` ⇒ diagnostic error), `ViewModelView.swift` (live path:
read `X-FOS-Registrations` on each response, register/re-register via dispatcher; degrade
to fetch-once when no channel). Tests: `Tests/FOSMacrosTests` expansion fixtures +
diagnostic (XCTest); `Tests/FOSMVVMTests` delivery behavior (group 9).

- [ ] Failing tests: expansion fixture shows `LiveViewModel` conformance; the combined-options
  diagnostic fires; degraded no-channel bind fetches once; response header registers.
- [ ] Verify fail → implement → pass → commit `feat: @ViewModel(options: [.live]) delivery`.

### Task 9: Seam hardening + docs sweep

**Files:** Test `Tests/FOSMVVMTests/SwiftUI Support/InvalidationSeamTests.swift` (first tests
for `viewModelInvalidated` teardown + `viewModelRefreshed` in-place swap — group 10).
Modify: `CHANGELOG.md` (feature entry; wire contracts noted as contracts, never shapes);
arch doc §C9 → implemented status + this spec pointer; north star §5 delivery note.
Post-merge obligation (recorded, not on-branch): `fosutilities-api-catalog-update` + plugin bump.

- [ ] Write seam tests → verify → docs sweep → full suite green (`swift test`) →
  `swiftformat . && swiftlint` → commit `test(FOSMVVM): invalidation seam hardening + docs sweep`.

---

**Execution notes:** work in a dedicated worktree (L1 practice); Opus subagents implement,
per-task dual review (spec-compliance + code-quality), escalate to Fable only where rigor
decides; suite must stay green after every task; access minimalism audited at Task 9
(zero new `package`).

---

## Execution deviations (recorded)

What the execution refined against the plan above — kept here (implementer prose), not in DocC.

- **T3 BLOCKED → binding-site discovery.** Task 3's `liveTransaction` collector first failed:
  bound *around* `db.transaction`, the task-local never reached the middleware because FluentKit's
  async `transaction` bridges through an unstructured `Task` (`makeFutureWithTask`). The fix binds
  the collector *inside* the closure `db.transaction` runs; both placements were spike-tested
  (outer fails, inner passes). Folded into spec §3.1's "Binding site" bullet (commit a2b008f).
- **Graph-sweep coverage.** `useLiveInvalidation` wires emit middleware for each registered
  container's whole graph (container + contained types + `.siblings` pivots), `ObjectIdentifier`-
  deduped so a doubly-reachable type (e.g. `Dock`, reached via its own registration and `Harbor`'s
  contained side) gets exactly one middleware — a duplicate would double-emit (guard test in
  `EmitMiddlewareTests.doubleReachedModelEmitsExactlyOnce`).
- **Fix rounds' notable finds** (post-task hardening, each its own commit):
  - **T6** — the SSE channel now validates HTTP status at open: a non-2xx response backs off
    instead of spinning and never falsely signals `.connected`.
  - **T7** — the dispatcher evicts a stale same-address registration entry (opportunistic
    dead-entry prune), preventing a collision from resurrecting a dead token.
  - **T8** — the capturing fetch overloads were tightened to `internal` (the seam was never
    public surface); and the resolver's failed-refresh guard preserves the prior registration set
    so a transient fetch error never deafens a live screen (the deaf-screen guard, spec §3.4).
- **Test harness — `withServedFluentTestApp`.** Task 4 added a serve-on-an-ephemeral-port
  streaming harness in FOSTestingVapor (long-lived SSE streams exceed `app.test(...)`). The name
  is provisional, pending owner naming arbitration.
- **FOSFoundation `package` symbol.** The one new `package` declaration in the whole layer:
  `DataFetch.send(…capturingResponseHeader:)`, so the FOSMVVM live resolver can read
  `X-FOS-Registrations` off the producing fetch. Zero new `package` in FOSMVVMVapor (Task 9 audit).
