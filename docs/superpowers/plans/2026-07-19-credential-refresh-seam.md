# Credential Refresh Seam — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a bound ViewModel recover from a rotated server credential, by giving `ClientCredentialProvider` a refresh seam and retrying the refused request exactly once.

**Architecture:** One new protocol requirement — `credentialHeaders(afterRejection:)` — declared on `ClientCredentialProvider` with a `nil`-returning default, so every existing conformance keeps compiling and keeps today's behavior. `ServerRequest+Fetch` splits header composition from the send, wraps **only the send** in a retry-aware `do`, and re-sends once when the provider supplies replacement headers. The SSE channel notifies the same seam on a 401 and discards the return, relying on the provider having persisted the refresh.

**Tech Stack:** Swift 6 (`swiftLanguageModes: [.v6]`), Swift Testing, Vapor (server-side round-trip tests only).

**Spec:** `docs/superpowers/specs/2026-07-19-credential-refresh-seam-design.md` — read it before starting. Rationale lives there, not here.

**Version target:** 0.10.0 (additive, minor).

---

## Required Reading Before Task 1

- The spec, especially **§4.1** (persistence obligation), **§5.1** (only a *server* rejection opens the seam), **§5.2** (Swift `catch` clauses do not chain).
- `Tests/FOSMVVMVaporTests/Protocols/ClientCredentialRoundTripTests.swift` — the harness Task 3 extends. It provides `withRunningServer` (via `RoundTripHarness.swift`), `RoundTripController`, and the actors `TokenVault` and `RequestTally` (Task 3 moves the latter two to the shared fixtures file).
- `Tests/FOSMVVMVaporTests/Protocols/CredentialSeamFixtures.swift` — the shared home for credential-seam fixtures. Already holds `StrictContractError` and `ShowOperationFailureRequest`, both of which Task 3 reuses.
- `Tests/FOSMVVMVaporTests/Middleware/ClientCredentialMiddlewareTests.swift:266` **and** `:380` — the two ends of the wire-shape contract. Read both before writing any round-trip test; see the warning at the head of Task 3.

**Two constraints that will bite if forgotten:**

1. The new method **must be a protocol requirement**, not extension-only. `MVVMEnvironment.clientCredentialProvider` is `(any ClientCredentialProvider)?` (`MVVMEnvironment.swift:111`); an extension-only method binds to the default through the existential, so the seam would silently never fire and nothing would fail to compile.
2. Contract tests use the **public** API only. No `@testable` for contract coverage.

**Already covered, do not re-test:** spec §7's first bullet — a provider with no override
throws the rejection after one request — is pinned today by `rejectionBypassesRequestErrorHandler`
part (a) at `Tests/FOSMVVMVaporTests/Middleware/ClientCredentialMiddlewareTests.swift:201`,
which uses a stock `BearerCredentialProvider`. That test passing unchanged after Task 3 **is**
the additivity proof.

---

## File Structure

**Modify:**
- `Sources/FOSMVVM/Protocols/ClientCredentialProvider.swift` — the requirement + defaulted extension + DocC
- `Sources/FOSMVVM/Protocols/ServerRequest+Fetch.swift:178-213` — split composition from send; add the bounded retry
- `Sources/FOSMVVM/SwiftUI Support/SSEInvalidationChannel.swift:130-132` — notify the seam on 401
- `CHANGELOG.md` — 0.10.0 entry

**Test:**
- `Tests/FOSMVVMTests/Protocols/ClientCredentialProviderTests.swift` — default-implementation behavior (unit)
- `Tests/FOSMVVMVaporTests/Protocols/ClientCredentialRoundTripTests.swift` — retry contract, real client ↔ real server
- `Tests/FOSMVVMVaporTests/LiveInvalidation/ClientChannelRoundTripTests.swift` — SSE 401 notification

---

## Task 1: The protocol requirement and its default

**Files:**
- Modify: `Sources/FOSMVVM/Protocols/ClientCredentialProvider.swift`
- Test: `Tests/FOSMVVMTests/Protocols/ClientCredentialProviderTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `ClientCredentialProviderTests.swift`, inside `struct ClientCredentialProviderTests`:

```swift
    @Test("A provider that does not override the refresh seam declines to refresh")
    func refreshSeamDefaultsToDeclining() async throws {
        let provider = BearerCredentialProvider { "abc" }

        let refreshed = await provider.credentialHeaders(
            afterRejection: CredentialRejectedError(code: .invalid)
        )

        #expect(refreshed == nil)
    }

    @Test("An overriding provider supplies replacement headers")
    func refreshSeamOverrideSuppliesHeaders() async throws {
        let provider = RefreshingProvider(refreshedTo: "fresh")

        let refreshed = await provider.credentialHeaders(
            afterRejection: CredentialRejectedError(code: .invalid)
        )

        #expect(refreshed?.count == 1)
        #expect(refreshed?.first?.field == "Authorization")
        #expect(refreshed?.first?.value == "Bearer fresh")
    }
```

And at file scope, beside the existing `private actor TokenVault`:

```swift
/// A provider that refreshes on rejection and **persists** the result, so a later
/// `credentialHeaders()` yields the refreshed credential (spec §4.1).
private struct RefreshingProvider: ClientCredentialProvider {
    let vault: TokenVault
    let refreshedTo: String

    init(refreshedTo: String, initial: String? = nil) {
        self.refreshedTo = refreshedTo
        self.vault = TokenVault(token: initial)
    }

    func credentialHeaders() async throws -> [(field: String, value: String)] {
        guard let token = await vault.token else { return [] }
        return [(field: "Authorization", value: "Bearer \(token)")]
    }

    func credentialHeaders(afterRejection: CredentialRejectedError) async -> [(field: String, value: String)]? {
        await vault.rotate(to: refreshedTo)
        return [(field: "Authorization", value: "Bearer \(refreshedTo)")]
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ClientCredentialProviderTests`
Expected: FAIL — `value of type 'BearerCredentialProvider' has no member 'credentialHeaders(afterRejection:)'`

- [ ] **Step 3: Add the requirement and its default**

In `ClientCredentialProvider.swift`, add to the `public protocol ClientCredentialProvider` body, after `credentialHeaders()` (currently line 62):

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

Then, immediately after the protocol's closing brace:

```swift

public extension ClientCredentialProvider {
    // A *requirement* with a default, not an extension-only method: `MVVMEnvironment`
    // holds the provider as `(any ClientCredentialProvider)?`, and an extension-only
    // method binds to the default through the existential — the override would never run.
    func credentialHeaders(afterRejection: CredentialRejectedError) async -> [(field: String, value: String)]? {
        nil
    }
}
```

- [ ] **Step 4: Extend `BearerCredentialProvider`'s DocC**

`BearerCredentialProvider` deliberately does **not** override the seam — it is built from a token closure with no refresh capability. Add to its DocC, after the "When the closure yields `nil`…" paragraph:

```swift
/// This provider never refreshes on rejection: a refused credential throws to the
/// caller. To recover from server-side rotation, conform your own type and implement
/// ``ClientCredentialProvider/credentialHeaders(afterRejection:)``.
```

- [ ] **Step 5: Run tests**

Run: `swift test --filter ClientCredentialProviderTests`
Expected: PASS (5 tests)

- [ ] **Step 6: Verify additivity — the whole suite still builds and passes**

Run: `swift build && swift test`
Expected: PASS. Any conformance that failed to compile means the default was not applied correctly.

- [ ] **Step 7: Format, lint, commit**

```bash
swiftformat . && swiftlint
git add Sources/FOSMVVM/Protocols/ClientCredentialProvider.swift Tests/FOSMVVMTests/Protocols/ClientCredentialProviderTests.swift
git commit -m "feat(credential): add credentialHeaders(afterRejection:) refresh seam"
```

---

## Task 2: Split header composition from the send (pure refactor)

No behavior changes. This exists so Task 3 can wrap **only the send** — see spec §5.1 and §5.2.

**Files:**
- Modify: `Sources/FOSMVVM/Protocols/ServerRequest+Fetch.swift:178-213`

- [ ] **Step 1: Confirm the baseline is green**

Run: `swift test --filter ClientCredentialRoundTripTests`
Expected: PASS (3 tests). These are the regression net for this refactor.

- [ ] **Step 2: Replace the method**

Replace lines **178-213** — the range **starts at the `@discardableResult` attribute**, not at
the `func` line. The replacement block below re-declares it; replacing from 179 leaves two
attributes and fails to compile.

```swift
    @discardableResult
    internal func processRequestCapturingRegistrations(mvvmEnv: MVVMEnvironment) async throws -> [ModelIdentity] {
        do {
            let headers = try await credentialedRequestHeaders(mvvmEnv: mvvmEnv)

            return try await sendCapturingRegistrations(headers: headers, mvvmEnv: mvvmEnv)
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
    }
```

(Replace only lines 178-213 — line 214's `}` already closes the `public extension`. Do not add another.)

Then add a new file-scope extension after that `public extension`'s closing brace:

```swift
private extension ServerRequest {
    /// The static headers: `Accept` (when the response carries no body) followed by
    /// `MVVMEnvironment.requestHeaders`.
    func staticRequestHeaders(mvvmEnv: MVVMEnvironment) -> [(field: String, value: String)] {
        var headers = [(field: String, value: String)]()
        if ResponseBody.self == EmptyBody.self {
            headers.append((field: "Accept", value: "text/plain"))
        }
        for (key, value) in mvvmEnv.requestHeaders {
            headers.append((field: key, value: value))
        }

        return headers
    }

    /// The static headers with the provider's credential appended.
    func credentialedRequestHeaders(mvvmEnv: MVVMEnvironment) async throws -> [(field: String, value: String)] {
        var headers = staticRequestHeaders(mvvmEnv: mvvmEnv)
        // Credential headers append AFTER the static requestHeaders: headers apply to the
        // URLRequest in order (setValue), so on a duplicate field the per-request
        // credential wins. (Maintainer rationale — `//`, not `///`; it is not customer contract.)
        if let credentialProvider = mvvmEnv.clientCredentialProvider {
            headers += try await credentialProvider.credentialHeaders()
        }

        return headers
    }

    /// One send of this request with exactly these headers.
    func sendCapturingRegistrations(
        headers: [(field: String, value: String)],
        mvvmEnv: MVVMEnvironment
    ) async throws -> [ModelIdentity] {
        try await processRequestCapturingRegistrations(
            baseURL: mvvmEnv.serverBaseURL,
            headers: headers,
            session: mvvmEnv.session
        ).registrations
    }
}
```

- [ ] **Step 3: Verify no behavior changed**

Run: `swift test --filter ClientCredentialRoundTripTests`
Expected: PASS (3 tests, unchanged)

Run: `swift test`
Expected: PASS

- [ ] **Step 4: Format, lint, commit**

```bash
swiftformat . && swiftlint
git add Sources/FOSMVVM/Protocols/ServerRequest+Fetch.swift
git commit -m "refactor(fetch): split header composition from the send"
```

---

## Task 3: The bounded retry

**Files:**
- Modify: `Sources/FOSMVVM/Protocols/ServerRequest+Fetch.swift`
- Test: `Tests/FOSMVVMVaporTests/Protocols/ClientCredentialRoundTripTests.swift`

### The one thing that will silently break every test here

`withRunningServer` boots the app with **Vapor's stock error serializer**, under which a
rejection reaches the client as `DataFetchError.badStatus(401)` — *not* a typed
`CredentialRejectedError`. The typed error only crosses the wire when FOS `ErrorMiddleware`
replaces the stock one. This is already pinned both ways:
`ClientCredentialMiddlewareTests.swift:266` (stock → `badStatus`) and
`ClientCredentialMiddlewareTests.swift:380` (FOS → typed).

**Every `withRunningServer { app in … }` register-closure in this task must therefore open
with these two lines**, before `app.grouped(…)`:

```swift
            app.middleware = .init()
            app.middleware.use(FOSMVVMVapor.ErrorMiddleware.default(environment: app.environment))
```

Omit them and the retry tests fail for a reason that looks like the retry is broken: the
client never sees a `CredentialRejectedError`, so the seam is never consulted and
`attempts.count` stays 1.

- [ ] **Step 1: Add the test fixtures**

Task 4 needs `RefreshingCredentialProvider` from a *different* file in the same target, so it
goes in the shared home: `Tests/FOSMVVMVaporTests/Protocols/CredentialSeamFixtures.swift`
(members there are internal, not `private`).

**That forces a move.** `TokenVault` and `RequestTally` are currently `private` in
`ClientCredentialRoundTripTests.swift` — an internal fixture cannot reference them
across files. So:

1. **Cut** `TokenVault` (lines **154-166**, including its two doc-comment lines) and
   `RequestTally` (lines **178-185**) from `ClientCredentialRoundTripTests.swift`.
   **These two ranges are not contiguous** — `CredentialResolutionFailure` (168-169) and
   `FailingCredentialProvider` (171-176) sit between them and must stay, or
   `throwingProviderSurfacesAndSendsNothing` breaks. Cut by name, two separate ranges.
2. **Paste** both into `CredentialSeamFixtures.swift`, dropping the `private` keyword.
3. Leave the *separate* `private actor TokenVault` in
   `Tests/FOSMVVMTests/Protocols/ClientCredentialProviderTests.swift` alone — different test
   target, and its existing comment already notes the deliberate duplication.

Then add to `CredentialSeamFixtures.swift`:

```swift
/// The server's current good credential — rotates to model a server restart.
actor ServerCredential {
    private var current: String

    init(current: String) {
        self.current = current
    }

    func isCurrent(_ token: String) -> Bool {
        token == current
    }
}

/// A client provider that refreshes on rejection and **persists** the refreshed value,
/// so a later `credentialHeaders()` yields it too (spec §4.1).
struct RefreshingCredentialProvider: ClientCredentialProvider {
    let vault: TokenVault
    let refreshedTo: String?
    let refreshTally: RequestTally

    func credentialHeaders() async throws -> [(field: String, value: String)] {
        guard let token = await vault.token else { return [] }
        return [(field: "Authorization", value: "Bearer \(token)")]
    }

    func credentialHeaders(afterRejection: CredentialRejectedError) async -> [(field: String, value: String)]? {
        await refreshTally.increment()
        guard let refreshedTo else { return nil }
        await vault.rotate(to: refreshedTo)

        return [(field: "Authorization", value: "Bearer \(refreshedTo)")]
    }
}
```

Note the test counts requests **in the verifier**, not the controller: the middleware rejects before the route runs, so a controller-side tally would never see a refused request.

- [ ] **Step 2: Write the failing tests**

Add to `struct ClientCredentialRoundTripTests`:

```swift
    @Test("A refreshed credential retries once and succeeds")
    func refreshRetriesOnceAndSucceeds() async throws {
        let serverCredential = ServerCredential(current: "rotated")
        let attempts = RequestTally()
        let refreshes = RequestTally()

        try await withRunningServer { app in
            app.middleware = .init()
            app.middleware.use(FOSMVVMVapor.ErrorMiddleware.default(environment: app.environment))

            let protectedGroup = app.grouped(
                ClientCredentialMiddleware(verifier: BearerCredentialVerifier { token in
                    await attempts.increment()
                    return await serverCredential.isCurrent(token)
                })
            )
            try protectedGroup.register(collection: Self.headerEchoController())
        } _: { base in
            let env = Self.environment(
                base: base,
                provider: RefreshingCredentialProvider(
                    vault: TokenVault(token: "stale"),
                    refreshedTo: "rotated",
                    refreshTally: refreshes
                )
            )

            let request = ShowObservedHeadersRequest()
            try await request.processRequest(mvvmEnv: env)

            #expect(request.responseBody?.authorization == "Bearer rotated")
            #expect(await attempts.count == 2)
            #expect(await refreshes.count == 1)
        }
    }

    @Test("A provider that declines to refresh rethrows the original rejection, unretried")
    func decliningProviderRethrowsUnretried() async throws {
        let serverCredential = ServerCredential(current: "rotated")
        let attempts = RequestTally()
        let refreshes = RequestTally()

        try await withRunningServer { app in
            app.middleware = .init()
            app.middleware.use(FOSMVVMVapor.ErrorMiddleware.default(environment: app.environment))

            let protectedGroup = app.grouped(
                ClientCredentialMiddleware(verifier: BearerCredentialVerifier { token in
                    await attempts.increment()
                    return await serverCredential.isCurrent(token)
                })
            )
            try protectedGroup.register(collection: Self.headerEchoController())
        } _: { base in
            let env = Self.environment(
                base: base,
                provider: RefreshingCredentialProvider(
                    vault: TokenVault(token: "stale"),
                    refreshedTo: nil,
                    refreshTally: refreshes
                )
            )

            let request = ShowObservedHeadersRequest()
            do {
                try await request.processRequest(mvvmEnv: env)
                Issue.record("Expected the original rejection to be rethrown")
            } catch let rejection as CredentialRejectedError {
                // The observable proxy for "the rejection reached the caller intact".
                // The framework never re-mints with a different code, so this cannot
                // distinguish original from freshly-minted — and reaching for something
                // that could would be asserting the representation.
                #expect(rejection.code == .invalid)
            } catch {
                Issue.record("Expected CredentialRejectedError, got \(error)")
            }

            #expect(await attempts.count == 1)
            #expect(await refreshes.count == 1)
        }
    }

    @Test("A second rejection throws — the retry is never recursive")
    func secondRejectionThrowsWithoutFurtherRetry() async throws {
        let serverCredential = ServerCredential(current: "never-matches")
        let attempts = RequestTally()
        let refreshes = RequestTally()

        try await withRunningServer { app in
            app.middleware = .init()
            app.middleware.use(FOSMVVMVapor.ErrorMiddleware.default(environment: app.environment))

            let protectedGroup = app.grouped(
                ClientCredentialMiddleware(verifier: BearerCredentialVerifier { token in
                    await attempts.increment()
                    return await serverCredential.isCurrent(token)
                })
            )
            try protectedGroup.register(collection: Self.headerEchoController())
        } _: { base in
            let env = Self.environment(
                base: base,
                provider: RefreshingCredentialProvider(
                    vault: TokenVault(token: "stale"),
                    refreshedTo: "also-wrong",
                    refreshTally: refreshes
                )
            )

            let request = ShowObservedHeadersRequest()
            await #expect(throws: CredentialRejectedError.self) {
                try await request.processRequest(mvvmEnv: env)
            }

            #expect(await attempts.count == 2)
            #expect(await refreshes.count == 1)
        }
    }

    @Test("The retry preserves static requestHeaders, and the refreshed credential still wins")
    func retryPreservesStaticHeaders() async throws {
        let serverCredential = ServerCredential(current: "rotated")

        try await withRunningServer { app in
            app.middleware = .init()
            app.middleware.use(FOSMVVMVapor.ErrorMiddleware.default(environment: app.environment))

            let protectedGroup = app.grouped(
                ClientCredentialMiddleware(verifier: BearerCredentialVerifier { token in
                    await serverCredential.isCurrent(token)
                })
            )
            try protectedGroup.register(collection: Self.headerEchoController())
        } _: { base in
            let env = Self.environment(
                base: base,
                requestHeaders: [
                    "Authorization": "Bearer stale-static",
                    "X-Client-Marker": "static-value"
                ],
                provider: RefreshingCredentialProvider(
                    vault: TokenVault(token: "stale"),
                    refreshedTo: "rotated",
                    refreshTally: RequestTally()
                )
            )

            let request = ShowObservedHeadersRequest()
            try await request.processRequest(mvvmEnv: env)

            #expect(request.responseBody?.authorization == "Bearer rotated")
            #expect(request.responseBody?.clientMarker == "static-value")
        }
    }

    @Test("A rejection thrown by the provider itself does not open the refresh seam")
    func providerThrownRejectionDoesNotOpenSeam() async throws {
        let refreshes = RequestTally()
        let attempts = RequestTally()

        try await withRunningServer { app in
            app.middleware = .init()
            app.middleware.use(FOSMVVMVapor.ErrorMiddleware.default(environment: app.environment))

            let protectedGroup = app.grouped(
                ClientCredentialMiddleware(verifier: BearerCredentialVerifier { _ in
                    await attempts.increment()
                    return true
                })
            )
            try protectedGroup.register(collection: Self.headerEchoController())
        } _: { base in
            let env = Self.environment(
                base: base,
                provider: RejectingCredentialProvider(refreshTally: refreshes)
            )

            let request = ShowObservedHeadersRequest()
            await #expect(throws: CredentialRejectedError.self) {
                try await request.processRequest(mvvmEnv: env)
            }

            // No request was sent, so no server refusal occurred — the seam stays shut (spec §5.1)
            #expect(await attempts.count == 0)
            #expect(await refreshes.count == 0)
        }
    }
```

**The highest-value test in the set** — spec §5.2. A wrong-but-compiling implementation
(inlining the retry into the existing `catch` arm) passes every test above and fails only
this one, because Swift `catch` clauses do not chain and the retry's non-rejection error
would escape `requestErrorHandler`:

```swift
    @Test("A non-rejection error on the retry still reaches requestErrorHandler")
    func retryOperationErrorReachesHandler() async throws {
        let serverCredential = ServerCredential(current: "rotated")
        let handled = ErrorSink()

        try await withRunningServer { app in
            app.middleware = .init()
            app.middleware.use(FOSMVVMVapor.ErrorMiddleware.default(environment: app.environment))

            let protectedGroup = app.grouped(
                ClientCredentialMiddleware(verifier: BearerCredentialVerifier { token in
                    await serverCredential.isCurrent(token)
                })
            )
            // Admission succeeds on the retry; the CONTROLLER then throws a typed
            // operation error — the path that must land in requestErrorHandler.
            try protectedGroup.register(collection: RoundTripController<ShowOperationFailureRequest>(actions: [
                .show: { _, _ in throw StrictContractError(errorCode: 42) }
            ]))
        } _: { base in
            let env = MVVMEnvironment(
                currentVersion: SystemVersion.current,
                appBundle: Bundle.main,
                requestHeaders: [:],
                clientCredentialProvider: RefreshingCredentialProvider(
                    vault: TokenVault(token: "stale"),
                    refreshedTo: "rotated",
                    refreshTally: RequestTally()
                ),
                deploymentURLs: [
                    .production: base, .staging: base, .debug: base, .test: base
                ],
                session: nil,
                requestErrorHandler: { _, error in handled.record(error) }
            )

            let request = ShowOperationFailureRequest()
            // Swallowed into the handler, NOT thrown — that is the contract
            try await request.processRequest(mvvmEnv: env)

            #expect(handled.count == 1)
            #expect(handled.last is StrictContractError)
        }
    }

    @Test("Concurrent refused requests each consult the seam")
    func concurrentRejectionsEachConsultTheSeam() async throws {
        let serverCredential = ServerCredential(current: "rotated")
        let refreshes = RequestTally()
        let vault = TokenVault(token: "stale")

        try await withRunningServer { app in
            app.middleware = .init()
            app.middleware.use(FOSMVVMVapor.ErrorMiddleware.default(environment: app.environment))

            let protectedGroup = app.grouped(
                ClientCredentialMiddleware(verifier: BearerCredentialVerifier { token in
                    await serverCredential.isCurrent(token)
                })
            )
            try protectedGroup.register(collection: Self.headerEchoController())
        } _: { base in
            let env = Self.environment(
                base: base,
                provider: RefreshingCredentialProvider(
                    vault: vault,
                    refreshedTo: "rotated",
                    refreshTally: refreshes
                )
            )

            // Models several bound ViewModels refused at once (spec §4 DocC warning)
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<4 {
                    group.addTask {
                        let request = ShowObservedHeadersRequest()
                        try await request.processRequest(mvvmEnv: env)
                        #expect(request.responseBody?.authorization == "Bearer rotated")
                    }
                }
                try await group.waitForAll()
            }

            // Each refused request consults the seam independently — the framework does NOT
            // coalesce, which is exactly why the DocC tells providers to single-flight.
            // A request that starts after the vault has rotated is never refused, so the
            // lower bound is 1, not 4.
            #expect(await refreshes.count >= 1)
        }
    }
```

Plus two more fixtures at file scope. The first is a **verbatim copy** of `ErrorSink` from
`ClientCredentialMiddlewareTests.swift:528` — copy it, do not reinvent it. Its doc comment
explains why: `requestErrorHandler` is a plain sync `@Sendable` closure, so an actor plus a
`Task` would make the count assertion racy on exactly the failure path this test exists to
catch.

```swift
/// Synchronous, lock-guarded error sink — the handler is a plain @Sendable
/// closure; an actor + Task would make the count assertion racy on the
/// failure path this test exists to catch.
private final class ErrorSink: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [any Error] = []

    func record(_ error: any Error) {
        lock.withLock { errors.append(error) }
    }

    var count: Int {
        lock.withLock { errors.count }
    }

    var last: (any Error)? {
        lock.withLock { errors.last }
    }
}
```

and:

```swift
/// A provider whose own header composition throws a rejection — models a client-side
/// credential failure, which must NOT be treated as a server refusal (spec §5.1).
private struct RejectingCredentialProvider: ClientCredentialProvider {
    let refreshTally: RequestTally

    func credentialHeaders() async throws -> [(field: String, value: String)] {
        throw CredentialRejectedError(code: .missing)
    }

    func credentialHeaders(afterRejection: CredentialRejectedError) async -> [(field: String, value: String)]? {
        await refreshTally.increment()
        return [(field: "Authorization", value: "Bearer anything")]
    }
}
```

- [ ] **Step 3: Run to verify they fail**

Run: `swift test --filter ClientCredentialRoundTripTests`
Expected: the retry tests FAIL (no retry happens — `attempts.count == 1` where 2 expected, and the success cases throw). `providerThrownRejectionDoesNotOpenSeam` may already PASS — that is fine, it is a regression guard for Step 4.

**If a test fails with `DataFetchError.badStatus(401)` rather than a missing retry, the
`ErrorMiddleware` lines are missing from that test's register-closure.** See the warning at
the head of this task.

- [ ] **Step 4: Add the retry**

In `ServerRequest+Fetch.swift`, replace `processRequestCapturingRegistrations(mvvmEnv:)` — again
**including its `@discardableResult` attribute line**, since the block below re-declares it:

```swift
    @discardableResult
    internal func processRequestCapturingRegistrations(mvvmEnv: MVVMEnvironment) async throws -> [ModelIdentity] {
        do {
            // Composition sits outside the retry-aware `do`: a rejection thrown by the provider
            // itself is a client-side failure, not a server refusal, and must not open the
            // refresh seam.
            let headers = try await credentialedRequestHeaders(mvvmEnv: mvvmEnv)

            do {
                return try await sendCapturingRegistrations(headers: headers, mvvmEnv: mvvmEnv)
            } catch let rejection as CredentialRejectedError {
                guard
                    let provider = mvvmEnv.clientCredentialProvider,
                    let refreshed = await provider.credentialHeaders(afterRejection: rejection)
                else {
                    throw rejection
                }

                // Exactly one retry. A second rejection falls to the outer arm and reaches the
                // caller; a non-rejection failure falls to the outer `ServerRequestError` arm,
                // which `catch` clauses cannot do on their own (they do not chain).
                return try await sendCapturingRegistrations(
                    headers: staticRequestHeaders(mvvmEnv: mvvmEnv) + refreshed,
                    mvvmEnv: mvvmEnv
                )
            }
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
    }
```

- [ ] **Step 5: Run tests**

Run: `swift test --filter ClientCredentialRoundTripTests`
Expected: PASS (10 tests — 3 pre-existing + 7 new)

Run: `swift test`
Expected: PASS

- [ ] **Step 6: Format, lint, commit**

```bash
swiftformat . && swiftlint
git add Sources/FOSMVVM/Protocols/ServerRequest+Fetch.swift Tests/FOSMVVMVaporTests/Protocols/ClientCredentialRoundTripTests.swift
git commit -m "feat(fetch): retry once with a refreshed credential after rejection"
```

---

## Task 4: SSE 401 notification

**Files:**
- Modify: `Sources/FOSMVVM/SwiftUI Support/SSEInvalidationChannel.swift:130-132`
- Test: `Tests/FOSMVVMVaporTests/LiveInvalidation/ClientChannelRoundTripTests.swift`

**Read first:** `ClientChannelRoundTripTests.swift` in full — it uses `withServedFluentTestApp`,
**not** `withRunningServer`. Model the new tests on `non2xxOpenBacksOffWithoutConnected`
(`ClientChannelRoundTripTests.swift:105`) and on the existing `DenyAllMiddleware`
(`ClientChannelRoundTripTests.swift:177`). Do not invent a second harness.

- [ ] **Step 1: Write the failing test**

Two tests, both asserting the refresh tally only — never recovery behavior. The channel's own
recovery is back-off reconnect, which is already covered.

- **401 → the seam is consulted.** Serve 401 via `DenyAllMiddleware`; use
  `RefreshingCredentialProvider` from Task 3 (already internal in `CredentialSeamFixtures.swift`).
- **500 → the seam is not consulted.** Add a `Deny500Middleware` beside the existing
  `DenyAllMiddleware`.

**Assert `>= 1`, never `== 1`.** The reconnect loop retries indefinitely with growing back-off,
so the 401 test's tally keeps climbing for as long as the channel lives — an equality assertion
is flaky by construction. The 500 test asserts `== 0`, which is stable.

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ClientChannelRoundTripTests`
Expected: FAIL — refresh tally is 0 on the 401 case.

- [ ] **Step 3: Add the notification**

In `openAndStream`, replace lines 130-132:

```swift
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // A 401 is the credential being refused. Tell the provider so it can refresh and
            // persist; the return is discarded because the reconnect below re-consults
            // `credentialHeaders()` — the channel carries no credential state of its own.
            if http.statusCode == 401 {
                _ = await credentialProvider?.credentialHeaders(
                    afterRejection: CredentialRejectedError(code: .invalid)
                )
            }

            throw SSEStreamOpenError.badStatus(http.statusCode)
        }
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter ClientChannelRoundTripTests`
Expected: PASS

Run: `swift test`
Expected: PASS

- [ ] **Step 5: Format, lint, commit**

```bash
swiftformat . && swiftlint
git add "Sources/FOSMVVM/SwiftUI Support/SSEInvalidationChannel.swift" Tests/FOSMVVMVaporTests/LiveInvalidation/ClientChannelRoundTripTests.swift
git commit -m "feat(live): notify the credential seam when an SSE open is refused"
```

---

## Task 5: Docs and catalog

**Files:**
- Modify: `CHANGELOG.md`
- Modify: the API catalog, via skill

- [ ] **Step 1: Add the CHANGELOG entry**

Under a new `## 0.10.0` heading, following the format of the existing 0.9.0 entry. State the **contract**, never the representation:

```markdown
### Added

- `ClientCredentialProvider.credentialHeaders(afterRejection:)` — a refresh seam that
  lets a client recover from a server-side credential rotation. When a request is refused
  with `CredentialRejectedError`, the provider may supply replacement headers and the
  request is retried exactly once; returning `nil` (the default) preserves the previous
  behavior of throwing to the caller. Providers must persist the refreshed credential —
  later requests and live-channel reconnects consult `credentialHeaders()`.
```

- [ ] **Step 2: Update the API catalog**

Run the `fosutilities-api-catalog-update` skill — public API changed, so the catalog audit will otherwise fail in CI.

- [ ] **Step 3: Full verification**

```bash
swift build && swift test && swiftformat --lint . && swiftlint
```
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md .claude/skills/shared/api-catalog/
git commit -m "docs(changelog): stamp 0.10.0 credential refresh seam"
```

---

## Out of Scope

Per spec §8 — do not implement any of these in this plan:

- The `ViewModelView.swift:517` bind swallow. Its own arc.
- Any credential acquisition, storage, or refresh coalescing inside the framework.
- Retry for anything other than `CredentialRejectedError`.
- A credential bind edge (rejected in spec §1.2).
- Any change to the 0.7.0 rethrow contract.
