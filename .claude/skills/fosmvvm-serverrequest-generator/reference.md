# FOSMVVM ServerRequest Generator - Reference Templates

Complete file templates for generating ServerRequest flows.

> **Architecture context:** See [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md) - especially "Core Principle: ServerRequest Is THE Way"

---

## REMEMBER: No Hardcoded URLs

Before using these templates, remember:

```swift
// ✅ Client invocation - ALWAYS
let request = {Action}Request(requestBody: .init(...))
let response = try await request.processRequest(baseURL: serverURL)

// ❌ NEVER do this
let url = URL(string: "http://server/api/something")!
```

The templates below define the **types**. The URL path is derived from the type name automatically.

---

## Placeholders

| Placeholder | Replace With | Example |
|-------------|--------------|---------|
| `{Action}` | Operation name (PascalCase) | `MoveIdea`, `CreateUser`, `DeleteDocument` |
| `{action}` | Same, camelCase | `moveIdea`, `createUser` |
| `{Entity}` | Entity being operated on | `Idea`, `User`, `Document` |
| `{entity}` | Same, camelCase | `idea`, `user`, `document` |
| `{ViewModelsTarget}` | Shared ViewModels SPM target | `ViewModels` |
| `{WebServerTarget}` | Server-side target | `WebServer`, `AppServer` |
| `{Protocol}` | Request protocol | `UpdateRequest`, `CreateRequest` |

---

## Template 1: ServerRequest Type

**Location:** `Sources/{ViewModelsTarget}/Requests/{Action}Request.swift`

```swift
import FOSFoundation
import FOSMVVM
import Foundation

public final class {Action}Request: {Protocol}, @unchecked Sendable {
    public typealias Query = EmptyQuery
    public typealias Fragment = EmptyFragment
    public typealias ResponseError = EmptyError

    public let requestBody: RequestBody?
    public var responseBody: ResponseBody?

    // What the client sends
    public struct RequestBody: ServerRequestBody, ValidatableModel {
        public let {entity}Id: ModelIdType
        // Add other fields as needed

        public init({entity}Id: ModelIdType) {
            self.{entity}Id = {entity}Id
        }

        public func validate(
            fields: [any FOSMVVM.FormFieldBase]?,
            validations: FOSMVVM.Validations
        ) -> FOSMVVM.ValidationResult.Status? {
            nil  // Add validation if needed
        }
    }

    // What the server returns
    public struct ResponseBody: {Protocol}ResponseBody {
        public let viewModel: {Entity}ViewModel  // Or appropriate ViewModel

        public init(viewModel: {Entity}ViewModel) {
            self.viewModel = viewModel
        }
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

// MARK: - Stubbable

public extension {Action}Request {
    static func stub() -> Self {
        .stub(requestBody: .stub())
    }

    static func stub(
        requestBody: RequestBody? = .stub(),
        responseBody: ResponseBody? = nil
    ) -> Self {
        .init(requestBody: requestBody, responseBody: responseBody)
    }
}

extension {Action}Request.RequestBody: Stubbable {
    public static func stub() -> Self {
        .init({entity}Id: .init())
    }
}

extension {Action}Request.ResponseBody: Stubbable {
    public static func stub() -> Self {
        .init(viewModel: .stub())
    }
}
```

---

## Template 2: Controller (Server-Side Handler)

**Location:** `Sources/{WebServerTarget}/Controllers/{Action}Controller.swift`

```swift
import Fluent
import FOSMVVM
import FOSMVVMVapor
import Vapor
import {ViewModelsTarget}

final class {Action}Controller: ServerRequestController {
    typealias TRequest = {Action}Request

    let actions: [ServerRequestAction: ActionProcessor] = [
        .{action}: {Action}Request.perform{Action}
    ]
}

private extension {Action}Request {
    static func perform{Action}(
        _ request: Vapor.Request,
        _ serverRequest: {Action}Request,
        _ requestBody: RequestBody
    ) async throws -> ResponseBody {
        let db = request.db

        // 1. Fetch entity (with relationships if needed)
        guard let {entity} = try await {Entity}.query(on: db)
            .filter(\.$id == requestBody.{entity}Id)
            .with(\.$createdBy)  // Add relationships as needed
            .first()
        else {
            throw Abort(.notFound, reason: "{Entity} not found: \(requestBody.{entity}Id)")
        }

        // 2. Perform the operation
        // {entity}.someField = requestBody.newValue
        // try await {entity}.save(on: db)

        // 3. Build and return ViewModel
        let viewModel = {Entity}ViewModel(
            id: try {entity}.requireID()
            // ... map fields
        )

        return .init(viewModel: viewModel)
    }
}
```

---

## Template 3: Controller Registration

**Location:** `Sources/{WebServerTarget}/routes.swift`

```swift
// Add to existing routes.swift
try versionedGroup.register(collection: {Action}Controller())
```

---

## Template 4: Client Invocation

### Native App (iOS, macOS, CLI, etc.)

```swift
// This is all you need - no URL strings!
let request = {Action}Request(requestBody: .init(
    {entity}Id: entityId
    // ... other fields
))

do {
    let response = try await request.processRequest(baseURL: serverURL)
    let viewModel = response?.viewModel
    // Use viewModel...
} catch {
    // Handle error
}
```

### WebApp Bridge (for browser clients)

**WebApp Route:** `Sources/{WebAppTarget}/routes.swift`

```swift
app.post("{action-kebab-case}") { req async throws -> Response in
    // 1. Decode what JS sent
    let body = try req.content.decode({Action}Request.RequestBody.self)

    // 2. Call server via ServerRequest (NOT hardcoded URL!)
    let serverRequest = {Action}Request(requestBody: body)
    guard let response = try await serverRequest.processRequest(baseURL: app.serverBaseURL) else {
        throw Abort(.internalServerError, reason: "No response from server")
    }

    // 3. Return response (HTML fragment or JSON)
    return try await req.view.render(
        "{Feature}/{Entity}View",
        ["viewModel": response.viewModel]
    )
}
```

**JavaScript Handler:**

```javascript
async function handle{Action}(data) {
    // CRITICAL: Capture DOM references BEFORE any await
    const element = data.element;
    const entityId = element.dataset.entityId;

    const request = {
        {entity}Id: entityId
        // ... other fields from data attributes
    };

    try {
        // POST to WebApp (NOT WebServer!)
        const response = await fetch('/{action-kebab-case}', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(request)
        });

        if (!response.ok) {
            throw new Error(await response.text() || 'Operation failed');
        }

        // Handle response (HTML or JSON depending on your pattern)
        const html = await response.text();
        // Swap into DOM...

    } catch (error) {
        console.error('Error:', error);
        // Handle error...
    }
}
```

---

## Protocol-Specific Templates

### ShowRequest (Read)

```swift
public final class Get{Entity}Request: ShowRequest, @unchecked Sendable {
    public typealias Fragment = EmptyFragment
    public typealias RequestBody = EmptyBody  // No body for GET

    public let query: Query?
    public var responseBody: ResponseBody?

    public struct Query: ServerRequestQuery {
        public let {entity}Id: ModelIdType
    }

    public struct ResponseBody: ServerRequestBody {
        public let viewModel: {Entity}ViewModel
    }
    // ...
}
```

### CreateRequest (Create)

```swift
public final class Create{Entity}Request: CreateRequest, @unchecked Sendable {
    // RequestBody: ValidatableModel required
    public struct RequestBody: ServerRequestBody, ValidatableModel {
        public let content: String
        // ... fields for new entity
    }

    public struct ResponseBody: CreateResponseBody {
        public let id: ModelIdType  // Or full ViewModel
    }
    // ...
}
```

### UpdateRequest (Update)

```swift
public final class Update{Entity}Request: UpdateRequest, @unchecked Sendable {
    public struct RequestBody: ServerRequestBody, ValidatableModel {
        public let {entity}Id: ModelIdType
        public let newValue: SomeType
    }

    public struct ResponseBody: UpdateResponseBody {
        public let viewModel: {Entity}ViewModel
    }
    // ...
}
```

### DeleteRequest (Soft Delete)

```swift
public final class Delete{Entity}Request: DeleteRequest, @unchecked Sendable {
    public struct RequestBody: ServerRequestBody {
        public let {entity}Id: ModelIdType
    }

    public typealias ResponseBody = EmptyBody  // Often no response needed
    // ...
}
```

---

## Checklist

### ServerRequest Type
- [ ] Extends correct protocol (ShowRequest, CreateRequest, UpdateRequest, DeleteRequest)
- [ ] RequestBody has all fields client needs to send
- [ ] ResponseBody contains what client needs back (often a ViewModel)
- [ ] Stubbable conformance for testing
- [ ] ValidatableModel on RequestBody (for write operations)

### Controller
- [ ] Correct action mapping (.show, .create, .update, .delete)
- [ ] Fetches entity with relationships (`with(\.$relation)`)
- [ ] Uses `try entity.requireID()` not `id!`
- [ ] Returns fully populated response

### Registration
- [ ] Controller registered in routes.swift

### Client Invocation
- [ ] Uses `request.processRequest(baseURL:)` - NO hardcoded URLs
- [ ] Handles response properly
- [ ] Error handling in place

### WebApp Bridge (if needed)
- [ ] Route decodes RequestBody
- [ ] Route uses ServerRequest (not hardcoded URL to WebServer)
- [ ] JS captures DOM references before await
- [ ] JS POSTs to WebApp, not WebServer

---

## Common Patterns

### ViewModel Response
```swift
public struct ResponseBody: UpdateResponseBody {
    public let viewModel: {Entity}CardViewModel
}
```

### ID-Only Response
```swift
public struct ResponseBody: CreateResponseBody {
    public let id: ModelIdType
}
```

### Empty Response
```swift
public typealias ResponseBody = EmptyBody
```

### Multiple ViewModels Response
```swift
public struct ResponseBody: ShowResponseBody {
    public let items: [{Entity}ViewModel]
    public let totalCount: Int
}
```
