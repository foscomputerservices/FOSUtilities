# FOSMVVM ServerRequest Generator - Reference Templates

Complete file templates for generating ServerRequest flows.

> **Architecture context:** See [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md) - especially "Core Principle: ServerRequest Is THE Way"

---

## REMEMBER: MVVMEnvironment + processRequest()

Before using these templates, remember:

```swift
// ✅ Import your shared module (contains ServerRequests AND SystemVersion)
import ViewModels  // ← See "The Shared Module Pattern" in FOSMVVMArchitecture.md

// ✅ Configure MVVMEnvironment ONCE at app/tool startup
let mvvmEnv = await MVVMEnvironment(
    currentVersion: .currentApplicationVersion,  // From shared module's SystemVersion extension
    appBundle: Bundle.module,
    deploymentURLs: [.debug: URL(string: "http://localhost:8080")!]
)
// Version headers (X-FOS-Version) are AUTOMATIC via SystemVersion.current

// ✅ Client invocation - ALWAYS use mvvmEnv
let request = {Action}Request(requestBody: .init(...))
try await request.processRequest(mvvmEnv: mvvmEnv)
let result = request.responseBody

// ❌ NEVER do this - violates DRY
try await request.processRequest(baseURL: someURL, headers: someHeaders)

// ❌ NEVER do this - hand-written HTTP
let url = URL(string: "http://server/api/something")!
```

The templates below define the **types**. The URL path is derived from the type name automatically. Configuration lives in MVVMEnvironment.

---

## Placeholders

| Placeholder | Replace With | Example |
|-------------|--------------|---------|
| `{Action}` | Request name stem, **noun-first** (PascalCase) | `IdeaMove`, `UserCreate`, `DocumentArchive` |
| `{action}` | Same, camelCase | `ideaMove`, `userCreate` |
| `{Entity}` | Entity being operated on | `Idea`, `User`, `Document` |
| `{entity}` | Same, camelCase | `idea`, `user`, `document` |
| `{ViewModelsTarget}` | Shared ViewModels SPM target | `ViewModels` |
| `{WebServerTarget}` | Server-side target | `WebServer`, `AppServer` |
| `{Protocol}` | Request protocol | `UpdateRequest`, `CreateRequest` |

Noun-first is the rule, not a preference: `UserCreateRequest`, never `CreateUserRequest`. See the [Naming Dictionary](../shared/NAMES.md) § request table.

---

## Template 1: ServerRequest Type

**Location:** `Sources/{ViewModelsTarget}/Requests/{Action}Request.swift`

```swift
import FOSFoundation
import FOSMVVM
import Foundation

public final class {Action}Request: {Protocol}, @unchecked Sendable {
    public typealias Fragment = EmptyFragment
    public typealias ResponseError = ValidationError
    // ^ A CreateRequest or UpdateRequest constrains ResponseError to a
    //   ValidatableViewModelRequestError, so EmptyError does not compile there:
    //   `ValidationError` is the ready-made choice. (A read may keep EmptyError.)

    public let query: Query?
    public let requestBody: RequestBody?
    public var responseBody: ResponseBody?

    // Which record the write targets: the ModelIdentity the ViewModel carried,
    // echoed back. The body never carries a raw id.
    public struct Query: TargetedQuery {
        public let target: ModelIdentity

        public init(target: ModelIdentity) {
            self.target = target
        }
    }

    // What the client sends: the editable values only
    public struct RequestBody: ServerRequestBody, ValidatableModel {
        public let newValue: SomeType
        // Add other fields as needed

        public init(newValue: SomeType) {
            self.newValue = newValue
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
        public let viewModel: {Container}ViewModel  // The container's children, data-bearing

        public init(viewModel: {Container}ViewModel) {
            self.viewModel = viewModel
        }
    }

    public init(
        query: Query? = nil,
        fragment: Fragment? = nil,
        requestBody: RequestBody? = nil,
        responseBody: ResponseBody? = nil
    ) {
        self.query = query
        self.requestBody = requestBody
        self.responseBody = responseBody
    }
}

// MARK: - Stubbable

public extension {Action}Request {
    static func stub() -> Self {
        .stub(query: .init(target: .stub()), requestBody: .stub())
    }

    static func stub(
        query: Query? = .init(target: .stub()),
        requestBody: RequestBody? = .stub(),
        responseBody: ResponseBody? = nil
    ) -> Self {
        .init(query: query, requestBody: requestBody, responseBody: responseBody)
    }
}

extension {Action}Request.RequestBody: Stubbable {
    public static func stub() -> Self {
        .init(newValue: .stub())
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

**Writes (create, update, archive) are served by the framework.** Adopt `WriteTargetProviding` / `DataModelWriter` on the request's `RequestBody` in the server target: `candidates` declares the auth-scoped set the `TargetedQuery.target` must resolve to, and `apply(to:)` assigns fields (synchronous, no database access). The framework loads, saves and re-serves the container's children. See `FOSMVVMVapor.md § Protocols` in the API catalog.

```swift
extension {Action}Request.RequestBody: DataModelWriter {
    static let candidates = {Entity}.loadingPlan(.write, within: .request)
    func apply(to {entity}: {Entity}) throws {
        {entity}.someField = newValue
    }
}
```

**Location of a hand-written handler (reads and custom actions only):** `Sources/{WebServerTarget}/Controllers/{Action}Controller.swift`

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
            .filter(\.$id == serverRequest.query?.{entity}Id)
            .with(\.$createdBy)  // Add relationships as needed
            .first()
        else {
            throw Abort(.notFound, reason: "{Entity} not found")
        }

        // 2. Build and return the ViewModel, rooted in the identity the factory passes in
        let viewModel = {Entity}ViewModel(
            modelIdentity: try {entity}.modelIdentity
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

### All Swift Clients (iOS, macOS, CLI, background jobs, etc.)

```swift
// MVVMEnvironment configured ONCE at app/tool startup (see "REMEMBER" section above)

// Make requests using mvvmEnv
let request = {Action}Request(
    query: .init(target: viewModel.modelIdentity),  // echoed back from the ViewModel
    requestBody: .init(newValue: newValue)
)

do {
    try await request.processRequest(mvvmEnv: mvvmEnv)
    let viewModel = request.responseBody?.viewModel
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
    // mvvmEnv is configured at WebApp startup
    let serverRequest = {Action}Request(requestBody: body)
    try await serverRequest.processRequest(mvvmEnv: req.application.mvvmEnv)

    guard let response = serverRequest.responseBody else {
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
public final class {Entity}ShowRequest: ShowRequest, @unchecked Sendable {
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
public final class {Entity}CreateRequest: CreateRequest, @unchecked Sendable {
    // ResponseError is constrained to a ValidatableViewModelRequestError
    public typealias ResponseError = ValidationError

    // RequestBody: ValidatableModel required
    public struct RequestBody: ServerRequestBody, ValidatableModel {
        public let content: String
        // ... fields for new entity
    }

    public struct ResponseBody: CreateResponseBody {
        public let viewModel: {Container}ViewModel  // The container's children, including the new one
    }
    // ...
}
```

### UpdateRequest (Update)

```swift
public final class {Entity}UpdateRequest: UpdateRequest, @unchecked Sendable {
    public typealias ResponseError = ValidationError

    public struct Query: TargetedQuery {
        public let target: ModelIdentity  // the identity the ViewModel carried, echoed back
    }

    public struct RequestBody: ServerRequestBody, ValidatableModel {
        public let newValue: SomeType  // editable values only, never an id
    }

    public struct ResponseBody: UpdateResponseBody {
        public let viewModel: {Container}ViewModel  // The container's children
    }
    // ...
}
```

### ArchiveRequest (the row stays, marked deleted)

```swift
public final class {Entity}ArchiveRequest: ArchiveRequest, @unchecked Sendable {
    public struct Query: TargetedQuery {
        public let target: ModelIdentity
    }

    public typealias ResponseBody = EmptyBody  // The container's remaining children are usually the more useful answer
    // ...
}
```

The archived model must declare its delete timestamp:

```swift
// in {Entity}
@Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?
```

Registering an `ArchiveRequest` for a model without one **fails at boot** with `ServerRequestControllerError.archiveUnsupported(request:model:)` — without that column Fluent's `delete(on:)` removes the row, which is a destroy wearing the archive verb. Add the timestamp, or serve a `DestroyRequest` instead.

### DestroyRequest (the row is removed)

```swift
public final class {Entity}DestroyRequest: DestroyRequest, @unchecked Sendable {
    public struct Query: TargetedQuery {
        public let target: ModelIdentity
    }

    public typealias ResponseBody = EmptyBody  // Or the container's remaining children
    // ...
}
```

Destroy is granted by name: the container must publish `ContainerOperation.destroyRecords`, which no wildcard grant covers.

### Large Upload RequestBody

For file uploads or large payloads, specify `maxBodySize` to override the server's default limit:

```swift
public final class {Entity}UploadRequest: CreateRequest, @unchecked Sendable {
    // ...

    public struct RequestBody: ServerRequestBody, ValidatableModel {
        // Override default body size limit (e.g., 50MB for file uploads)
        public static var maxBodySize: ServerRequestBodySize? { .mb(50) }

        public let fileName: String
        public let fileData: Data
        // ... other fields

        public func validate(
            fields: [any FOSMVVM.FormFieldBase]?,
            validations: FOSMVVM.Validations
        ) -> FOSMVVM.ValidationResult.Status? {
            nil
        }
    }
    // ...
}
```

Available size units:
- `.bytes(_ count: UInt)` - Raw bytes
- `.kb(_ count: UInt)` - Kilobytes (× 1,024)
- `.mb(_ count: UInt)` - Megabytes (× 1,048,576)
- `.gb(_ count: UInt)` - Gigabytes (× 1,073,741,824)

### Custom ResponseError — Design From the Throw

`ResponseError` is the operation's *semantic* error — the well-defined Swift
error the operation would `throw` if it were a local function call.
`ServerRequestError` (`Error, Codable, Sendable`) makes that throw
wire-capable: the controller throws it, `ErrorMiddleware` encodes it into the
response, and the client's `processRequest` rethrows the same typed error.

It is **NOT an HTTP-status mapping**:
- never design an error case from a status ("what should a 401 become?")
- never have a client read a status to interpret a result —
  clients branch by catching the typed case

**A create or update constrains it.** `CreateRequest` and `UpdateRequest` require `ResponseError: ValidatableViewModelRequestError`, so a write whose only failure mode is a refused validation simply declares `public typealias ResponseError = ValidationError` and writes no error type at all. Reach for a custom error on a write only when the operation also throws something that is not a validation — and conform it to `ValidatableViewModelRequestError` (a `validations: [ValidationResult]` property plus `init(validations:)`), which is what lets a refusal raised by the body's rules or the model's `validateModel(in:)` arrive as this same type.

### Custom ResponseError - Pattern 1: Associated Values

For errors with dynamic data in messages, use `LocalizableSubstitutions`:

```swift
public final class {Entity}CreateRequest: CreateRequest, @unchecked Sendable {
    public typealias ResponseError = {Entity}CreateError
    // ...
}

public struct {Entity}CreateError: ValidatableViewModelRequestError {
    public let code: ErrorCode
    public let message: LocalizableSubstitutions
    public let validations: [ValidationResult]

    public init(validations: [ValidationResult]) {
        self.code = .validationFailed
        self.message = ErrorCode.validationFailed.message
        self.validations = validations
    }

    public enum ErrorCode: Codable {
        case validationFailed
        case duplicateContent
        case quotaExceeded(requestedSize: Int, maximumSize: Int)
        case invalidCategory(category: String)

        var message: LocalizableSubstitutions {
            switch self {
            case .validationFailed:
                .init(
                    baseString: .localized(for: Self.self, parentType: {Entity}CreateError.self, propertyName: "validationFailed"),
                    substitutions: [:]
                )
            case .duplicateContent:
                .init(
                    baseString: .localized(for: Self.self, parentType: {Entity}CreateError.self, propertyName: "duplicateContent"),
                    substitutions: [:]
                )
            case .quotaExceeded(let requestedSize, let maximumSize):
                .init(
                    baseString: .localized(for: Self.self, parentType: {Entity}CreateError.self, propertyName: "quotaExceeded"),
                    substitutions: [
                        "requestedSize": LocalizableInt(value: requestedSize),
                        "maximumSize": LocalizableInt(value: maximumSize)
                    ]
                )
            case .invalidCategory(let category):
                .init(
                    baseString: .localized(for: Self.self, parentType: {Entity}CreateError.self, propertyName: "invalidCategory"),
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
```

```yaml
en:
  {Entity}CreateError:
    ErrorCode:
      validationFailed: "Some of the values entered need correcting."
      duplicateContent: "The requested content is a duplicate."
      quotaExceeded: "Size %{requestedSize} exceeds maximum %{maximumSize}."
      invalidCategory: "The category %{category} is not valid."
```

### Custom ResponseError - Pattern 2: Simple String Codes

For simpler errors without associated values:

```swift
public struct {Entity}SimpleError: ServerRequestError {
    public let code: ErrorCode
    public let message: LocalizableString

    public enum ErrorCode: Codable, Sendable {
        case notFound
        case permissionDenied

        var message: LocalizableString {
            .localized(case: self, parentType: {Entity}SimpleError.self)
        }
    }

    public init(code: ErrorCode) {
        self.code = code
        self.message = code.message
    }
}
```

```yaml
en:
  {Entity}SimpleError:
    ErrorCode:
      notFound: "The requested item was not found."
      permissionDenied: "You don't have permission to perform this action."
```

This form is fine as a read request's `ResponseError`. Serving it from a create or update means conforming it to `ValidatableViewModelRequestError` as well — see Pattern 1.

**Controller throwing custom error:**

```swift
private extension {Entity}CreateRequest {
    static func performCreate(
        _ request: Vapor.Request,
        _ serverRequest: {Entity}CreateRequest,
        _ requestBody: RequestBody
    ) async throws -> ResponseBody {
        // Check for duplicate
        if try await {Entity}.query(on: request.db)
            .filter(\.$content == requestBody.content)
            .first() != nil {
            throw {Entity}CreateError(code: .duplicateContent)
        }

        // Check quota
        let count = try await {Entity}.query(on: request.db).count()
        if count >= quotaLimit {
            throw {Entity}CreateError(code: .quotaExceeded(
                requestedSize: requestBody.size,
                maximumSize: quotaLimit
            ))
        }

        // ... proceed with creation
    }
}
```

**Client handling custom error:**

```swift
do {
    try await request.processRequest(mvvmEnv: mvvmEnv)
} catch let error as {Entity}CreateError {
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

---

## Checklist

### ServerRequest Type
- [ ] Name is noun-first (`{Entity}CreateRequest`, never `Create{Entity}Request`)
- [ ] Extends correct protocol (ShowRequest, CreateRequest, UpdateRequest, ArchiveRequest, DestroyRequest)
- [ ] RequestBody has all fields client needs to send
- [ ] ResponseBody contains what client needs back (often a ViewModel)
- [ ] ResponseError answers "what would this operation throw locally?" (EmptyError if nothing well-defined) — never derived from an HTTP status
- [ ] Create/Update: ResponseError is a `ValidatableViewModelRequestError` — `typealias ResponseError = ValidationError` unless the operation also throws a non-validation error
- [ ] Archive: the target model declares `@Timestamp(key: "deleted_at", on: .delete)`, or the request is a DestroyRequest instead
- [ ] Stubbable conformance for testing
- [ ] ValidatableModel on RequestBody (for write operations)
- [ ] `maxBodySize` set on RequestBody if handling large uploads (files, images, etc.)

### Controller
- [ ] Correct action mapping (.show, .create, .update, .archive, .destroy)
- [ ] Fetches entity with relationships (`with(\.$relation)`)
- [ ] Uses `try entity.requireID()` not `id!`
- [ ] Returns fully populated response

### Registration
- [ ] Controller registered in routes.swift

### Client Invocation
- [ ] MVVMEnvironment configured once at app/tool startup
- [ ] Uses `request.processRequest(mvvmEnv:)` - NO baseURL/headers per-call
- [ ] Handles response via `request.responseBody`
- [ ] Catches custom `ResponseError` type if defined (branches on the typed case, never on an HTTP status)
- [ ] Generic error fallback for unexpected errors

### WebApp Bridge (if needed)
- [ ] MVVMEnvironment configured at WebApp startup
- [ ] Route decodes RequestBody
- [ ] Route uses `processRequest(mvvmEnv:)` (not hardcoded URL to WebServer)
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

### Container's Children Response
A write answers with the container's children (data-bearing), not an id:
```swift
public struct ResponseBody: CreateResponseBody {
    public let viewModel: BoardViewModel  // the board's cards, including the new one
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

---

## Built-in ValidationError

`ValidationError` is FOSMVVM's field-level validation failure, and the `ResponseError` a create or update normally declares:

```swift
public typealias ResponseError = ValidationError
```

**A registered write route rarely throws it by hand.** The framework runs the request body's `Fields` rules and the target model's `validateModel(in:)` around the write, and rethrows whatever they refuse as the request's own `ResponseError`, with the results inside. Put the rule on the `Fields` protocol or in the model's lifecycle hook and the wire carries it.

When you do build results yourself, `Validations` is append-only and field ids are minted from key paths:

```swift
// In controller
let validations = Validations()

if requestBody.email.isEmpty {
    validations.append(.init(
        status: .error,
        fieldId: #fieldId(\{Entity}Fields.email),
        message: .localized(for: {Entity}CreateRequest.self, propertyName: "emailRequired")
    ))
}

if let error = validations.validationError {
    throw error
}
```

`FormFieldIdentifier` has no public string initializer — `#fieldId(\Model.property)` is the only mint, so a hand-typed `"email"` cannot drift away from the property it names. The identity is scoped to the type the key path names: mint from the `Fields` protocol the form field was declared on, not from the request body or the model that adopts it.

```swift
// Client handling — catch the request's own typed error
catch let error as {Entity}CreateRequest.ResponseError {
    validations.replace(with: error.validations)   // drives .withFormValidations()
}
```

## Other Common Error Patterns

### Rate Limit Error
```swift
public struct RateLimitError: ServerRequestError {
    public let retryAfterSeconds: Int
    public let limit: Int
    public let resetAt: LocalizableDate
}
```

### Permission Error
```swift
public struct PermissionError: ServerRequestError {
    public let code: ErrorCode
    public let message: LocalizableString

    public enum ErrorCode: Codable, Sendable {
        case insufficientRole
        case accountSuspended

        var message: LocalizableString {
            .localized(case: self, parentType: PermissionError.self)
        }
    }

    public init(code: ErrorCode) {
        self.code = code
        self.message = code.message
    }
}
```
