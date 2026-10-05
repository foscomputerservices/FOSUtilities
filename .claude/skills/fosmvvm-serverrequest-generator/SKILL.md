---
name: fosmvvm-serverrequest-generator
description: Generate FOSMVVM ServerRequest types for CRUD operations and client-server communication. Scaffolds requests, response bodies, and typed error handling.
homepage: https://github.com/foscomputerservices/FOSUtilities
metadata: {"clawdbot": {"emoji": "🔌", "os": ["darwin", "linux"]}}
---

# FOSMVVM ServerRequest Generator

> **Read [`shared/functional-discipline.md`](../shared/functional-discipline.md) before proceeding.** Every rule below derives from it.

Generate ServerRequest types for client-server communication.

> **Architecture context:** See [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md) | [OpenClaw reference]({baseDir}/references/FOSMVVMArchitecture.md)

> **API catalog:** check [`../shared/api-catalog/FOSMVVM.md`](../shared/api-catalog/FOSMVVM.md) § Protocols and [`../shared/api-catalog/FOSFoundation.md`](../shared/api-catalog/FOSFoundation.md) § Coding, § Networking before hand-writing helpers.

---

## STOP AND READ THIS

**ServerRequest is THE way to communicate with an FOSMVVM server. No exceptions.**

```
┌──────────────────────────────────────────────────────────────────────┐
│                 ALL CLIENTS USE ServerRequest                         │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  iOS App:         Button tap    →  request.processRequest(mvvmEnv:)   │
│  macOS App:       Button tap    →  request.processRequest(mvvmEnv:)   │
│  WebApp:          JS → WebApp   →  request.processRequest(mvvmEnv:)   │
│  CLI Tool:        main()        →  request.processRequest(mvvmEnv:)   │
│  Data Collector:  timer/event   →  request.processRequest(mvvmEnv:)   │
│  Background Job:  cron trigger  →  request.processRequest(mvvmEnv:)   │
│                                                                       │
│  MVVMEnvironment holds: baseURL, headers, version, error handling     │
│  Configure ONCE at startup, use EVERYWHERE via processRequest()       │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘
```

### What You Must NEVER Do

> ← **Functional discipline:** the transport is part of the projection function, not per-call-site output — hand-rolling HTTP re-implements the function at every call site.

```swift
// ❌ WRONG - hardcoded URL
let url = URL(string: "http://server/api/users/123")!
var request = URLRequest(url: url)

// ❌ WRONG - string path
try await client.get("/api/users/\(id)")

// ❌ WRONG - manual JSON encoding
let json = try JSONEncoder().encode(body)
request.httpBody = json
```

```javascript
// ❌ WRONG - hardcoded fetch path
fetch('/api/users/123')

// ❌ WRONG - constructing URLs manually
fetch(`/api/ideas/${ideaId}/move`)
```

### What You Must ALWAYS Do

**Step 1: Configure MVVMEnvironment once at startup**

```swift
// CLI tool, background job, data collector - configure at startup
// Import your shared module to get SystemVersion.currentApplicationVersion
import ViewModels  // ← Your shared module (see FOSMVVMArchitecture.md)

let mvvmEnv = await MVVMEnvironment(
    currentVersion: .currentApplicationVersion,  // From shared module
    appBundle: Bundle.module,
    deploymentURLs: [.debug: URL(string: "http://localhost:8080")!]
)
// NOTE: Version headers (X-FOS-Version) are AUTOMATIC via SystemVersion.current
```

The shared module contains `SystemVersion+App.swift`:
```swift
// In your shared ViewModels module
public extension SystemVersion {
    static var currentApplicationVersion: Self { .v1_0 }
    static var v1_0: Self { .init(major: 1, minor: 0, patch: 0) }
}
```

**Step 2: Use processRequest(mvvmEnv:) everywhere**

```swift
// ✅ RIGHT - ServerRequest with MVVMEnvironment
let request = UserShowRequest(query: .init(userId: id))
try await request.processRequest(mvvmEnv: mvvmEnv)
let user = request.responseBody

// ✅ RIGHT - Create operation
let createRequest = IdeaCreateRequest(requestBody: .init(content: content))
try await createRequest.processRequest(mvvmEnv: mvvmEnv)
let newId = createRequest.responseBody?.id

// ✅ RIGHT - Update operation
let updateRequest = IdeaMoveRequest(requestBody: .init(ideaId: id, newStatus: status))
try await updateRequest.processRequest(mvvmEnv: mvvmEnv)
```

**The path is derived from the type name. The HTTP method comes from the protocol. You NEVER write URL strings. Configuration lives in MVVMEnvironment - you NEVER pass baseURL/headers to individual requests.**

---

## When to Use This Skill

- Implementing any client-server communication
- Adding CRUD operations (create, read, update, archive, destroy)
- Building data collectors or sync tools
- Any Swift code that needs to talk to the server

**If you're about to write `URLRequest` or a hardcoded path string, STOP and use this skill instead.**

---

## What ServerRequest Provides

| Concern | How ServerRequest Handles It |
|---------|------------------------------|
| URL Path | Derived from type name via `Self.path` (e.g., `IdeaMoveRequest` → `/idea_move`) |
| HTTP Method | Determined by `action.httpMethod` (ShowRequest=GET, CreateRequest=POST, etc.) |
| Request Body | `RequestBody` type, automatically JSON encoded via `requestBody?.toJSONData()` |
| Response Body | `ResponseBody` type, automatically JSON decoded into `responseBody` |
| Error Response | `ResponseError` type — the operation's *thrown* error carried across the wire; `processRequest` rethrows it client-side (see below) |
| Validation | `RequestBody: ValidatableModel` for write operations |
| Body Size Limits | `RequestBody.maxBodySize` for large uploads (files, images) |
| Type Safety | Compiler enforces correct types throughout |

---

## ResponseError Is the Operation's Throw, Not a Status Mapping

If there were no wire, the operation would be a local function call that
`throw`s a well-defined Swift error. `ResponseError` **is** that error.
`ServerRequestError` (`Error, Codable, Sendable`) exists so the throw can
happen *across the wire*:

- The server-side handler `throw`s the typed error
- It rides the response as `Codable` (via `ErrorMiddleware`)
- The client's `processRequest` rethrows the **same typed error**,
  as if the call had been local

**Design from the throw, never from the transport:**

- ✅ Ask: "what would this operation `throw` if it were local?" —
  that error (usually an enum-carrying struct) is the `ResponseError`
- ❌ Never ask: "what should a 401 / an HTTP status become?" —
  statuses are transport dressing; they carry no result semantics
- Clients branch by **catching the typed case** —
  never by reading an HTTP status back

### Credential rejection is already typed — do not design around it

A rejected credential reaches the client as `CredentialRejectedError`, a
FOS-owned error, **regardless of what your `ResponseError` is**. Catch it; never
branch on the 401.

This holds because of the wire's shape, not a decode order. Every error body
crosses inside one typed envelope (0.16.0) — exactly one of the surface
rejection or the request's own `ResponseError` — encoded by the server's
`ErrorMiddleware` and decoded by the client:

```swift
package enum WireError<E: ServerRequestError>: Error, Codable {
    case surface(CredentialRejectedError)
    case response(E)
}
```

The envelope names which one it carries, so nothing is tried and nothing can
be mistaken for anything else — a permissive `ResponseError` (`EmptyError`
decodes from anything) cannot swallow a rejection, and a request error with a
field named `reason` cannot pun into one. So:

- ✅ `EmptyError` is safe on a **read** request behind a credential middleware.
  It cannot swallow a rejection — the envelope carries the rejection in its own
  case, and `EmptyError` is only ever asked to decode the `response` case. (A
  `CreateRequest` or `UpdateRequest` cannot use it at all — see *A write
  request's ResponseError carries validations* below.)
- ❌ Do **not** add a permissive `String` field to a `ResponseError` "so a 401
  isn't swallowed." That was never a real risk, and the field buys nothing: a
  body that is not the envelope — Vapor's stock abort, a proxy's error page —
  never reaches your error type at all; it falls to the status path.

If your *read* operation has no well-defined throw, use `EmptyError`. A required
free-text `reason: String` is not a lighter-weight error — it is an error with
no vocabulary a client can branch on, which defeats the point of the type.

**Why this protects encapsulation:** an HTTP status is a raw,
publicly-mintable number — any failure can wear a 401, so routing result
semantics on one is the stringly-typed encapsulation break (see SOLID /
encapsulation in `CLAUDE.md`). The typed error IS the contract; the moment a
client sniffs a status, the error vocabulary you declared stops being the
whole contract.

**User-presentable errors conform to `LocalizableError`.** When the error will
be shown to the user (the common case — the client's `alert(error:)` presents
the screen's error binding), compose the `ResponseError` like a ViewModel:
`@LocalizableError` macro, `@LocalizedString`/`@LocalizedSubs` message
property, exposed as `localizedMessage`. `ErrorMiddleware` localizes the
message as it encodes the throw, so the client presents it with no
localization store of its own — the same encode-time localization every
ViewModel property gets (SRP: the error carries its meaning; presentation
never invents copy for it):

```swift
@LocalizableError
public struct ResponseError: ServerRequestError {
    public let maximum: Int

    @LocalizedSubs(substitutions: \.subs) public var errorMessage
    public var localizedMessage: any Localizable { errorMessage }

    private var subs: [String: any Localizable] {
        ["maximum": LocalizableInt(value: maximum)]
    }

    public init(maximum: Int) { self.maximum = maximum }
}
```

The YAML rides the request's existing localization file — keys derive from
the error's type + property names, exactly as ViewModel properties do.

### A write request's ResponseError carries validations

`CreateRequest` and `UpdateRequest` constrain their error type: `ResponseError: ValidatableViewModelRequestError`. This is a **protocol constraint, not a convention** — a create or update request that declares `EmptyError`, or a bespoke error of its own, does not compile.

`ValidationError` is the ready-made choice, and the right one unless the operation also throws something that is not a validation:

```swift
public final class CardCreateRequest: CreateRequest, @unchecked Sendable {
    public typealias ResponseError = ValidationError
    // …
}
```

What it buys: a validation failure raised **anywhere on the server** — the request body's own `Fields` rules, or the target model's `validateModel(in:)`, or a constraint the model claimed through `validationResult(for:)` — reaches the client as that one typed error, with the results inside. The view reads `error.validations`; nothing has to know which layer refused.

```swift
do {
    try await request.processRequest(mvvmEnv: mvvmEnv)
} catch let error as CardCreateRequest.ResponseError {
    validations.replace(with: error.validations)   // drives .withFormValidations()
}
```

When the operation genuinely has non-validation failure modes too, declare your own error and conform it to `ValidatableViewModelRequestError` — it needs a `validations: [ValidationResult]` property and an `init(validations:)`, and the framework fills that initializer in when a validation refuses the write.

**SOLID.** The constraint is **LSP** with **ISP** teeth: every write request is substitutable for every other at the framework's write path, which rethrows a server-side `ValidationError` as `SR.ResponseError(validations:)`. An error type that cannot carry validations breaks that substitution — and it breaks it *on the client*, at decode time, far from the request that declared it. The segregated protocol is what makes the requirement visible in the type, so the compiler catches it instead of a user seeing an unexplained failure.

---

## Request Protocol Selection

Choose based on the operation:

| Operation | Protocol | HTTP Method | RequestBody Required? |
|-----------|----------|-------------|----------------------|
| Read data | `ShowRequest` | GET | No |
| Read ViewModel | `ViewModelRequest` | GET | No |
| Create entity | `CreateRequest` | POST | Yes (ValidatableModel) |
| Update entity | `UpdateRequest` | PATCH | Yes (ValidatableModel) |
| Replace entity | (use `.replace` action) | PUT | Yes |
| Archive (row stays, marked deleted) | `ArchiveRequest` | DELETE | No |
| Destroy (row removed) | `DestroyRequest` | DELETE | No |

> The left column is the **protocol** you conform to (`CreateRequest`, `UpdateRequest`, …).
> That is NOT the name of your concrete type — see naming below.

`CreateRequest` and `UpdateRequest` additionally constrain `ResponseError` to a `ValidatableViewModelRequestError` — use `public typealias ResponseError = ValidationError` unless you have a reason not to.

## Archive or Destroy

Both ride the DELETE method, and they are different operations:

**Archive** leaves the model in place, marked deleted through its delete timestamp. Fluent's default queries stop returning it; the data is still there, still referable, still restorable.

**Destroy** removes the row. Nothing comes back.

**The delete-timestamp rule.** Registering an `ArchiveRequest` route for a model that declares no `@Timestamp(key: "deleted_at", on: .delete)` **fails at boot** with `ServerRequestControllerError.archiveUnsupported(request:model:)`. Without that column Fluent's `delete(on:)` would remove the row — a destroy wearing the archive verb — so the mismatch is refused where it is cheap to see:

```swift
// in the model
@Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?
```

The fix is one of two things, and never a third: give the model the delete timestamp, or serve a `DestroyRequest` instead. There is no flag that makes an archive remove a row.

The container must grant the operation. An archive needs `ContainerOperation.archiveRecords`, which a wildcard grant does cover; a destroy needs `destroyRecords`, which **no** wildcard covers — removal is always granted by name.

**SOLID.** Two protocols rather than one protocol with a "force" parameter is **ISP**: the operation the client asked for is legible in the type, and the client cannot ask for one and get the other. The boot check is **LSP** — every registered `ArchiveRequest` really does archive, so no caller has to check whether *this* model's archive happens to destroy.

---

## Naming the Concrete Request Type

**Concrete write/action requests are noun-first: `<Noun><Verb>Request`.**

| Operation | ✅ Concrete type | ❌ Not |
|-----------|-----------------|--------|
| Create a User | `UserCreateRequest` | `CreateUserRequest` |
| Update a User | `UserUpdateRequest` | `UpdateUserRequest` |
| Replace a User (PUT) | `UserReplaceRequest` | `ReplaceUserRequest` |
| Archive a User | `UserArchiveRequest` | `ArchiveUserRequest` |
| Semantic action | `IdeaMoveRequest` | `MoveIdeaRequest` |
| Raw-data read | `UserShowRequest` | — |

Noun-first keeps an entity's whole request family cohesive and sortable
(`UserArchiveRequest`/`UserCreateRequest`/`UserShowRequest`/`UserUpdateRequest` group
together) — an **SRP** win, and it matches the already-noun-first `ShowRequest` form.
ViewModel *read* requests drop the verb entirely (`DocksRequest`, not `DocksShowRequest`).

**Full rules and rationale:** [Naming Dictionary](../shared/NAMES.md).

---

## What This Skill Generates

### Core Files (Always)

| File | Location | Purpose |
|------|----------|---------|
| `{Action}Request.swift` | `{ViewModelsTarget}/Requests/` | The ServerRequest type |
| `{Action}Controller.swift` | `{WebServerTarget}/Controllers/` | Server-side handler |

### Optional: WebApp Bridge (for web clients)

| File | Purpose |
|------|---------|
| WebApp route | Bridges JS fetch to ServerRequest.fetch() |
| JS handler guidance | How to invoke from browser |

---

## How to Use This Skill

**Invocation:**
/fosmvvm-serverrequest-generator

**Prerequisites:**
- Operation requirements understood from conversation context
- RequestBody and ResponseBody structures discussed or documented
- Client type identified (iOS app, WebApp, CLI tool, background job, etc.)

**Workflow integration:**
This skill is typically used when implementing client-server communication. The skill references conversation context automatically—no file paths or Q&A needed. Often follows fosmvvm-viewmodel-generator (for ResponseBody ViewModels) and fosmvvm-fields-generator (for RequestBody validation).

## Pattern Implementation

This skill references conversation context to determine ServerRequest structure:

### Operation Type Detection

From conversation context, the skill identifies:
- **CRUD operation** (create, read, update, archive, destroy)
- **HTTP semantics** (GET for read, POST for create, PATCH/PUT for update, DELETE for archive and destroy)
- **Protocol choice** (ShowRequest, ViewModelRequest, CreateRequest, UpdateRequest, ArchiveRequest, DestroyRequest)

### Request Structure Design

From requirements already in context:
- **RequestBody fields** (what data the client sends)
- **Query parameters** (URL query string data)
- **Fragment parameters** (URL fragment/anchor data)
- **Validation requirements** (ValidatableModel for write operations)

### Response Structure Design

From requirements already in context:
- **ResponseBody type** (often a ViewModel, sometimes just an ID)
- **ResponseError type** — ask "what would this operation `throw` if it were
  a local call?"; that error is the `ResponseError` (`EmptyError` if nothing
  well-defined). Never derive it from HTTP statuses. A create or update must
  name a `ValidatableViewModelRequestError` — normally `ValidationError`.
- **Success scenarios** (what indicates successful operation)
- **Error scenarios** (known failure modes the client must branch on —
  each becomes a typed case the client catches)

### Client Detection

From conversation context:
- **Target platform** (iOS/macOS app, WebApp browser, CLI tool, background job)
- **Bridge requirements** (whether WebApp route needed for browser clients)
- **MVVMEnvironment setup** (how client configures baseURL and headers)

### File Generation

**Core files:**
1. ServerRequest type with RequestBody, ResponseBody, ResponseError
2. Controller with action handler
3. Route registration

**Optional (for WebApp clients):**
4. WebApp route bridging JS to ServerRequest
5. JavaScript handler guidance

### Context Sources

Skill references information from:
- **Prior conversation**: Operation requirements, data structures discussed
- **Specification files**: If Claude has read API specs or feature docs into context
- **Existing patterns**: From codebase analysis of similar requests

---

### ServerRequest Type Template

```swift
// {Action}Request.swift
import FOSMVVM

public final class {Action}Request: {Protocol}, @unchecked Sendable {
    public typealias Query = EmptyQuery       // or custom Query type
    public typealias Fragment = EmptyFragment
    // ResponseError: a read may use EmptyError or a nested ResponseError struct
    //   (see below); a CreateRequest/UpdateRequest must name a
    //   ValidatableViewModelRequestError — `typealias ResponseError = ValidationError`

    public let requestBody: RequestBody?
    public var responseBody: ResponseBody?

    // What the client sends
    public struct RequestBody: ServerRequestBody, ValidatableModel {
        // Fields...
    }
    // ^ When the body carries USER-ENTERED field values (things a person types
    //   into the requesting client's UI), it adopts the entity's {Name}Fields
    //   protocol — `RequestBody: ServerRequestBody, {Name}Fields, Stubbable` —
    //   and its `validate` calls the Fields helpers
    //   (`{name}FieldsValidateModel(validations:fields:)`), so the form, the
    //   wire, and the model all validate with the ONE shared contract. A
    //   hand-written `validate` returning nil satisfies the compiler and
    //   validates nothing. Bodies carrying only operation parameters (ids,
    //   verbs, machine payloads) owe no Fields protocol; `EmptyBody` covers
    //   the body-less write. This applies to the whole write family:
    //   CreateRequest, UpdateRequest, and ReplaceRequest.

    // What the server returns
    public struct ResponseBody: {Protocol}ResponseBody {
        // Fields (often contains a ViewModel)
    }

    // Optional: Custom error type (nested, not top-level!)
    // public struct ResponseError: ServerRequestError { ... }

    public init(
        query: Query? = nil,
        fragment: Fragment? = nil,
        requestBody: RequestBody? = nil,
        responseBody: ResponseBody? = nil
    ) {
        self.requestBody = requestBody
        self.responseBody = responseBody
    }
}
```

**Note:** All subtypes (RequestBody, ResponseBody, ResponseError) are nested inside the request class. This avoids namespace pollution and provides unique YAML localization keys automatically.

### Controller Template

**Controller action = Protocol name (minus "Request")**

| Protocol | Action | HTTP Method |
|----------|--------|-------------|
| `ShowRequest` | `.show` | GET |
| `ViewModelRequest` | `.show` | GET |
| `CreateRequest` | `.create` | POST |
| `UpdateRequest` | `.update` | PATCH |
| `ArchiveRequest` | `.archive` | DELETE |
| `DestroyRequest` | `.destroy` | DELETE |
| Custom request | Whatever fits your semantics | Depends on action |

The pattern is mechanical: `UpdateRequest` → `.update`. `CreateRequest` → `.create`. Just match the names.

```swift
// {Action}Controller.swift
import Vapor
import FOSMVVM
import FOSMVVMVapor

final class {Action}Controller: ServerRequestController {
    typealias TRequest = {Action}Request

    let actions: [ServerRequestAction: ActionProcessor] = [
        .{action}: {Action}Request.performAction
    ]
}

private extension {Action}Request {
    static func performAction(
        _ request: Vapor.Request,
        _ serverRequest: {Action}Request,
        _ requestBody: RequestBody
    ) async throws -> ResponseBody {
        let db = request.db

        // 1. Fetch/validate
        // 2. Perform operation
        // 3. Build response (often a ViewModel)

        return .init(...)
    }
}
```

### Registration — one call

`register(request:app:)` registers every request. Swift picks the overload from the
request's protocol, so the same call serves a read, a create, an update, an archive
or a destroy:

```swift
func routes(_ app: Application) throws {
    let authed = app.grouped(ClientCredentialMiddleware(verifier: myVerifier))
    try authed.register(request: BoardPageRequest.self, app: app)   // guarded read (GET)
    try authed.register(request: CardUpdateRequest.self, app: app) // write (PATCH)
    try authed.register(request: CardArchiveRequest.self, app: app) // write (DELETE)
    try app.register(request: LandingPageRequest.self, app: app)   // public — Application is a RoutesBuilder
}
```

**Mount on middleware-only groups.** A path-prefixing group — `app.grouped("admin")` —
is **rejected at boot**, because the client derives the served URL from the request
type. Adding a prefix on the server would move the route out from under the client's
own derivation.

There is no `register(viewModel:)`; it was removed. A write request that reaches the
read overload fails fast at boot rather than silently registering GET-only, and an
`ArchiveRequest` whose model declares no delete timestamp is refused there too.

**Route collections are the exception, not the pattern.** Reach for
`ServerRequestController` and `register(collection:)` only for operations
`register(request:app:)` does not cover — a `ReplaceRequest`, or a multi-record
operation.

### Client Invocation

**All Swift clients (iOS, macOS, CLI, background jobs, etc.):**

```swift
// MVVMEnvironment configured once at app/tool startup (see "What You Must ALWAYS Do")
let request = {Action}Request(requestBody: .init(...))
try await request.processRequest(mvvmEnv: mvvmEnv)
let result = request.responseBody
```

**WebApp (browser clients):**
See [WebApp Bridge Pattern](#webapp-bridge-pattern) below.

---

### Device-token register request

An app that receives push notifications sends its device token to the server with a register request. The body carries the `PushRegistration.Registration`'s `deviceToken`, `topic`, `environment` (`PushEnvironment`) and `locale`, exactly the values `PushRegistration`'s `onDeviceToken` hook hands over. The server's handler upserts the row, since the hook runs at every launch and whenever Apple replaces the token.

> **SOLID protected: DIP.** The token travels through a ServerRequest and the server owns its storage; neither the client library nor the push sender owns a table. See `fosmvvm-swiftui-app-setup` (Push notifications) and the `FOSMVVM.md § Push Notifications` catalog entry.

---

## WebApp Bridge Pattern

When the client is a web browser, you need a bridge between JavaScript and ServerRequest:

```
Browser                    WebApp (Swift)                      WebServer
   │                            │                                  │
   │  POST /action-name         │                                  │
   │  (JSON body)               │                                  │
   │ ─────────────────────────► │                                  │
   │                            │  request.processRequest(mvvmEnv:)│
   │                            │ ────────────────────────────────►│
   │                            │ ◄────────────────────────────────│
   │  ◄──────────────────────── │  (ResponseBody)                  │
   │  (HTML fragment or JSON)   │                                  │
```

**The WebApp route is internal wiring** - it's how browsers invoke ServerRequest, just like a button tap invokes it in iOS.

### WebApp Route

```swift
// WebApp routes.swift
app.post("{action-name}") { req async throws -> Response in
    // 1. Decode what JS sent
    let body = try req.content.decode({Action}Request.RequestBody.self)

    // 2. Call server via ServerRequest (NOT hardcoded URL!)
    // mvvmEnv is configured at WebApp startup
    let serverRequest = {Action}Request(requestBody: body)
    try await serverRequest.processRequest(mvvmEnv: req.application.mvvmEnv)

    // 3. Return response (HTML fragment or JSON)
    guard let response = serverRequest.responseBody else {
        throw Abort(.internalServerError, reason: "No response from server")
    }
    // ...
}
```

### JavaScript Handler

```javascript
async function handle{Action}(data) {
    const response = await fetch('/{action-name}', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
    });
    // Handle response...
}
```

**Note:** The JS fetches to the WebApp (same origin), which then uses ServerRequest to talk to the WebServer. The browser NEVER talks directly to the WebServer.

---

## Common Patterns

### ViewModel Response

Most operations return a ViewModel for UI update:

```swift
public struct ResponseBody: UpdateResponseBody {
    public let viewModel: IdeaCardViewModel
}
```

### ID-Only Response

Some operations just need confirmation:

```swift
public struct ResponseBody: CreateResponseBody {
    public let id: ModelIdType
}
```

### Empty Response

An archive or destroy sometimes returns nothing — though the container's remaining children are usually the more useful answer:

```swift
// Use EmptyBody as ResponseBody
public typealias ResponseBody = EmptyBody
```

---

## ResponseError - Typed Error Handling

Each `ServerRequest` can define a custom `ResponseError` type for structured error responses from the server.

### How It Works

When processing a response:
1. Framework tries to decode as `ResponseBody`
2. If that fails, tries to decode as `ResponseError`
3. If `ResponseError` decode succeeds, that error is thrown
4. Client catches with try/catch at the call site

### When to Use Custom ResponseError

**Use custom `ResponseError` when:**
- Operation has known failure modes (validation, quota, permissions)
- Server returns structured error details (field names, error codes)
- Client needs to take specific action based on error type
- You want field-level validation error display

**Use `EmptyError` (default) when:**
- Operation rarely fails
- Failures are exceptional (network down, server crash)
- No structured error response expected
- You only need success/failure, not why

**Not available to a create or update.** Their `ResponseError` must be a `ValidatableViewModelRequestError`; `EmptyError` is not one, so the declaration does not compile. Reach for `public typealias ResponseError = ValidationError`.

### Nesting Pattern

**ResponseError MUST be nested inside the request class**, just like RequestBody and ResponseBody:

```swift
public final class IdeaCreateRequest: CreateRequest, @unchecked Sendable {
    public typealias Query = EmptyQuery
    public typealias Fragment = EmptyFragment
    // No typealias needed - ResponseError is nested

    public let requestBody: RequestBody?
    public var responseBody: ResponseBody?

    // ✅ All subtypes nested inside the request
    public struct RequestBody: ServerRequestBody, ValidatableModel { ... }
    public struct ResponseBody: CreateResponseBody { ... }
    public struct ResponseError: ServerRequestError { ... }  // ← Nested, not top-level

    public init(...) { ... }
}
```

**Why nesting matters:**
- Consistent with RequestBody/ResponseBody pattern
- Avoids namespace pollution (no `IdeaCreateError`, `IdeaMoveError`, etc. at top level)
- YAML localization keys are scoped: `IdeaCreateRequest.ResponseError.ErrorCode.quotaExceeded`
- No need for unique type names like `GovernanceLessonCreateError` - nesting provides uniqueness

### Pattern 1: Errors with Associated Values

For errors that need dynamic data in their messages, use `LocalizableSubstitutions`:

Most create and update requests want `public typealias ResponseError = ValidationError` and nothing else. Write a bespoke error only when the operation throws something that is **not** a validation — and then conform it to `ValidatableViewModelRequestError`, as below, so the framework can still hand it the results a refused write produced.

```swift
public final class IdeaCreateRequest: CreateRequest, @unchecked Sendable {
    // ... other typealiases and properties ...

    public struct ResponseError: ValidatableViewModelRequestError {
        public let code: ErrorCode
        public let message: LocalizableSubstitutions

        // ValidatableViewModelRequestError: a create/update error carries the
        // results of a refused write, whichever layer refused it.
        public let validations: [ValidationResult]

        public init(validations: [ValidationResult]) {
            self.code = .validationFailed
            self.message = ErrorCode.validationFailed.message
            self.validations = validations
        }

        public enum ErrorCode: Codable, Sendable {
            case validationFailed
            case duplicateContent
            case quotaExceeded(requestedSize: Int, maximumSize: Int)
            case invalidCategory(category: String)

            var message: LocalizableSubstitutions {
                switch self {
                case .validationFailed:
                    .init(
                        baseString: .localized(for: Self.self, parentType: ResponseError.self, propertyName: "validationFailed"),
                        substitutions: [:]
                    )
                case .duplicateContent:
                    .init(
                        baseString: .localized(for: Self.self, parentType: ResponseError.self, propertyName: "duplicateContent"),
                        substitutions: [:]
                    )
                case .quotaExceeded(let requestedSize, let maximumSize):
                    .init(
                        baseString: .localized(for: Self.self, parentType: ResponseError.self, propertyName: "quotaExceeded"),
                        substitutions: [
                            "requestedSize": LocalizableInt(value: requestedSize),
                            "maximumSize": LocalizableInt(value: maximumSize)
                        ]
                    )
                case .invalidCategory(let category):
                    .init(
                        baseString: .localized(for: Self.self, parentType: ResponseError.self, propertyName: "invalidCategory"),
                        substitutions: [
                            "category": LocalizableString.constant(category)
                        ]
                    )
                }
            }
        }

        public init(code: ErrorCode) {
            self.code = code
            self.message = code.message  // Required to localize properly via Codable
            self.validations = []
        }
    }
}
```

```yaml
en:
  IdeaCreateRequest:
    ResponseError:
      ErrorCode:
        validationFailed: "Some of the values entered need correcting."
        duplicateContent: "The requested content is a duplicate of an existing idea."
        quotaExceeded: "The requested content size %{requestedSize} exceeds the maximum allowed size %{maximumSize}."
        invalidCategory: "The category %{category} is not valid."
```

### Pattern 2: Simple Errors (String-Based Codes)

For simpler errors without associated values, use a `String` raw value enum:

```swift
public final class IdeaMoveRequest: UpdateRequest, @unchecked Sendable {
    // ... other typealiases and properties ...

    public struct ResponseError: ValidatableViewModelRequestError {
        public let code: ErrorCode
        public let message: LocalizableString
        public let validations: [ValidationResult]

        public enum ErrorCode: Codable, Sendable {   // never `: String` — a raw value is a publicly-mintable string and cannot localize
            case validationFailed
            case ideaNotFound
            case invalidTransition

            var message: LocalizableString {
                .localized(case: self, parentType: ResponseError.self)
            }
        }

        public init(validations: [ValidationResult]) {
            self.code = .validationFailed
            self.message = ErrorCode.validationFailed.message
            self.validations = validations
        }

        public init(code: ErrorCode) {
            self.code = code
            self.message = code.message  // Required to localize properly via Codable
            self.validations = []
        }
    }
}
```

```yaml
en:
  IdeaMoveRequest:
    ResponseError:
      ErrorCode:
        validationFailed: "Some of the values entered need correcting."
        ideaNotFound: "The idea was not found"
        invalidTransition: "Cannot move to the requested status"
```

### Type Safety Means You Already Know

**STOP. Before you panic about "how do I know what error type I have?"**

This isn't JavaScript. The type system tells you everything at compile time:

```swift
// When you write this request...
let request = IdeaMoveRequest(requestBody: body)

// ...you KNOW:
// - IdeaMoveRequest.ResponseError exists (it's declared in the type)
// - It has exactly the cases you defined (ideaNotFound, invalidTransition)
// - Each case has whatever properties you gave it

// So when you catch, you catch THE SPECIFIC TYPE:
do {
    try await request.processRequest(mvvmEnv: mvvmEnv)
} catch let error as IdeaMoveRequest.ResponseError {
    // I KNOW this is IdeaMoveRequest.ResponseError
    // I KNOW it has .code
    // I KNOW .code is ErrorCode enum with ideaNotFound, invalidTransition
    // No mystery. No runtime discovery. No "what if?"
}
```

**The anti-pattern (JavaScript brain):**
```swift
// ❌ WRONG - treating typed errors as unknown
catch let error as ServerRequestError {
    // "How do I get the message? What properties does it have?"
    // This thinking is WRONG. You're not in a typeless world.
}
```

**The pattern (Swift brain):**
```swift
// ✅ RIGHT - you know the exact type
catch let error as IdeaMoveRequest.ResponseError {
    switch error.code {
    case .ideaNotFound: // I know this exists
    case .invalidTransition: // I know this exists
    }
}
```

The `ServerRequestError` protocol is a marker (`Error, Codable, Sendable`). It doesn't guarantee properties because **it doesn't need to** - you catch the concrete type, not the protocol.

### Client Error Handling

The primary pattern is try/catch at the call site:

```swift
do {
    try await request.processRequest(mvvmEnv: mvvmEnv)
} catch let error as IdeaCreateRequest.ResponseError {
    switch error.code {
    case .validationFailed:
        validations.replace(with: error.validations)
    case .duplicateContent:
        showDuplicateWarning(message: error.message)
    case .quotaExceeded(let requestedSize, let maximumSize):
        showQuotaError(requested: requestedSize, maximum: maximumSize, message: error.message)
    case .invalidCategory(let category):
        highlightInvalidCategory(category, message: error.message)
    }
} catch {
    showGenericError(error)
}
```

### Built-in ValidationError

`ValidationError` is FOSMVVM's field-level validation failure, and the `ResponseError` a create or update normally declares.

**On a registered write route you rarely throw it yourself.** The framework already runs the request body's `Fields` rules and the target model's `validateModel(in:)` around the write, and rethrows whatever they refuse as the request's own `ResponseError`. Put the rule where it belongs — on the `Fields` protocol, or in the model's lifecycle hook — and the wire carries it for you.

When you do build results by hand, `Validations` is append-only and field ids are minted from key paths:

```swift
// In a controller — collect, then throw
let validations = Validations()

if requestBody.email.isEmpty {
    validations.append(.init(
        status: .error,
        fieldId: #fieldId(\UserFields.email),
        message: .localized(for: UserCreateRequest.self, propertyName: "emailRequired")
    ))
}

if let error = validations.validationError {
    throw error
}
```

There is no public string initializer for `FormFieldIdentifier` — `#fieldId(\Model.property)` is the only mint, so a client and a server cannot drift on a hand-typed `"email"`. The identity is scoped to the type the key path names, so mint from the `Fields` protocol the form field was declared on, not from the request body or the model that adopts it.

```swift
// Client catches the request's own typed error and reads .validations
catch let error as UserCreateRequest.ResponseError {
    validations.replace(with: error.validations)
}
```

**SOLID.** Minting the identifier from a key path rather than a string is the encapsulation precondition SOLID assumes: a `String` has no wall — anyone can mint one, and a typo compiles into a message that will never find its field. The typed identifier makes the form contract checkable at the point it is written.

> **Architecture context:** See [ServerRequestError - Typed Error Responses](../../docs/FOSMVVMArchitecture.md#serverrequesterror---typed-error-responses) for full details.

---

## Testing ServerRequests

**Always test via `ServerRequest.processRequest(mvvmEnv:)` - never via manual HTTP.**

See [fosmvvm-serverrequest-test-generator](../fosmvvm-serverrequest-test-generator/SKILL.md) for complete testing guidance.

```swift
// ✅ RIGHT - tests the actual client code path
let request = {Entity}UpdateRequest(
    query: .init(entityId: id),
    requestBody: .init(name: "New Name")
)
try await request.processRequest(mvvmEnv: testMvvmEnv)
#expect(request.responseBody?.viewModel.name == "New Name")

// ❌ WRONG - manual HTTP bypasses version negotiation
try await app.sendRequest(.PATCH, "/entity/\(id)", body: json)
```

---

## See Also

- [Naming Dictionary](../shared/NAMES.md) - Canonical rules for naming requests (noun-first) and types
- [Architecture Patterns](../shared/architecture-patterns.md) - Mental models (errors are data, type safety, etc.)
- [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md) - Full architecture, especially "Core Principle: ServerRequest Is THE Way"
- [fosmvvm-serverrequest-test-generator](../fosmvvm-serverrequest-test-generator/SKILL.md) - For testing ServerRequest types
- [fosmvvm-viewmodel-generator](../fosmvvm-viewmodel-generator/SKILL.md) - For ViewModels returned by requests
- [fosmvvm-fields-generator](../fosmvvm-fields-generator/SKILL.md) - For ValidatableModel in RequestBody
- [fosmvvm-leaf-view-generator](../fosmvvm-leaf-view-generator/SKILL.md) - For Leaf templates that render ViewModels
- [reference.md](reference.md) - Complete file templates

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-12-24 | Initial Kairos-specific skill |
| 2.0 | 2025-12-26 | Complete rewrite: top-down architecture focus, "ServerRequest Is THE Way" principle, generalized from Kairos, WebApp bridge as platform pattern |
| 2.1 | 2025-12-27 | MVVMEnvironment is THE configuration holder for all clients (CLI, iOS, macOS, etc.) - not raw baseURL/headers. DRY principle enforcement. |
| 2.2 | 2025-12-27 | Added shared module pattern - SystemVersion.currentApplicationVersion from shared module, reference to FOSMVVMArchitecture.md |
| 2.3 | 2025-12-27 | Added `ServerRequestBodySize` for large upload body size limits (`maxBodySize` on RequestBody) |
| 2.4 | 2026-01-08 | Added controller action mapping table, testing section with reference to test generator skill |
| 2.5 | 2026-01-08 | Simplified action mapping: "action = protocol name minus Request". Removed drama, just state the pattern. |
| 2.6 | 2026-01-09 | Added ResponseError section with two patterns: associated values (LocalizableSubstitutions) and simple string codes (LocalizableString). Added YAML examples and built-in ValidationError usage. |
| 2.7 | 2026-01-20 | ResponseError MUST be nested inside request class (like RequestBody/ResponseBody). Updated patterns to show nesting with correct YAML key paths. |
| 2.8 | 2026-01-20 | Added "Type Safety Means You Already Know" section - explicit mental model that Swift's type system means you catch concrete error types, not protocols. Prevents JavaScript-brain panic about runtime type discovery. |
| 2.9 | 2026-01-24 | Update to context-aware approach (remove file-parsing/Q&A). Skill references conversation context instead of asking questions or accepting file paths. |
| 2.11 | 2026-09-29 | `CreateRequest`/`UpdateRequest` constrain `ResponseError` to `ValidatableViewModelRequestError` (`typealias ResponseError = ValidationError` is the ready-made choice); archive-vs-destroy section with the delete-timestamp boot rule; `Validations` is append-only and `FormFieldIdentifier` is minted with `#fieldId(\Model.property)`; remaining verb-first and Delete-era examples flipped. |
| 2.12 | 2026-09-30 | A field identity is scoped by the type the key path names, so a hand-built `ValidationResult` mints from the `Fields` protocol the form field was declared on, not from the request body. |
| 2.10 | 2026-07-02 | Concrete request types are noun-first (`<Noun><Verb>Request`); added "Naming the Concrete Request Type" section + [Naming Dictionary](../shared/NAMES.md) cross-ref; flipped all verb-first examples (`CreateIdeaRequest`→`IdeaCreateRequest`, `MoveIdeaRequest`→`IdeaMoveRequest`, etc.). (backlog A1) |
| 2.13 | 2026-10-05 | Add "Device-token register request" pointer. |
