# C8a — Controller Composition Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compose C8's guarded read/write pipelines onto the general `ServerRequestController` dispatch layer as framework-supplied processors, making `register(request:)` pre-specializing sugar and deleting the parallel routing scaffold.

**Architecture:** `ServerRequestController` (the shipped 0.3.0–0.4.0 general layer) is reconciled to the C8 binding — its default `boot(routes:)` groups on `TRequest.path`, binds `VaporServerRequestMiddleware<TRequest>` (the single URL-parse point), maps **all six** `ServerRequestAction` verbs to HTTP methods, and hands each processor **one complete typed instance** (query + sort + decoded body). The four `register(request:)` doors keep their exact public signatures and boot-check batteries but now instantiate an internal `GuardedRequestController<TRequest>` whose `actions` are the guarded pipelines (`serve` / `serveUpdate` / `serveCreate` / `serveDelete`). `VaporServerRequestHost` and the inline write-route registrations are deleted — the routing scaffold exists once.

**Tech Stack:** Swift 6 / Vapor 4 / Swift Testing (`withFluentTestApp` harness) in the worktree `/Users/david/Repository/FOS/FOSUtilities-model-identity` (branch `spec/model-identity-live-invalidation`).

---

## David's rulings (2026-07-05, all live — do not relitigate)

1. **Two-arg `ActionProcessor`**: `@Sendable (Vapor.Request, TRequest) async throws -> TRequest.ResponseBody`. The bound instance carries query, sort, and (on body verbs) the decoded `requestBody`. Processors that need the body unwrap it; `ServerRequestControllerError.missingRequestBody` is the throw.
2. **`invalidAction` repurposed**: with all six verbs mapped, its old throw site dies; it now fires at boot when one controller's `actions` binds two actions to the same HTTP method at its one URL (`.delete` + `.destroy` — both DELETE). Two deletion semantics need two request types (two URLs).
3. **Renames**: file `Vapor Support/UpdateController.swift` → `Vapor Support/ServerRequestController.swift` ('Update' is a 0.3.0 fossil); internal class `GuardedRequestController<TRequest>` (distinct word shape vs `ServerRequestController`; "guarded" is the handoff's vocabulary for the framework pipelines).

## Rationale (implementer prose — none of this goes in DocC)

- **Why the two-arg processor**: the three-arg shape existed because the old layer hand-constructed `TRequest(query: nil, …)` and had to smuggle the body alongside. Once the middleware binds the real instance and the boot decodes the body into it, a separate body parameter is a second way to say one thing (bloat per the minimal-surface gate). The `EmptyBody` force-cast (`UpdateController.swift:95`) dies with it: on body verbs whose `RequestBody == EmptyBody` there is nothing to decode and `requestBody` stays `nil`.
- **Why guards stay in the sugar doors, not the controller**: the boot-check battery (write-at-read-door reject, AppState builder, plan/candidate derivation, Replace/Destroy "not yet supported") expresses what the *guarded* specialization promises, not what general dispatch requires. A hand-written PUT processor via the general mechanism is legitimate (the handoff pins this) — only the guarded doors defer Replace.
- **Why the route shape cannot change**: 552 tests pin GET/PATCH/POST/DELETE at `SR.path` with the middleware bound. The controller's `boot` must produce byte-identical routing (same group, same middleware, same body-stream strategy) — the refactor is plumbing-beneath.
- **Known pre-existing incoherence, out of scope**: `ControllerRouting.path(for:)` (`ControllerRouting.swift:53–65`) appends `/create`, `/delete`, `/destroy` to client URLs while `boot` registers every verb at `baseURL`. Predates C8. Flagged in the arch doc (Task 4); not touched.
- **Sequential cache contract**: every processor runs inside the one Vapor handler task, exactly as the deleted inline closures did — no concurrency shape changes.
- **`Controller` protocol (`Protocols/Controller.swift`) is NOT part of this refactor** — it is a separate older mechanism (`ResolvableViewModelRequest`); leave untouched.

## File Structure

- **Rename + rewrite**: `Sources/FOSMVVMVapor/Vapor Support/UpdateController.swift` → `Sources/FOSMVVMVapor/Vapor Support/ServerRequestController.swift` (protocol + default boot + error enum + private runner)
- **Create**: `Sources/FOSMVVMVapor/Vapor Support/GuardedRequestController.swift` (internal, ~20 lines)
- **Modify**: `Sources/FOSMVVMVapor/Vapor Support/ViewModelRequest.swift` (four doors swap scaffold → controller; `writeRouteGroup` deleted)
- **Delete**: `Sources/FOSMVVMVapor/Vapor Support/VaporServerRequestHost.swift` lines 22–49 (the host class + RouteCollection) — the `serve(_:)` / `resolveAppState` extension (lines 51–109) MOVES to a new home `Sources/FOSMVVMVapor/Vapor Support/ServeRequest.swift` (it is the shared serve point, not host plumbing)
- **Test (new)**: `Tests/FOSMVVMVaporTests/Protocols/ServerRequestControllerTests.swift`
- **Docs**: arch doc §C8 note, C8 spec §11, C8 plan deviations, CHANGELOG, DocC on the touched public symbols

---

### Task 1: Reconcile `ServerRequestController` (two-arg processor, six verbs, middleware binding)

**Files:**
- Rename: `Sources/FOSMVVMVapor/Vapor Support/UpdateController.swift` → `ServerRequestController.swift` (git mv)
- Test: `Tests/FOSMVVMVaporTests/Protocols/ServerRequestControllerTests.swift` (create)

- [ ] **Step 1: `git mv` the file, commit the pure rename**

```bash
cd /Users/david/Repository/FOS/FOSUtilities-model-identity
git mv "Sources/FOSMVVMVapor/Vapor Support/UpdateController.swift" "Sources/FOSMVVMVapor/Vapor Support/ServerRequestController.swift"
swift build 2>&1 | tail -3   # still compiles (rename only)
git commit -m "refactor(FOSMVVMVapor): rename UpdateController.swift to ServerRequestController.swift — the file holds the general controller protocol"
```

- [ ] **Step 2: Write the failing contract tests**

Create `Tests/FOSMVVMVaporTests/Protocols/ServerRequestControllerTests.swift`. Model the fixtures on `VaporResponseBodyFactoryTests.swift`'s existing request fixtures (reuse its patterns: `withFluentTestApp`, typed requests with a Query). The tests assert **through public routes only** — never internals:

```swift
// ServerRequestControllerTests.swift — contract tests for the GENERAL dispatch layer:
// a hand-written controller (no guarded pipelines) gets middleware binding, all six
// verbs, and the one-URL/one-method boot check.

import FOSMVVM
@testable import FOSMVVMVapor   // @testable ONLY for internal fixture reuse, never for assertions
import FOSTestingVapor
import Testing
import Vapor
import VaporTesting

@Suite("ServerRequestController general dispatch (C8a)", .serialized)
struct ServerRequestControllerTests {
    // 1. A hand-written .show processor receives the middleware-BOUND instance:
    //    GET <path>?query=… → processor sees query parsed (old layer: nil).
    @Test func showProcessorReceivesBoundQuery() async throws { /* register controller
        with .show echoing bound.query into the response body; assert echoed value */ }

    // 2. .delete registers DELETE (old layer threw invalidAction at boot).
    @Test func deleteActionRegistersDELETE() async throws { /* .delete processor returns
        a marker body; DELETE <path> → 200 + marker */ }

    // 3. Body verb: .update processor receives the DECODED body on the instance.
    @Test func updateProcessorReceivesDecodedBody() async throws { /* PATCH with JSON
        body; processor echoes bound.requestBody?.field */ }

    // 4. Boot check: actions carrying BOTH .delete and .destroy throw
    //    ServerRequestControllerError.invalidAction at registration.
    @Test func deletePlusDestroyFailsFastAtBoot() async throws { /* expect throw */ }

    // 5. EmptyBody request on a body verb: no decode, requestBody nil, processor runs.
    @Test func emptyBodyVerbSkipsDecode() async throws { /* .update on an
        EmptyBody-RequestBody request; empty HTTP body; processor asserts
        bound.requestBody == nil and returns a marker */ }
}
```

Write the five test bodies fully (fixture requests need: a Query type carrying one string, a Decodable RequestBody with one field, marker ResponseBody conforming to `ServerRequestBody`). Follow the existing fixture naming in the test target (Harbor vocabulary).

- [ ] **Step 3: Run to verify the new tests fail**

```bash
swift test --filter ServerRequestControllerTests 2>&1 | tail -5
```
Expected: compile failure (two-arg closures don't match the shipped three-arg `ActionProcessor`) — that IS the failing state.

- [ ] **Step 4: Rewrite `ServerRequestController.swift`**

Replace the protocol + boot + runner with (keep the license header; write customer-framed DocC — drafts below are normative):

```swift
import FOSFoundation
import FOSMVVM
import Vapor

/// The general dispatch layer for serving a ``ServerRequest``: conform, supply one
/// processor per ``ServerRequestAction``, and register the controller as a route
/// collection — grouping, HTTP-method mapping, body decoding, and typed request
/// binding are derived for you, once.
///
/// ```swift
/// final class ReplaceBerthController: ServerRequestController {
///     typealias TRequest = ReplaceBerthRequest
///
///     let actions: [ServerRequestAction: ActionProcessor] = [
///         .replace: { req, bound in
///             guard let body = bound.requestBody else {
///                 throw ServerRequestControllerError.missingRequestBody
///             }
///             // full request power; return the response body
///         }
///     ]
/// }
///
/// // boot:
/// try app.routes.register(collection: ReplaceBerthController())
/// ```
///
/// Prefer ``Vapor/Application/register(request:)`` — it instantiates this mechanism
/// pre-specialized with the framework's guarded pipelines (declared loads, write
/// gates, the refresh fall-through). Reach for a hand-written controller when an
/// operation falls outside the guarded verbs (e.g. `ReplaceRequest`, multi-record
/// operations): the same general mechanism serves both.
public protocol ServerRequestController: AnyObject, ControllerRouting, RouteCollection, SendableMetatype {
    associatedtype TRequest: ServerRequest

    /// Serves one action: receives the raw `Vapor.Request` (full request power) and
    /// the **bound** typed request — query and sort parsed from the URL, and, on a
    /// body-carrying verb, the decoded `requestBody`.
    typealias ActionProcessor = @Sendable (
        Vapor.Request,
        TRequest
    ) async throws -> TRequest.ResponseBody

    /// The actions this controller serves, each mapped to its HTTP method at
    /// ``ControllerRouting/baseURL`` (`.show` GET · `.create` POST · `.replace` PUT ·
    /// `.update` PATCH · `.delete`/`.destroy` DELETE).
    var actions: [ServerRequestAction: ActionProcessor] { get }
}

public extension ServerRequestController {
    static var baseURL: String { TRequest.path }

    func boot(routes: RoutesBuilder) throws {
        // One URL carries one handler per HTTP method: .delete and .destroy both ride
        // DELETE, so one controller may register only one of them (two deletion
        // semantics are two request types — two URLs).
        if actions.keys.contains(.delete), actions.keys.contains(.destroy) {
            throw ServerRequestControllerError.invalidAction(.destroy)
        }

        let groupName = Self.baseURL == "/" ? "" : Self.baseURL
        let group = routes
            .grouped(.constant(groupName))
            .grouped(VaporServerRequestMiddleware<TRequest>())
        let bodyStrategy = TRequest.RequestBody.maxBodySize.bodyStreamStrategy

        for (action, processor) in actions {
            switch action {
            case .show:
                group.get { req in
                    try await runServerRequest(req, decodesBody: false, processor: processor)
                }
            case .create:
                group.on(.POST, body: bodyStrategy) { req in
                    try await runServerRequest(req, decodesBody: true, processor: processor)
                }
            case .replace:
                group.on(.PUT, body: bodyStrategy) { req in
                    try await runServerRequest(req, decodesBody: true, processor: processor)
                }
            case .update:
                group.on(.PATCH, body: bodyStrategy) { req in
                    try await runServerRequest(req, decodesBody: true, processor: processor)
                }
            case .delete, .destroy:
                group.on(.DELETE) { req in
                    try await runServerRequest(req, decodesBody: false, processor: processor)
                }
            }
        }
    }
}

public enum ServerRequestControllerError: Error, CustomDebugStringConvertible {
    case invalidAction(ServerRequestAction)
    case missingRequestBody

    public var debugDescription: String {
        switch self {
        case .invalidAction(let action):
            "Invalid ServerRequestAction combination involving \(action): .delete and .destroy both map to HTTP DELETE at one URL — two deletion semantics need two request types. Register one of them on this controller."
        case .missingRequestBody:
            "Server request was missing its request body."
        }
    }
}

// MARK: Private Methods

/// Binds the complete typed request (the middleware parsed query + sort; a body verb
/// decodes `RequestBody` here) and runs the processor. `EmptyBody` requests decode
/// nothing — `requestBody` stays nil.
private func runServerRequest<TRequest: ServerRequest>(
    _ req: Vapor.Request,
    decodesBody: Bool,
    processor: @Sendable (Vapor.Request, TRequest) async throws -> TRequest.ResponseBody
) async throws -> Vapor.Response {
    let bound: TRequest = try req.requireServerRequest()

    let request: TRequest = if decodesBody, TRequest.RequestBody.self != EmptyBody.self {
        TRequest(
            query: bound.query,
            sort: bound.sort,
            fragment: bound.fragment,
            requestBody: try req.content.decode(TRequest.RequestBody.self),
            responseBody: nil
        )
    } else {
        bound
    }

    return try await processor(req, request)
        .buildResponse(req)
}
```

- [ ] **Step 5: Run the new tests + full suite**

```bash
swift test --filter ServerRequestControllerTests 2>&1 | tail -5   # 5 PASS
swift test 2>&1 | tail -3                                          # 557 green (552 + 5)
```

- [ ] **Step 6: swiftformat + swiftlint + commit**

```bash
swiftformat . && swiftlint --quiet
git add -A && git commit -m "feat(FOSMVVMVapor)!: ServerRequestController serves all six verbs with the middleware-bound typed instance (C8a)

BREAKING: ActionProcessor is now @Sendable (Vapor.Request, TRequest) — the bound
instance carries query, sort, and the decoded body; the separate RequestBody
parameter and the nil-query construction are gone. invalidAction now guards the
one-URL/one-method rule (.delete + .destroy on one controller)."
```

### Task 2: `GuardedRequestController` + compose the read door

**Files:**
- Create: `Sources/FOSMVVMVapor/Vapor Support/GuardedRequestController.swift`
- Create: `Sources/FOSMVVMVapor/Vapor Support/ServeRequest.swift` (the moved serve point)
- Delete: `Sources/FOSMVVMVapor/Vapor Support/VaporServerRequestHost.swift`
- Modify: `Sources/FOSMVVMVapor/Vapor Support/ViewModelRequest.swift:49-61` (read door)
- Modify: `Sources/FOSTestingVapor/VaporServerTestCase.swift:55-57` (the test harness constructs the deleted host)
- Modify: `Sources/FOSMVVMVapor/Protocols/VaporResponseBodyFactory.swift:59` (DocC link to the deleted host)

- [ ] **Step 1: Create `GuardedRequestController.swift`**

```swift
import FOSMVVM
import Vapor

// The pre-specialized controller register(request:) instantiates: the general
// dispatch mechanism carrying the framework's guarded pipelines as its processors.
// Guards live in the processors (and the register-door boot checks) — never in
// which door was walked through.
final class GuardedRequestController<TRequest: ServerRequest>: ServerRequestController {
    let actions: [ServerRequestAction: ActionProcessor]

    init(actions: [ServerRequestAction: ActionProcessor]) {
        self.actions = actions
    }
}
```

- [ ] **Step 2: Move the serve point; delete the host**

`git mv` is wrong here (half the file moves): create `ServeRequest.swift` containing the `extension Vapor.Request { serve(_:) / resolveAppState }` block **verbatim** from `VaporServerRequestHost.swift:51-109` (keep its DocC), then delete `VaporServerRequestHost.swift`.

- [ ] **Step 3: Swap the read door's registration**

In `ViewModelRequest.swift`, the read `register(request:)` body's last line changes:

```swift
// was: try routes.register(collection: VaporServerRequestHost<SR>())
try routes.register(collection: GuardedRequestController<SR>(actions: [
    .show: { req, bound in try await req.serve(bound) }
]))
```

(The three boot checks above it are unchanged.)

- [ ] **Step 4: Swap the FOSTestingVapor harness's registration**

`Sources/FOSTestingVapor/VaporServerTestCase.swift:55-57` constructs the deleted host. The file is DEBUG-gated and already `@testable import FOSMVVMVapor` (line 20), so the internal controller is reachable — a like-for-like swap, nothing widened:

```swift
// was: try app.routes.register(collection: VaporServerRequestHost<Request>())
try app.routes.register(collection: GuardedRequestController<Request>(actions: [
    .show: { req, bound in try await req.serve(bound) }
]))
```

Also repoint the DocC link at `Sources/FOSMVVMVapor/Protocols/VaporResponseBodyFactory.swift:59`: ``` ``VaporServerRequestHost`` ``` → the route registered by ``Vapor/Application/register(request:)`` (plain prose; the replacement type is internal so a symbol link can't target it).

- [ ] **Step 5: Full suite — read pipeline pinned by existing tests**

```bash
swift test 2>&1 | tail -3
```
Expected: 557 green, zero modified tests. Any read-path failure means the controller's routing differs from the host's — fix the controller, never the test.

- [ ] **Step 6: swiftformat + swiftlint + commit**

```bash
swiftformat . && swiftlint --quiet
git add -A && git commit -m "refactor(FOSMVVMVapor): the read door registers a GuardedRequestController — VaporServerRequestHost deleted; serve point moves to ServeRequest.swift (C8a)"
```

### Task 3: Compose the three write doors; delete the inline scaffold

**Files:**
- Modify: `Sources/FOSMVVMVapor/Vapor Support/ViewModelRequest.swift:79-144` (three write doors) and `:158-163` (delete `writeRouteGroup`)

- [ ] **Step 1: Swap the update door**

Replace the `writeRouteGroup(for:).on(.PATCH…)` block with:

```swift
try routes.register(collection: GuardedRequestController<SR>(actions: [
    .update: { req, bound in
        guard let body = bound.requestBody else {
            throw ServerRequestControllerError.missingRequestBody
        }
        return try await req.serveUpdate(bound, body: body)
    }
]))
```

- [ ] **Step 2: Swap the create door** (same shape: `.create:` + `serveCreate(bound, body: body)`)

- [ ] **Step 3: Swap the delete door**

```swift
try routes.register(collection: GuardedRequestController<SR>(actions: [
    .delete: { req, bound in try await req.serveDelete(bound) }
]))
```

- [ ] **Step 4: Delete `writeRouteGroup(for:)`** (`ViewModelRequest.swift:158-163`). Verify nothing else references it: `grep -rn writeRouteGroup Sources Tests` → empty.

- [ ] **Step 5: Full suite — the write pipeline + boot-check battery pinned by existing tests**

```bash
swift test 2>&1 | tail -3
```
Expected: 557 green, zero modified tests (verb–door coherence, create gate, refresh fall-through, token lint — all still pass through the composed doors).

- [ ] **Step 6: swiftformat + swiftlint + commit**

```bash
swiftformat . && swiftlint --quiet
git add -A && git commit -m "refactor(FOSMVVMVapor): write doors register GuardedRequestControllers — the inline route scaffold is deleted; the routing shape exists once (C8a)"
```

### Task 4: Docs reconciliation (same-branch obligations from the handoff)

**Files:**
- Modify: `docs/superpowers/specs/2026-07-03-authorized-container-data-loading-architecture.md` (§C8 forward note)
- Modify: `docs/superpowers/specs/2026-07-05-vapor-response-body-factory-design.md` (§11 amendment)
- Modify: `docs/superpowers/plans/2026-07-05-l1-c8-vapor-response-body-factory.md` (one deviation line)
- Modify: `CHANGELOG.md`
- Optional rename: `Tests/FOSMVVMVaporTests/Protocols/VaporServerRequestHostTests.swift` → `ServedRequestRouteTests.swift` (the named type no longer exists; tests unchanged)
- Comment-only tweak: `Tests/FOSMVVMVaporTests/Protocols/VaporResponseBodyFactoryTests.swift:17` says "Grows from VaporServerRequestHostTests" — update the name to match the rename (no test body changes)

- [ ] **Step 1: Arch doc §C8** — REWRITE the "second write door … disposition pending David" forward note to the recorded truth: the controller family is the **general dispatch layer**; C8's doors are framework-specialized controllers (`GuardedRequestController`); hand-written processors are the sanctioned home for operations the guarded verbs don't cover yet (Replace/destroy/multi-record), shrinking as future slices add guarded verbs. Add the `ControllerRouting.path(for:)` `/create`-`/delete`-`/destroy` vs `baseURL` incoherence as a recorded pre-existing flag.

- [ ] **Step 2: C8 spec §11** — append to the existing "Implementation-time amendments" block: the composition correction (parallel scaffold → processors on the general layer; two-arg `ActionProcessor`; six-verb map; David's three rulings).

- [ ] **Step 3: C8 plan** — one line in "Execution deviations (recorded)" pointing at this plan.

- [ ] **Step 4: CHANGELOG** — under Unreleased/Changed:

```markdown
- **BREAKING: `ServerRequestController` is the one general dispatch layer.**
  `ActionProcessor` is now `@Sendable (Vapor.Request, TRequest) async throws ->
  TRequest.ResponseBody` — the typed request arrives bound (query + sort parsed
  once by the request middleware; a body verb decodes `requestBody` onto it). All
  six `ServerRequestAction`s now map to HTTP methods (`.show` GET, `.delete`/
  `.destroy` DELETE join POST/PUT/PATCH); `register(request:)` and the write
  overloads are unchanged sugar that pre-specialize this mechanism with the
  framework's guarded pipelines. A controller listing both `.delete` and
  `.destroy` fails fast at boot (one URL, one DELETE handler).
```

- [ ] **Step 5: Full suite + audit-unchanged check + commit**

```bash
swift test 2>&1 | tail -3
swiftformat . && swiftlint --quiet
git add -A && git commit -m "docs: C8a recorded — controller family is the general dispatch layer; arch/spec/plan/CHANGELOG reconciled"
```

---

## Definition of Done

- [ ] All four register-door public signatures byte-identical; writer protocols / `VaporResponseBodyFactory` / `ProjectionContext` untouched (the `:59` DocC-link repoint is prose only, no declaration change)
- [ ] 552 pre-existing tests pass **unmodified** (baseline verified on the rebased worktree HEAD `d870d00`, 2026-07-05; the optional test-file rename changes no test body); + 5 new controller contract tests
- [ ] `grep -rn 'VaporServerRequestHost\|writeRouteGroup' Sources Tests` → empty (after the harness swap, the DocC repoint, and the optional test-file rename; a comment mention in the renamed test file is acceptable)
- [ ] Zero `package` in FOSMVVMVapor (`grep -rn 'package ' Sources/FOSMVVMVapor --include='*.swift'` → empty)
- [ ] `swiftformat` + `swiftlint` clean at every commit
- [ ] Docs: arch §C8 note rewritten, spec §11 amended, C8-plan deviation line, CHANGELOG entry
