# Layer 1 · C3 — The Authorization Provider Seam (Design Spec)

**Status:** Reviewed — spec-document + FOSMVVM-discipline reviewers (2026-07-04), no blockers; all
findings folded in (§Review reconciliation). Decisions D-C3-1/D-C3-2 **RESOLVED
(confirmed by David, 2026-07-04)**.
**Date:** 2026-07-04
**Layer:** 1, component **C3** of `2026-07-03-authorized-container-data-loading-architecture.md`.
**Targets:** FOSMVVMVapor only. (C3's shared core — `ContainerAuthorization` — already shipped with C6.)
**Depends on:** C6 (engine, shipped) + C1 (`ContainerOperation`, shipped).
**Blocks:** C8 (the factory is the first caller of the provider-driven load path).

> **The problem C3 solves** — *who supplies the grants?* C6's engine scopes every load by a set of
> `ContainerAuthorization`s, but takes them as a parameter: acquisition is the caller's problem. C3 is
> the DI seam that makes acquisition structural: the app registers **one provider** at boot ("given
> this request, here are the current subject's authorizations"), the framework fetches through it when
> first needed and memoizes for the request. For **callers of the provider-driven path**, this makes
> the cache's one-authorization-set-per-Request contract structural; the shipped `package`
> `authorizedBy:` engine entry retains only the documented contract until C8 routes all framework
> callers through the provider-driven entry (C8-audit item, §DoD). The framework still never sees a
> user, role, or grant table (arch §3: the app owns axis 2's data).

## Deviation from the arch §C3 sketch (deliberate, surfaced)

The arch sketched the provider as `authorizations(for: request, type:, operation:)` — per-(type,
operation) narrowing, marked [DIRECTION]. C3 ships **complete-set-once-per-request** instead:
per-call narrowing would re-invoke app code on every load, permitting mid-request grant drift (exactly
the axis D-C3-2 closes) and making coherent memoization impossible. The DoD updates the arch sketch
with this rationale.

## Scope (what ships)

1. **`ContainerAuthorizationProvider`** (public protocol) — associatedtype
   `Authorization: ContainerAuthorization`; one requirement:
   `func containerAuthorizations(for request: Request) async throws -> [Authorization]`.
   `Sendable` (held in `Application` storage for the process lifetime).
2. **`Application.useContainerAuthorizationProvider(_:)`** (public, throwing) — boot-time registration,
   mirroring `register(_:migration:)`'s idiom. Registering twice **throws**
   (`.duplicateAuthorizationProvider`, payload = both provider type names, diagnostic only).
3. **Internal provider-driven engine entry** —
   `Request.authorizedRecords(of:containing:for:sortedBy:pagination:)` (no `authorizedBy:`): opens the
   stored provider existential once per call (cheap — no fetch), and inside the opened **generic**
   context memoizes `[P.Authorization]` under a generic `StorageKey`, then calls the shipped generic
   engine directly. **Generics are preserved end-to-end — no existential authorization array exists
   anywhere**, and the shipped engine's "no existential arrays cross this seam" note stays fully true.
   No provider registered ⇒ throws `.noAuthorizationProvider` (a load that silently used an empty
   grant set would be indistinguishable from "unauthorized" — configuration bugs must not hide as auth
   denials; C4's silent-`[]` lesson).
4. **Two new `ContainmentError` cases** (`.duplicateAuthorizationProvider`, `.noAuthorizationProvider`)
   with diagnostic descriptions. *Access note:* these extend a **legacy-`package`** enum; the cases
   belong there, but the enum's level predates the access-minimalism rule and its recorded
   justification ("in-package tests assert the typed cases") is exactly what that rule disallows —
   `ContainmentError`'s level goes on the C8 package audit as a demotion candidate.
5. Tests (§Testing — exercising the corrected contract-vs-coverage taxonomy).

**Access-minimalism note (applied): C3 introduces ZERO new `package` symbols** (the two new enum
*cases* ride an existing package enum — flagged above, audit-listed). The two public symbols have the
app as their named consumer (it must conform and register; nothing less than `public` serves).
Everything else is `internal` — the floor for the acquisition/convenience split's cross-file consumers
(engine file ↔ registration file; `fileprivate` cannot serve them) — with all consumers same-module
(engine, then C8). No "might be public later" allowances.

## Non-goals

- **A default/concrete authorization record** — D-C3-1 (OQ-L1-2). The framework ships the abstraction
  only; the app's grant row, role model, and subject stay app-side (arch §3 boundary).
- **Public exposure of the provider-driven load** — C8 decides the public surface.
- **Multi-provider composition** — one provider per app; composition, if ever needed, lives inside the
  app's single conformance (concatenate sources there).
- **Mid-request grant re-reads / memo invalidation** — D-C3-2 (below).
- **L2** subscription authorization (rides the same provider when L2 lands — named seam, nothing more).

## Types & placement (all FOSMVVMVapor)

### C3.1 `ContainerAuthorizationProvider` (`Protocols/ContainerAuthorizationProvider.swift`, public)

**Customer DocC (drafted first):**

```swift
/// Supplies the current subject's container authorizations for a request — conform once, register at
/// boot, and every framework load is scoped by what you return.
///
/// ```swift
/// struct GrantProvider: ContainerAuthorizationProvider {
///     func containerAuthorizations(for request: Request) async throws -> [DockGrant] {
///         // however your app resolves the subject — session, token, headers…
///         let userId = try request.auth.require(SessionUser.self).id
///         return try await UserDockGrantRow.query(on: request.db)
///             .filter(\.$user.$id == userId).all()
///             .map(\.snapshot)                       // project Sendable value snapshots
///     }
/// }
/// ```
///
/// The framework fetches through your provider when first needed and reuses the result for every load
/// in that request — return the **complete** grant set, never a per-container slice. Return `[]` for
/// an unauthenticated or unprivileged subject: they simply load empty sets (routes stay
/// authentication-only; data access is enforced by scoping, never by route guards).
public protocol ContainerAuthorizationProvider: Sendable {
    /// Your app's authorization value (see ``ContainerAuthorization`` for the conformance pattern).
    associatedtype Authorization: ContainerAuthorization
    /// The current subject's complete authorization set for this request.
    func containerAuthorizations(for request: Request) async throws -> [Authorization]
}
```

### C3.2 Registration (`Extensions/Application+Containment.swift`, public — extends the existing file)

**Customer DocC (drafted first):**

```swift
public extension Application {
    /// Register the app's authorization provider — the framework scopes every container load through it.
    ///
    /// ```swift
    /// // in configure(_:)
    /// try app.useContainerAuthorizationProvider(GrantProvider())
    /// ```
    ///
    /// - Throws: if a provider is already registered — exactly one provider per application,
    ///   caught at boot.
    func useContainerAuthorizationProvider(_ provider: some ContainerAuthorizationProvider) throws
}
```

Internally: private `StorageKey` holding `any ContainerAuthorizationProvider` — the unavoidable
heterogeneous-storage erasure, confined behind the private key with SE-0352 opening at the single
internal call site (same posture as C4's registry). Duplicate ⇒ `.duplicateAuthorizationProvider`.

### C3.3 Provider-driven engine entry + opened-generic memoization (internal; `Extensions/Request+ContainerLoad.swift` — extends the engine file)

```swift
internal extension Request {
    // The C8 entry: acquisition + scoping in one call. Opens the stored provider (cheap; no fetch)
    // and forwards to the generic core below — generics preserved end-to-end.
    func authorizedRecords(
        of container: ModelIdentity,
        containing containedType: any DataModel.Type,
        for operation: ContainerOperation,
        sortedBy sortTerms: [AnySortTerm] = [],
        pagination: Pagination? = nil
    ) async throws -> [any DataModel]
    // guard let provider = application.<storage> else { throw .noAuthorizationProvider }
    // return try await authorizedRecords(via: provider, ...)   // SE-0352 opens `any` → P
}

// The opened-generic core: memoizes [P.Authorization] under a generic StorageKey (one provider per
// app ⇒ exactly one key instantiation), then calls the SHIPPED generic engine — no existential
// authorization array exists anywhere; the memo box is plainly Sendable (ContainerAuthorization
// requires Sendable — unlike the record cache, no @unchecked posture; do not copy it).
private struct AuthorizationMemoKey<P: ContainerAuthorizationProvider>: StorageKey {
    typealias Value = [P.Authorization]
}
```

Fetch-once semantics: first call fetches via `provider.containerAuthorizations(for: self)` and stores;
later calls (any container/type/operation in the same `Request`) read the memo. A fresh `Request` has
a fresh memo (lock-protected `Request` storage, one handler task — same isolation argument as the
record cache).

## Testing (`Tests/FOSMVVMVaporTests/Containment/AuthorizationProviderTests.swift`)

**Discipline note:** C3's full contract — "the registered provider's grants scope every load" —
becomes observable at a *public* surface only when C8's factory ships. Until then, the
acquisition/convenience tests are **coverage tests and say so** (`@testable import FOSMVVMVapor` — the
sanctioned use), asserting behavior (what loads, invocation counts, typed throws), never
representation. No access level is widened for tests.

1. **Registration fail-fast** (contract via the public registration API; the typed
   `.duplicateAuthorizationProvider` case assertion is a coverage rider reading package API) —
   registering succeeds once; a second registration (same or different provider type) throws.
2. **Provider-driven scoping (coverage)** — register a provider vending dock1-only grants; the
   internal entry returns dock1's berths; dock2's identity → empty; a provider vending `[]` → empty
   (data-scoping invariant end-to-end through acquisition).
3. **Memoization (coverage)** — a counting provider (locked counter) is invoked exactly once across
   multiple entry calls on the same `Request` (different containers/types); a fresh `Request` invokes
   it again.
4. **No provider (coverage)** — the entry throws `.noAuthorizationProvider` (never returns empty).
5. **Async provider (coverage)** — a provider that awaits real Fluent work (query the harbor
   fixtures' grant-like rows) works end-to-end.

## Risks & mitigations

- **Provider outliving a request's assumptions** (Application-scoped state). It receives the `Request`
  per call and should hold no per-request state; the DocC example models the stateless shape.
  `Sendable` is structurally required; the residual risk is documented here, not enforceable.
- **Apps forgetting registration** — fail-fast `.noAuthorizationProvider` at first load (test 4).
- **The `authorizedBy:` engine entry bypasses acquisition** — by design until C8; the structural-claim
  scoping (§problem statement) is honest about it, and the C8 audit revisits demoting/removing that
  entry once the factory routes all callers.

## Definition of done

- Tests 1–5 green; full suite green; swiftformat/swiftlint clean.
- DocC with examples on both public symbols; internal symbols carry `//` maintainer notes only.
- **Zero new `package` symbols** (grep); the two new enum cases acknowledged as riding a
  legacy-`package` enum.
- Coverage tests explicitly labeled where `@testable` is used.
- `ContainmentError`'s type-level doc refreshed to cover request-time cases (it already covers
  `.unregisteredNamespace` poorly — fix both).
- CHANGELOG: the two public symbols.
- Arch §C3 updated: DECISION-PROPOSED → resolved per D-C3-1; the provider sketch updated to
  full-set-per-request (with the drift/memoization rationale); cache-contract note updated
  (structural for the provider-driven path).
- **C8 package-audit items appended** (to the audit list in the handoff/arch): `ContainmentError`'s
  `package` level (demotion candidate); the `authorizedBy:` engine entry (demote/remove once C8 routes
  all framework callers).

## Design rationale (kept out of DocC)

- **Why a protocol, not a registered closure.** The seam is the app's to conform and document; the
  associatedtype keeps the app's surface existential-free. A closure would erase `Authorization` at
  exactly the point the app still has it concrete.
- **Why complete-set-once (the arch-sketch deviation).** Per-(type,operation) narrowing re-invokes app
  code per load: mid-request grant drift becomes possible (reopening the cache-collision axis C6
  closed) and memoization loses coherence. One fetch, one set, one request.
- **Why opened-generic memoization (review-driven).** The draft originally memoized
  `[any ContainerAuthorization]` (internal existential array) and added an existential engine variant.
  The document reviewer showed the generic-preserving alternative is real: open the stored provider
  per call (no fetch), memoize `[P.Authorization]` under a generic `StorageKey` inside the opened
  context, call the shipped generic engine. One provider per app means exactly one key instantiation.
  This eliminates every existential authorization array AND the second engine entry — the governance
  question "is there any other way?" had a yes.
- **Why missing-provider throws instead of empty-scoping.** Empty grants are a *valid state*
  (unauthenticated); a missing provider is a *configuration bug*. Conflating them buries the bug as
  universal-denial.
- **Why exactly one provider.** App-side composition is trivial; framework-side merge semantics are
  complexity with no consumer.
- **Rejected:** default authorization record (D-C3-1); public provider-driven load (C8 owns the public
  surface); `package` anything new; per-call re-acquisition (drift + incoherent memoization); closure
  registration (loses the typed conformance); existential memoization + existential engine variant
  (superseded by opened-generic memoization).

## Decisions

- **D-C3-1 — OQ-L1-2: thin framework.** Protocol + DI seam only; the app owns the concrete grant
  record/role model. **RESOLVED: thin (confirmed by David, 2026-07-04)** — his arch §3
  PROPOSED position; Defer-API — no role-system consumer exists; the DocC example shows the app-side
  pattern instead.
- **D-C3-2 — memoization is per-`Request`, non-invalidatable.** A grant change mid-request is
  deliberately not observed within that request (the request completes under the grant set it started
  with; pass-#2 refresh re-reads *records*, not grants). **RESOLVED: yes (confirmed by David, 2026-07-04)** —
  mid-request grant re-reads would reintroduce the collision axis C6 closed; an internal invalidation
  hook is deferred until a consumer demands it (and would first require relaxing the DocC wording —
  already phrased fetch-when-first-needed, not exactly-once, to leave that door open).

## Review reconciliation (2026-07-04; spec-document + FOSMVVM-discipline reviewers)

Verdicts: Sound-with-fixes / Approve-with-fixes — all folded:

- **Opened-generic memoization adopted** (doc MAJOR-2): replaces the internal existential array + the
  existential engine variant; the doc reviewer's generic-StorageKey design is the shipped shape. This
  also moots the discipline reviewer's erasure-direction finding (MINOR-2) — no shared-core funneling
  exists; the engine's "no existential arrays" note stays true end-to-end.
- **"Structural guarantee" claim scoped** (discipline MAJOR-1): structural for the provider-driven
  path only while the `package` `authorizedBy:` entry coexists; that entry added to the C8 audit
  (demote/remove once C8 routes all callers).
- **Arch-sketch deviation surfaced** (doc MAJOR-1 / discipline MINOR-5): dedicated section + rationale
  + DoD item updating the arch's provider sketch.
- **Enum-case access acknowledged** (discipline MINOR-3): zero new package *symbols*, but the two new
  cases ride a legacy-`package` enum — stated in Scope; `ContainmentError` level audit-listed.
- **DocC "once per request" relaxed** (discipline MINOR-4) to fetch-when-first-needed/reused — the
  publishable contract that survives a future invalidation hook.
- Test-1 taxonomy exactified (doc MINOR-4 / discipline NIT-6: contract with a labeled coverage rider);
  `ContainmentError` type-doc refresh in DoD (doc NIT-5); internal-vs-fileprivate floor stated in the
  access note (NIT-7); memo box plainly-Sendable note in C3.3 (NIT-8).
