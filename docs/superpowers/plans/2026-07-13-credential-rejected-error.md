# CredentialRejectedError Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A credential rejection from `ClientCredentialMiddleware` crosses the wire as the typed `CredentialRejectedError` and is rethrown by `processRequest(mvvmEnv:)` — retiring the `DataFetchError.badStatus(401)` client contract.

**Architecture:** Per `docs/superpowers/specs/2026-07-13-credential-rejection-typed-error-design.md` (READ IT FIRST — it is the source of truth). Server: verifier throws the typed error; a new general `Encodable & AbortError` case in FOS `ErrorMiddleware` serves the typed body WITH the error's own status/headers. Client: an internal `WireError<E>` wrapper rides the ONE existing `errorType:` slot — `DataFetch`/FOSFoundation are untouched. The error self-identifies via a strict, internal discriminator.

**Tech Stack:** Swift 6 / Swift Testing (`.serialized` where suites share servers), Vapor, existing `withRunningServer` harness (`Tests/FOSMVVMVaporTests/Protocols/RoundTripHarness.swift`).

**Ground rules for every task:**
- TDD: failing test first, minimal code, green, commit. Granular local commits are fine (squash before PR).
- `swiftformat .` before each commit (auto-adds the license header to new files).
- NEVER publish the envelope shape (discriminator key/value) in DocC, CHANGELOG, or README — it is pinned ONLY by the `//` maintainer comment and internal tests.
- The working tree already carries UNRELATED uncommitted doc edits (errors-are-data doc sweep + this spec). Create the feature branch first; commit only files this plan touches; leave the rest untouched.

---

### Task 0: Branch + baseline

- [ ] **Step 1:** `git checkout -b feature/credential-rejected-error`
- [ ] **Step 2:** Run `swift test` — record the baseline is green before any change. Expected: all tests pass (≈1200+).

---

### Task 1: `CredentialRejectedError` (FOSMVVM)

**Files:**
- Create: `Sources/FOSMVVM/Protocols/CredentialRejectedError.swift`
- Test: `Tests/FOSMVVMTests/Protocols/CredentialRejectedErrorTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// CredentialRejectedErrorTests.swift
import FOSFoundation
import FOSMVVM
import Foundation
import Testing

@Suite("CredentialRejectedError contract")
struct CredentialRejectedErrorTests {
    @Test("Round-trips through JSON: code preserved, challenge transient")
    func roundTrip() throws {
        let original = CredentialRejectedError(code: .invalid, challenge: "Bearer")
        let decoded: CredentialRejectedError = try original.toJSON().fromJSON()

        #expect(decoded.code == .invalid)
        #expect(decoded.challenge == nil) // transient: never crosses the wire
    }

    @Test("Both codes round-trip")
    func bothCodes() throws {
        for code in [CredentialRejectedError.Code.missing, .invalid] {
            let decoded: CredentialRejectedError =
                try CredentialRejectedError(code: code).toJSON().fromJSON()
            #expect(decoded.code == code)
        }
    }

    @Test("Does NOT decode from bodies lacking the envelope")
    func strictDecode() {
        // Vapor's stock abort body, a plain reason string, and an empty object
        // must all fail — nothing puns into the rejection.
        for body in [
            #"{"error":true,"reason":"Unauthorized"}"#,
            #""Invalid bearer credential""#,
            "{}"
        ] {
            let decoded: CredentialRejectedError? = try? body.fromJSON()
            #expect(decoded == nil, "must not decode from: \(body)")
        }
    }

    @Test("Forward-compat: the committed wire form still decodes")
    func forwardCompat() throws {
        // INTERNAL representation pin (golden blob). The ONE place the envelope
        // shape is asserted — see the maintainer comment beside CodingKeys.
        let committedWireForm = #"{"__fosServerError":"credentialRejected","code":"invalid"}"#
        let decoded: CredentialRejectedError = try committedWireForm.fromJSON()
        #expect(decoded.code == .invalid)
    }
}
```

- [ ] **Step 2:** Run `swift test --filter CredentialRejectedErrorTests` — Expected: FAIL (type does not exist).

- [ ] **Step 3: Implement**

```swift
// CredentialRejectedError.swift
import Foundation

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
///     case .missing: break // no credential was presented — check the
///                          // MVVMEnvironment's clientCredentialProvider
///     case .invalid: break // presented but refused — refresh the credential
///                          // and retry (safe: the operation never ran)
///     }
/// }
/// ```
///
/// The rejection happens **before** the operation runs, so retrying after
/// recovery never duplicates the operation's effects.
///
/// This error always throws to the call site — it is never routed to
/// ``MVVMEnvironment/requestErrorHandler``.
public struct CredentialRejectedError: ServerRequestError {
    /// Why the credential seam rejected the request
    ///
    /// `.missing` — no credential accompanied the request; typically the client
    /// has no `ClientCredentialProvider` configured (or it returned no headers).
    /// `.invalid` — a credential was presented and the server's verifier refused
    /// it; refresh the credential and retry.
    public enum Code: String, Codable, Sendable {
        case missing
        case invalid
    }

    /// Why the request was rejected
    public let code: Code

    /// The authentication challenge the verifier answers with (for example
    /// `"Bearer"`), used server-side to dress the response's
    /// `WWW-Authenticate` header. Never crosses the wire — always `nil` on
    /// a decoded value.
    public let challenge: String?

    /// Creates the rejection thrown by a `ServerCredentialVerifier`
    ///
    /// - Parameters:
    ///   - code: Why the request was rejected
    ///   - challenge: The scheme for the response's `WWW-Authenticate`
    ///     header (default: none)
    public init(code: Code, challenge: String? = nil) {
        self.code = code
        self.challenge = challenge
    }

    // Wire envelope — INTERNAL detail; never publish in DocC/CHANGELOG/README.
    // The discriminator key + fixed value make the decode strict: init(from:)
    // fails unless both match, so nothing puns into (or out of) this type.
    // Shape pinned by CredentialRejectedErrorTests.forwardCompat.
    private enum CodingKeys: String, CodingKey {
        case discriminator = "__fosServerError"
        case code
    }

    private static let discriminatorValue = "credentialRejected"

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .discriminator) == Self.discriminatorValue else {
            throw DecodingError.dataCorruptedError(
                forKey: .discriminator,
                in: container,
                debugDescription: "Not a credential rejection"
            )
        }
        self.code = try container.decode(Code.self, forKey: .code)
        self.challenge = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.discriminatorValue, forKey: .discriminator)
        try container.encode(code, forKey: .code)
    }
}
```

- [ ] **Step 4:** Run `swift test --filter CredentialRejectedErrorTests` — Expected: PASS.
- [ ] **Step 5:** `swiftformat . && git add Sources/FOSMVVM/Protocols/CredentialRejectedError.swift Tests/FOSMVVMTests/Protocols/CredentialRejectedErrorTests.swift && git commit -m "feat(FOSMVVM): CredentialRejectedError — the credential seam's typed rejection"`

---

### Task 2: `WireError<E>` internal decode wrapper (FOSMVVM)

**Files:**
- Create: `Sources/FOSMVVM/Protocols/WireError.swift`
- Test: `Tests/FOSMVVMTests/Protocols/WireErrorTests.swift`

- [ ] **Step 1: Write the failing tests** (internal type → `@testable import`; this is coverage of internal plumbing, not the public contract)

```swift
// WireErrorTests.swift
import FOSFoundation
@testable import FOSMVVM
import Foundation
import Testing

private struct StrictError: ServerRequestError {
    let errorCode: Int
}

@Suite("WireError decode precedence")
struct WireErrorTests {
    @Test("A rejection body decodes .surface — even when E is EmptyError")
    func rejectionBeatsEmptyError() throws {
        let rejection = try CredentialRejectedError(code: .invalid).toJSON()

        let strict: WireError<StrictError> = try rejection.fromJSON()
        guard case .surface(let error) = strict else {
            Issue.record("Expected .surface, got \(strict)"); return
        }
        #expect(error.code == .invalid)

        // EmptyError decodes from ANYTHING — the wrapper must claim the
        // rejection FIRST (this retires the documented swallow).
        let permissive: WireError<EmptyError> = try rejection.fromJSON()
        guard case .surface = permissive else {
            Issue.record("EmptyError swallowed the rejection"); return
        }
    }

    @Test("A request-error body decodes .response")
    func responseErrorPassesThrough() throws {
        let wire: WireError<StrictError> = try #"{"errorCode":42}"#.fromJSON()
        guard case .response(let error) = wire else {
            Issue.record("Expected .response, got \(wire)"); return
        }
        #expect(error.errorCode == 42)
    }

    @Test("A body matching neither type fails to decode")
    func neitherFallsThrough() {
        let wire: WireError<StrictError>? = try? #"{"unrelated":true}"#.fromJSON()
        #expect(wire == nil)
    }
}
```

- [ ] **Step 2:** Run `swift test --filter WireErrorTests` — Expected: FAIL (type does not exist).

- [ ] **Step 3: Implement**

```swift
// WireError.swift
import Foundation

// The client-side decode order for a ServerRequest error body: the well-known
// surface errors (closed, FOS-owned list — CredentialRejectedError today) are
// tried STRICTLY before the request's own ResponseError. Passed to DataFetch
// as the ONE existing `errorType:` — FOSFoundation stays untouched; add a
// future surface error HERE, nowhere else.
enum WireError<E: ServerRequestError>: Error, Decodable {
    case surface(CredentialRejectedError)
    case response(E)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let rejection = try? container.decode(CredentialRejectedError.self) {
            self = .surface(rejection)
        } else {
            self = try .response(container.decode(E.self))
        }
    }
}
```

- [ ] **Step 4:** Run `swift test --filter WireErrorTests` — Expected: PASS.
- [ ] **Step 5:** `swiftformat . && git add Sources/FOSMVVM/Protocols/WireError.swift Tests/FOSMVVMTests/Protocols/WireErrorTests.swift && git commit -m "feat(FOSMVVM): WireError — surface-before-response error decode order"`

---

### Task 3: Transport dressing — `ErrorMiddleware` `Encodable & AbortError` case + `AbortError` conformance (FOSMVVMVapor)

**Files:**
- Create: `Sources/FOSMVVMVapor/CredentialRejectedError+Vapor.swift`
- Modify: `Sources/FOSMVVMVapor/Middleware/ErrorMiddleware.swift:72` (new first case) and its type DocC
- Test: `Tests/FOSMVVMVaporTests/Middleware/ErrorMiddlewareDressingTests.swift`

- [ ] **Step 1: Write the failing test** — model on `ClientCredentialMiddlewareTests`' `withRunningServer` usage (real socket; `.serialized` if the harness requires it — mirror the existing suite's traits)

```swift
// ErrorMiddlewareDressingTests.swift
//
// ErrorMiddleware transport-dressing contract: an error that is BOTH Encodable
// and AbortError is served with its typed body AND its own status/headers; a
// plain Encodable error keeps the typed body with 400 (unchanged).

import FOSFoundation
import FOSMVVM
import FOSMVVMVapor
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import Vapor

private struct DressedError: ServerRequestError, AbortError {
    let errorCode: Int
    var status: HTTPResponseStatus { .conflict }          // 409 — distinctive
    var headers: HTTPHeaders { ["X-Dressed": "yes"] }
    var reason: String { "dressed" }
}

private struct PlainEncodableError: ServerRequestError {
    let errorCode: Int
}

@Suite("ErrorMiddleware dressing (running server)", .serialized)
struct ErrorMiddlewareDressingTests {
    @Test("Encodable & AbortError: typed body + its own status and headers")
    func dressedErrorKeepsStatusAndBody() async throws {
        try await withRunningServer { app in
            app.middleware = .init()
            app.middleware.use(FOSMVVMVapor.ErrorMiddleware.default(environment: app.environment))
            app.get("boom") { _ -> String in throw DressedError(errorCode: 7) }
        } _: { base in
            let (status, body, headers) = try await rawGet(base.appendingPathComponent("boom"))
            #expect(status == 409)
            #expect(headers["X-Dressed"] == "yes")
            let decoded: DressedError? = try? body.fromJSON()
            #expect(decoded?.errorCode == 7)
        }
    }

    @Test("Plain Encodable: typed body + 400 (existing contract unchanged)")
    func plainEncodableKeeps400() async throws {
        try await withRunningServer { app in
            app.middleware = .init()
            app.middleware.use(FOSMVVMVapor.ErrorMiddleware.default(environment: app.environment))
            app.get("boom") { _ -> String in throw PlainEncodableError(errorCode: 9) }
        } _: { base in
            let (status, body, _) = try await rawGet(base.appendingPathComponent("boom"))
            #expect(status == 400)
            let decoded: PlainEncodableError? = try? body.fromJSON()
            #expect(decoded?.errorCode == 9)
        }
    }
}
```

Write a file-private helper `rawGet(_ url: URL, headers: [String: String] = [:], readHeaders: [String]) async throws -> (status: Int, body: String, headers: [String: String])` using the same URLSession-continuation shape as `ClientCredentialMiddlewareTests.send` (`ClientCredentialMiddlewareTests.swift:260-287`) — do NOT try to reuse `send` itself: it is `private static`, hard-codes the `/protected` path, and returns only the `WWW-Authenticate` header. This helper takes a full URL; resolve each returned header with `http.value(forHTTPHeaderField:)` (case-insensitive) rather than indexing `allHeaderFields` — key capitalization differs between Darwin and FoundationNetworking (a Linux-only flake otherwise).

> **Encoder note:** `req.localizingEncoder` throws unless
> `app.localizationStore` is set (`Request+FOS.swift:169-176`). The
> `withRunningServer` harness sets it (`RoundTripHarness.swift:42`), so these
> tests are covered — but any fixture built WITHOUT `withRunningServer` must
> set the store itself (see Task 6).

- [ ] **Step 2:** Run `swift test --filter ErrorMiddlewareDressingTests` — Expected: `dressedErrorKeepsStatusAndBody` FAILS (status is 400 today, headers lost); `plainEncodableKeeps400` PASSES (pins the unchanged contract).

- [ ] **Step 3: Implement** — in `ErrorMiddleware.swift`, insert the new case as the FIRST case *inside* the `switch error {` (which opens at line 72 — the case goes at line 73, before `case let encodable as any Encodable:`); mirror the existing Encodable branch exactly, differing only in status/headers:

```swift
            case let encodableAbort as any (Encodable & AbortError):
                do {
                    let encoder = try req.localizingEncoder

                    var abortHeaders = encodableAbort.headers
                    abortHeaders.replaceOrAdd(
                        name: HTTPHeaders.Name.contentType.description,
                        value: "application/json;charset=utf-8"
                    )
                    (reason, errorData, status, headers, source) = try (
                        "",
                        encodableAbort.toJSONData(encoder: encoder),
                        encodableAbort.status,
                        abortHeaders,
                        .capture()
                    )
                } catch {
                    (reason, errorData, status, headers, source) = (
                        encodableAbort.reason,
                        nil,
                        encodableAbort.status,
                        encodableAbort.headers,
                        .capture()
                    )
                }
```

Update `ErrorMiddleware`'s type DocC with the contract sentence from the spec §5. Then create the conformance:

```swift
// CredentialRejectedError+Vapor.swift
import FOSMVVM
import Vapor

/// Dresses the rejection for the transport: `401 Unauthorized` with the
/// verifier's authentication challenge (for example `WWW-Authenticate:
/// Bearer`). The response *body* remains the typed error — FOSMVVM clients
/// decode and rethrow it; the status exists for proxies, logs, and RFC 7235
/// conformance, never for client branching.
extension CredentialRejectedError: AbortError {
    public var status: HTTPResponseStatus { .unauthorized }

    public var headers: HTTPHeaders {
        guard let challenge else { return [:] }
        return ["WWW-Authenticate": challenge]
    }

    public var reason: String {
        // Constant — a rejection reason must never echo the presented credential
        "Credential rejected"
    }
}
```

- [ ] **Step 4:** Run `swift test --filter ErrorMiddlewareDressingTests` — Expected: PASS (both).
- [ ] **Step 5:** Run `swift test --filter ClientCredentialMiddlewareTests` — Expected: PASS (nothing server-side has changed yet; this guards ordering).
- [ ] **Step 6:** `swiftformat . && git add -A Sources/FOSMVVMVapor Tests/FOSMVVMVaporTests && git commit -m "feat(FOSMVVMVapor): Encodable & AbortError dressing case; CredentialRejectedError 401 conformance"`

---

### Task 4: Server rejection path — verifier throws typed, middleware wraps (FOSMVVMVapor)

**Files:**
- Modify: `Sources/FOSMVVMVapor/Middleware/ClientCredentialMiddleware.swift:89-94` (respond), `:132-147` (BearerCredentialVerifier.verify), and the type DocC (spec §5/§9)
- Test: extend `Tests/FOSMVVMVaporTests/Middleware/ClientCredentialMiddlewareTests.swift`

- [ ] **Step 1: Write the failing wire-level test** (add to the existing suite)

```swift
    @Test("Under FOS ErrorMiddleware, a rejection body IS the typed CredentialRejectedError")
    func rejectionBodyIsTypedUnderFOSErrorMiddleware() async throws {
        try await withRunningServer { app in
            app.middleware = .init()
            app.middleware.use(FOSMVVMVapor.ErrorMiddleware.default(environment: app.environment))
            Self.registerProtectedRoute(app, isValid: { _ in false })
        } _: { base in
            let rejected = try await Self.send(
                to: base,
                headers: ["Authorization": "Bearer nope"]
            )

            #expect(rejected.status == 401)                       // transport dressing
            #expect(rejected.wwwAuthenticate == "Bearer")          // RFC 7235 preserved
            let typed: CredentialRejectedError? = try? rejected.body.fromJSON()
            #expect(typed?.code == .invalid)                       // the semantics

            let missing = try await Self.send(to: base, headers: [:])
            let missingTyped: CredentialRejectedError? = try? missing.body.fromJSON()
            #expect(missingTyped?.code == .missing)
        }
    }
```

- [ ] **Step 2:** Run `swift test --filter ClientCredentialMiddlewareTests/rejectionBodyIsTypedUnderFOSErrorMiddleware` — Expected: FAIL (body is Vapor/FOS reason text today; typed decode nil).

- [ ] **Step 3: Implement.** In `BearerCredentialVerifier.verify`, replace each `Abort` 1:1 — same guards, same branch semantics:

```swift
    public func verify(headers: HTTPHeaders) async throws {
        guard let token = headers.bearerAuthorization?.token else {
            throw CredentialRejectedError(code: .missing, challenge: "Bearer")
        }

        guard await isValid(token) else {
            throw CredentialRejectedError(code: .invalid, challenge: "Bearer")
        }
    }
```

In `ClientCredentialMiddleware.respond`, wrap any non-typed verifier throw (the shipped verifier contract is "throw to reject"):

```swift
    public func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        // Ensure that the presented credential admits the request
        do {
            try await verifier.verify(headers: request.headers)
        } catch let rejection as CredentialRejectedError {
            throw rejection
        } catch {
            // The verifier contract is "throw to reject" — any throw is a
            // rejection; custom verifiers throw CredentialRejectedError
            // directly to carry richer intent (code, challenge).
            throw CredentialRejectedError(code: .invalid)
        }

        return try await next.respond(to: request)
    }
```

Rewrite the type DocC's "Client-Side Contract" + "Known limitation" sections per spec §5, and update `ServerCredentialVerifier`'s DocC ("typically `Abort(.unauthorized)`" → throw `CredentialRejectedError`; wrapping otherwise).

- [ ] **Step 4:** Run `swift test --filter ClientCredentialMiddlewareTests` — Expected: the new test PASSES; wire-level tests (401, no-echo, WWW-Authenticate, per-request, custom-verifier, parse edges) PASS; the two client-contract tests (`rejectionSurfacesAsBadStatus401ToTheClient`, `emptyErrorResponseSwallowsThe401`) still PASS (client not yet wired — the envelope doesn't decode into `StrictContractError`, and `EmptyError` still decodes anything).
  - **Watch:** the wire tests run Vapor's STOCK middleware — a thrown `CredentialRejectedError` must still produce 401 + `WWW-Authenticate` there via its `AbortError` conformance. If `wwwAuthenticate` assertions fail, the conformance headers aren't reaching the stock serializer — fix the conformance, not the tests.
- [ ] **Step 5:** `swiftformat . && git add Sources/FOSMVVMVapor/Middleware/ClientCredentialMiddleware.swift Tests/FOSMVVMVaporTests/Middleware/ClientCredentialMiddlewareTests.swift && git commit -m "feat(FOSMVVMVapor): credential rejections are served as typed CredentialRejectedError"`
  - **Staging rule (applies to EVERY commit in this plan):** the working tree carries pre-existing UNRELATED edits (`Sources/FOSMVVM/Protocols/ServerRequest.swift` DocC sweep, `.claude-plugin/plugin.json`, several `.claude/` docs). NEVER use bare `git add -A` / `git add .` — stage only the exact paths each step lists.

---

### Task 5: Client decode path + handler bypass (FOSMVVM) — reshapes the client contract

**Files:**
- Modify: `Sources/FOSMVVM/Protocols/ServerRequest+Fetch.swift:120-147` (errorType + unwrap), `:192` (bypass), `MVVMEnvironment.swift` (requestErrorHandler DocC — 5 sites, see Step 3d)
- Test: reshape the two client-contract tests in `ClientCredentialMiddlewareTests.swift`; add bypass + precedence + skew tests there

- [ ] **Step 1: Reshape/write the failing tests.** Replace `rejectionSurfacesAsBadStatus401ToTheClient` and `emptyErrorResponseSwallowsThe401` (same fixtures, new contract), and add three tests:

```swift
    @Test("On a FOSMVVM client, a rejection surfaces as the typed CredentialRejectedError")
    func rejectionSurfacesTypedToTheClient() async throws {
        try await withRunningServer { app in
            try Self.registerRejectingClientContractRoutes(app)
        } _: { base in
            let env = Self.environment(
                base: base,
                provider: BearerCredentialProvider { "revoked-token" }
            )

            let request = ShowStrictErrorReplyRequest()
            do {
                try await request.processRequest(mvvmEnv: env)
                Issue.record("Expected CredentialRejectedError, but the request succeeded")
            } catch let rejection as CredentialRejectedError {
                #expect(rejection.code == .invalid)
            } catch {
                Issue.record("Expected CredentialRejectedError, got \(error)")
            }

            #expect(request.responseBody == nil)
        }
    }

    @Test("EmptyError no longer swallows a rejection — the typed error wins")
    func emptyErrorNoLongerSwallowsRejections() async throws {
        try await withRunningServer { app in
            try Self.registerRejectingClientContractRoutes(app)
        } _: { base in
            let env = Self.environment(
                base: base,
                provider: BearerCredentialProvider { "revoked-token" }
            )

            let request = ShowGrantedReplyRequest() // ResponseError == EmptyError
            do {
                try await request.processRequest(mvvmEnv: env)
                Issue.record("Expected CredentialRejectedError, but the request succeeded")
            } catch let rejection as CredentialRejectedError {
                #expect(rejection.code == .invalid)
            } catch {
                Issue.record("Expected CredentialRejectedError, got \(error) — the swallow is back")
            }
        }
    }

    @Test("A rejection bypasses requestErrorHandler; operation errors still route to it")
    func rejectionBypassesRequestErrorHandler() async throws {
        try await withRunningServer { app in
            try Self.registerRejectingClientContractRoutes(app)
            // ADMITTED route whose controller throws an operation error — the
            // positive half: ordinary ResponseErrors still route to the handler.
            try Self.registerAdmittedThrowingRoute(app)
        } _: { base in
            let handled = ErrorSink() // synchronous, lock-guarded — see support code
            let env = Self.environment(
                base: base,
                provider: BearerCredentialProvider { "revoked-token" },
                requestErrorHandler: { _, error in handled.record(error) }
            )

            // (a) A rejection THROWS to the caller — never reaches the handler
            let rejected = ShowStrictErrorReplyRequest()
            do {
                try await rejected.processRequest(mvvmEnv: env)
                Issue.record("Expected CredentialRejectedError")
            } catch is CredentialRejectedError {
                // thrown to the caller — NOT swallowed into the handler
            } catch {
                Issue.record("Expected CredentialRejectedError, got \(error)")
            }
            #expect(handled.count == 0)

            // (b) An operation's own ResponseError still routes to the handler
            // (handler swallows: no throw, responseBody stays nil)
            let admittedEnv = Self.environment(
                base: base,
                provider: BearerCredentialProvider { "valid-token" },
                requestErrorHandler: { _, error in handled.record(error) }
            )
            let failing = ShowOperationFailureRequest()
            try await failing.processRequest(mvvmEnv: admittedEnv)
            #expect(handled.count == 1)
            #expect(handled.last is StrictContractError)
            #expect(failing.responseBody == nil)
        }
    }

    @Test("Precedence: a permissive custom ResponseError does not swallow a rejection")
    func permissiveCustomResponseErrorDoesNotSwallow() async throws {
        try await withRunningServer { app in
            try Self.registerRejectingClientContractRoutes(app) // also registers the permissive fixture
        } _: { base in
            let env = Self.environment(
                base: base,
                provider: BearerCredentialProvider { "revoked-token" }
            )

            let request = ShowPermissiveErrorReplyRequest() // ResponseError decodes loose JSON
            do {
                try await request.processRequest(mvvmEnv: env)
                Issue.record("Expected CredentialRejectedError")
            } catch let rejection as CredentialRejectedError {
                #expect(rejection.code == .invalid)
            } catch {
                Issue.record("Expected CredentialRejectedError, got \(error)")
            }
        }
    }

    @Test("Skew fallback: a plain 401 without the envelope behaves as today")
    func plain401WithoutEnvelopeFallsBack() async throws {
        try await withRunningServer { app in
            // Vapor's STOCK middleware — the old-server wire shape (no envelope)
            let protected = app.grouped(
                ClientCredentialMiddleware(verifier: BearerCredentialVerifier { _ in false })
            )
            try protected.register(collection: RoundTripController<ShowStrictErrorReplyRequest>(actions: [
                .show: { _, _ in GrantedReply(message: "granted") }
            ]))
        } _: { base in
            let env = Self.environment(
                base: base,
                provider: BearerCredentialProvider { "revoked-token" }
            )

            let request = ShowStrictErrorReplyRequest()
            do {
                try await request.processRequest(mvvmEnv: env)
                Issue.record("Expected a failure")
            } catch DataFetchError.badStatus(httpStatusCode: let code) {
                #expect(code == 401) // pre-envelope fallback, unchanged
            } catch {
                Issue.record("Expected badStatus(401) fallback, got \(error)")
            }
        }
    }
```

Support code to add to the suite's fixtures:

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

    var count: Int { lock.withLock { errors.count } }
    var last: (any Error)? { lock.withLock { errors.last } }
}

/// A permissive error — its single optional field decodes from ANY JSON
/// object, like EmptyError but user-defined (spec §6 test 7).
private struct PermissiveContractError: ServerRequestError {
    let note: String?
}

/// Same .show shape as the other fixtures; ResponseError is permissive.
private final class ShowPermissiveErrorReplyRequest: ServerRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias Fragment = EmptyFragment
    typealias RequestBody = EmptyBody
    typealias ResponseBody = GrantedReply
    typealias ResponseError = PermissiveContractError

    var action: ServerRequestAction { .show }
    var responseBody: GrantedReply?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil,
         requestBody: EmptyBody? = nil, responseBody: GrantedReply? = nil) {
        self.responseBody = responseBody
    }
}

/// Same .show shape; the CONTROLLER throws StrictContractError after
/// admission — drives the handler-routing positive half.
private final class ShowOperationFailureRequest: ServerRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias Fragment = EmptyFragment
    typealias RequestBody = EmptyBody
    typealias ResponseBody = GrantedReply
    typealias ResponseError = StrictContractError

    var action: ServerRequestAction { .show }
    var responseBody: GrantedReply?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil,
         requestBody: EmptyBody? = nil, responseBody: GrantedReply? = nil) {
        self.responseBody = responseBody
    }
}
```

And two fixture registrations:
- extend `registerRejectingClientContractRoutes(_:)` to also register
  `RoundTripController<ShowPermissiveErrorReplyRequest>`;
- add `registerAdmittedThrowingRoute(_:)`: assumes FOS `ErrorMiddleware.default`
  is already installed globally by `registerRejectingClientContractRoutes`
  (called first in the same fixture) — registers ONLY a new protected group
  with a `ClientCredentialMiddleware` admitting `"valid-token"`, containing
  `RoundTripController<ShowOperationFailureRequest>` whose `.show` action
  `throw`s `StrictContractError(errorCode: 99)`.
- extend `Self.environment(base:provider:)` with an optional
  `requestErrorHandler:` parameter (default nil), passed through to
  `MVVMEnvironment`.

Note the stock-middleware fixture: `plain401WithoutEnvelopeFallsBack` must NOT install FOS ErrorMiddleware — after Task 4 the middleware throws `CredentialRejectedError` and Vapor's stock serializer emits `{"error":true,"reason":"Credential rejected"}` — no envelope, by construction.

Also update the suite's header comment block (lines 17–36) to describe the NEW contract.

- [ ] **Step 2:** Run `swift test --filter ClientCredentialMiddlewareTests` — Expected: the reshaped/new tests FAIL (client still throws `badStatus`/`EmptyError`); `plain401WithoutEnvelopeFallsBack` PASSES (pins the fallback).

- [ ] **Step 3: Implement.** In `ServerRequest+Fetch.swift`:

(a) Both `send` calls (`:128` and `:140`): `errorType: WireError<Self.ResponseError>.self`.

(b) Wrap the body of `processRequestCapturingRegistrations(baseURL:headers:session:)` so wrapper values unwrap to their payload before propagating — add around the existing `dataFetch.send` calls (both branches):

```swift
        // WireError is decode plumbing — unwrap so callers catch the payload
        // (the surface rejection or the request's typed ResponseError).
        do {
            ... existing sends ...
        } catch let wire as WireError<Self.ResponseError> {
            switch wire {
            case .surface(let rejection): throw rejection
            case .response(let error): throw error
            }
        }
```

(c) In `processRequestCapturingRegistrations(mvvmEnv:)` (`:192`), add BEFORE the `ServerRequestError` catch:

```swift
        } catch let rejection as CredentialRejectedError {
            // A surface rejection always reaches the caller — recovery
            // (refresh credential, retry) is a call-site decision.
            throw rejection
        } catch let error as ServerRequestError {
```

(d) `MVVMEnvironment.swift` — append the bypass note to the `requestErrorHandler` DocC at EVERY occurrence: the property (`:118`) AND all four initializers' parameter docs (`:228`, `:282`, `:365`, `:431` — grep `requestErrorHandler:` to be sure none is missed): surface rejections (``CredentialRejectedError``) are never routed here — they always throw to the caller.

- [ ] **Step 4:** Run `swift test --filter ClientCredentialMiddlewareTests` — Expected: ALL PASS.
- [ ] **Step 5:** Run `swift test` (full suite) — Expected: green; any request-flow test that previously relied on rejection swallowing surfaces here.
- [ ] **Step 6:** `swiftformat . && git add Sources/FOSMVVM/Protocols/ServerRequest+Fetch.swift "Sources/FOSMVVM/SwiftUI Support/MVVMEnvironment.swift" Tests/FOSMVVMVaporTests/Middleware/ClientCredentialMiddlewareTests.swift && git commit -m "feat(FOSMVVM): rejections decode typed and throw past requestErrorHandler"` (staging rule: exact paths only — the tree carries unrelated edits)

---

### Task 6: Test-harness surface — `TestingServerRequestResponse.credentialRejection` (FOSTestingVapor)

**Files:**
- Modify: `Sources/FOSTestingVapor/TestingServerRequestResponse.swift:23-42`
- Test: `Tests/FOSMVVMVaporTests/TestingServerRequestResponseTests.swift` (this target already exercises the harness; keep the new suite beside the middleware tests if a better home doesn't exist)

- [ ] **Step 1a: Promote the localization stub.** `RoundTripLocalizationStore` in `Tests/FOSMVVMVaporTests/Protocols/RoundTripHarness.swift` is `private`; change it to `internal` (target-visible) so this suite can reuse it. **This is load-bearing:** `req.localizingEncoder` throws unless `app.localizationStore` is set (`Request+FOS.swift:169-176`) — without it, the dressing case falls back to a plaintext body and `credentialRejection` never decodes.

- [ ] **Step 1b: Write the failing test** — an `app.testing().test(request…)` run against a protected route:

```swift
@Suite("TestingServerRequestResponse credential rejection")
struct TestingServerRequestResponseTests {
    @Test("A rejection populates credentialRejection; error stays nil")
    func rejectionIsTyped() async throws {
        let app = try await Application.make(.testing)
        do {
            app.localizationStore = RoundTripLocalizationStore() // REQUIRED — see Step 1a
            app.middleware = .init()
            app.middleware.use(FOSMVVMVapor.ErrorMiddleware.default(environment: app.environment))
            let protected = app.grouped(
                ClientCredentialMiddleware(verifier: BearerCredentialVerifier { _ in false })
            )
            try protected.register(collection: RoundTripController<ShowGrantedReplyRequest>(actions: [
                .show: { _, _ in GrantedReply(message: "granted") }
            ]))

            try await app.testing().test(ShowGrantedReplyRequest()) { response in
                #expect(response.status == .unauthorized)          // transport contract
                #expect(response.credentialRejection?.code == .invalid) // the semantics
                #expect(response.error == nil)                     // EmptyError does NOT swallow
                #expect(response.body == nil)
            }
        } catch {
            try await app.asyncShutdown(); throw error
        }
        try await app.asyncShutdown()
    }
}
```

(Adjust `app.localizationStore` spelling to however `RoundTripHarness.swift:42` sets it — copy that line verbatim. Fixtures `ShowGrantedReplyRequest`/`GrantedReply`/`RoundTripController` may need `fileprivate` → target-visibility moves; if so, move them into the existing shared fixture file used by `RoundTripHarness.swift` rather than duplicating.)

- [ ] **Step 2:** Run `swift test --filter TestingServerRequestResponseTests` — Expected: FAIL (`credentialRejection` does not exist).

- [ ] **Step 3: Implement** in `TestingServerRequestResponse`:

```swift
    /// The received ``CredentialRejectedError``, if the protected route
    /// rejected the request's credential — assert rejections on this typed
    /// value, never on `status` alone
    public let credentialRejection: CredentialRejectedError?

    init(response: TestingHTTPResponse) throws {
        self.status = response.status
        self.headers = response.headers
        self.body = try? response.body.fromJSON()
        // Same decode order as the client: the surface rejection is claimed
        // first so a permissive ResponseError (EmptyError) can't swallow it.
        let rejection: CredentialRejectedError? = try? response.body.fromJSON()
        self.credentialRejection = rejection
        self.error = rejection == nil ? (try? response.body.fromJSON()) : nil
    }
```

- [ ] **Step 4:** Run `swift test --filter TestingServerRequestResponseTests` — Expected: PASS.
- [ ] **Step 5:** `swiftformat . && git add Sources/FOSTestingVapor/TestingServerRequestResponse.swift Tests/FOSMVVMVaporTests/TestingServerRequestResponseTests.swift Tests/FOSMVVMVaporTests/Protocols/RoundTripHarness.swift && git commit -m "feat(FOSTestingVapor): typed credentialRejection on TestingServerRequestResponse"` (add any fixture file moved in Step 1b; exact paths only)

---

### Task 7: Documentation sweep

**Files:**
- Modify: `CHANGELOG.md` (Unreleased), `.claude/docs/FOSMVVMArchitecture.md` (§ ServerRequestError — add the surface-error paragraph), `.claude/skills/shared/api-catalog/FOSMVVM.md` (new `CredentialRejectedError` entry), `.claude/skills/shared/api-catalog/FOSMVVMVapor.md` (replace the ClientCredentialMiddleware "Limitation" paragraph and the ErrorMiddleware entry's contract), `.claude/skills/shared/api-catalog/FOSTesting.md` (harness entry gains `credentialRejection`)

- [ ] **Step 1:** CHANGELOG under `## [Unreleased]` — contract statements ONLY, never the envelope shape:

```markdown
### Added

- **`CredentialRejectedError`** (FOSMVVM / FOSMVVMVapor). A credential rejection from
  `ClientCredentialMiddleware` now crosses the wire as a typed, `Codable` error and is
  rethrown by `processRequest(mvvmEnv:)` — catch it to recover (`.missing` /
  `.invalid`); it always throws to the caller (never `requestErrorHandler`). Requires
  FOS `ErrorMiddleware.default` (already the documented configuration). Retires the
  `DataFetchError.badStatus(401)` client contract and the documented `EmptyError`
  rejection-swallow. `TestingServerRequestResponse` gains `credentialRejection`.

### Changed

- **`ErrorMiddleware`**: an error conforming to both `Encodable` and `AbortError` is
  now served with its typed body AND its own status/headers (previously such errors
  were served `400 Bad Request`). Plain `Encodable` errors are unchanged.
```

- [ ] **Step 2:** Apply the catalog/architecture edits (follow `fosutilities-api-catalog` entry style; the reach-for index line in the repo `CLAUDE.md` API-catalog section may need a "credential rejection / typed 401" pointer). Run the catalog audit if CI expects it (`fosutilities-api-catalog-update` skill describes it) — plugin version is ALREADY bumped to 2.14.0 uncommitted in this working tree; do not bump again for this same unreleased batch.
- [ ] **Step 3: Stage CAREFULLY — three of these files already carry unrelated hunks.** `.claude/docs/FOSMVVMArchitecture.md`, `.claude/skills/shared/api-catalog/FOSMVVM.md`, and `.claude/skills/shared/api-catalog/FOSMVVMVapor.md` hold the pre-existing errors-are-data sweep: use `git add -p <file>` on those three and stage ONLY the hunks this task wrote (CredentialRejectedError content). The clean files stage whole: `git add CHANGELOG.md .claude/skills/shared/api-catalog/FOSTesting.md CLAUDE.md` (drop any of these not actually touched). Then `git commit -m "docs: CredentialRejectedError contract across CHANGELOG, catalog, architecture doc"`.

---

### Task 8: Final verification

- [ ] **Step 1:** `swift test` — full suite green.
- [ ] **Step 2:** `swiftformat . --lint` → 0 files require formatting; `swiftlint` → no new violations.
- [ ] **Step 3:** Grep the diff for envelope leakage — two checks, both must come back empty:
  - `git diff main -- '*.md' 'Sources/**/*.docc/**' | grep -n "__fosServerError"` (published prose)
  - `git diff main -- 'Sources/**/*.swift' | grep -nE '^\+\s*///.*__fosServerError'` (DocC lines inside source — `///` is published; the `//` maintainer pin and the test fixtures are the ONLY legitimate occurrences)
- [ ] **Step 4:** Review `git log --oneline main..HEAD`; squash to a few logical commits per repo convention BEFORE any PR. **Do NOT open a PR — David reviews first (hard gate).**
