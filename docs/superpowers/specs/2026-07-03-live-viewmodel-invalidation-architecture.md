# Live ViewModel Invalidation — Architecture (North Star)

**Status:** Design / reconciliation. Not yet implemented.
**Date:** 2026-07-03
**Author:** David Hunt (design), with Claude (reconciliation)
**Scope:** FOSFoundation, FOSMVVM, FOSMVVMVapor, FOSMacros
**Related:** Port-Authority `fosutilities-improvements.md` "three architecture design passes" (this subsumes pass #1 *live `.bind()`* and pass #2 *server-hosted `ViewModelOperations` refresh-after-write*).

> This is the **Architecture-is-Truth** artifact for the whole effort. It captures the full
> vision and the decisions locked during design so the three layer-specs share one context.
> Implementation proceeds **layer by layer** (0 → 1 → 2); each layer gets its own detailed
> spec → plan → implementation cycle. Layer 0's spec is
> `2026-07-03-model-identity-foundation-design.md`.

---

## 1. Problem

FOSMVVM is request/response only. Screens that must stay current (collections, dashboards,
anything another actor can mutate) have no mechanism to refresh when server state changes —
the client only learns of a change by re-issuing a request it has no reason to re-issue.

Two *kinds* of change must be handled, and conflating them is the classic mistake:

1. **Item change** — a single data record's fields mutate (e.g. `Dock #5.status`).
2. **Container / projection change** — the *membership or ordering* of a collection changes:
   a record is inserted/deleted, an authorization is granted/revoked, or an existing record
   crosses a filter/sort boundary so it enters, leaves, or reorders within a projection. **No
   single item identity captures this** — it is a property of the *container's data projection*
   (its filter + sort + authorization over a population).

The design must serve **both axes with one identity primitive and one emit**, and must be
**invisible to the ViewModel author** — they opt a ViewModel into `.live` and bind a view; they
never see transport, subscriptions, dispatch, or reconnection.

## 2. This is a refinement, not an invention

The container / record / authorization / load model is not novel — it distills a **proven,
production-tested** pattern for authorized, filtered, sorted collection loading behind an MVVM
projection. FOSUtilities' contribution is to re-root it on stronger foundations: a **sealed, opaque
identity** primitive, end-to-end type-safety (no stringly-typed keys), clean SPMLibraries/DIP
boundaries, and dependency injection in place of global singletons. §7 maps the established concepts
onto the FOSUtilities types.

## 3. The identity primitive (Layer 0)

One value type roots the entire system; it does **triple duty** — wire routing, **persistence**,
and **authorization** — which is why it must be sealed, `Codable`, and value-comparable.

```swift
// Opaque namespace token — vends only the needed semantics, never a String surface.
// NO public String construction (no ExpressibleByStringLiteral); only a Type goes in.
public struct ModelNamespace: Hashable, Codable, Sendable {
    private let value: String                    // sealed — no public getter, no public String init
    public init(for type: Any.Type) { value = String(reflecting: type) }
    // Codable is single-value (encodes as a bare "User"); init(from:) is the only string→ns path.
}

// Opaque, sealed, NON-generic identity. Hashable/Codable/Sendable only — no value getters.
public struct ModelIdentity: Hashable, Codable, Sendable {
    private let namespace: ModelNamespace
    private let id: String                        // canonical form of Model.id; sealed
    // No public init from raw strings; only a Model can mint one.
}
public extension ModelIdentity {
    // Convenience comparability to a Model (filtering sugar; NOT Equatable conformance).
    static func == (lhs: ModelIdentity, rhs: some Model) -> Bool {
        (try? lhs == rhs.modelIdentity) ?? false
    }
}

// Model declares its namespace (requirement + reflection default → override via marker type).
public protocol Model {
    // ...existing (id, requireId(), ...)... — NOTE: the dormant `modelType: String` is REMOVED
    static var modelIdentityNamespace: ModelNamespace { get }
}
public extension Model {
    static var modelIdentityNamespace: ModelNamespace { .init(for: Self.self) }
    var modelIdentity: ModelIdentity {
        get throws { try .init(namespace: Self.modelIdentityNamespace, id: requireId()) }
    }
}

// Opt-in: a ViewModel whose identity is rooted in a stable data-model identity.
public protocol ModelIdentifiedViewModel: ViewModel {
    var modelIdentity: ModelIdentity { get }
}

// vmId derives from modelIdentity — single source of truth, owner-scoped on ModelIdentity
// (no ViewModelId.init(modelIdentity:); it vends a ViewModelId, never the raw token string).
public extension ModelIdentity {
    var viewModelId: ViewModelId { /* derive the rendering identity from the sealed identity */ }
}
```

**Locked decisions & rationale:**

- **Sealed / opaque, no value getters.** An exposed `String` is an attractive nuisance — it
  *will* be parsed, routed on, or used to reconstruct a type, and that abuse lands far from
  here. The value is minted only from a typed `Model`; it is never read back out on the client.
- **Non-generic.** The dispatcher must hold identities from many ViewModel types in one uniform
  `[ModelIdentity: Set<Registration>]` map. A `ModelIdentity<ID>` would fragment that or force
  `AnyHashable`/existential. `ModelIdType == UUID` universally, so a generic buys nothing.
- **`Model` declares the namespace** (requirement + `String(reflecting:)` default). Reflection is
  the zero-config default; a Model that wants refactor-stability overrides by anchoring to a **stable
  marker type** (`.init(for: UserIdentity.self)`) — **no** `ExpressibleByStringLiteral`, so there is
  no public String construction path anywhere (a Type goes in, never a String). The
  requirement-plus-default pairing is what makes the override real (extension-only would merely
  shadow). The existing dormant `Model.modelType: String` is **removed** (David's call).
- **Opt-in `ModelIdentifiedViewModel`.** Singleton/ephemeral ViewModels keep just `vmId`. ISP-clean,
  additive, mirrors how `ClientHostedViewModelFactory` is already opt-in. `.live` requires it.
- **Identity is persisted.** Identity values are stored in DB columns (e.g. an authorization record
  stores a reference to the container it authorizes). So `ModelIdentity`'s `Codable` form is a
  **persistence format** and needs the same version-stability discipline as other versioned
  FOSMVVM wire types.
- **Identity is the shared auth primitive.** An authorization test is **container-identity
  equality** — the requested container reference compared to the one the authorization grants — but it
  is *applied while scoping the load* (§4: authorize by data-scoping, never by guarding a route), not
  as a route guard. The same `ModelIdentity` that routes a nudge also gates a permission — hence
  `Hashable`/`Equatable`/`== some Model` are load-bearing, not sugar.

## 4. The container system (Layer 1)

A **container** is "a record that owns/contains other records"; its contents are a **data
projection** = filter + sort + authorization over a population.

- `Container: Model` with `static var containedRecordTypes: [Model.Type]`.
- **`ContainerCardinality`** (`.toOne(keyName, fk)` / `.toMany(keyName, fk, pivotSchema)`) —
  Fluent-coupled, so it lives in **FOSMVVMVapor**, never on the shared `Model` (crossing the
  persistence type across the SPMLibraries boundary is an LSP/DIP violation).
- **`ContainerOperation`** (`readRecords`/`writeRecords`/`createRecords`/`deleteRecords`/
  `destroyRecords`/`anyOperation`) — the **security boundary**. Authorization is expressed as
  "User X may {operation} the records in Container Y," enforced via `authorizesXXX` helpers (never
  raw enum comparison — OCP). Access control is container-scoped identity equality.
- **Authorization by data-scoping, not route-guarding** (a foundational discipline, and this repo's
  own rule — "ViewModels are middleware-gated, never string-route-grouped"). Routes are gated only
  by *authentication*; fine-grained *authorization* is enforced by **what data the load engine will
  attach** for the requested `ContainerOperation`. A brute-forced request that isn't authorized
  simply loads nothing — an empty projection, or a write with no target to act on. This is why auth
  lives in the load engine, not in route guards, and it is impossible to "forget" on a new endpoint.
- **Server load engine:** auth-filtered, filtered, sorted, eager-loaded, request-scoped-cached load
  of a container's records. **Filter, sort, and pagination live in the `Request.Query`.** Sort by
  **KeyPath**, not string columns (string-column sorting is a known wart — ambiguous columns, no
  type-safety — to avoid). Keep the proven lessons: cardinality drives the SQL; re-sort results to
  the relationship's id order; a `maxRecordsWarningThreshold` guardrail.
- **Unified server-hosted container factory.** Prior designs split *load* from *projection* across
  two separate protocols, which proved awkward to keep in sync. On these roots they collapse into
  one server-hosted container factory (the server analogue of `ClientHostedViewModelFactory`)
  declaring contained type(s), filter/sort (from query), auth operation, and projection in one place.
- **Server type registry** (`ModelNamespace → Model.Type`): needed because the server must map an
  incoming namespace back to a queryable type — which the sealed client identity deliberately
  cannot. **Injected, not global** (a global type registry is a known anti-pattern — it defeats
  parallel-test isolation and leaks shared state; inject the registry into the Vapor
  `Application`/`Request` context instead). **Populated as a side-effect of migration/Model
  registration at boot** — declaring the migration *is* the registration, so there is no drift and
  no forgot-to-register failure mode. Server-only; never linked into the client.

## 5. Live invalidation (Layer 2)

**Prior art.** Server-driven invalidation is itself proven: an earlier production system tagged
render regions with scope ids and pushed `(scope-id + new HTML)` to clients over a socket, swapping
just that node — a hand-rolled server-driven reactive UI. Our design keeps the *idea* (server names
what changed; the client refreshes that scope) and refines it in two ways: (1) we push an **identity
nudge, not rendered content**, so the client refreshes through the normal fetch→localize→project
pipeline (the "transport the invariant, resolve at the edges" discipline), and (2) we use **SSE**
where the prior art used a WebSocket — that push was one-directional anyway, and our payload is a
tiny one-way nudge, so the lighter transport is the exact fit. Both refinements sit behind the seam,
so either is reversible.

**Transport — SSE, invisible, reversible.**
- The nudge is strictly server→client and tiny (a `ModelIdentity`, never VM data). SSE = one
  long-lived HTTP `GET` per client streaming `text/event-stream`; client consumes via
  `URLSession.bytes`. No upgrade handshake, rides existing headers/auth/session. WebSocket's
  duplex is unused for a nudge; polling wastes requests. Because it never surfaces in any
  ViewModel/View API, the choice is **fully reversible** behind the seam.
- **Default derives from existing config.** `URLPackage` gains `invalidationBaseURL: URL? = nil`
  defaulting to `serverBaseURL` (exact mirror of the existing `resourcesBaseURL ?? serverBaseURL`
  idiom). Common case: configure nothing.
- **Override seam.** `MVVMEnvironment.invalidationChannel: (any InvalidationChannel)?` — `nil` ⇒
  synthesized default SSE channel over `invalidationBaseURL`. The `any` existential here is the
  **sanctioned** DIP kind (a single injected dependency), not an existential-as-data smell.

**Client dispatcher.**
- One object (owned by `MVVMEnvironment`/an actor it holds) consuming the channel's
  `AsyncStream<ModelIdentity>` and holding `[ModelIdentity: Set<Registration>]`, where a
  `Registration` bumps *one* bound view's re-fetch trigger.
- **Two-granularity match** from a *single* emit:
  - **exact `ModelIdentity`** → item views and container views rooted at a parent id
    (e.g. "the berths of Dock X" registers `ModelIdentity(Dock, X)`);
  - **`ModelNamespace`** → *unbounded* container views over a whole population
    ("all Docks" registers `ModelNamespace(Dock)`).
- Refines the existing seam: today `viewModelInvalidated` is one global `Binding<Bool>` honored
  only by `VMServerResolverView`; the dispatcher replaces it with per-registration, identity-keyed
  callbacks. `.invalidateBinding($bool)` stays as the manual escape hatch.
- **Monotonic freshness gate.** A nudge-triggered re-fetch can race a newer push or a second nudge,
  so an *older* response must never overwrite a newer one. The gate drops stale writes by comparing
  `ViewModelId.freshness` (`if incoming.freshness <= existing.freshness → drop`) — a dedicated opaque
  **nested** `ViewModelId.Freshness` (`Comparable`) value (a **GMT `Date`** = the version's *birth
  moment*) **Layer 0 adds**,
  orthogonal to identity (`ViewModelId` stays `id`-only for `==`/`hash`/`.id()` and is deliberately
  *not* `Comparable`, avoiding a total-order-law violation). The birth moment is *preserved* across the
  wire (decode never re-stamps to the client's now), so ordering is by birth, not arrival. Layer 0
  delivers the orderable type **and** the durable wire form (`freshness` always encoded under the short
  key `fsh`, canonical GMT; frozen now, pre-1.0; excluded from version-baseline comparison). **Layer 2**
  adds only the *producer* (server
  assigns the birth moment) and the *consumer* (the gate) — no format change.

**Emit — two altitudes.**
- **`ModelMiddleware` (DB lifecycle)** — the robust broadcast point, using Fluent's standard
  `ModelMiddleware` lifecycle-hook pattern (the same pattern used for cross-model validation): a
  per-type `ModelMiddleware` registered at boot. Fires on **every** `create/update/delete`
  regardless of origin, so no write silently fails to notify. This carries **pass #1** (broadcast
  to all other bound clients).
- **Request handler (post-write refresh)** — re-projects and returns the fresh VM to the **caller**
  (**pass #2**). These are *different altitudes*, cleanly separated: respond-to-caller vs
  broadcast-to-all.
- **A record emits an identity *set*.** A join/relationship record (e.g. an authorization record
  holding a container reference plus parent links) mutates its own identity, but staleness lands on
  the *container it references*. So a Model declares its **invalidation identity set** = its own
  `ModelIdentity` + any container refs it links. Membership-change nudges originate here.
  **Emit only after the mutation commits — post-transaction, not post-responder.** (L2 note:
  a Fluent `ModelMiddleware` resolves when the create/update/delete *operation's* future completes,
  which is **not** necessarily after the enclosing transaction commits. Fire the nudge on commit, so
  a rolled-back write never nudges clients into re-fetching data that then disappears.)
- **Inject the channel into the middleware — do not smuggle it onto the `Database`.** A
  `ModelMiddleware` runs in the Fluent lifecycle where there is no `Request`, so the emit needs the
  invalidation channel by another route. Prior-art regret: an earlier system smuggled ambient
  context onto the `Database` via a decorator and cast it back out — fragile, test-only-verified.
  The channel must be **injected into the middleware at registration (boot)**, held as a stored
  dependency — never sideband-attached to `Database`.

**Delivery.**
- `@ViewModel(options: [.live])` macro (mirroring `.clientHostedFactory`; `ViewModelOptions` in
  `ViewModelMacro.swift` has one case today and extends cleanly) synthesizes the per-VM glue:
  resource key, the trigger the `.bind()` resolver reads, register-on-appear / unregister-on-disappear.
- Degrades to plain request/response (fetch-once-on-appear, *not* polling) when absent — shipping a screen non-live then adding
  `.live` is purely additive.
- Harden + test the existing (untested, undocumented, server-resolver-only) invalidation seam as
  part of this layer.

## 6. Registration / emit convergence (worked example)

A change inside a container emits against the **container's** identity, not the mutated leaf's.
(Illustrated with a `Dock` that contains `Berth`s plus per-dock access grants.)

- item view bound to Dock X → registers `ModelIdentity(Dock, X)`
- container view (the berths *of* Dock X) → **also** registers `ModelIdentity(Dock, X)`
- a field change to Dock X, a berth added to X, or an access grant on X → **all** emit
  `ModelIdentity(Dock, X)` → one match, three change kinds.
- "all Docks in the system" (unbounded) → registers `ModelNamespace(Dock)`; any
  `ModelIdentity(Dock, n)` emit matches by namespace component.

## 7. Established concepts → FOSUtilities reconciliation

The left column names the *established pattern* (from proven collection-loading MVVM designs); the
right column is its FOSUtilities realization.

| Established concept | FOSUtilities realization | Disposition |
|---|---|---|
| Data record / model | `FOSMVVM.Model` | exists |
| Record reference (id + type) | `ModelIdentity` | refined — sealed/opaque vs string + global registry |
| Container (owns records) + contained types | `Container: Model` + `containedRecordTypes` | add (L1) |
| Container reference (id + type) | collapse into `ModelIdentity` + `Container` conformance | refined — a container *is* a Model |
| Container cardinality (to-one/to-many + FK/pivot) | `ContainerCardinality`, **FOSMVVMVapor only** | add (L1) — Fluent-coupled |
| Container operation (read/write/create/delete/…) | container-scoped auth vocabulary | transfers (refined) |
| Authorized load middleware + request-scoped cache | server container load engine | add (L1) |
| String-column sort | KeyPath sort descriptors | refined (L1) |
| Split load / projection protocols | unified server-hosted container factory | refined (L1) |
| Post-write model refresh | request-level refresh (pass #2) | transfers (L1/L2) |
| Global type registry | injected, migration-populated `ModelNamespace → Model.Type` registry | refined (L1) — DI over global |
| Cross-model validation via `ModelMiddleware` | live-emit `ModelMiddleware` (same Fluent pattern) | new use of a standard pattern (L2) |
| Hand-declared string route base + path builder | type-derived request path | already refined in FOSMVVM |
| existing `Model.modelType: String` (`String(describing:)`, dormant/unused) | opaque `ModelNamespace` (`String(reflecting:)`) | **removed** (L0, David's call) — `modelType` deleted; `ModelNamespace` replaces it |
| Request-scoped record cache | same Vapor `Request.storage` mechanism | transfers |

## 8. Layering & sequencing

- **Layer 0 — Identity foundation** (FOSFoundation/FOSMVVM). Prerequisite for all; independently
  useful (stable VM identity + shared auth primitive). **First spec + plan.**
- **Layer 1 — Container formalization** (FOSMVVM shared + FOSMVVMVapor). Ships on L0; useful without
  live (auth-scoped server-hosted collections). Subsumes pass #2's request-level refresh.
- **Layer 2 — Live invalidation** (FOSMVVM + FOSMVVMVapor + FOSMacros). Ships on L0+L1. The doc's
  pass #1. Includes hardening/testing the existing invalidation seam.

## 9. Open questions

Both questions raised during design are now **resolved** (recorded here as an audit trail; IDs stay
stable, and new questions would continue OQ-3…). None currently open.

- **OQ-1 — Identity `Codable` versioning — RESOLVED (David).** There is **no on-the-wire versioning**
  of the identity encoding. It is frozen; a breaking change to it is governed by the **library's major
  version** (semver `Major.minor.patch`) — no per-field or `SystemVersion` negotiation.
- **OQ-2 — Freshness gate mixed-origin clock skew — RESOLVED, non-issue (David).** The gate compares
  only *ordering*, which is preserved across the wire, and a ViewModel's freshness always has a
  **single origin**: one side stamps it, and the required open wss/TCP connection guarantees the client
  talks to a single server. Future multi-server setups are NTP-close (sub-second); a few-ms "slop"
  tolerance can be added then if it's ever actually needed.

## 10. Deferred

Decided to push out of this arc or to a later layer; approach noted where already known.

- **DEF-1 — Server-side subscription awareness.** v1: the server broadcasts every relevant
  `ModelIdentity` and the client dispatcher filters. Per-client server-side subscription tracking
  (send only relevant nudges) is a scaling optimization, deferred.
- **DEF-2 — Composite subtree matching.** v1: leaf-level registration by bind boundaries (embedded
  children covered by the parent's registration). ViewModel-declared identity subtrees (finer-grained
  embedded invalidation) deferred past v1.
- **DEF-3 — Broader coarse `ModelNamespace` invalidation.** Designed-for (the type exists), but only
  *unbounded* containers use namespace-level matching in v1; broader coarse modes are additive later.
- **DEF-4 — `SystemVersion` per-contract lines.** Out of scope here — belongs to the separate design
  pass #3 (independent per-contract version lines); cross-ref only.
- **DEF-5 — Reconnection strategy (L2).** Approach decided: the simplest loop — on reconnect, re-fetch
  visible views (a nudge is disposable; a stale view is the only failure mode and a full re-fetch
  cures it). Implemented in L2.
- **DEF-6 — Freshness stamping access across the module boundary (L2).** `ViewModelId.Freshness.init()`
  is `internal` to FOSMVVM (only `ViewModelId` and tests construct it in L0). The L2 **producer** lives
  in FOSMVVMVapor and will need to assign/stamp a `Freshness` (e.g. the data's `updatedAt` rather than
  construction-now) — `internal` won't reach it. L2 broadens access via `package`/`@_spi`, or exposes
  an in-FOSMVVM stamping API the producer calls.
- **DEF-7 — Fail-fast guard for persisted-identity namespaces (L1).** L0 *guides* that any Model whose
  `modelIdentity` is persisted anchors `modelIdentityNamespace` to a stable marker type (not the
  `String(reflecting:)` default, which embeds a refactor-fragile module+type path into stored rows). L1
  introduces persistence (`Container`, stored identity columns), so it's the layer to consider
  *enforcing* that guidance — e.g. a boot/`DEBUG` assertion (piggybacking the migration-populated
  registry) that every persisted-identity Model has overridden the reflection default. Elevates a
  "must-hold-forever" convention from a doc SHOULD to a guard.
