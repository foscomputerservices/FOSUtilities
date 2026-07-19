# Credential Refresh Seam — Design Spec

**Date:** 2026-07-19
**Status:** DRAFT — awaiting David's review.
**Names arbitrated (David, 2026-07-19):** `credentialHeaders(afterRejection:)`,
returning optional headers, non-throwing.
**Version target:** 0.10.0 (additive, minor — default implementation preserves
current behavior for every existing conformance).

> **READ FIRST.** Successor to `2026-07-13-credential-rejection-typed-error-design.md`
> (shipped 0.7.0). That design made rejection *typed and visible to the call site*.
> This one gives the call site that FOSMVVM itself owns — the ViewModel bind — a way
> to act on it. Section 8 lists what this design deliberately does **not** fix.

---

## 1. Problem

A server rotates its bearer token. The client holds a cached one. Every subsequent
`.live` ViewModel bind fails with `CredentialRejectedError(code: .invalid)` —
permanently. The only remedy is deleting the client's cache file by hand and
relaunching.

Three facts compose into the trap.

**(a) The rejection deliberately bypasses recovery.**
`Sources/FOSMVVM/Protocols/ServerRequest+Fetch.swift:201`:

```swift
        } catch let rejection as CredentialRejectedError {
            // A surface rejection always reaches the caller — recovery
            // (refresh credential, retry) is a call-site decision.
            throw rejection
        } catch let error as ServerRequestError {
            if let errorHandler = mvvmEnv.requestErrorHandler {
                errorHandler(self, error)
                return []
            } else {
                throw error
            }
        }
```

This is contract, not oversight — `MVVMEnvironment.swift:119` states it: *"Surface
rejections (`CredentialRejectedError`) are never routed here — they always throw to
the caller."* The 0.7.0 design ratified it under "Throw past `requestErrorHandler`."

**(b) For a bound ViewModel, FOSMVVM *is* the call site — and it swallows.**
`Sources/FOSMVVM/SwiftUI Support/ViewModelView.swift:517`:

```swift
        } catch { // fosmvvm-review:disable:this no-silent-failure -- Error handling is TBD
            print("ViewModel Bind Error: \(error)")
            // TODO: Error handling
```

The application never receives the decision point the contract promises it.

**(c) The provider is never told, so it keeps returning the dead credential.**
`ClientCredentialProvider` is consulted per request and documented to pick up
rotation automatically (`ClientCredentialProvider.swift:22-26`). That promise holds
only if something updates the credential. Nothing tells the provider its credential
was refused, so it re-supplies the same dead value forever.

### 1.1 Why notification alone is insufficient

Every bind trigger in `ViewModelView.swift` is an **edge** — `onChange` of `query`
(:418), of `fragment` (:422), of the invalidation and refresh signals (:429, :435,
:448), or the first `.task` (:452). **Nothing observes the credential.**

So a notify-only seam produces: bind fails → provider is told → app refreshes the
token successfully → the view still holds `nil` and sits on `ProgressView`, because
`resolveServerHostedRequest` already returned `(nil, [])` and no edge will fire
again. The console then holds a *valid* credential and still shows nothing until
the operator navigates away and back.

The edge that would normally rescue it — `liveCoordinator.refreshSignal` — is
exactly the one that is also dead, because SSE is reconnecting on the same stale
token.

**Some retry is therefore load-bearing, not a convenience.**

### 1.2 Why the fix is not a new bind edge

An earlier candidate was to publish a credential-refresh edge for resolvers to
observe, composing onto `refreshSignal`. It does not compose.
`LiveRegistrationCoordinator.swift:55` routes by identity, via a token the screen
obtains only on a **successful** bind — `ViewModelView.swift:475`:

```swift
    private func loadAndBind() async {
        let (vm, registrations) = await resolveServerHostedRequest()
        viewModel = vm
        guard vm != nil else { return }
        registerLive(registrations)
    }
```

A credential-rejected bind returns `(nil, [])`, hits that `guard`, and registers
nothing. The stalled screens are precisely the ones the dispatcher cannot reach.
Non-live screens never register at all and stall identically. A credential edge
would have to be app-wide, identity-agnostic, and observed by every resolver — a
new mechanism beside the dispatcher, not an extension of it. Rejected on cost and
on the "compose onto the general, never a parallel door" rule.

---

## 2. Scope

**In:** the notification/refresh seam and a single bounded retry.

**Out:** the `ViewModelView.swift:517` swallow. It gets its own arc. Its own TODO
asks for app-level out-of-band error surfacing rather than per-view error views;
that is a real design pass and must not hold this fix hostage.

Consequence to state plainly: after this change a rotation recovers **silently**.
The operator sees a brief `ProgressView` and then live data. A rotation that
recovery *cannot* fix still shows nothing but a console print — unchanged, and
addressed only by the swallow arc.

---

## 3. Arbitrated decisions (David, 2026-07-19)

**One call, not two.** Notification and supply are a single responsibility:
*here is what was refused; give me what to send instead, or tell me you have
nothing.* A separate notify-then-re-ask opens a window in which the provider may
rotate again, letting the retry use headers the provider never sanctioned for this
recovery.

**Returns optional headers.** `nil` is an unambiguous "do not retry." The framework
never asks a second question.

**Non-throwing.** A failed refresh returns `nil` so the framework rethrows the
*original* `CredentialRejectedError`. A throwing method would replace the real
diagnosis with a refresh-plumbing error at the call site. The provider logs its own
failure app-side.

**Named as an overload of the existing supply method.** `credentialHeaders(afterRejection:)`
roots on `credentialHeaders()` and adds no new name to the namespace — therefore no
new confusable name shape. The argument label carries the disambiguation, which is
the part that reads at a call site.

Rejected names, recorded so they are not re-proposed: `credentialRejected(_:)`
(notification framing this design rejects; also `credentialRejected`/`credentialHeaders`
is a shared-leading-word, mid-token-differing pair), `refreshedCredentialHeaders(after:)`
(`after:` does not say after *what*), `renewCredentialHeaders(afterRejection:)`
(loses the rooting).

---

## 4. Surface (DocC first)

Added to `ClientCredentialProvider`, `Sources/FOSMVVM/Protocols/ClientCredentialProvider.swift`:

```swift
    /// The replacement headers to retry with after the server refused the last set
    ///
    /// Called when a request fails with ``CredentialRejectedError``. Refresh your
    /// credential and return its headers to have the request retried once with
    /// them; return `nil` — the default — and the rejection throws to the caller
    /// unchanged.
    ///
    /// ```swift
    /// func credentialHeaders(afterRejection: CredentialRejectedError) async -> [(field: String, value: String)]? {
    ///     guard afterRejection.code == .invalid else { return nil }
    ///     guard let token = await SessionStore.shared.refreshAccessToken() else { return nil }
    ///     return [(field: "Authorization", value: "Bearer \(token)")]
    /// }
    /// ```
    ///
    /// - Important: **Persist the refreshed credential** — returning it is not enough.
    ///     The returned headers are used for this one retry; every later request, and
    ///     every live-channel reconnect, calls ``credentialHeaders()`` instead. A
    ///     provider that returns a fresh credential without storing it keeps handing
    ///     out the refused one.
    /// - Important: Several screens can be refused at once — each bound ViewModel
    ///     issues its own request and is refused independently. Coalesce concurrent
    ///     refreshes (single-flight) inside your provider; this method may be called
    ///     several times in quick succession with the same rejection.
    /// - Parameter afterRejection: The rejection the server returned, so a provider
    ///     can distinguish a missing credential from an invalid one
    /// - Returns: Headers to retry the request with once, or `nil` when no fresh
    ///     credential is available — the rejection then throws to the caller
    func credentialHeaders(afterRejection: CredentialRejectedError) async -> [(field: String, value: String)]?
```

With a default implementation, which is what makes this additive:

```swift
public extension ClientCredentialProvider {
    func credentialHeaders(afterRejection: CredentialRejectedError) async -> [(field: String, value: String)]? {
        nil
    }
}
```

### 4.1 The persistence obligation

The two overloads are not independent. `credentialHeaders(afterRejection:)` returns
what *this* retry sends; `credentialHeaders()` answers every request after it. The
design is only coherent if a refresh performed by the former becomes visible to the
latter — **the provider must persist, not merely return.**

A provider that returns fresh headers without storing them is legal as written and
fails in two places, neither of which looks like a failure:

- **Every later fetch** re-consults `credentialHeaders()`, gets the refused
  credential, is rejected, and refreshes again — two round trips per request,
  indefinitely. Every request still *succeeds*, so nothing surfaces.
- **The live channel never recovers on an idle app** (§6), because its only path
  back to a good credential is `credentialHeaders()` on reconnect.

This is the hardest defect in the design to notice from the fetch path alone, which
is why it is stated as a protocol-level obligation in the DocC above rather than as
a note on the SSE arm.

The alternative — have the SSE arm reuse the returned headers directly — was
rejected. It fixes only the second symptom, leaves the per-request doubling in
place, and requires the channel to carry credential state across a reconnect, which
§6 exists to avoid.

`BearerCredentialProvider` does **not** override it. It is constructed from a
token-yielding closure with no refresh capability, and inventing one would put
credential acquisition inside the framework. Its DocC gains a line pointing to a
custom conformance for refresh-on-rejection.

---

## 5. Call site — the fetch path

`processRequestCapturingRegistrations(mvvmEnv:)`, `ServerRequest+Fetch.swift:201`.
The rejection arm gains one bounded retry before the existing rethrow:

- catch `CredentialRejectedError`
- if `mvvmEnv.clientCredentialProvider` is nil → rethrow (unchanged)
- ask `credentialHeaders(afterRejection:)`; `nil` → rethrow the **original**
  rejection (unchanged)
- otherwise re-send **once**, with the static `requestHeaders` recomposed exactly as
  on the first attempt and the returned credential headers appended last, preserving
  the documented duplicate-field precedence at `ServerRequest+Fetch.swift:189-193`
- a second `CredentialRejectedError` rethrows — the retry is never recursive
- any non-rejection error from the retry follows the existing
  `ServerRequestError` / `requestErrorHandler` arm

**Exactly once, and only here.** The retry is not a general policy: it triggers only
on `CredentialRejectedError`, only when a provider affirmatively supplies
replacement headers.

Header composition is shared between the first attempt and the retry rather than
duplicated, so the two can never drift.

### 5.1 Only a *server* rejection opens the seam

The existing `:201` arm also catches a `CredentialRejectedError` thrown by the
provider's own `credentialHeaders()` at `:193` — before any request is sent. The
seam must **not** fire there: no server refused anything, and asking a provider that
just failed to supply a credential to supply a replacement is circular. A rejection
originating in header composition rethrows unchanged.

### 5.2 Structural constraint the implementer will hit

Swift `catch` clauses do not chain: an error thrown *inside* the
`catch let rejection as CredentialRejectedError` block does not fall through to the
sibling `catch let error as ServerRequestError`. So the retry cannot simply be
inlined into the existing arm — the retry's non-rejection errors would escape
`requestErrorHandler`, silently breaking the contract §7 pins.

Both this and §5.1 resolve the same way: hoist header composition and the send into
one private helper, and wrap **only the send** in the retry-aware `do`. Header
composition then sits outside it (satisfying §5.1 by construction), and the retry
routes its result back through the single error-handling arm rather than duplicating
it (satisfying §5.2).

---

## 6. Call site — the SSE channel

`SSEInvalidationChannel.openAndStream`, `SSEInvalidationChannel.swift:115-153`.

SSE mostly rides along for free: it re-consults the provider on every reconnect, so
once any fetch retry drives the refresh, the next reconnect picks up the good token.
**This depends entirely on the §4.1 persistence obligation** — without it the
reconnect re-reads the refused credential and the channel never recovers.

The gap is an app idle enough that no fetch ever fires — SSE then reconnects forever
on a dead token, back-off capped, never refreshing. Closing it: when the open fails
with a 401, call `credentialHeaders(afterRejection:)` with
`CredentialRejectedError(code: .invalid)` and discard the return, then continue into
the existing drop-and-back-off path. The discard is deliberate — the reconnect
re-consults `credentialHeaders()` and picks up the refreshed value; SSE gains no
retry logic of its own.

Only 401 maps this way. Every other non-2xx stays an anonymous drop, per the
existing comment at `SSEInvalidationChannel.swift:125-129`.

---

## 7. Testing

Contract, never representation.

- provider without an override → one request, rejection throws (today's behavior,
  proving additivity)
- provider returning headers → exactly two requests, second carries the new
  credential, call succeeds
- provider returning `nil` → one request, original `CredentialRejectedError`
  rethrown, error identity preserved
- second rejection on the retry → exactly two requests, rethrown, no third
- retry preserves static `requestHeaders`, and credential headers still win on a
  duplicate field
- a non-rejection error on the retry still reaches `requestErrorHandler`
- concurrent refused requests each call the seam — asserts the documented
  many-calls contract the DocC warns about
- SSE 401 invokes the seam; a non-401 non-2xx does not

Test-side providers must be able to count calls and vary their answer per call.

**Not testable framework-side:** the §4.1 persistence obligation. It is a property of
the conforming provider, and the framework cannot observe whether a refresh was
stored. It is enforced by DocC only — which is why §4.1 states it as a contract
rather than a suggestion.

---

## 8. Non-goals

- **The bind swallow** (`ViewModelView.swift:517`) — own arc, §2.
- **Credential acquisition.** The framework never mints, refreshes, or stores a
  credential. It reports a refusal and re-sends what it is handed.
- **Refresh coalescing.** Provider-side; documented, not enforced.
- **Retry for anything but credential rejection.** No general retry policy enters
  FOSMVVM by this door.
- **A credential bind edge.** Rejected in §1.2.
- **Changing the 0.7.0 rethrow contract.** A rejection that recovery cannot fix
  still reaches the caller, unchanged.

---

## 9. Rotation, confirmed (client, 2026-07-19)

Rotation is real: the server rotated its token on restart, and that is what broke
the console. The client's agent processes survived it because they re-pull on a 426
rejection; the SwiftUI console had no equivalent path. That missing path is exactly
what this design adds.

Whether restart-rotation is *intentional* remains open on the client's side. It does
not gate this work: a rotated credential must be recoverable however rotation is
triggered. Urgency is real; the design is independent of the answer.

**Adoption cost, confirmed by the client:** a few lines. Their provider is backed by
an actor fetcher whose `fetchFresh()` already single-flights, so the concurrent-refresh
coalescing the §4 DocC warns about is satisfied by construction — and, being an actor
holding the fetched credential, so is the §4.1 persistence obligation. That is one
data point, not a general one; both obligations stay documented for providers that
are not actor-backed.
