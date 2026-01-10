# FOSMVVM Architecture Overview

This document captures the conceptual architecture of FOSMVVM for quick reference.

## The M-V-VM Pattern in FOSMVVM

FOSMVVM implements a Model-View-ViewModel architecture with a key design principle: **the same patterns work whether you have a server or not**.

- **Model** - The source of truth for what exists (data + identity)
- **View** - SwiftUI views that render ViewModels
- **ViewModel** - A projection of Model data, shaped for presentation

---

## The Model Layer

The Model is the **center of the architecture**. Both reads and writes flow through it.

### What is a Model?

A Model represents an **entity that exists** - a User, an Idea, a Document. It has:

- **Identity** (`id: ModelIdType?`) - uniquely identifies the instance
- **All fields** - both user-editable and system-assigned
- **Relationships** - connections to other Models
- **Persistence** - how it's stored (database, file, memory)

```swift
// Model.swift - The core protocol
public protocol Model: Codable, Hashable {
    var id: ModelIdType? { get }
}
```

### Model vs ViewModel

| Aspect | Model | ViewModel |
|--------|-------|-----------|
| Purpose | What EXISTS | How to PRESENT it |
| Relationship | IS the truth | Projects FROM the truth |
| Contents | All fields | Selected, shaped fields |
| Identity | `id: ModelIdType` | `vmId: ViewModelId` |
| Relationships | Has them (FK, joins) | Flattened/projected |
| Localization | Raw data | Localized for display |

A Model contains the **truth**. A ViewModel contains a **presentation-shaped projection** of that truth.

### ValidatableModel

When a Model receives data from external sources, it conforms to `ValidatableModel`:

```swift
public protocol ValidatableModel {
    func validate(fields: [any FormFieldBase]?, validations: Validations) -> ValidationResult.Status?
}
```

External sources include:
- User input (forms)
- External APIs (REST, webhooks)
- Imported files
- Any untrusted data crossing the system boundary

This is the contract that **Fields protocols** implement - shared validation logic used by:
- CRUD request bodies (API validation)
- Form ViewModels (UI validation)
- Persistence layer (storage validation)

### The Fields Protocol Pattern

A `{Name}Fields` protocol defines the **user-editable subset** of a Model:

```
Model (full entity)
    │
    ├── id, createdAt, updatedAt, relationships...  ← system-managed
    │
    └── implements → {Name}Fields protocol          ← user-editable
                         │
                         ├── property definitions
                         ├── FormField metadata
                         └── validation methods
```

**Key insight:** The Model implements Fields, but contains MORE than Fields. A `User` Model has `passwordHash`, `lastLoginIP`, `createdAt` - but `UserFields` only exposes `email`, `firstName`, `lastName`.

---

## The Request Landscape

FOSMVVM defines a hierarchy of request types that all flow through the Model layer.

### Core Principle: ServerRequest Is THE Way

**Any code that communicates with an FOSMVVM server uses ServerRequest. No exceptions.**

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
│  MVVMEnvironment configured ONCE at startup, used EVERYWHERE          │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘
```

**NEVER do this:**
```swift
// WRONG - hardcoded URL
let url = URL(string: "http://server/api/users/123")!
let request = URLRequest(url: url)

// WRONG - string path
try await client.get("/api/users/\(id)")

// WRONG - fetch with path string (JavaScript)
fetch('/api/users/123')
```

**ALWAYS do this:**
```swift
// RIGHT - ServerRequest with MVVMEnvironment (configured once at startup)
let request = UserShowRequest(query: .init(userId: id))
try await request.processRequest(mvvmEnv: mvvmEnv)
let user = request.responseBody
```

**Why this matters:**
- **Type safety** - Compiler catches RequestBody/ResponseBody mismatches
- **Single source of truth** - Path derived from type name, HTTP method from protocol
- **No string typos** - Can't misspell a URL when there is no URL
- **Automatic serialization** - Encoding/decoding handled by the type
- **Testable** - Mock at type level, not URL level
- **Unified architecture** - Same pattern works for ALL client types

The WebApp's `(JS → WebApp)` bridge is internal wiring - the browser-specific mechanism to get from "button click" to `request.processRequest()`. Architecturally, it's equivalent to native app code.

### Request Hierarchy

```
                              ServerRequest
                     (base protocol for HTTP interactions)
                                   │
       ┌───────────┬───────────┬──┴──┬─────────────┬─────────────┐
       │           │           │     │             │             │
       ▼           ▼           ▼     ▼             ▼             ▼
  ShowRequest  CreateRequest  UpdateRequest  DeleteRequest  DestroyRequest
  (GET/show)   (POST/create) (PATCH/update) (DELETE/soft)  (DELETE/hard)
       │           │           │
       │           │           │
       ▼           ▼           ▼
ViewModelRequest  RequestBody:  RequestBody:
(ResponseBody:    ValidatableModel  ValidatableModel
 ViewModel)
```

### Reads: ShowRequest and ViewModelRequest

`ShowRequest` is the base for all GET/show operations:

```swift
public protocol ShowRequest: ServerRequest, Stubbable {}
```

`ViewModelRequest` specializes ShowRequest for ViewModel responses:

```swift
public protocol ViewModelRequest: ShowRequest
    where ResponseBody: RequestableViewModel {}
```

Flow: `ViewModelRequest` → `ViewModelFactory.model(context:)` → queries Model → returns shaped ViewModel

Use `ShowRequest` directly for non-ViewModel GET responses (health checks, raw data exports, etc.).

### Writes: CRUD Requests

Modify the Model layer with validated data:

```swift
// Create new entity
public protocol CreateRequest: ServerRequest
    where RequestBody: ValidatableModel {}

// Update existing entity
public protocol UpdateRequest: ServerRequest
    where RequestBody: ValidatableModel {}

// Soft delete (mark as deleted)
public protocol DeleteRequest: ServerRequest {}

// Hard delete (permanent removal)
public protocol DestroyRequest: ServerRequest {}
```

Flow: `CreateRequest` → validate `RequestBody` → persist to Model layer

### The Shared Validation Contract

The same `ValidatableModel` (via Fields protocol) validates data at every layer:

```
┌─────────────────────────────────────────────────────────────────┐
│                    UserFields Protocol                          │
│            (defines email, firstName, lastName)                 │
│                                                                 │
│  Adopted by:                                                    │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │ CreateUserReq   │  │ UserFormVM      │  │ User (Model)    │ │
│  │ .RequestBody    │  │ (form display)  │  │ (persistence)   │ │
│  │                 │  │                 │  │                 │ │
│  │ API validation  │  │ UI validation   │  │ DB validation   │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

**Define once, validate everywhere.**

---

## Hosting Modes

FOSMVVM supports two hosting modes. **This is a per-ViewModel decision, not a per-app decision.** An app can freely mix both modes - each ViewModel chooses based on where its data comes from.

The hosting mode determines:
- Where the factory lives (server vs. client)
- Who writes the factory (you vs. macro)
- Where localization happens (server vs. client)

### Server-Hosted Mode

When a ViewModel's data comes from a server:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              CLIENT                                      │
│  ┌──────────┐    ┌─────────────────┐    ┌─────────────────────────────┐ │
│  │   View   │◄───│    ViewModel    │◄───│     ViewModelRequest        │ │
│  │ (SwiftUI)│    │ (localized)     │    │  (fetches from server)      │ │
│  └──────────┘    └─────────────────┘    └─────────────────────────────┘ │
│                          ▲                                               │
│                          │ JSON (already localized)                      │
└──────────────────────────┼───────────────────────────────────────────────┘
                           │
┌──────────────────────────┼───────────────────────────────────────────────┐
│                          │            SERVER                             │
│                  ┌───────┴─────────┐                                     │
│                  │ ViewModelFactory│ ◄── Localizes via JSONEncoder       │
│                  │   model(ctx)    │     (hand-written factory)          │
│                  └───────┬─────────┘                                     │
│                          │                                               │
│                  ┌───────▼─────────┐    ┌─────────────────┐              │
│                  │     Model       │    │ LocalizationStore│              │
│                  │   (Database)    │    │    (YAML)       │              │
│                  └─────────────────┘    └─────────────────┘              │
└──────────────────────────────────────────────────────────────────────────┘
```

**Characteristics:**
- Factory is **hand-written** on server (`ViewModelFactory` protocol)
- Localization happens **on server** during JSON encoding
- Client receives **fully localized** ViewModels
- Client needs **no localization resources**

**Use when:** ViewModel data comes from a server API or database.

### Client-Hosted Mode

When a ViewModel's data is local to the device:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         CLIENT (standalone app)                          │
│                                                                          │
│  ┌──────────┐    ┌─────────────────┐    ┌─────────────────────────────┐ │
│  │   View   │◄───│    ViewModel    │◄───│ ClientHostedViewModelFactory│ │
│  │ (SwiftUI)│    │ (localized)     │    │   (macro-generated)         │ │
│  └──────────┘    └─────────────────┘    └──────────────┬──────────────┘ │
│                                                        │                 │
│                  ┌─────────────────┐    ┌──────────────▼──────────────┐ │
│                  │ LocalizationStore│    │         AppState           │ │
│                  │    (YAML)       │    │   (in-memory/local data)   │ │
│                  └─────────────────┘    └─────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

**Characteristics:**
- Factory is **auto-generated** by the `@ViewModel` macro
- Localization happens **on client** during encoding
- Client **bundles** localization resources (YAML files)
- No server required

**Use when:** ViewModel data comes from local storage, preferences, or in-memory state.

### Quick Reference

| Question | Server-Hosted | Client-Hosted |
|----------|---------------|---------------|
| Where's the data? | Server/Database | Local state |
| Who writes factory? | You | Macro |
| Localization resources | Server only | Bundled in app |
| Macro | `@ViewModel` | `@ViewModel(options: [.clientHostedFactory])` |

**Hybrid example:** An iPhone app with server-based sign-in:
- `SettingsViewModel` → Client-Hosted (local preferences)
- `SignInViewModel` → Server-Hosted (authentication API)

### Client-Hosted Macro

The `@ViewModel` macro with `clientHostedFactory` option generates everything needed:

```swift
@ViewModel(options: [.clientHostedFactory])
public struct SettingsViewModel {
    @LocalizedString public var title

    public var vmId: ViewModelId

    public init(theme: Theme) {
        self.vmId = .init()
        // theme is captured in auto-generated AppState
    }
}

// Macro generates:
// - public typealias Request = ClientHostedRequest
// - public struct AppState { ... }
// - public final class ClientHostedRequest: ViewModelRequest { ... }
// - public static func model(context:) async throws -> Self { ... }
```

No hand-written factory needed - the macro analyzes the `init` parameters and generates appropriate `AppState` and factory.

---

## The ViewModel's Core Responsibility

A ViewModel's primary job is **shaping data for presentation**. It transforms raw Model data into formats the UI can display. This shaping happens in two places:

1. **ViewModelFactory** - Determines *what* data is needed and *how* to transform it (queries, mappings, projections)
2. **Localization** - Determines *how* to present data in context (formatting, substitutions, ordering)

### Contextual Presentation

Not all languages present data the same way. Consider a greeting:

```yaml
# English puts the name at the end
en:
  GreetingViewModel:
    welcomeMessage: "Welcome back, %{userName}!"

# Japanese puts the name first with honorific
ja:
  GreetingViewModel:
    welcomeMessage: "%{userName}さん、おかえりなさい！"

# German might restructure entirely
de:
  GreetingViewModel:
    welcomeMessage: "Willkommen zurück, %{userName}!"
```

The ViewModel uses `@LocalizedSubs` to bind the substitution:

```swift
@ViewModel
public struct GreetingViewModel {
    @LocalizedSubs(substitutions: \.subs) var welcomeMessage

    private var subs: [String: any Localizable] {
        ["userName": LocalizableString.constant(userName)]
    }

    public let userName: String
}
```

The substitution point `%{userName}` is placed correctly per locale during encoding.

### Localization Types for Shaping

| Type | Property Wrapper | Use Case |
|------|------------------|----------|
| `LocalizableString` | `@LocalizedString` | Static UI text |
| `LocalizableInt` | `@LocalizedInt` | Formatted numbers (grouping, locale) |
| `LocalizableDate` | `@LocalizedDate` | Formatted dates (locale, timezone) |
| `LocalizableSubstitutions` | `@LocalizedSubs` | Dynamic data embedded in localized text |
| `LocalizableCompoundValue` | `@LocalizedCompoundString` | Multiple pieces joined (handles RTL/LTR) |

### Why This Matters

The View layer just renders what it receives. All the "shaping" intelligence is in:
- **Factory** - which data, how transformed
- **Localization** - where in the text, what format

This keeps Views simple and makes the app truly locale-aware, not just translated.

### Anti-Pattern: Composition in Views

If the View is composing data, the shaping is in the wrong layer:

```swift
// WRONG - View is doing composition
Text(viewModel.firstName) + Text(" ") + Text(viewModel.lastName)

// Problems:
// - Ordering is hardcoded (some locales put family name first)
// - Separator is hardcoded (some locales use no space)
// - RTL languages would display incorrectly
```

```swift
// RIGHT - ViewModel provides the shaped result
Text(viewModel.fullName)

// The ViewModel uses @LocalizedCompoundString to compose with locale-awareness
@LocalizedCompoundString(pieces: \.namePieces, separator: \.nameSeparator) var fullName
```

**Rule:** Views should never concatenate, format, or reorder ViewModel properties. If you see `+` or string interpolation in a View, the shaping belongs in the ViewModel.

---

## Core Protocols

### Model (`Sources/FOSMVVM/Protocols/Model.swift`)

The source of truth for an entity that exists.

```swift
public protocol Model: Codable, Hashable {
    static var modelType: String { get }
    var id: ModelIdType? { get }
    func requireId() throws -> ModelIdType
}
```

Key characteristics:
- **id** - Unique identifier for the instance
- **Codable** - Can be serialized for storage/transmission
- **Hashable** - Can be compared and used in sets/dictionaries

### ValidatableModel (`Sources/FOSMVVM/Protocols/ValidatableModel.swift`)

A Model that can validate its data.

```swift
public protocol ValidatableModel {
    func validate(fields: [any FormFieldBase]?, validations: Validations) -> ValidationResult.Status?
}
```

Used by Fields protocols to provide shared validation across API, UI, and persistence layers.

### ViewModel (`Sources/FOSMVVM/Protocols/ViewModel.swift`)

A representation of data shaped for presentation in a View.

```swift
public protocol ViewModel: ServerRequestBody, RetrievablePropertyNames, Identifiable, Stubbable {
    var vmId: ViewModelId { get }
}
```

Key characteristics:
- **vmId** - Unique identifier, ideally derived from underlying data
- **ServerRequestBody** - Can be serialized for HTTP transmission
- **RetrievablePropertyNames** - Enables localization property binding
- **Stubbable** - Testing support with `stub()` factory

Use the `@ViewModel` macro to auto-generate `propertyNames()` bindings.

### RequestableViewModel

A ViewModel that can be directly requested from the server:

```swift
public protocol RequestableViewModel: ViewModel {
    associatedtype Request: ViewModelRequest
}
```

### ViewModelFactory

The **projector** - transforms Model data into ViewModel projections.

```swift
public protocol ViewModelFactory where Self: ViewModel {
    associatedtype Context: ViewModelFactoryContext
    static func model(context: Context) async throws -> Self
}
```

The factory:
1. Queries the Model layer (SELECT)
2. Projects data into ViewModel properties (columns, transforms)
3. Returns ViewModel with pending localization

This maps directly to relational algebra:
- **Model** → Table (source data)
- **ViewModelFactory** → SELECT statement (the projector)
- **ViewModel** → Result set (the projection)

Localization happens during encoding via `JSONEncoder.localizingEncoder()`.

### ServerRequest (`Sources/FOSMVVM/Protocols/ServerRequest.swift`)

Standardized REST communication:

```swift
public protocol ServerRequest {
    associatedtype Query: ServerRequestQuery      // URL query params
    associatedtype Fragment: ServerRequestFragment // URL fragment
    associatedtype RequestBody: ServerRequestBody  // HTTP body (outgoing)
    associatedtype ResponseBody: ServerRequestBody // HTTP body (incoming)

    var action: ServerRequestAction { get }  // show, create, update, delete, etc.
}
```

Specialized variants:
- **ShowRequest** - GET, read-only
  - **ViewModelRequest** - ShowRequest where ResponseBody is a ViewModel
- **CreateRequest** - POST, RequestBody must be ValidatableModel
- **UpdateRequest** - PATCH, RequestBody must be ValidatableModel
- **DeleteRequest** - DELETE (soft)
- **DestroyRequest** - DELETE (hard)

### ServerRequestBody and Body Size Limits

`ServerRequestBody` is the protocol for request/response body data:

```swift
public protocol ServerRequestBody: Codable, Sendable {
    static var bodyPath: String { get }
    static var maxBodySize: ServerRequestBodySize? { get }
}
```

For large uploads (files, images, etc.), specify `maxBodySize` to override the server's default body collection limit:

```swift
struct FileUploadBody: ServerRequestBody {
    static var maxBodySize: ServerRequestBodySize? { .mb(50) }

    let fileName: String
    let fileData: Data
}
```

The `ServerRequestBodySize` enum provides type-safe size specifications:

```swift
public enum ServerRequestBodySize {
    case bytes(_ count: UInt)  // Raw bytes
    case kb(_ count: UInt)     // Kilobytes (× 1,024)
    case mb(_ count: UInt)     // Megabytes (× 1,048,576)
    case gb(_ count: UInt)     // Gigabytes (× 1,073,741,824)
}
```

When a `ServerRequestController` registers routes, it automatically applies the body size limit from the `RequestBody` type.

### ServerRequestError - Typed Error Responses

Each `ServerRequest` can define a custom `ResponseError` type for structured error handling:

```swift
public protocol ServerRequest {
    associatedtype ResponseError: ServerRequestError
    // ...
}

public protocol ServerRequestError: Error, Codable, Sendable {}
```

#### How Error Decoding Works

When processing a response, the framework follows this flow:

```
Server returns response
         │
         ▼
┌────────────────────────────────┐
│ Check HTTP status (200-299)   │
│  - Success? Continue to decode │
│  - Failure? Fall to error path │
└────────────────────────────────┘
         │
         ▼
┌────────────────────────────────┐
│ Try decode as ResponseBody     │
│  - Success? Return result      │
│  - Failure? Fall to error path │
└────────────────────────────────┘
         │ (on any error)
         ▼
┌────────────────────────────────┐
│ Try decode as ResponseError    │
│  - Success? THROW that error   │◄── Custom error surfaces here
│  - Failure? Throw DataFetchError│
└────────────────────────────────┘
         │
         ▼
┌────────────────────────────────┐
│ Client catches error           │
│  try/catch at call site        │
└────────────────────────────────┘
```

The key insight: if the server returns JSON that can't decode as `ResponseBody` but CAN decode as `ResponseError`, that typed error is thrown. This works even when HTTP status is 200 (some APIs return errors with success status codes).

#### Why Use Custom ServerRequestError?

**1. Type-Safe Error Handling**

```swift
struct CreateIdeaError: ServerRequestError {
    let field: String
    let message: String
    let code: ErrorCode

    enum ErrorCode: String, Codable {
        case duplicateContent
        case quotaExceeded
        case invalidCategory
    }
}

final class CreateIdeaRequest: CreateRequest {
    typealias ResponseError = CreateIdeaError
    // ...
}

// Client gets structured error handling
do {
    try await request.processRequest(mvvmEnv: mvvmEnv)
} catch let error as CreateIdeaError {
    switch error.code {
    case .duplicateContent: showDuplicateWarning()
    case .quotaExceeded: showUpgradePrompt()
    case .invalidCategory: highlightCategoryField()
    }
}
```

**2. Validation Errors with Field-Level Detail**

```swift
struct ValidationError: ServerRequestError {
    let errors: [FieldError]

    struct FieldError: Codable {
        let field: String
        let messages: [LocalizableString]
    }
}

// Server returns:
// { "errors": [
//     { "field": "email", "messages": ["Invalid format"] },
//     { "field": "password", "messages": ["Too short", "Needs uppercase"] }
// ]}

// Client highlights specific fields
catch let error as ValidationError {
    for fieldError in error.errors {
        formFields[fieldError.field]?.showErrors(fieldError.messages)
    }
}
```

**3. Different Requests, Different Error Shapes**

```swift
final class LoginRequest: CreateRequest {
    typealias ResponseError = LoginError  // credentials, lockout, 2FA required
}

final class FileUploadRequest: CreateRequest {
    typealias ResponseError = UploadError  // file too large, invalid type, quota
}

final class PaymentRequest: CreateRequest {
    typealias ResponseError = PaymentError  // card declined, insufficient funds
}
```

**4. Error Recovery Information**

```swift
struct RateLimitError: ServerRequestError {
    let retryAfterSeconds: Int
    let currentLimit: Int
    let resetAt: LocalizableDate
}

// Client implements smart retry
catch let error as RateLimitError {
    await Task.sleep(for: .seconds(error.retryAfterSeconds))
    try await request.processRequest(mvvmEnv: mvvmEnv)
}
```

**5. Contextual Error Handling at Call Site**

The primary pattern is try/catch where you make the request:

```swift
do {
    try await request.processRequest(mvvmEnv: mvvmEnv)
    // Success - use request.responseBody
} catch let error as CreateIdeaError {
    switch error.code {
    case .duplicateContent: showDuplicateWarning()
    case .quotaExceeded: showUpgradePrompt()
    case .invalidCategory: highlightCategoryField()
    }
} catch {
    showGenericError(error)
}
```

This gives you full context about what operation failed and lets you take appropriate action.

**6. Localized Error Messages**

Error types can use `LocalizableString` for automatic localization (see [The Localization System](#the-localization-system)):

```swift
struct LocalizedError: ServerRequestError {
    let userMessage: LocalizableString  // Localized via YAML like any ViewModel property
    let technicalCode: String           // "SESSION_EXPIRED"
}
```

#### When to Use EmptyError

Use `EmptyError` (the default) when:
- The operation rarely fails
- Failures are truly exceptional (network down, server crash)
- No structured error response is expected from the server
- You only need success/failure, not why

#### Quick Reference

| Aspect | EmptyError | Custom ServerRequestError |
|--------|------------|---------------------------|
| Error detail | None | Full structured context |
| Field-level info | No | Yes |
| Recovery guidance | No | Yes |
| Type-safe handling | No | Yes |
| Localized messages | No | Yes |
| Per-request customization | No | Yes |

---

## The Localization System

### Design Goals (from `Localizable.swift`)

- Work on ALL Swift platforms (iOS, macOS, Linux, Windows)
- Use YAML files that are diff-able and mergeable
- Bind tightly to ViewModels via property wrappers
- **Deferred localization** - resolve at encode time, not declaration time
- Fully testable for missing localizations

### Deferred Localization Pattern

```
LocalizableString.localized(ref)  →  encode()  →  LocalizableString.constant("Hello")
        ↑                              ↑                     ↑
   "Pointer to YAML"          Localizer resolves      "Actual string"
```

1. Property wrappers store a **reference** to a YAML key path
2. During `encode()`, the Localizer looks up values in LocalizationStore
3. Decoded ViewModel has fully resolved strings

**Key insight:** This pattern works identically in both hosting modes:
- **Server-hosted:** Server encodes → localization resolves → client receives localized JSON
- **Client-hosted:** Client encodes → localization resolves → same result, just local

### Key Types

| Type | Purpose |
|------|---------|
| `Localizable` | Base protocol for all localizable types |
| `LocalizableString` | Text that can be `.empty`, `.constant`, or `.localized(ref)` |
| `LocalizableDate` | Date formatted per locale |
| `LocalizableInt` | Integer formatted per locale |
| `LocalizableSubstitutions` | Template string with `%{key}` substitution points |
| `LocalizableCompoundValue` | Multiple pieces joined with locale-aware ordering |
| `LocalizableRef` | Reference to YAML key path |
| `LocalizationStore` | Protocol for translation storage |
| `YamlStore` | YAML-based implementation |

### Property Wrappers

```swift
@ViewModel struct MyViewModel {
    // Simple values
    @LocalizedString var title           // String from YAML
    @LocalizedInt(value: 42) var count   // Formatted integer
    @LocalizedDate var createdAt         // Formatted date

    // Contextual composition
    @LocalizedSubs(substitutions: \.subs) var greeting  // "Hello, %{name}!"
    @LocalizedCompoundString(pieces: \.pieces) var fullName  // Joins pieces with locale-aware ordering

    private var subs: [String: any Localizable] { ["name": ...] }
    private var pieces: [LocalizableString] { [firstName, lastName] }
}
```

### YAML Structure

```yaml
en:
  TypeName:                    # Swift type name
    propertyName: "value"      # Direct property
    fieldName:                 # Nested for fields
      title: "Field Title"
      placeholder: "Enter..."
      validationMessages:
        required: "Field is required"
```

Key path: `TypeName.fieldName.title`

---

## The Forms System

### FormField (`Sources/FOSMVVM/Forms/FormField.swift`)

A rich, platform-agnostic description of a form input:

```swift
public struct FormField<Value>: FormFieldBase {
    let fieldId: FormFieldIdentifier      // Unique ID within form
    let title: LocalizableString          // Display label
    let placeholder: LocalizableString?   // Placeholder text
    let type: FormFieldType               // Control type
    var options: [FormInputOption<Value>] // Constraints & behavior
}
```

### FormFieldType

```swift
public enum FormFieldType {
    case text(inputType: FormInputType)      // Single-line input
    case textArea(inputType: FormInputType)  // Multi-line input
    case checkbox                            // Boolean toggle
    case colorPicker                         // Color selection
    case select                              // Dropdown
}
```

### FormInputType

Maps to platform semantics (keyboard types, autofill):

```swift
public enum FormInputType {
    case text, emailAddress, password, tel, url, date, number
    case givenName, familyName, organizationName  // Apple autofill
    // ... many more
}
```

### FormInputOption

Constraints and presentation options:

```swift
public enum FormInputOption<Value> {
    case required(value: Bool)
    case minLength(value: Int), maxLength(value: Int)
    case minValue(value: Int), maxValue(value: Int)
    case minDate(date: Date), maxDate(date: Date)
    case autocomplete(value: Autocomplete)
    case autocapitalize(value: Autocapitalize)
    case disabled(value: Bool)
}
```

### FormFieldModel

Property wrapper that binds FormField to ViewModel data:

```swift
@ViewModel struct UserFormModel: UserFields {
    @FormFieldModel(UserFormModel.emailField) var email: String?
    @FormFieldModel(UserFormModel.firstNameField) var firstName: String?
}
```

---

## Form Specifications (Fields Protocols)

A `{Name}Fields` protocol is a **Form Specification** - the single source of truth for user input:

### What It Defines

1. **Properties** - What data can the user provide
2. **FormField definitions** - How to present each field (type, keyboard, autofill)
3. **Validation rules** - What constraints apply
4. **Localization** - Titles, placeholders, error messages

### Structure

```swift
// The Form Specification
public protocol IdeaFields: ValidatableModel, Codable, Sendable {
    var content: String { get set }
    var ideaValidationMessages: IdeaFieldsMessages { get }
}

public extension IdeaFields {
    static var contentRange: ClosedRange<Int> { 1...10000 }

    static var contentField: FormField<String?> { .init(
        fieldId: .init(id: "content"),
        title: .localized(for: IdeaFieldsMessages.self, propertyName: "content", messageKey: "title"),
        placeholder: .localized(for: IdeaFieldsMessages.self, propertyName: "content", messageKey: "placeholder"),
        type: .textArea(inputType: .text),
        options: [.required(value: true)] + FormInputOption.rangeLength(contentRange)
    ) }

    func validateContent(_ fields: [FormFieldBase]?) -> [ValidationResult]? { ... }
}

// Validation Messages
@FieldValidationModel public struct IdeaFieldsMessages {
    @LocalizedString("content", messageGroup: "validationMessages", messageKey: "required")
    public var contentRequiredMessage
}
```

### Where It's Used

The same Fields protocol is adopted by multiple types:

```swift
// In RequestBody (client → server transmission)
struct RequestBody: ServerRequestBody, IdeaFields { ... }

// In ViewModel (for form rendering)
@ViewModel struct IdeaFormViewModel: IdeaFields { ... }

// In Model (for persistence validation)
final class Idea: Model, IdeaFields { ... }
```

**Key insight:** Validation is shared - defined once, used everywhere.

### Generated Files

A complete form specification consists of:

1. **`{Name}Fields.swift`** - Protocol + FormField definitions + validation methods
2. **`{Name}FieldsMessages.swift`** - `@FieldValidationModel` struct with `@LocalizedString` properties
3. **`{Name}FieldsMessages.yml`** - YAML localization file

---

## Request/Response Cycle

### Reading Data (ViewModelRequest)

1. Client creates `ViewModelRequest`
2. Server's `ViewModelFactory.model(context:)` queries database
3. Factory builds ViewModel with pending localizations
4. Server encodes with `JSONEncoder.localizingEncoder()` → resolves all strings
5. Client decodes fully localized ViewModel
6. View displays ViewModel

### Writing Data (CreateRequest/UpdateRequest)

1. Client fills form (Fields protocol provides metadata + validation)
2. Client validates locally using Fields validation methods
3. Client creates Request with RequestBody conforming to Fields
4. Server receives, validates again (same Fields protocol)
5. Server persists to Model

---

## Key Macros

| Macro | Purpose |
|-------|---------|
| `@ViewModel` | Generates `propertyNames()` for localization binding |
| `@ViewModel(options: [.clientHostedFactory])` | Additionally generates `ClientHostedViewModelFactory` support (AppState, Request, factory method) |
| `@FieldValidationModel` | Generates `propertyNames()` for validation message types |
| `@VersionedFactory` | Generates versioned `model(context:)` dispatcher for API versioning |

### What @ViewModel Generates

The `@ViewModel` macro always generates:
- `ViewModel` protocol conformance
- `RetrievablePropertyNames` protocol conformance
- `propertyNames()` function mapping `LocalizableId` → property names

With `clientHostedFactory` option, it additionally generates:
- `typealias Request = ClientHostedRequest`
- `AppState` struct (from init parameters)
- `ClientHostedRequest` class
- `model(context:)` factory method

---

## Testing Support

FOSMVVM provides comprehensive testing infrastructure for ViewModels, ensuring codable round-trips, versioning stability, and multi-locale translations all work correctly.

### Stubbable Protocol

All ViewModels conform to `Stubbable`:

```swift
public protocol Stubbable {
    static func stub() -> Self
}
```

Use `isStub` property to detect stub instances. The `stub()` method provides default instances for testing and SwiftUI previews.

### LocalizableTestCase Protocol

Test suites that verify ViewModels should conform to `LocalizableTestCase`:

```swift
import FOSTesting
import Testing

@Suite("My ViewModel Tests")
struct MyViewModelTests: LocalizableTestCase {
    let locStore: LocalizationStore

    init() throws {
        self.locStore = try Self.loadLocalizationStore(
            bundle: Bundle.module,
            resourceDirectoryName: "TestYAML"
        )
    }
}
```

This protocol provides:
- `locStore` - The localization store loaded from YAML
- `locales` - Set of locales to test (default: `en`, `es`)
- `encoder(locale:)` - Helper to create localizing encoders
- Testing methods for ViewModels, FieldValidationModels, and FormFields

### Core Testing Method: expectFullViewModelTests

The primary testing method verifies everything in one call:

```swift
@Test func dashboardViewModel() throws {
    try expectFullViewModelTests(DashboardViewModel.self)
}
```

This single call verifies:
1. **Codable round-trip** - ViewModel can encode and decode without data loss
2. **Versioned ViewModel stability** - Structure hasn't changed unexpectedly
3. **Translations for all locales** - Every `@LocalizedString` property has values in all configured locales

**This is the standard pattern for most ViewModel tests.**

### Testing Specific Formatting Behavior

When you need to verify specific substitution or formatting behavior, add locale-specific assertions after `expectFullViewModelTests()`:

```swift
@Test func embeddedLocalization() throws {
    // First: comprehensive tests for all locales
    try expectFullViewModelTests(MainViewModel.self)

    // Then: verify specific substitution behavior with known English values
    let vm: MainViewModel = try .stub()
        .toJSON(encoder: encoder(locale: en))
        .fromJSON()

    #expect(try vm.greeting.localizedString == "Welcome, John!")
    #expect(try vm.itemCount.localizedString == "42 items")
}
```

This extended pattern is optional - use it only when testing specific formatting techniques like `@LocalizedSubs` substitutions or `@LocalizedCompoundString` composition.

### Available Testing Methods

| Method | Purpose |
|--------|---------|
| `expectFullViewModelTests(_:locales:)` | Complete ViewModel testing (codable, versioning, translations) |
| `expectTranslations(_:locales:)` | Translation-only verification |
| `expectFullFieldValidationModelTests(_:locales:)` | Complete FieldValidationModel testing |
| `expectFullFormFieldTests(_:locales:)` | FormField title/placeholder translations |
| `expectCodable(_:encoder:decoder:)` | Codable round-trip only |
| `expectVersionedViewModel(_:encoder:)` | Versioning stability only |

### YAML Structure for Test ViewModels

Test ViewModels need YAML entries for their `@LocalizedString` properties:

```yaml
# TestYAML/MyViewModel.yml
en:
  MyViewModel:
    pageTitle: "Dashboard"
    emptyMessage: "No items yet"

es:
  MyViewModel:
    pageTitle: "Tablero"
    emptyMessage: "No hay elementos todavía"
```

For embedded/child ViewModels, include entries for all ViewModel types in the hierarchy.

### Test File Organization

```
Tests/
  {Target}Tests/
    Localization/
      {Feature}ViewModelTests.swift
    TestYAML/
      {ViewModelName}.yml
```

### Quick Reference

**Standard test (most cases):**
```swift
@Test func myFeature() throws {
    try expectFullViewModelTests(MyViewModel.self)
}
```

**With specific behavior verification:**
```swift
@Test func myFeatureWithSubstitutions() throws {
    try expectFullViewModelTests(MyViewModel.self)

    let vm: MyViewModel = try .stub()
        .toJSON(encoder: encoder(locale: en))
        .fromJSON()
    #expect(try vm.greeting.localizedString == "Hello, World!")
}
```

### ServerRequest Testing

ServerRequest types are tested using VaporTesting infrastructure with typed request/response handling.

**Core Pattern:** Use `TestingApplicationTester.test()` with a typed `ServerRequest`:

```swift
import FOSTestingVapor
import VaporTesting

@Test func showRequest_success() async throws {
    try await withTestApp { app in
        let request = UserShowRequest(query: .init(userId: validId))

        try await app.testing().test(request, locale: en) { response in
            #expect(response.status == .ok)
            #expect(response.body?.viewModel.name == "Expected Name")
        }
    }
}
```

**What the infrastructure handles:**
- Path derivation from type name (`UserShowRequest` → `/user_show`)
- HTTP method from action (`ShowRequest` → GET)
- Query/body encoding
- Header injection (locale, version)
- Response decoding to typed `ResponseBody`

**TestingServerRequestResponse<R>** provides typed access:

| Property | Type | Description |
|----------|------|-------------|
| `status` | `HTTPStatus` | HTTP status code |
| `headers` | `HTTPHeaders` | Response headers |
| `body` | `R.ResponseBody?` | Typed response (auto-decoded) |
| `error` | `R.ResponseError?` | Typed error (auto-decoded) |

**NEVER do this:**
```swift
// WRONG - manual URL construction
try await app.test(.GET, "/user_show?userId=123") { response in }

// WRONG - manual HTTP request
let url = URL(string: "http://localhost/path")!
```

**Test organization:**
```
Tests/
  {Target}Tests/
    Requests/
      {Feature}RequestTests.swift
    TestYAML/
      {ViewModelName}.yml
```

For complete ServerRequest test patterns, see the [fosmvvm-serverrequest-test-generator](../.claude/skills/fosmvvm-serverrequest-test-generator/SKILL.md) skill.

---

## The Shared Module Pattern

A typical FOSMVVM project is a Swift Package with multiple targets. The key architectural element is the **shared module** - a target that both clients and server import.

### Why a Shared Module?

Clients and server must agree on:
- **ServerRequest types** - The API contract (request/response shapes)
- **ViewModels** - The data structures clients render
- **Fields protocols** - Validation logic (same rules everywhere)
- **SystemVersion** - App version constants (same version header everywhere)

Without a shared module, these would be duplicated and drift apart.

### Project Structure

```
Package.swift
Sources/
  ViewModels/                    ← SHARED MODULE (imported by ALL others)
    ViewModels/
      UserViewModel.swift
      IdeaCardViewModel.swift
    Requests/
      CreateIdeaRequest.swift
      MoveIdeaRequest.swift
    FieldModels/
      IdeaFields.swift
      UserFields.swift
    Versioning/
      SystemVersion+App.swift    ← App version constants (see below)

  WebServer/                     ← Server target (imports ViewModels)
    Controllers/
    DataModels/
    ViewModelFactories/

  WebApp/                        ← Web client (imports ViewModels)
    Routes/
    Views/

  iOSApp/                        ← iOS app (imports ViewModels)

  JSONLImporter/                 ← CLI tool (imports ViewModels)
```

### Dependency Graph

```
                    ┌─────────────────┐
                    │   ViewModels    │  ← Shared module
                    │  (shared types) │
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│   WebServer   │   │    WebApp     │   │   CLI Tools   │
│   (Vapor)     │   │   (Vapor)     │   │  (standalone) │
└───────────────┘   └───────────────┘   └───────────────┘
        │                    │                    │
        └────────────────────┴────────────────────┘
                             │
                    All use same ServerRequest types
                    All use same SystemVersion
                    All use processRequest(mvvmEnv:)
```

### SystemVersion in the Shared Module

The shared module defines app version constants:

```swift
// Sources/ViewModels/Versioning/SystemVersion+App.swift
import FOSFoundation

public extension SystemVersion {
    /// The current application version
    static var currentApplicationVersion: Self { .v1_0 }

    // Version constants
    static var v1_0: Self { .init(major: 1, minor: 0, patch: 0) }
    static var v1_1: Self { .init(major: 1, minor: 1, patch: 0) }
}
```

All targets import this and use the same version:

```swift
// In any client (iOS, CLI, WebApp, etc.)
let mvvmEnv = await MVVMEnvironment(
    currentVersion: .currentApplicationVersion,  // From shared module
    appBundle: Bundle.module,
    deploymentURLs: [.debug: URL(string: "http://localhost:8080")!]
)
```

### What Belongs Where

| Artifact | Location | Why |
|----------|----------|-----|
| ServerRequest types | Shared module | API contract |
| ViewModels | Shared module | Response shapes |
| Fields protocols | Shared module | Validation logic |
| SystemVersion extension | Shared module | Version constants |
| DataModels (Fluent) | Server only | Database schema |
| ViewModelFactories | Server only | Query logic |
| Controllers | Server only | Route handlers |
| Views (SwiftUI/Leaf) | Client only | Rendering |

### Key Insight

If a type is needed by both client and server, it belongs in the shared module. This includes:
- Anything in a `ServerRequest` definition
- Anything used by `MVVMEnvironment`
- Anything that must be consistent across all targets

---

## File Organization Conventions

```
Sources/
  {ViewModelsTarget}/           # Shared ViewModels package (the shared module)
    ViewModels/
      {Name}ViewModel.swift
    FieldModels/
      {Name}Fields.swift
      {Name}FieldsMessages.swift
    Requests/
      {Name}Request.swift

  {ResourcesPath}/              # Localization resources
    ViewModels/
      {Name}ViewModel.yml
    FieldModels/
      {Name}FieldsMessages.yml

  {WebServerTarget}/            # Server-side (Vapor)
    ViewModelFactories/
      {Name}ViewModelFactory.swift
    DataModels/
      {Name}.swift
```

---

## Summary

FOSMVVM provides:

1. **Model at the center** - The source of truth that reads and writes flow through
2. **ViewModels as projections** - Shaped views of Model data for presentation
3. **Flexible hosting** - Same ViewModel patterns work server-hosted or client-hosted
4. **Shared validation** - Define once in Fields, use everywhere (API, UI, persistence)
5. **Deferred localization** - Localization happens at encode time, wherever that occurs
6. **Type-safe requests** - ServerRequest protocol hierarchy for CRUD operations
7. **Platform-agnostic forms** - FormField abstraction works on iOS, web, etc.
8. **Testing support** - Stubbable ViewModels, LocalizableTestCase for ViewModel tests, TestingApplicationTester for ServerRequest tests

The key insight is that **the Model is the center**. ViewModels are projections of Model data shaped for display. CRUD requests are validated mutations of Model data. Both reads and writes flow through the Model layer.
