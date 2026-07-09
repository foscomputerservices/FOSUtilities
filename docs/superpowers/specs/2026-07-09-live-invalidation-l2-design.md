# L2 — Live ViewModel Invalidation: emit, transport, dispatch, delivery

**Date:** 2026-07-09
**Status:** Approved by David (live session 2026-07-09); dual-reviewed (spec-document:
Approved, all citations verified · FOSMVVM-discipline: Sound, no violations); review
advisories reconciled (§11)
**Parent:** `2026-07-03-live-viewmodel-invalidation-architecture.md` (the north star; §5 is this
layer's arc-level design) · `2026-07-03-authorized-container-data-loading-architecture.md` §C9
**Depends on:** L0 (`ModelIdentity`, `ModelNamespace`, `ViewModelId.Freshness`) · L1 C1–C8a
(registry, engine+cache, provider auth, plans, `ResponseBodyFactory`, write doors) — all merged
to `main` · the `client-credential-provider` branch (`ClientCredentialProvider`,
`ClientCredentialMiddleware`) — assumed merged before L2 lands
**Scope:** FOSMVVM, FOSMVVMVapor, FOSMacros, FOSTestingVapor

---

## 1. Problem

FOSMVVM is request/response only. A screen that another actor can mutate — a collection, a
dashboard — learns of the change only by re-issuing a request it has no reason to re-issue.
L1 closed the *caller's* half (pass #2: a write door re-serves its own caller through the genuine
GET pipeline). This layer closes the *other clients'* half (pass #1): after a committed mutation,
every **other** bound client showing affected data refreshes — invisibly to the ViewModel author,
who opts in with `@ViewModel(options: [.live])` and writes nothing else.

The north star §5 locked the architecture: the server pushes an **identity nudge, never VM data**
(a `ModelIdentity` set) over **SSE**; the client re-fetches through the normal
fetch→localize→project pipeline; a **monotonic freshness gate** (`ViewModelId.Freshness`, wire key
`fsh`, shipped in L0) drops stale arrivals. This spec turns §5 into contracts, reconciled against
what L1 actually shipped.

## 2. Scope & north-star reconciliation

**v1 scope (session decisions, 2026-07-09):**

- SwiftUI native clients only; a browser/WASM channel is deferred (§9).
- Framework-first; the Harbor-graph fixtures (Pier/Dock/Berth) carry the proof. No consumer
  app gates the arc.
- Single server process; the in-memory hub is the seam a multi-instance fan-out plugs into
  later (§9).
- The SSE stream authenticates via `ClientCredentialProvider.credentialHeaders()` at
  stream-open (`Sources/FOSMVVM/Protocols/ClientCredentialProvider.swift`).
- One spec (this document); the implementation plan stages the work.

**Where the north star §5 drifted from shipped L1 — reconciled here:**

1. **Pass #2 is shipped.** §5's "Emit — two altitudes" second altitude (post-write refresh to
   the caller) landed with C8/C8a: the write doors commit, invalidate
   (`invalidateWrittenContainers`, `Sources/FOSMVVMVapor/Containment/WriteRoute.swift:183`),
   and re-serve through the read pipeline. **L2 is pass #1 only.**
2. **`RefreshRequest` no longer exists** (removed by the factory generalization). Any §5-era
   text referencing it re-roots on the shipped write doors and
   `ResponseBodyFactory` (`Sources/FOSMVVM/Protocols/ResponseBodyFactory.swift:38`).
3. **The type registry exists** (C4 migration-as-registration, `ModelNamespace →
   RegisteredModel`) — L2's emit middleware and identity-set derivation ride it.
4. **The client invalidation seam is richer than §5 assumed**: `invalidateBinding(_:)` /
   `viewModelInvalidated` (teardown) and `viewModelRefreshed` (in-place swap) both exist in
   `VMServerResolverView` (`Sources/FOSMVVM/SwiftUI Support/ViewModelView.swift:397`), untested.
   L2 replaces the *internals* with per-registration dispatch, keeps `invalidateBinding(_:)` as
   the manual escape hatch, and brings both seams under test (the §5 hardening obligation).

## 3. Contract

### 3.1 Server emit — one altitude, one broadcast point

**A per-type Fluent `ModelMiddleware` is the only emit point.** The write doors do not emit:
every door write is itself a Fluent save the middleware sees, and writes that bypass the doors
(app code, background jobs) are equally covered — no write silently fails to notify.

- **Boot wiring piggybacks C4.** `Application.useLiveInvalidation(on:)` (§4) enables the layer:
  it sweeps the existing type registry and registers emit middleware for every registered model,
  and sets the flag so later `app.register(type, migration:)` calls do the same. Either
  call order works. The hub is **injected into each middleware at registration** — the north
  star's hard rule; nothing is ever attached to `Database`.
- **The hub** (internal actor, FOSMVVMVapor) receives `emit(Set<ModelIdentity>)` and fans out
  to every connected SSE client (DEF-1: no per-client filtering). It is the seam behind which
  multi-instance fan-out plugs in later.
- **The identity set is derived, zero author code (D-L2-2).** For a mutated record: its own
  `ModelIdentity` **plus the identities of the containers it belongs to**, derived by inverting
  the C4 containment declarations — the registry knows `Dock` declared
  `.children(\Dock.$berths)`; the middleware on `Berth` reads the owning `Dock` id off the
  instance through the relation's parent key (feasibility verified:
  `ChildrenProperty.parentKey` is public, `fluent-kit/Sources/FluentKit/Properties/
  Children.swift:16`; C4's own code walks it at `Children.swift:203`). `.parent` relations are
  read directly; `.siblings` membership is covered by the registered pivot model's own parents.
  A model no container declares emits only its own identity. Saving a Berth of Dock X therefore
  emits `{ModelIdentity(Berth, b), ModelIdentity(Dock, X)}` — field change, membership change,
  and grant change all land on the container identity the north star's worked example requires.
- **Post-commit discipline (D-L2-1).** `Database.inTransaction`
  (`fluent-kit/Sources/FluentKit/Database/Database.swift:20`) splits the world:
  - `inTransaction == false` — every shipped door write (auto-commit single saves,
    `WriteRoute.swift:83`): middleware completion *is* post-commit → **emit immediately**.
  - `inTransaction == true` — app-side `database.transaction { }`: Fluent exposes no commit
    hook, and an early emit is not a wasted fetch but a **stale-forever** hazard (the nudged
    client re-fetches pre-commit state and no second nudge ever comes). The middleware
    **suppresses** the emit and logs one warning naming the model type. The sanctioned path is
    `Request.liveTransaction { db in … }` / `Application.liveTransaction { db in … }` (§4),
    which collects the identity sets produced inside the closure and flushes them to the hub
    **only after the transaction commits**; a throw/rollback discards them. The wrapper hangs
    on `Request`/`Application` because that is where the hub lives — never on `Database`.
  - **The discriminator is a Swift task-local (pinned here — it brushes the no-`Database`
    rule).** Both a bare `db.transaction { }` and a `liveTransaction { }` run with
    `inTransaction == true`, yet the middleware must suppress in the first and collect in the
    second — and a `ModelMiddleware` sees only the `Database`. `liveTransaction` installs a
    **task-local collector** for the closure's duration; the middleware routes in order:
    task-local collector present → **collect**; else `inTransaction` → **suppress + warn**;
    else → **emit**. Task-locals flow with structured concurrency — ambient to the transaction's
    task tree, attached to nothing, invisible in any API — honoring the north star's rule.
  - **Binding site (spike-verified 2026-07-09):** the wrapper binds the collector **inside the
    closure it hands `db.transaction`**, not around the transaction call. FluentKit's async
    `transaction` bridges through an *unstructured* Task
    (`fluent-kit/Sources/FluentKit/Concurrency/Database+Concurrency.swift:26`,
    `eventLoop.makeFutureWithTask`), so an outer binding never reaches the middleware; bound
    inside the closure, save→middleware propagation holds (both placements spike-tested — outer
    fails, inner passes). Same mechanism, same contract; the discriminator's semantics are
    unchanged.
- **Accepted overlap:** the writing client receives pass #2's fresh response *and* its own
  broadcast nudge → one redundant re-fetch, absorbed by the freshness gate. DEF-1's later
  per-client filtering removes it.

### 3.2 Wire nudge + SSE transport

**Payload.** One SSE event per emit; the `data:` line is the emitted identity set — a JSON array
of `ModelIdentity` in L0's frozen `Codable` form, produced by `JSONEncoder.defaultEncoder` and
consumed by `JSONDecoder.defaultDecoder` (never a raw `JSONDecoder()` — the PL-5 lesson). No VM
data, no event names, **no SSE `id:` field**: v1 deliberately opts out of `Last-Event-ID` replay
because the missed-nudge story is reconnect ⇒ sweep (below), which makes server-side replay
memory unnecessary.

**Server endpoint (FOSMVVMVapor).** One `GET` route streaming `text/event-stream`, fed from the
hub. It is *not* a `ServerRequest` — it returns no `ResponseBody`; it is infrastructure, like
the resource routes. `useLiveInvalidation(on:)` mounts it on the passed `RoutesBuilder` so apps
hang it on their auth-middleware group (the C8a/PL-4 pattern: middleware-only groups, no
parallel auth door).

- **Heartbeat:** periodic SSE comment lines (`:` keep-alive) so intermediaries don't cut idle
  streams and dead clients are detected. Transport hygiene; no API surface.
- **Slow-client policy:** each client stream has a bounded buffer; on overflow the server
  **closes that stream**. Correctness is preserved by the reconnect sweep — no nudge is ever
  silently dropped on an open, healthy stream.

**Client channel (FOSMVVM).** The DIP seam, exactly as the north star locked it:
`MVVMEnvironment.invalidationChannel: (any InvalidationChannel)?` — `nil` synthesizes the
default SSE channel (the sanctioned single-injected-dependency existential). The URL derives
the way resources already do (`MVVMEnvironment.swift:81`, `resourcesBaseURL ?? serverBaseURL`):
a `invalidationBaseURL: URL? = nil` sibling on the URL package; the common case configures
nothing.

- **Consumption:** `URLSession.bytes`, line-parsed `text/event-stream`.
- **Auth:** `ClientCredentialProvider.credentialHeaders()` attaches at stream-open. Mid-stream
  credential rotation self-heals: the stream drops → reconnect re-consults the provider.
- **Lifecycle:** the channel opens on the **first** dispatcher registration (an app with no
  `.live` screens never opens a socket) and stays open for the app's foreground lifetime.
- **Reconnect — the correctness cornerstone:** on every (re)connect after a drop, the channel
  signals `connected` and the dispatcher fires **all current registrations** as if nudged. One
  refresh sweep covers whatever was missed while disconnected; the freshness gate absorbs the
  redundancy. This single rule is why the server keeps no replay buffer, no `Last-Event-ID`,
  no per-client memory.

**Reversibility (restated):** none of this surfaces in ViewModel/View API — swapping SSE for a
WebSocket or long-poll later is a channel-internal change.

### 3.3 Client dispatcher + freshness gate

**The dispatcher** is one `@MainActor` object owned by `MVVMEnvironment`, created with the
channel, internal. Two registration tiers (north star two-granularity):

- exact — `[ModelIdentity: registrations]`
- namespace — `[ModelNamespace: registrations]` (unbounded screens only, DEF-3)

A **registration** is a token pairing one bound view with a re-fetch trigger. An incoming nudge
fires exact matches plus namespace matches (every `ModelIdentity` carries its namespace
component). The token's death (view disappears) unregisters. The reconnect sweep fires every
registration.

*Honesty note for review:* every shipped plan root kind (query-rooted, `.apex`) resolves to an
**exact** identity, so the derived registration header (§3.4) may never carry a bare
`ModelNamespace` in v1 — the namespace tier ships (it is small and the north star locked the
design) but may sit dormant until a namespace-scoped plan kind exists. DEF-3 anticipated this
("designed-for; only unbounded containers use it").

**Nudge-triggered refresh is an in-place swap, never a teardown.** A live screen must not flash
a `ProgressView` on every remote mutation. The trigger re-fetches through the normal pipeline
and swaps the VM the way the shipped `viewModelRefreshed` path already does
(`ViewModelView.swift:432`); the current VM stays visible until its replacement arrives.
`invalidateBinding(_:)` (`Sources/FOSMVVM/SwiftUI Support/View.swift:84`) keeps its teardown
semantics as the manual escape hatch, unchanged.

**The freshness gate** guards the swap point in the resolver: an arriving VM replaces the
current one **only if `incoming.vmId.freshness > current.vmId.freshness`**; an older response
racing a newer one is dropped silently. The clock is L0's shipped
`ViewModelId.Freshness` (`Sources/FOSMVVM/Protocols/ViewModelId.swift:143` — `Comparable`,
birth-moment preserved across the wire, unforgeable internal `init`).

**Freshness producer — deliberately unchanged.** The north star anticipated L2 might need to
broaden `Freshness.init` access for a server-side producer. It does not: every served VM stamps
`freshness = .now` at construction (`ViewModelId()`) during server projection, which *is* the
version's birth moment. L2 adds only the consumer (the gate); no access broadening, no
`package`/`@_spi` seam — a plan author should not re-open this.

**Gate scoping (new, explicit):** the gate applies only to **same-request refreshes** —
nudge-triggered re-fetches and pushed refreshes. A `query`/`fragment` change is navigation
(different data, incomparable freshness) and bypasses the gate; today's `onChange(of: query)`
path stays gate-free.

### 3.4 `.live` delivery — the macro and the registration set

**The registration set is server-derived from the executed plan (D-L2-3).** Every served
response executed a `RecordLoadPlan`; its resolved roots plus touched containers are precisely
the response's staleness surface — the *same set shape* the write path computes for cache
invalidation (`WriteRoute.swift:183-193`). The read path derives it from its **own**
`ResolvedRecordLoadPlan` (net-new derivation mirroring that shape — `invalidateWrittenContainers`
itself is write-path code, not directly reusable). The executor **deposits the set in
`Request.storage`** — the same request-scoped mechanism the container-record cache already
rides — and the centralized `buildResponse` reads it there and attaches it as a **header
(D-L2-4)**, beside the existing version header (`SystemVersion.httpHeader = "X-FOS-Version"`,
`Sources/FOSMVVM/Versioning/SystemVersion.swift:31`). That deposit-and-read pair is the single
new integration point on the shared serve surface. VM `Codable` shapes and version baselines
stay byte-identical; only the bind resolver reads the header.

- Zero author code; exact by construction; immune to drift.
- **Each refresh re-registers the latest response's set** — a screen whose plan touched new
  containers starts listening to them automatically.
- A rooted plan yields exact identities; an unbounded plan would yield its `ModelNamespace`
  (see the §3.3 honesty note).
- The header is attached to every served response (the server does not know which clients are
  live; the set is already in hand at serve time, the cost is bytes).

**`@ViewModel(options: [.live])` synthesizes a marker conformance** — `LiveViewModel` — and
nothing else. `ViewModelOptions` extends as built
(`Sources/FOSMacros/ViewModelMacro.swift:48`, one case today). The resolver gains a live-aware
path when `VM: LiveViewModel`:

- on each arriving response: register its header set with the dispatcher (replacing the prior
  registration), swap through the freshness gate;
- on disappear: the registration token dies → unregistered;
- no channel configured / stream down: degrades to today's fetch-once-on-appear — shipping a
  screen non-live and adding `.live` later is purely additive (north star promise).

**v1 constraint:** `.live` is server-hosted binding only. `.live` + `.clientHostedFactory` on
one VM is a **macro diagnostic error** (a client-hosted VM has no server response to derive
registrations from). Lifting it later is additive (§9).

## 4. Public surface (signature-normative)

Everything not listed here is `internal`: the dispatcher, the hub, the emit middleware, SSE
framing/parsing, the registration token.

```swift
// ── FOSMacros ───────────────────────────────────────────────────────────────
private enum ViewModelOptions: String {
    case clientHostedFactory
    case live                    // NEW — synthesizes LiveViewModel conformance;
}                                // combined with .clientHostedFactory ⇒ diagnostic error

// ── FOSMVVM ─────────────────────────────────────────────────────────────────
/// Marker adopted via `@ViewModel(options: [.live])`; the bind resolver
/// registers/refreshes such ViewModels through the invalidation dispatcher.
public protocol LiveViewModel: RequestableViewModel {}

/// One event from the server's invalidation stream.
public enum InvalidationEvent: Sendable {
    case connected                        // (re)connected — the dispatcher sweeps
    case invalidated(Set<ModelIdentity>)  // one server emit
}

/// The transport seam (DIP). `nil` on MVVMEnvironment ⇒ the default SSE channel.
public protocol InvalidationChannel: Sendable {
    func events() -> AsyncStream<InvalidationEvent>
}

// MVVMEnvironment additions (mirroring the resourcesBaseURL idiom):
//   invalidationChannel: (any InvalidationChannel)? = nil
//   URL package: invalidationBaseURL: URL? = nil   // nil ⇒ serverBaseURL

// ── FOSMVVMVapor ────────────────────────────────────────────────────────────
public extension Vapor.Application {
    /// Enables live invalidation: mounts the SSE endpoint on `routes` (hang it on
    /// your auth-middleware group) and registers the emit middleware for every
    /// registered container model — past and future registrations alike.
    func useLiveInvalidation(on routes: any RoutesBuilder) throws
}

public extension Vapor.Request {
    /// A Fluent transaction whose committed writes still nudge live clients:
    /// identity sets produced inside the closure flush to the hub on commit and
    /// are discarded on rollback. The sanctioned replacement for
    /// `db.transaction { }` in live applications.
    func liveTransaction<T: Sendable>(
        _ closure: @Sendable @escaping (any Database) async throws -> T
    ) async throws -> T
}
// + the same wrapper on Vapor.Application (background jobs).
```

## 5. Naming

| Concept | Name | Rooting / legibility |
|---|---|---|
| macro option | `.live` | locked by north star; joins `clientHostedFactory` |
| marker protocol | `LiveViewModel` | `RequestableViewModel`/`ViewModelView` family; leading "Live…" shape distinct from every "ViewModel…" symbol |
| channel protocol | `InvalidationChannel` | shipped invalidation family (`invalidateBinding`, `viewModelInvalidated`, `invalidateContainerRecords`) |
| channel event | `InvalidationEvent` | same family |
| env seam | `invalidationChannel` / `invalidationBaseURL` | mirrors `resourcesBaseURL ?? serverBaseURL` idiom |
| boot call | `useLiveInvalidation(on:)` | C8 `use` family (`useAppState`, `useApexContainerResolver`) |
| tx wrapper | `liveTransaction { }` | distinct leading shape from Fluent's `transaction` |

Rejected: `LiveRequestable` (authors face VMs, not requests); `LiveChannel` (names the feature,
not the event); `invalidatingTransaction` (long confusable middle against
`invalidateContainerRecords`).

## 6. Wire contracts (frozen pre-1.0, like L0's `fsh`)

- **Registration header:** `X-FOS-Registrations` — value: the derived identity set, JSON array
  of `ModelIdentity` (L0 frozen encoding) via `JSONEncoder.defaultEncoder`. Joins
  `X-FOS-Version` in `buildResponse`. Consumers treat it as opaque; the resolver is the only
  reader.
- **SSE endpoint:** `GET <group>/invalidations`, `Content-Type: text/event-stream`; events are
  `data:`-only (JSON array of `ModelIdentity`); comment-line heartbeats; no `id:`/`event:`
  fields in v1.
- **Nudge payload:** the identity set only — never VM data, never a rendered fragment.

## 7. Decisions

| ID | Decision |
|---|---|
| D-L2-1 | In-transaction emits are **suppressed** (one warning); the sanctioned `liveTransaction` wrapper collects and flushes on commit. Rejected: emit-on-operation (stale-forever race, violates north star); `Database` decorator buffering (the prior-art regret the north star forbids). |
| D-L2-2 | Invalidation identity sets are **derived from C4 containment** — zero author code, no drift. A declared override is deferred until a consumer needs one. |
| D-L2-3 | A `.live` screen's registration set is **server-derived from the executed plan** and re-registered on every refresh. Rejected: client-declared (author obligation + drift); hybrid (no consumer yet). |
| D-L2-4 | The set travels as a **response header** (`X-FOS-Registrations`) beside the version header. Rejected: a field on the encoded VM (baseline churn; response-scoped metadata inside model data). |
| scope | SwiftUI-only v1 · framework-first · single server process · one spec · SSE auth via `ClientCredentialProvider` · `.live`+`.clientHostedFactory` = diagnostic. |

## 8. Test groups

1. **Emit / auto-commit** — a door write emits post-save; the set matches the fixtures (Berth
   save ⇒ {Berth, owning Dock}); delete and create emit membership changes on the container.
2. **Emit / transactions** — in-transaction save emits nothing + warns once; `liveTransaction`
   flushes on commit; a thrown/rolled-back `liveTransaction` emits nothing.
3. **Derivation** — `.parent`/`.children` inversion against the Harbor graph; pivot-model saves
   cover `.siblings`; an uncontained model emits only itself.
4. **Hub + SSE endpoint** — connected stream receives framed events; heartbeat lines flow;
   buffer overflow closes the stream. (Plan-level: long-lived streams may exceed
   `app.test(...)`; mind the async-boot gotcha — `app.asyncBoot()` for lifecycle handlers.)
5. **Registration header** — served responses carry the executed plan's set; write-door
   refreshes carry the refreshed set; the header round-trips through
   `defaultEncoder`/`defaultDecoder`.
6. **Client channel** — event-stream parsing; `connected` on (re)open; credential headers
   attach at open; reconnect back-off.
7. **Dispatcher** — exact and namespace matching; token death unregisters; re-registration
   replaces; reconnect sweep fires all.
8. **Freshness gate** — older-drops / newer-swaps; navigation (`query`/`fragment` change)
   bypasses; the redundant self-nudge after a write is absorbed.
9. **Delivery** — `.live` expansion fixture (XCTest, macro rule);
   `.live`+`.clientHostedFactory` diagnostic; degraded no-channel behavior = fetch-once.
10. **Seam hardening** — first tests for the shipped `viewModelInvalidated` teardown and
    `viewModelRefreshed` in-place swap.

## 9. Deferred

- **DEF-1..3** (north star §10) stand: no server-side subscription filtering; no subtree
  matching; namespace matching only for unbounded screens.
- **DEF-L2-4 — multi-instance fan-out.** The hub is single-process; a cross-instance
  propagation backend (e.g. a pub/sub bridge) plugs in behind `emit`.
- **DEF-L2-5 — browser/WASM channel.** An `EventSource` consumer for Leaf/React/WASM clients;
  the wire contract (§6) is already sufficient.
- **DEF-L2-6 — `.live` for client-hosted ViewModels.** Requires a client-side registration
  source; the diagnostic keeps the door closed, lifting it is additive.
- **DEF-L2-7 — declared identity-set override** (from D-L2-2) and **author-added
  registrations** (from D-L2-3), each waiting on a real consumer.

## 10. Build order (plan handoff)

Server emit (middleware + hub + wrapper) → transport (endpoint + client channel) → dispatcher +
gate → delivery (macro + resolver + header). Plan via the `fosmvvm-planning` gate
(design-first / DocC-first), then `superpowers:writing-plans`; subagent-driven TDD per L1
practice. Suite baseline entering L2: green on `main` + `client-credential-provider`.

## 11. Review reconciliation (2026-07-09)

Both reviewers approved on the first pass; four advisories were folded in:

1. **`liveTransaction` discriminator pinned** (spec-document reviewer) — the middleware's
   collect-vs-suppress routing is a **task-local collector** installed by the wrapper
   (§3.1); pinned in the spec, not left to the plan, because it brushes the north star's
   no-`Database`-attachment rule.
2. **Freshness producer non-change made explicit** (discipline reviewer) — L2 uses
   construction-now stamping; the anticipated access-broadening is deliberately not needed
   (§3.3).
3. **`buildResponse` deposit seam named** (discipline reviewer) — the executor deposits the
   registration set in `Request.storage`; `buildResponse` reads it there. The read path derives
   its own set from its `ResolvedRecordLoadPlan`; `invalidateWrittenContainers` is write-path
   code, not directly reusable (§3.4).
4. **Citation anchors corrected** — `Freshness` at `ViewModelId.swift:143`.

Standing (disclosed, not defects): the credential-branch merge precondition (header block);
the possibly-dormant namespace tier (§3.3 honesty note).

## 12. Implementation reconciliation (2026-07-09)

What implementation refined against the contract above. Each item is a clarification, not a
change of decision.

- **§3.1 — middleware coverage is the registered GRAPH.** `useLiveInvalidation` wires an emit
  middleware for each registered container's whole graph — the container itself, every contained
  type, and every `.siblings` pivot — deduped by `ObjectIdentifier` so a type reachable through
  several descriptors gets exactly one middleware (`Application+LiveInvalidation.swift`
  `registerInvalidationEmitMiddleware`). This is required by the Berth contract: FluentKit
  type-filters `ModelMiddleware` per concrete model, so each covered type needs its own instance,
  and an *erased* middleware would sever the task-local the collect-vs-suppress routing rides
  (the T3 binding-site finding; reviewer-ruled sound).
- **§3.1 — binding-site amendment already in-spec.** The "bind the collector inside the closure
  `db.transaction` runs, not around the call" refinement (commit a2b008f) is folded into §3.1's
  "Binding site" bullet — cross-reference only, no new text.
- **§3.2 / §6 — the SSE `: open` comment preamble.** The stream opens with one SSE comment line
  because Vapor flushes response headers only with the first body byte; the preamble forces the
  header flush (and the client's `.connected`) at open rather than at first nudge. Ruled within
  the frozen §6 contract — comments are not events (no `data:`, no `id:`/`event:`), so no
  representation was pinned that a consumer could parse.
- **§3.4 — supplemental-hook-only containers are outside v1.** The deposited registration set is
  derived from the executed plan's tuples only; a container touched *solely* by a
  `SupplementalRecordLoading` hook is outside the v1 registration surface (mirrors the internal
  note at `PlanExecutor.swift` `depositRegistrationSet`). A screen depending on such a container
  self-heals on the next `.connected` sweep; a declared override (DEF-L2-7) covers it when a
  consumer needs it.
- **§4 — exactly one `package` symbol.** The whole layer added a single `package` declaration:
  `DataFetch.send(…capturingResponseHeader:)` (FOSFoundation), so FOSMVVM's live resolver can read
  `X-FOS-Registrations` off the very fetch that produced the ViewModel — the why-required
  statement lives at the declaration (`DataFetch.swift`). Everything else held `internal`; zero
  `package` in FOSMVVMVapor.
- **§3.4 — failed refreshes preserve the prior registration set.** A failed re-fetch returns
  `(nil, [])`; the resolver's guard covers both the swap and the re-registration, so the screen
  keeps its stale data AND keeps listening with the prior set. `[]` re-registers (deafening the
  screen until the next sweep) only on a genuinely-empty *successful* response — never on the
  error path (`VMServerResolverView.refreshInPlace`).
- **§3.2 — `.connected` fires on the FIRST open, not only on re-opens after a drop.** The channel
  emits `.connected` at the initial connection as well, deliberately: it closes the serve→subscribe
  race window (a nudge emitted between a screen's first serve and its subscription would otherwise be
  lost), because the initial `.connected` sweep re-fetches every current registration. The cost is one
  extra gated fetch at first appearance, which the freshness gate absorbs as redundant.
