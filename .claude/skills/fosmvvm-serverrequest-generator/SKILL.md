---
name: fosmvvm-serverrequest-generator
description: Generate ServerRequest types for client-server communication in FOSMVVM. Use when implementing any operation that talks to the server - CRUD operations, data sync, actions, etc. ServerRequest is THE way clients communicate with servers.
---

# FOSMVVM ServerRequest Generator

Generate ServerRequest types for client-server communication.

> **Architecture context:** See [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md)

---

## STOP AND READ THIS

**ServerRequest is THE way to communicate with an FOSMVVM server. No exceptions.**

```
┌─────────────────────────────────────────────────────────────────────┐
│                 ALL CLIENTS USE ServerRequest                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  iOS App:         Button tap    →  request.processRequest(baseURL:)  │
│  macOS App:       Button tap    →  request.processRequest(baseURL:)  │
│  WebApp:          JS → WebApp   →  request.processRequest(baseURL:)  │
│  CLI Tool:        main()        →  request.processRequest(baseURL:)  │
│  Data Collector:  timer/event   →  request.processRequest(baseURL:)  │
│  Background Job:  cron trigger  →  request.processRequest(baseURL:)  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### What You Must NEVER Do

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

```swift
// ✅ RIGHT - ServerRequest abstracts everything
let request = UserShowRequest(query: .init(userId: id))
let response = try await request.processRequest(baseURL: serverURL)

// ✅ RIGHT - Create operation
let createRequest = CreateIdeaRequest(requestBody: .init(content: content))
let response = try await createRequest.processRequest(baseURL: serverURL)

// ✅ RIGHT - Update operation
let updateRequest = MoveIdeaRequest(requestBody: .init(ideaId: id, newStatus: status))
let response = try await updateRequest.processRequest(baseURL: serverURL)
```

**The path is derived from the type name. The HTTP method comes from the protocol. You NEVER write URL strings.**

---

## When to Use This Skill

- Implementing any client-server communication
- Adding CRUD operations (Create, Read, Update, Delete)
- Building data collectors or sync tools
- Any Swift code that needs to talk to the server

**If you're about to write `URLRequest` or a hardcoded path string, STOP and use this skill instead.**

---

## What ServerRequest Provides

| Concern | How ServerRequest Handles It |
|---------|------------------------------|
| URL Path | Derived from type name via `Self.path` (e.g., `MoveIdeaRequest` → `/move_idea`) |
| HTTP Method | Determined by `action.httpMethod` (ShowRequest=GET, CreateRequest=POST, etc.) |
| Request Body | `RequestBody` type, automatically JSON encoded via `requestBody?.toJSONData()` |
| Response Body | `ResponseBody` type, automatically JSON decoded into `responseBody` |
| Validation | `RequestBody: ValidatableModel` for write operations |
| Type Safety | Compiler enforces correct types throughout |

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
| Soft delete | `DeleteRequest` | DELETE | No |
| Hard delete | `DestroyRequest` | DELETE | No |

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

## Generation Process

### Step 1: Understand the Operation

Ask:
1. **What operation?** (create, read, update, delete)
2. **What data goes IN?** (RequestBody fields)
3. **What data comes OUT?** (ResponseBody - often a ViewModel)
4. **Who calls this?** (iOS app, WebApp, CLI tool, etc.)

### Step 2: Choose Protocol

Based on operation type:
- Reading → `ShowRequest` or `ViewModelRequest`
- Creating → `CreateRequest`
- Updating → `UpdateRequest`
- Deleting → `DeleteRequest`

### Step 3: Generate ServerRequest Type

```swift
// {Action}Request.swift
import FOSMVVM

public final class {Action}Request: {Protocol}, @unchecked Sendable {
    public typealias Query = EmptyQuery       // or custom Query type
    public typealias Fragment = EmptyFragment
    public typealias ResponseError = EmptyError

    public let requestBody: RequestBody?
    public var responseBody: ResponseBody?

    // What the client sends
    public struct RequestBody: ServerRequestBody, ValidatableModel {
        // Fields...
    }

    // What the server returns
    public struct ResponseBody: {Protocol}ResponseBody {
        // Fields (often contains a ViewModel)
    }

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

### Step 4: Generate Controller

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

### Step 5: Register Controller

```swift
// In WebServer routes.swift
try versionedGroup.register(collection: {Action}Controller())
```

### Step 6: Client Invocation

**Native apps (iOS, macOS, CLI, etc.):**
```swift
let request = {Action}Request(requestBody: .init(...))
let response = try await request.processRequest(baseURL: serverURL)
// Use response.responseBody
```

**WebApp (browser clients):**
See [WebApp Bridge Pattern](#webapp-bridge-pattern) below.

---

## WebApp Bridge Pattern

When the client is a web browser, you need a bridge between JavaScript and ServerRequest:

```
Browser                    WebApp (Swift)                      WebServer
   │                            │                                  │
   │  POST /action-name         │                                  │
   │  (JSON body)               │                                  │
   │ ─────────────────────────► │                                  │
   │                            │  request.processRequest(baseURL:)│
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
    let serverRequest = {Action}Request(requestBody: body)
    let response = try await serverRequest.processRequest(baseURL: app.serverBaseURL)

    // 3. Return response (HTML fragment or JSON)
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

Delete operations often return nothing:

```swift
// Use EmptyBody as ResponseBody
public typealias ResponseBody = EmptyBody
```

---

## Collaboration Protocol

1. **Clarify the operation** - What are we doing?
2. **Confirm RequestBody/ResponseBody** - What goes in, what comes out?
3. **Generate ServerRequest type** - Get feedback
4. **Generate Controller** - Get feedback
5. **Show registration** - Where to wire it up
6. **Client invocation** - How to call it (native vs WebApp)

---

## See Also

- [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md) - Full architecture, especially "Core Principle: ServerRequest Is THE Way"
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
