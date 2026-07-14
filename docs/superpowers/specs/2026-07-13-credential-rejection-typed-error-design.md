# Credential Rejection as a Typed Error — Design Spec

**Date:** 2026-07-13
**Status:** RATIFIED (David, 2026-07-13) — structural decisions (§2) and names.
**Names:** `CredentialRejectedError`, cases `.missing` / `.invalid`, transient
`challenge` property KEPT, no `message` field. Internal wrapper name
(`WireError`) and test-harness property (`credentialRejection`) are
implementation-level defaults, cheap to rename in review.
**Version target:** 0.7.0 (additive, minor).

> **READ FIRST.** This spec is the source of truth for the design; the
> deferral history lives in the consumer project's ledger. Everything here
> was gated through `fosmvvm-planning` (surface → DocC → contract tests →
> rationale). Section 9 lists what this design *retires*.

---

## 1. Problem

A credential rejection is a *middleware* failure that precedes every operation
on a protected route group. Today it surfaces client-side as
`DataFetchError.badStatus(httpStatusCode: 401)` — a transport number, not
typed data — because:

- `DataFetch` decodes exactly ONE error type per request
  (`errorType: Self.ResponseError.self`, `ServerRequest+Fetch.swift:128,140`),
  and the rejection belongs to no single request's vocabulary.
- `ClientCredentialMiddleware`'s verifier throws a bare
  `Abort(.unauthorized, reason:)` (`ClientCredentialMiddleware.swift:134,142`),
  which FOS `ErrorMiddleware` serves as a reason-string body.

Under the errors-are-data ruling (2026-07-10): statuses carry no result
semantics; a failure the client branches on must be a typed `Codable` error
riding the ServerRequest error path. The credential seam is the layer that
failed — its throw must cross the wire typed, like any other.

**The local-call model.** A local call through a credential layer can throw
from *that layer* — a domain distinct from the operation's own — and the
caller catches both without the operation declaring the credential error.
The client-visible thrown vocabulary of `processRequest` is therefore:

    the request's ResponseError  ∪  the surface's own well-known errors

This design adds the first well-known surface error.

---

## 2. Ratified decisions (David, 2026-07-13)

**Per-seam error types.** One well-known FOS type per framework seam
(credential rejection now; a version-rejection type later *if and when a
consumer needs it* — defer-API-until-client-exists). The internal decode
wrapper tries a closed, FOS-owned list in order. Each seam owns its meaning,
payload, and transport dressing.

**Throw past `requestErrorHandler`.** The well-known surface error always
throws to the call site. `requestErrorHandler` (`MVVMEnvironment.swift:118`)
keeps its documented job — operation errors from a request's own
`ResponseError`. No swallow-into-nil for rejections; callers doing recovery
(refresh credential, retry) see the trigger.

**Transport dressing: `ErrorMiddleware` gains a general
`Encodable & AbortError` case, ordered first.** Typed body via the localizing
encoder AND the error's own status/headers. `CredentialRejectedError`
conforms to `AbortError` via extension in FOSMVVMVapor. Behavior change for
any existing `Encodable & AbortError` app error: today body+400, after
body+own-status — the fix, not a regression.

**Names.** `CredentialRejectedError` (event-framed, rooted in the seam's
shipped *Credential* stem and *reject* verb); `Code` cases `.missing`
(nothing presented — client config bug) / `.invalid` (presented and refused —
rooted in the shipped `isValid`); `challenge` KEPT (transient, preserves
RFC 7235 dressing); **no `message` field** (code-only; the client app owns
UX wording — see §8).

---

## 3. Mechanics

### 3.1 Server: serving the rejection

```
verifier.verify(headers:) throws
        │
        ▼
ClientCredentialMiddleware catches:
  - already CredentialRejectedError?  → rethrow as-is
  - CancellationError?                → rethrow as cancellation
  - anything else                     → wrap: .init(code: .invalid)
        │
        ▼                     (verifier contract is "throw to reject", §8;
                               cancellation is a control-flow signal,
                               not a domain rejection — it propagates)
FOS ErrorMiddleware:
  case any (Encodable & AbortError)   ← NEW, ordered first
        │
        ▼
Response: the error's status (.unauthorized) + its headers (challenge)
          + body = localizingEncoder(error)   ← self-identifying envelope
```

- `BearerCredentialVerifier` switches from `Abort` to throwing
  `CredentialRejectedError(code: .missing)` / `(code: .invalid)` with
  `challenge: "Bearer"`.
- Custom verifiers may throw `CredentialRejectedError` directly (richer
  intent) or keep throwing anything — the middleware wraps.
- The "never echo the presented credential" constraint is unchanged and now
  structurally easier: the error has no free-text field to echo into.

### 3.2 Client: decoding the rejection — FOSFoundation UNTOUCHED

The decode-order lives in an **internal** FOSMVVM wrapper passed as the ONE
existing `errorType:` parameter — `DataFetch` keeps its single-error contract:

```swift
// INTERNAL — FOSMVVM plumbing, not public API
enum WireError<E: ServerRequestError>: Error, Decodable {
    case surface(CredentialRejectedError)   // strict: requires the envelope
    case response(E)

    init(from decoder: Decoder) throws {
        // 1. Try CredentialRejectedError STRICTLY: required discriminator
        //    key must be present with its exact expected value — else fall
        //    through.
        // 2. Try E (the request's ResponseError).
        // 3. Else throw (DataFetch falls back to DataFetchError as today).
    }
}
```

`ServerRequest+Fetch.swift` passes `errorType: WireError<Self.ResponseError>.self`
and unwraps in `processRequestCapturingRegistrations(baseURL:)`:
`.surface` → throw the `CredentialRejectedError`; `.response` → throw the
typed `ResponseError`. The `catch let error as ServerRequestError` block
(`ServerRequest+Fetch.swift:192`) adds one pre-check implementing the
routing decision (§2): `CredentialRejectedError` rethrows past the handler.

### 3.3 The self-identifying envelope

`CredentialRejectedError`'s `Codable` form carries a required discriminator
key with a fixed expected value; `init(from:)` **fails** unless both match
exactly.

- The concrete key/value are an INTERNAL detail: pinned by a `//` maintainer
  comment beside `CodingKeys` + an internal representation test + a committed
  golden-blob forward-compat fixture. **Never published in DocC/CHANGELOG/README**
  (the `published-representation` rule). Public docs state the contract only:
  opaque, `Codable` round-trips, stable within a major version.
- Strictness kills both puncture directions:
  - nothing puns INTO `CredentialRejectedError` (a request's `ResponseError`,
    Vapor's stock `{"error":true,"reason":…}`, and plain reason-strings all
    lack the discriminator);
  - `EmptyError` can no longer swallow rejections — the wrapper claims the
    rejection body at step 1, before `EmptyError`'s decode-from-anything
    runs. This retires the documented `DataFetch` 401-visibility gotcha
    (`ClientCredentialMiddleware.swift:61–68`) for rejections.

### 3.4 Test harness (hidden consumer)

`FOSTestingVapor`'s `TestingServerRequestResponse` decodes `R.ResponseError`
today. It composes the SAME wrapper (one decode-chain definition, reused) and
exposes the rejection typed:

- `error: R.ResponseError?` — unchanged semantics.
- `credentialRejection: CredentialRejectedError?` — NEW, so server tests
  assert rejections as typed data, not status-only. (Per-seam types mean a
  future seam error adds its own property; no generic slot.)

---

## 4. Public surface (planning-gate applied)

### FOSMVVM

| Symbol | Justification (caller need) |
|---|---|
| `struct CredentialRejectedError: ServerRequestError` | The typed rejection callers catch; the credential seam's throw crossing the wire. |
| `CredentialRejectedError.Code` enum: `.missing`, `.invalid` | The two caller-actionable meanings: nothing presented (client config bug) vs presented-and-refused (refresh/re-pull). Rooted in shipped verifier semantics (`isValid`). |
| `CredentialRejectedError.init(code:challenge:)` | Constructed by the middleware, custom verifiers, and tests. |
| `CredentialRejectedError.challenge: String?` — **transient, NOT encoded** | Carries the RFC 7235 challenge value ("Bearer") from verifier to transport dressing without Vapor types in FOSMVVM. Nil client-side. RATIFIED kept. |

Gate notes:
- **No `message` property (RATIFIED).** Deliberate deviation from the
  `code + message` worked shape in `ServerRequestError`'s DocC: FOS ships no
  localized strings today (all `Localizable` content is app-supplied), and
  rejection UX is a client-hosted-ViewModel decision (Error UI Is Not
  Special). A message adds localization machinery for marginal value.
- **No stringly-typing:** no free-text reason field anywhere on the type.
- **One serialization:** the envelope IS the type's only `Codable` form.
- Boundaries hold: FOSFoundation untouched; Vapor conformance lives in
  FOSMVVMVapor.

### FOSMVVMVapor

| Symbol | Justification |
|---|---|
| `extension CredentialRejectedError: AbortError` | Supplies `.unauthorized` + challenge header to the dressing case (§2). |
| `ErrorMiddleware.default` — new first case `any (Encodable & AbortError)` | General mechanism (§2); no new public symbol, a documented behavior refinement. |
| `ClientCredentialMiddleware` respond path | No signature change; rejection wrapping is internal behavior. DocC contract rewritten (§9). |
| `BearerCredentialVerifier` | No signature change; throws `CredentialRejectedError` instead of `Abort`. |

### FOSTestingVapor

| Symbol | Justification |
|---|---|
| `TestingServerRequestResponse.credentialRejection` | Server tests must assert rejections as typed data. |

### Explicitly NOT in scope

- `ClientCredentialProvider` rejection hook / auto-refresh-retry — future,
  additive. The enabling property is recorded in §8 (pre-operation ⇒
  retry-safe) so the future pass doesn't re-derive it.
- A version-rejection well-known error — deferred until a consumer exists;
  the wrapper's closed-list shape already accommodates it.
- `RequireVersionedAppMiddleware`, `DataFetch`, `DataFetchError` — untouched.

---

## 5. Customer-facing DocC (drafted FIRST)

### `CredentialRejectedError`

```swift
/// The error thrown when a protected route rejects the request's credential
///
/// Routes grouped behind `ClientCredentialMiddleware` verify the presented
/// credential before the operation runs. When verification rejects the
/// request, this error crosses the wire and is rethrown by
/// ``ServerRequest/processRequest(mvvmEnv:)`` — catch it to recover:
///
/// ```swift
/// do {
///     try await request.processRequest(mvvmEnv: mvvmEnv)
/// } catch let error as CredentialRejectedError {
///     switch error.code {
///     case .missing: … // no credential was presented — check the
///                      // MVVMEnvironment's clientCredentialProvider
///     case .invalid: … // presented but refused — refresh the credential
///                      // and retry (safe: the operation never ran)
///     }
/// }
/// ```
///
/// The rejection happens **before** the operation runs, so retrying after
/// recovery never duplicates the operation's effects.
///
/// This error always throws to the call site — it is never routed to
/// ``MVVMEnvironment/requestErrorHandler``.
```

### `CredentialRejectedError.Code`

```swift
/// Why the credential seam rejected the request
///
/// `.missing` — no credential accompanied the request; typically the client
/// has no `ClientCredentialProvider` configured (or it returned no headers).
/// `.invalid` — a credential was presented and the server's verifier refused
/// it; refresh the credential and retry.
```

### `AbortError` conformance (FOSMVVMVapor)

```swift
/// Dresses the rejection for the transport: `401 Unauthorized` with the
/// verifier's authentication challenge (for example `WWW-Authenticate:
/// Bearer`). The response *body* remains the typed error — FOSMVVM clients
/// decode and rethrow it; the status exists for proxies, logs, and RFC 7235
/// conformance, never for client branching.
```

### `ErrorMiddleware` (type DocC contract addition)

```swift
/// An error that is both `Encodable` and `AbortError` is served with its
/// typed body (localized through the request's encoder) AND its own status
/// and headers. A plain `Encodable` error keeps the typed body with
/// `400 Bad Request`.
```

### `ClientCredentialMiddleware` — "Client-Side Contract" section REPLACED

```swift
/// ## Client-Side Contract
///
/// On a FOSMVVM client, a rejection surfaces from
/// `processRequest(mvvmEnv:)` as `CredentialRejectedError` — the same typed
/// error whether the request's own `ResponseError` is `EmptyError` or a
/// custom type. Catch it to recover; see ``CredentialRejectedError``.
```

### `MVVMEnvironment.requestErrorHandler` (parameter DocC addition)

```swift
///   - requestErrorHandler: … Surface rejections
///     (``CredentialRejectedError``) are never routed here — they always
///     throw to the caller.
```

---

## 6. Contract tests (public contract only; no `@testable` for contract)

**FOSMVVM (unit):**
1. `CredentialRejectedError` round-trips via `try value.toJSON().fromJSON()`
   — code preserved, equality holds, `challenge` does NOT survive
   (transient).
2. Forward-compat: committed golden-blob rejection body decodes into
   `CredentialRejectedError` (INTERNAL test — the one place the envelope
   shape is pinned, beside the `//` maintainer note).
3. Wrapper precedence (internal test): rejection body → `.surface`; a
   request-error body → `.response`; Vapor stock abort JSON and a plain
   reason-string → neither (falls through).

**FOSMVVMVapor (E2E over the real middleware stack — remember
`app.asyncBoot()` for async lifecycle handlers):**
4. Protected route, no credential → client-side `processRequest` throws
   `CredentialRejectedError` with `.missing`; transport shows 401 +
   challenge header (transport assertions verify the *server's* dressing
   contract — the client never branches on them).
5. Protected route, bad credential → `.invalid`.
6. **EmptyError retirement:** protected request whose `ResponseError ==
   EmptyError` → rejection throws `CredentialRejectedError`, NOT a
   silently-decoded `EmptyError`.
7. **Precedence:** request with a permissive custom `ResponseError` →
   rejection still surfaces as `CredentialRejectedError` (wrapper claims it
   first).
8. **Skew fallback:** a plain 401 without the envelope (old-server shape) →
   today's behavior (`DataFetchError.badStatus` for required-field
   `ResponseError`s) — no regression.
9. **Handler bypass:** `MVVMEnvironment` with `requestErrorHandler` set →
   rejection still throws; handler NOT called; a request's own
   `ResponseError` still routes to the handler.
10. **Dressing:** an `Encodable & AbortError` test error → own status +
    typed body; a plain `Encodable` error → 400 + typed body (unchanged).
11. Existing `ClientCredentialMiddlewareTests` pinning the old 401-visibility
    contract are RESHAPED to the new contract (not deleted — same scenarios,
    new assertions).

**FOSTestingVapor:**
12. `TestingServerRequestResponse.credentialRejection` populated on
    rejection; `error` remains nil; and vice versa for operation errors.

---

## 7. Compatibility & versioning

- **0.7.0, additive.** No wire shape removed; the rejection body *changes*
  from a localized reason-string to the typed envelope.
- New client ↔ old server: envelope decode fails → falls through to
  `ResponseError` / `badStatus` exactly as today (test 8).
- Old client ↔ new server: required-field `ResponseError`s fail to decode the
  envelope → `badStatus(401)` as today. `EmptyError` requests: the old
  client's `EmptyError` still decodes-anything and swallows — the documented
  pre-existing hazard, unchanged for old clients, retired for new ones.
- The `ErrorMiddleware` dressing change is called out in the CHANGELOG
  (contract statement only — no envelope shape).

## 8. Rationale & rejected alternatives (implementer prose — NOT for DocC)

- **Per-request `admissionRejected` cases (the consumer's fallback option):**
  rejected on *siting*, not just ceremony — a rejection is
  1-per-protected-surface, not 1-per-request; embedding it in every request's
  vocabulary mis-sites a 1:many responsibility at the 1:1 level (the
  RefreshRequest lesson) and drifts (×12 in the consumer).
- **Threading a second `errorType` through `DataFetch`:** rejected — touches
  many public FOSFoundation overloads for an FOSMVVM concern. The internal
  wrapper composes onto the shipped single-error mechanism with zero
  FOSFoundation change and keeps the decode-order in ONE place.
- **Carrying HTTP status on `DataFetchError` typed errors:** dead — the
  status-first frame the errors-are-data ruling killed.
- **One shared surface-error type:** rejected (§2) — a single shape must
  absorb every seam's payload and its per-case transport dressing; per-seam
  types keep SRP and crisper catches.
- **`message: LocalizableString`:** cut (RATIFIED) — FOS ships no localized
  strings today; rejection UX is a client-hosted-ViewModel decision. Cheap to
  add later; expensive to remove.
- **Middleware wraps ANY verifier throw as `.invalid`:** follows the shipped
  verifier contract ("throw to reject" — `ClientCredentialMiddleware.swift:38`).
  A verifier with genuine infra failures (DB down) can throw
  `CredentialRejectedError` itself or — better — that distinction is a future
  verifier-contract refinement, not this pass.
- **Pre-operation ⇒ retry-safe (record for the future hook):**
  `ClientCredentialMiddleware.respond` rejects BEFORE `next.respond`
  (`ClientCredentialMiddleware.swift:89–93`) — the operation never ran, so
  refresh-and-retry after a rejection can never duplicate a non-idempotent
  operation. This is the property that legitimizes a future
  `ClientCredentialProvider` auto-refresh seam.

## 9. What this design retires

- `ClientCredentialMiddleware` DocC "Client-Side Contract" +
  "Known limitation" sections (`ClientCredentialMiddleware.swift:52–68`) —
  replaced (§5).
- The tests pinning the badStatus(401) client contract — reshaped (test 11).
- API catalog `FOSMVVMVapor.md § ClientCredentialMiddleware` "Limitation"
  paragraph — replaced with the typed contract.
- Architecture doc / catalog gain the surface-error description; the
  `status-interpreted-as-result` review check's anti-pattern example becomes
  fixable-by-framework instead of merely-detectable.
- Consumer-side (not this repo): the `badStatus(401)` interim catch and the
  rotation deferral's prong-1 dependency.

## 10. Decision record (all resolved 2026-07-13)

1. Type name `CredentialRejectedError`; cases `.missing` / `.invalid` —
   RATIFIED.
2. Transient `challenge` property — RATIFIED kept.
3. No `message` field — RATIFIED.
4. Internal wrapper `WireError` and harness property `credentialRejection` —
   implementation defaults, renameable in review.
