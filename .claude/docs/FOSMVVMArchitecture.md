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
  ShowRequest  CreateRequest  UpdateRequest  ArchiveRequest  DestroyRequest
  (GET/show)   (POST/create) (PATCH/update) (DELETE/archive) (DELETE/destroy)
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
    where RequestBody: ValidatableModel,
    ResponseError: ValidatableViewModelRequestError {}

// Update existing entity
public protocol UpdateRequest: ServerRequest
    where RequestBody: ValidatableModel,
    ResponseError: ValidatableViewModelRequestError {}

// Archive (the row stays, marked deleted through its delete timestamp)
public protocol ArchiveRequest: ServerRequest {}

// Destroy (the row is removed)
public protocol DestroyRequest: ServerRequest {}
```

Flow: `CreateRequest` → validate `RequestBody` → persist to Model layer, where the model's own validation runs again before the row is written.

A write request's `ResponseError` must be able to carry validation results, which is why `CreateRequest` and `UpdateRequest` constrain it; `ValidationError` is the ready-made choice. Registering an `ArchiveRequest` for a model that declares no `@Timestamp(key:, on: .delete)` fails at boot with `ServerRequestControllerError.archiveUnsupported(request:model:)` — give the model the timestamp, or serve a `DestroyRequest` instead.

### The Shared Validation Contract

A Fields protocol states the user-editable contract once — the properties, the FormField definitions, the rules, the localized messages — and three types adopt it, so one rule set answers for a value wherever the value appears.

**`UserFields`, adopted by:**

- **`UserCreateRequest.RequestBody`** — the wire body. Checked when the request arrives, before anything is loaded.
- **`UserFormViewModel`** — the form. Checked as the user edits, and again at submit.
- **`User`** — the `DataModel`. Checked once more immediately before the row is written.

**Define once, validate everywhere.**

#### Two validations, not one

**Field validation** is the Fields protocol's own `validate(fields:validations:)`. It judges the model's values in isolation — an empty title, a number outside its range — and needs nothing but the model. It runs on create and update. Archive, destroy and restore write none of the model's own columns, so there is nothing in them to judge.

**Model validation** is `DataModelLifecycle.validateModel(in:)`. It judges the model against the rest of the database — a title already taken within its board, a board that still has cards and so may not be destroyed. It receives a `DataModelWriteContext` carrying the action, the database, and the `Application`, and returns one `ValidationResult` per rule that failed. It runs for every action, the three that write no columns included.

The two are layers of one answer, not alternatives. Field validation goes first and model validation never runs when it failed: a rule that queries the database against a value the form already refused would be asking a question that has no meaning.

Both write into one accumulator. The framework creates one `Validations` per write; no level can assign the array, so no level can erase what another found. The Fields rules hand their results to `replace(with:)` — field-scoped, so running them again re-answers for their own fields rather than stacking a second copy of the same message, and leaves every other level's results standing. `validateModel(in:)` returns its results rather than holding the accumulator, which is what makes that guarantee structural rather than a convention.

A `ValidationResult` that names no field is about the model as a whole. `ValidationResult(status:message:)` mints one, `Message.addressesModel` recognizes one, and `withFormValidations()` is the modifier that shows them — the field views only ever show messages naming their own field.

#### The order, for one write

1. **`willWrite(in:)`** — the model may change itself: derive, trim, stamp. This is the one hook that mutates. A throw here is an error, never a validation.
2. **Field validation** — the Fields protocol's rules, with `fields: nil`, on create and update.
3. **Refusal** — errors, or warnings under a blocking policy, stop here with a `ValidationError` carrying everything collected.
4. **`validateModel(in:)`** — every action. Every rule runs; nothing short-circuits inside it.
5. **Refusal** again, by the same rule.
6. **The write** — Fluent applies the action. A driver constraint failure is offered to `validationResult(for:)`; a returned result becomes a `ValidationError`, and `nil` rethrows the original error unchanged.
7. **`didWrite(in:)`** — the same database, so the same transaction. May write related rows. A throw rolls the transaction back.
8. **`didCommit(in:)`** — `async`, non-throwing, side effects only.

Every hook is a protocol requirement with a do-nothing default, so a model declares only the ones it needs and a model that declares none saves exactly as it did before. The defaults live on the protocol rather than in an extension alongside it, because an extension-only hook would let a model's override compile and never be called.

`ValidationWarningPolicy` decides what a warning does at the two refusal points. The default, `.advisory`, lets the write proceed; `.blocking` stops it and sends the warnings to the client the way an error is sent. An advisory warning on a write that succeeds is logged and dropped — carrying it would be a wire change to every write's response.

#### Registration is what installs it

```swift
// in configure(_:)
try app.register(Board.self, migration: Board.Initial())                  // a container
try app.register(Card.self, migration: Card.Initial())                    // a contained model
try app.register(ServiceStatus.self, migration: ServiceStatus.Create())   // declared by no container
```

`register(_:migration:)` adds the Fluent migration, enters the model in the type registry, and installs the lifecycle for it — one call, so declaring the migration *is* registering the model and there is no second step to forget. Every `DataModel` goes through it, container or not. A bare `app.migrations.add(...)` on a `DataModel` creates the table and skips the hooks; the review reports it.

The lifecycle is installed ahead of live invalidation's emit, so it is the outer of the two: both validations run before anything else touches the row, and the emit fires inside the write.

#### After the commit

`didCommit(in:)` receives a `DataModelCommitContext` — the action and the `Application`, and no database, because the transaction is over. It is where the email is sent and the other system is told.

It runs when the transaction commits inside `liveTransaction { }`, with or without live invalidation enabled, and immediately after the write on an auto-commit `save(on:)`. Inside a bare `database.transaction { }` it does not run at all and the framework warns once per type: nothing there can observe the commit. Use `liveTransaction` for any write whose commit a hook must see.

#### What a batch write cannot do

FluentKit's `[Card].create(on:)` and `[Card].delete(on:)` call each model's middleware with a `next` that writes nothing, then issue one bulk statement after every middleware has returned. The consequences are the contract, not a defect to work around:

- The hooks run per model, before any row exists — so `didWrite(in:)` sees no row.
- A constraint failure is never offered to `validationResult(for:)`.
- A batch delete always dispatches `.destroy`; `.archive` is unreachable through it.

Write the models individually where any of that matters. The review warns on a batch write of a `DataModel`.

#### The typed error path

A write request's `ResponseError` conforms to `ValidatableViewModelRequestError`; `CreateRequest` and `UpdateRequest` require it. The write route catches the `ValidationError` raised by the body's own rules and by the save, and rethrows it as `SR.ResponseError(validations:)` — so the lifecycle stays request-agnostic and the client always decodes the error type its request declared, then reads `.validations` from it.

```swift
public typealias ResponseError = ValidationError   // the ready-made choice
```

Without the constraint a write request could declare an error type that cannot carry validations, and the user would get a decode failure where the messages should have been.

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

Localization happens during encoding via `JSONEncoder.localizingEncoder(in:store:)`.

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
- **ArchiveRequest** - DELETE (the row stays, marked deleted)
- **DestroyRequest** - DELETE (the row is removed)

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

**`ResponseError` is the operation's semantic error — NOT an HTTP-status mapping.**

If there were no wire, the operation would be a local function call,
and it would `throw` a well-defined Swift error.
`ResponseError` **is** that error.
`ServerRequestError` exists so the throw can happen *across the wire*:

1. Server-side code `throw`s the typed error
2. It rides the response body as `Codable` (encoded by `ErrorMiddleware`)
3. The client's `processRequest` rethrows the **same typed error** —
   as if the call had been local

The HTTP status underneath is transport dressing the framework applies.
It carries no result semantics, and nobody should read it back to
interpret a result.

**Design starts from the throw, never from the status:**

- ✅ "What would this operation `throw` if it were a local call?" —
  that error is the `ResponseError`
- ❌ "What should a 401 become on the client?" —
  status-first thinking; the wrong frame entirely

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

The key insight: this decode chain is transport *plumbing*, not semantics. If the server returns JSON that can't decode as `ResponseBody` but CAN decode as `ResponseError`, that typed error is thrown — even when the HTTP status is 200. The status check exists only to route decoding down the error path; the client branches by **catching the typed case**, never by reading a status.

**Never interpret results from HTTP statuses:**

```swift
// ❌ WRONG - status sniffing. A 401 is a raw transport number;
// ANY failure can wear it, so the client learns nothing typed.
catch DataFetchError.badStatus(401) {
    refreshSessionAndRetry()
}

// ✅ RIGHT - the operation's thrown vocabulary crossed the wire; catch the case
catch let error as LoginError where error.code == .sessionExpired {
    refreshSessionAndRetry()
}
```

#### The Framework's Own Typed Throws

The middleware stack is itself a layer that can throw
**before the operation runs** — a credential check, a version gate.

FOS declares well-known typed errors for those rejections.
The client-visible thrown vocabulary of `processRequest` is therefore:

    the request's ResponseError  ∪  the framework's own well-known errors

There is currently one such error: **`CredentialRejectedError`**.

- Served by `ClientCredentialMiddleware` + FOS `ErrorMiddleware`.
- Two caller-actionable meanings: `.missing` / `.invalid`.
- Rethrown typed by `processRequest` — always thrown
  **past** `requestErrorHandler`, never routed to it.
- Decoded **before** the request's own `ResponseError`, so a
  permissive `ResponseError` (even `EmptyError`) cannot swallow it.
- The rejection happens before the operation runs, so
  refresh-and-retry after recovery never duplicates effects.

```swift
do {
    try await request.processRequest(mvvmEnv: mvvmEnv)
} catch let error as CredentialRejectedError {
    switch error.code {
    case .missing: break // no credential was presented — check the
                         // MVVMEnvironment's clientCredentialProvider
    case .invalid: break // presented but refused — refresh the credential
                         // and retry (safe: the operation never ran)
    }
}
```

#### Why Use Custom ServerRequestError?

**1. Errors with Associated Values (Parameterized Messages)**

For errors that need dynamic data in their messages, use `LocalizableSubstitutions`:

```swift
struct CreateIdeaError: ServerRequestError {
    let code: ErrorCode
    let message: LocalizableSubstitutions

    enum ErrorCode: Codable {
        case duplicateContent
        case quotaExceeded(requestedSize: Int, maximumSize: Int)
        case invalidCategory(category: String)

        var message: LocalizableSubstitutions {
            switch self {
            case .duplicateContent:
                .init(
                    baseString: .localized(for: Self.self, parentType: CreateIdeaError.self, propertyName: "duplicateContent"),
                    substitutions: [:]
                )
            case .quotaExceeded(let requestedSize, let maximumSize):
                .init(
                    baseString: .localized(for: Self.self, parentType: CreateIdeaError.self, propertyName: "quotaExceeded"),
                    substitutions: [
                        "requestedSize": LocalizableInt(value: requestedSize),
                        "maximumSize": LocalizableInt(value: maximumSize)
                    ]
                )
            case .invalidCategory(let category):
                .init(
                    baseString: .localized(for: Self.self, parentType: CreateIdeaError.self, propertyName: "invalidCategory"),
                    substitutions: [
                        "category": LocalizableString.constant(category)
                    ]
                )
            }
        }
    }

    init(code: ErrorCode) {
        self.code = code
        self.message = code.message  // Required to localize properly via Codable
    }
}
```

```yaml
en:
  CreateIdeaError:
    ErrorCode:
      duplicateContent: "The requested content is a duplicate of an existing idea."
      quotaExceeded: "The requested content size %{requestedSize} exceeds the maximum allowed size %{maximumSize}."
      invalidCategory: "The category %{category} is not valid."
```

**2. Simple Errors (Case-Keyed Codes)**

For simpler errors without associated values, use a plain enum — no raw value — and localize each case by the case itself:

```swift
struct SimpleError: ServerRequestError {
    let code: ErrorCode
    let message: LocalizableString

    enum ErrorCode: Codable, Sendable {
        case serverFailed
        case applicationFailed

        var message: LocalizableString {
            .localized(case: self, parentType: SimpleError.self)
        }
    }

    init(code: ErrorCode) {
        self.code = code
        self.message = code.message  // Required to localize properly via Codable
    }
}
```

```yaml
en:
  SimpleError:
    ErrorCode:
      serverFailed: "The server failed"
      applicationFailed: "The application failed"
```

**Enums never take a `String` raw value** (ruled 2026-09-02)

An enum never takes a `String` raw value. A raw value opens a public string door — `Reason(rawValue: "invalid")` — that anyone can mint or parse, and it makes the case's spelling the user-facing text, which cannot localize. Cases localize through the YAML tree keyed by type and case; the wire carries the case, not a string the type published.

The shipped form is the plain enum above: Swift synthesizes its `Codable`, the wire carries the case name, and `LocalizableString.localized(case:parentType:)` derives the YAML key from the case. `enum X: String` is a review blocker (`no-string-backed-enums`).

**3. Type-Safe Client Handling**

```swift
final class CreateIdeaRequest: CreateRequest {
    typealias ResponseError = CreateIdeaError
    // ...
}

// Client gets structured error handling
do {
    try await request.processRequest(mvvmEnv: mvvmEnv)
} catch let error as CreateIdeaError {
    switch error.code {
    case .duplicateContent:
        showDuplicateWarning(message: error.message)
    case .quotaExceeded(let requestedSize, let maximumSize):
        showQuotaError(requested: requestedSize, maximum: maximumSize, message: error.message)
    case .invalidCategory(let category):
        highlightInvalidCategory(category, message: error.message)
    }
}
```

**4. Validation Errors with Field-Level Detail**

FOSMVVM provides built-in `ValidationError` that conforms to `ServerRequestError`:

```swift
// ValidationError contains ValidationResults with field-specific messages
public struct ValidationError: ValidatableViewModelRequestError {
    public let validations: [ValidationResult]
}

public struct ValidationResult: Codable, Hashable, Sendable {
    public let status: Status           // .info, .warning, .error
    public let messages: [Message]

    public struct Message: Codable, Hashable, Sendable {
        public let fieldIds: [FormFieldIdentifier]
        public let message: LocalizableString
    }
}
```

**Controller throwing validation errors:**

```swift
static func performCreate(
    _ request: Vapor.Request,
    _ serverRequest: CreateUserRequest,
    _ requestBody: RequestBody
) async throws -> ResponseBody {
    let validations = Validations()

    // Validate fields
    if requestBody.email.isEmpty {
        validations.append(.init(
            status: .error,
            fieldId: #fieldId(\UserFields.email),
            message: .localized(for: CreateUserRequest.self, propertyName: "emailRequired")
        ))
    }

    if requestBody.password.count < 8 {
        validations.append(.init(
            status: .error,
            fieldId: #fieldId(\UserFields.password),
            message: .localized(for: CreateUserRequest.self, propertyName: "passwordTooShort")
        ))
    }

    // Throw if any errors
    if let error = validations.validationError {
        throw error
    }

    // ... proceed with creation
}
```

**Client handling validation errors:**

```swift
do {
    try await request.processRequest(mvvmEnv: mvvmEnv)
} catch let error as ValidationError {
    for validation in error.validations {
        for message in validation.messages {
            for fieldId in message.fieldIds {
                formFields[fieldId]?.showError(message.message)
            }
        }
    }
}
```

**5. Different Requests, Different Error Shapes**

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

**6. Error Recovery Information**

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

**7. Localized Error Messages**

Error types can use any `Localizable` type for automatic localization (see [The Localization System](#the-localization-system)):

```swift
struct LocalizedError: ServerRequestError {
    let userMessage: LocalizableString  // Localized via YAML like any ViewModel property
    let technicalCode: String           // "SESSION_EXPIRED"
}
```

#### When to Use EmptyError

Use `EmptyError` (the default) when the operation, as a local call, would have
nothing well-defined to throw:
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
    @LocalizedDate(value: model.createdAt) var createdAt // Formatted date

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
}

public extension IdeaFields {
    static var contentRange: ClosedRange<Int> { 1...10000 }

    // A @LocalizedString property binds its key only while its own model is being encoded,
    // so a message read out of an IdeaFieldsMessages instance and carried in a
    // ValidationResult would encode empty. Mint the travelling message from the type.
    static var contentRequiredMessage: LocalizableString {
        .localized(for: IdeaFieldsMessages.self, propertyName: "content", messageGroup: "validationMessages", messageKey: "required")
    }

    static var contentField: FormField<String?> { .init(
        fieldId: #fieldId(\Self.content),
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

// In the DataModel — the framework runs these rules again before the row is written
final class Idea: DataModel, IdeaFields { ... }
```

**Key insight:** Validation is shared - defined once, used everywhere.

The `DataModel` adoption is not decoration. Once the model is registered with `try app.register(Idea.self, migration: Idea.Initial())`, the framework runs these same rules on every create and update, whatever wrote the row — see [The Shared Validation Contract](#the-shared-validation-contract), which also covers the model-level validation a Fields protocol cannot express.

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
4. Server encodes with `JSONEncoder.localizingEncoder(in:store:)` → resolves all strings
5. Client decodes fully localized ViewModel
6. View displays ViewModel

### Writing Data (CreateRequest/UpdateRequest)

1. Client fills form (Fields protocol provides metadata + validation)
2. Client validates locally using Fields validation methods
3. Client creates Request with RequestBody conforming to Fields
4. Server receives, validates again (same Fields protocol)
5. Server loads the writer's candidate scope, resolves the target, applies the body, and saves — and the save runs the model's lifecycle: `willWrite`, the Fields rules once more, `validateModel` against the rest of the database, the write, `didWrite`, then `didCommit` on commit
6. A refusal at either point reaches the client as the request's own `ResponseError`, carrying the results

---

## Containment and Authorization

A server never loads for a route; it loads for a subject. Every record a projection reads arrives through a plan the factory declared, executed against the subject's grants. Two ideas carry that: containment, which says what owns what, and authorization, which says what the subject may do.

### Two axes of authorization

A grant (`ModelAuthorization`) names one model and answers two questions.

**The model-level axis.** What may the holder do to the named model itself: `ModelOperation` — `read`, `write`, `archive`, `destroy`, or the `anyOperation` wildcard (everything but destroy). There is no `create`: a model is created into a container, never on itself.

**The container-level axis.** What does the named model, when it is a container, extend to the models it contains, by contained type: `ContainerOperation` — `readRecords`, `writeRecords`, `createRecords`, `archiveRecords`, `destroyRecords`, or the `anyOperation` wildcard (again, everything but destroy). `AuthorityFlow.inherits` carries that extension down the containment path; `.guards` stops it at the container, so a deeper load needs a grant anchored there.

A container is a model, so it is authorized the same way: its own row by the first axis, its members by the second. A leaf answers the first axis only.

### The union rule

Either authority suffices, and the two never have to agree. A subject may archive a Board because a grant names the Board with `archive`, or because a grant on its Workspace extends `archiveRecords` of type Board. Neither grant knows about the other. Nothing an existing grant authorizes stops being authorized when a grant on a model is added; the model-level axis only adds.

The default answer to the model-level question is `false`, so an app that has only ever written container grants changes nothing until it adopts the axis.

### Scopes

Every clause of a plan is declared within a `ContainmentScope`, the region of data one party owns. The scope decides where the plan begins; the subject's grants decide what loads inside it. A scope never widens authority.

- **`.parent`** — the scope the enclosing factory bound. Every child shares it unless it deliberately opens its own.
- **`.request`** — the container the client named. The request's query is a `ScopedQuery`. One request names one container.
- **`.application`** — the container the application resolves for this caller, registered once with `useApplicationScope(_:)`, or, with nothing registered, the one system container. Overviews, system-wide models, creating a top-level container.
- **`.subject`** — what the subject's grants reach. Nothing to name, nothing to resolve.

### The subject scope

A plan within `.subject` binds to the models of its first type that the subject's grants authorize for the plan's operation, taken one hop deep and as a union: every model a grant names with the operation, plus every such model inside a granted container that directly contains the type. One query per plan, with the request's filter, sort, and window applied inside it, so paging across the union is exact and the total is one count.

Deeper reach stays declared. `via:` descends from the bound set through ordinary containment; each bound model is its own root and anchors its own subtree. The plan never infers a path.

The subject scope is a read scope and a write-candidate scope, never a create scope: a create declares the container it creates into, and `creationPlan(within: .subject)` is refused at boot. A write whose candidates are within the subject scope accepts a target reachable by either authority and refuses one reachable by neither, as not-found.

Every bound model registers for live refresh, so a change to any listed row refreshes the list. The subject's own identity registers too when the provider vends it (`subjectIdentity(for:)`); an app that declares its grant model as contained by the subject then refreshes a subject's lists when a grant is written, through the ordinary invert.

### The container with no table

A model no other model owns — a top-level Workspace, a system-wide status row — has nothing to hang a grant on and nothing to be created into. `SystemContainer` is the answer: a container with one instance and no storage, declaring what it owns as every row of a type, `containment: [.all(Workspace.self), .all(SystemStatus.self)]`, registered with `register(_:)` and no migration.

Its `identity` is minted from the type and is stable, so a grant row stores it like any identity. A grant on it extends to every row of the listed types by the ordinary container-level axis, which is also how it feeds the subject scope: a read of Workspaces within `.subject` includes them all through that one grant.

Create at the top lives here. Creating a Workspace is an operation on no record, so the system container is the only container that can hold a `createRecords` grant for it: `Workspace.creationPlan(within: .application)`, with the application scope bound to the system container. A write to any owned row marks the system container stale, so every list within the application scope refreshes on a create or destroy at the top.

More than one system container is allowed. With exactly one registered and no `useApplicationScope(_:)`, plans within `.application` bind to it by themselves.

### Where it lives

Declarations: `Sources/FOSMVVM/Protocols/` — `ModelOperation`, `ModelAuthorization`, `ContainmentScope`, `LoadingPlan`, `ScopedQuery`, `Container`. Execution: `Sources/FOSMVVMVapor/Containment/` and `Extensions/Request+ContainerLoad.swift` — the engine, the plan executor, the write route, registration, and `SystemContainer` with `ContainmentRelation.all(_:)`. The provider: `Sources/FOSMVVMVapor/Protocols/ModelAuthorizationProvider.swift`.

---

## Live Invalidation

A ViewModel opted into live refresh with `@ViewModel(options: [.live])` re-fetches whenever the server signals that the data it was served from has changed. Most of this is automatic: a Fluent-persisted model nudges live clients on every committed save, and plan-loaded records register their dependency with no code.

Two cases fall outside that automatic path — a response reads state the record-load plan can't see (an `Application`-hosted actor's snapshot, a computed aggregate), and a non-Fluent source mutates that state. A paired public contract closes them.

### The register / invalidate pair (non-Fluent sources)

**Register a dependency on what you read; invalidate projections of what you changed.**

- **`ProjectionContext.registerDependency(on:)`** (read side) — the factory declares that its response depends on a model the plan didn't load. The registered identity rides to the client with the response.
- **`Application.invalidateProjections(of:)`** / **`Request.invalidateProjections(of:)`** (write side) — the non-Fluent source nudges live clients when its state changes. Inside `liveTransaction(_:)` the nudge reaches clients only if the transaction commits; where live invalidation is not enabled it is a no-op.

**Both are required, and they must name the same entity.** Emit without a matching registration nudges nobody; registration without a matching emit refreshes never. That pairing *is* the live contract.

**Fluent-persisted models never need either call** — their saves already notify live clients. Reach for the pair only for state Fluent doesn't own.

**v1 scope:** the write side emits the changed model's *own* identity only — no containment derivation for non-Fluent sources. A screen that must refresh on a container's change registers a dependency on that container directly.

---

## Key Macros

| Macro | Purpose |
|-------|---------|
| `@ViewModel` | Generates `propertyNames()` for localization binding |
| `@ViewModel(options: [.clientHostedFactory])` | Additionally generates `ClientHostedViewModelFactory` support (AppState, Request, factory method) |
| `@FieldValidationModel` | Generates `propertyNames()` for validation message types |
| `@VersionedFactory` | Generates versioned `model(context:)` dispatcher for API versioning |
| `#fieldId(\Model.property)` | The one mint for a `FormFieldIdentifier`, scoped by the type the key path names; `\Self` inside a `Fields` protocol's extension names the protocol, so every adopter shares the identity; `#fieldId(\Model.items, index:)` names one element of a repeated field |

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

### The SPMLibraries umbrella — the Xcode-side twin

The shared module solves agreement between targets that are *compiled together*. An Xcode project has a second version of the same problem: several Xcode targets (app, unit tests, UI tests, frameworks) each consuming the same external SPM package products.

**When more than one Xcode target consumes SPM package products, vend them through a single `SPMLibraries` umbrella framework that every target depends on — never link the SPM products directly into each target.** `SPMLibraries` is a thin framework whose dependencies list every external package product (`FOSFoundation`, `FOSMVVM`, …); every other target depends on it.

**Why — a generic Xcode + SPM bug, not FOS-specific.** Linking an SPM library statically into multiple targets compiles a *separate copy of its types into each target*, and Swift's mangled type name carries the linking context. The "same" type then has a different runtime identity per target, so an instance crossing a target boundary fails `is` / `as?` / `==` / `===` against the same type on the other side: **`TypeA != TypeA`**. It compiles clean and breaks at runtime, far from the cause. One umbrella *dynamic* framework means one canonical copy and one shared type identity everywhere.

**Why it matters especially here.** FOSMVVM leans hard on comparing types — type-derived request paths, ViewModel/Request resolution, versioning. An app that skips the umbrella breaks exactly where those comparisons happen. The umbrella looks like redundant re-vending to a mainstream Xcode eye, which is why it has to be stated rather than left implicit.

Two carve-outs, both deliberate:

- **Testing products** (`FOSTesting`, `FOSTestingUI`, `FOSTestingVapor`) stay *out* of the umbrella and link directly into test targets. The umbrella embeds in the shipping app, and testing products must not ride along; their types are never shared across target boundaries, so the identity rule does not apply to them. (Ruled 2026-08-19.)
- **Single-embed.** The app embeds the umbrella and every local framework with sign-on-copy; every other target links without embedding. A hosted unit-test bundle links only because its test host, the app, already carries the embedded copy; embedding twice puts two copies in one process — the identity failure the umbrella exists to prevent, reintroduced. A UI-test bundle has no host — it runs in a separate runner process and drives the app from outside — and links only because that is the shape the scaffolder settled on, by trial and error, and emits in every template.

This is enforced in three places, and they must agree: the scaffolder's `project.yml` templates emit it, `fosmvvm-doctor` audits an existing project for it (rules R4a/R4b/R5), and generated projects ship a `memory/spm-libraries-settled.md` carrying the argument for the app's own future sessions.

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
