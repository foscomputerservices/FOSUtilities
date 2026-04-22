---
name: fosmvvm-viewmodel-generator
description: Generate FOSMVVM ViewModels for SwiftUI screens, pages, and components. Scaffolds RequestableViewModel, localization bindings, and stub factories.
homepage: https://github.com/foscomputerservices/FOSUtilities
metadata: {"clawdbot": {"emoji": "🏗️", "os": ["darwin", "linux"]}}
---

# FOSMVVM ViewModel Generator

Generate ViewModels following FOSMVVM architecture patterns.

## Conceptual Foundation

> For full architecture context, see [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md) | [OpenClaw reference]({baseDir}/references/FOSMVVMArchitecture.md)

A **ViewModel** is the bridge in the Model-View-ViewModel architecture:

```
┌─────────────┐      ┌─────────────────┐      ┌─────────────┐
│    Model    │ ───► │    ViewModel    │ ───► │    View     │
│   (Data)    │      │  (The Bridge)   │      │  (SwiftUI)  │
└─────────────┘      └─────────────────┘      └─────────────┘
```

**Key insight:** In FOSMVVM, ViewModels are:
- **Created by a Factory** (either server-side or client-side)
- **Localized during encoding** (resolves all `@LocalizedString` references)
- **Consumed by Views** which just render the localized data

---

## First Decision: Hosting Mode

**This is a per-ViewModel decision.** An app can mix both modes - for example, a standalone iPhone app with server-based sign-in.

**The key question: Where does THIS ViewModel's data come from?**

| Data Source | Hosting Mode | Factory |
|-------------|--------------|---------|
| Server/Database | Server-Hosted | Hand-written |
| Local state/preferences | Client-Hosted | Macro-generated |
| **ResponseError (caught error)** | **Client-Hosted** | Macro-generated |

### Server-Hosted Mode

When data comes from a server:
- Factory is **hand-written** on server (`ViewModelFactory` protocol)
- Factory queries database, builds ViewModel
- Server localizes during JSON encoding
- Client receives fully localized ViewModel

**Examples:** Sign-in screen, user profile from API, dashboard with server data

### Client-Hosted Mode

When data is local to the device:
- Use `@ViewModel(options: [.clientHostedFactory])`
- Macro **auto-generates** factory from init parameters
- Client bundles YAML resources
- Client localizes during encoding

**Examples:** Settings screen, onboarding, offline-first features, **error display**

### Error Display Pattern

Error display is a classic client-hosted scenario. You already have the data from `ResponseError` - just wrap it in a **specific** ViewModel for that error:

```swift
// Specific ViewModel for MoveIdeaRequest errors
@ViewModel(options: [.clientHostedFactory])
struct MoveIdeaErrorViewModel {
    let message: LocalizableString
    let errorCode: String

    public var vmId = ViewModelId()

    // Takes the specific ResponseError
    init(responseError: MoveIdeaRequest.ResponseError) {
        self.message = responseError.message
        self.errorCode = responseError.code.rawValue
    }
}
```

Usage:
```swift
catch let error as MoveIdeaRequest.ResponseError {
    let vm = MoveIdeaErrorViewModel(responseError: error)
    return try await req.view.render("Shared/ToastView", vm)
}
```

**Each error scenario gets its own ViewModel:**
- `MoveIdeaErrorViewModel` for `MoveIdeaRequest.ResponseError`
- `CreateIdeaErrorViewModel` for `CreateIdeaRequest.ResponseError`
- `SettingsValidationErrorViewModel` for settings form errors

Don't create a generic "ToastViewModel" or "ErrorViewModel" - that's unified error architecture, which we avoid.

**Key insights:**
- No server request needed - you already caught the error
- The `LocalizableString` properties in `ResponseError` are **already localized** (server did it)
- Standard ViewModel → View encoding chain handles this correctly; already-localized strings pass through unchanged
- Client-hosted ViewModel wraps existing data; the macro generates the factory

### Hybrid Apps

Many apps use both:
```
┌───────────────────────────────────────────────┐
│               iPhone App                       │
├───────────────────────────────────────────────┤
│ SettingsViewModel           → Client-Hosted   │
│ OnboardingViewModel         → Client-Hosted   │
│ MoveIdeaErrorViewModel      → Client-Hosted   │  ← Error display
│ SignInViewModel             → Server-Hosted   │
│ UserProfileViewModel        → Server-Hosted   │
└───────────────────────────────────────────────┘
```

**Same ViewModel patterns work in both modes** - only the factory creation differs.

### Core Responsibility: Shaping Data

A ViewModel's job is **shaping data for presentation**. This happens in two places:

1. **Factory** - *what* data is needed, *how* to transform it
2. **Localization** - *how* to present it in context (including locale-aware ordering)

**The View just renders** - it should never compose, format, or reorder ViewModel properties.

### What a ViewModel Contains

A ViewModel answers: **"What does the View need to display?"**

| Content Type | How It's Represented | Example |
|--------------|---------------------|---------|
| Static UI text | `@LocalizedString` | Page titles, button labels (fixed text) |
| Dynamic enum values | `LocalizableString` (stored) | Status/state display (see Enum Localization Pattern) |
| Dynamic data in text | `@LocalizedSubs` | "Welcome, %{name}!" with substitutions |
| Composed text | `@LocalizedCompoundString` | Full name from pieces (locale-aware order) |
| Formatted dates | `LocalizableDate` | `createdAt: LocalizableDate` |
| Formatted numbers | `LocalizableInt` | `totalCount: LocalizableInt` |
| Dynamic data | Plain properties | `content: String`, `count: Int` |
| Nested components | Child ViewModels | `cards: [CardViewModel]` |

### What a ViewModel Does NOT Contain

- Database relationships (`@Parent`, `@Siblings`)
- Business logic or validation (that's in Fields protocols)
- Raw database IDs exposed to templates (use typed properties)
- Unlocalized strings that Views must look up

### Anti-Pattern: Composition in Views

```swift
// ❌ WRONG - View is composing
Text(viewModel.firstName) + Text(" ") + Text(viewModel.lastName)

// ✅ RIGHT - ViewModel provides shaped result
Text(viewModel.fullName)  // via @LocalizedCompoundString
```

If you see `+` or string interpolation in a View, the shaping belongs in the ViewModel.

## ViewModel Protocol Hierarchy

```swift
public protocol ViewModel: ServerRequestBody, RetrievablePropertyNames, Identifiable, Stubbable {
    var vmId: ViewModelId { get }
}

public protocol RequestableViewModel: ViewModel {
    associatedtype Request: ViewModelRequest
}
```

**ViewModel** provides:
- `ServerRequestBody` - Can be sent over HTTP as JSON
- `RetrievablePropertyNames` - Enables `@LocalizedString` binding (via `@ViewModel` macro)
- `Identifiable` - Has `vmId` for SwiftUI identity
- `Stubbable` - Has `stub()` for testing/previews

**RequestableViewModel** adds:
- Associated `Request` type for fetching from server

## Two Categories of ViewModels

### 1. Top-Level (RequestableViewModel)

Represents a full page or screen. Has:
- An associated `ViewModelRequest` type
- A `ViewModelFactory` that builds it from database
- Child ViewModels embedded within it

```swift
@ViewModel
public struct DashboardViewModel: RequestableViewModel {
    public typealias Request = DashboardRequest

    @LocalizedString public var pageTitle
    public let cards: [CardViewModel]  // Children
    public var vmId: ViewModelId = .init()
}
```

### 2. Child (plain ViewModel)

Nested components built by their parent's factory. No Request type.

```swift
@ViewModel
public struct CardViewModel: Codable, Sendable {
    public let id: ModelIdType
    public let title: String
    public let createdAt: LocalizableDate
    public var vmId: ViewModelId = .init()
}
```

---

## Display vs Form ViewModels

ViewModels serve two distinct purposes:

| Purpose | ViewModel Type | Adopts Fields? |
|---------|----------------|----------------|
| **Display data** (read-only) | Display ViewModel | No |
| **Collect user input** (editable) | Form ViewModel | Yes |

### Display ViewModels

For showing data - cards, rows, lists, detail views:

```swift
@ViewModel
public struct UserCardViewModel {
    public let id: ModelIdType
    public let name: String
    @LocalizedString public var roleDisplayName
    public let createdAt: LocalizableDate
    public var vmId: ViewModelId = .init()
}
```

**Characteristics:**
- Properties are `let` (read-only)
- No validation needed
- No FormField definitions
- Just projects Model data for display

### Form ViewModels

For collecting input - create forms, edit forms, settings:

```swift
@ViewModel
public struct UserFormViewModel: UserFields {  // ← Adopts Fields!
    public var id: ModelIdType?
    public var email: String
    public var firstName: String
    public var lastName: String

    public let userValidationMessages: UserFieldsMessages
    public var vmId: ViewModelId = .init()
}
```

**Characteristics:**
- Properties are `var` (editable)
- **Adopts a Fields protocol** for validation
- Gets FormField definitions from Fields
- Gets validation logic from Fields
- Gets localized error messages from Fields

### The Connection

```
┌─────────────────────────────────────────────────────────────────┐
│                    UserFields Protocol                          │
│        (defines editable properties + validation)               │
│                                                                 │
│  Adopted by:                                                    │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │ CreateUserReq   │  │ UserFormVM      │  │ User (Model)    │ │
│  │ .RequestBody    │  │ (UI form)       │  │ (persistence)   │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
│                                                                 │
│  Same validation logic everywhere!                              │
└─────────────────────────────────────────────────────────────────┘
```

### Quick Decision Guide

**The key question: "Is the user editing data in this ViewModel?"**

- **No** → Display ViewModel (no Fields)
- **Yes** → Form ViewModel (adopt Fields)

| ViewModel | User Edits? | Adopt Fields? |
|-----------|-------------|---------------|
| `UserCardViewModel` | No | No |
| `UserRowViewModel` | No | No |
| `UserDetailViewModel` | No | No |
| `UserFormViewModel` | Yes | `UserFields` |
| `CreateUserViewModel` | Yes | `UserFields` |
| `EditUserViewModel` | Yes | `UserFields` |
| `SettingsViewModel` | Yes | `SettingsFields` |

---

## Third Decision: Interactive vs Display-Only

**This is a per-ViewModel decision, independent of hosting mode.**

**The key question: Does the user initiate actions through this ViewModel's view?**

| View behavior | ViewModel kind | Operations file generated? |
|---------------|----------------|----------------------------|
| Renders data only — no user actions | **Display-only** | No |
| Has buttons, forms, toggles, menus, drag-and-drop | **Interactive** | Yes |

Interactive ViewModels have a companion **Operations** file (`{Name}ViewModelOperations.swift`), co-located with the ViewModel. Display-only ViewModels have no Operations at all — do not invent an empty protocol to satisfy a generic parameter. The test base class for display-only views is ``ViewModelDisplayTestCase<VM>``, which takes no Operations type.

### Decision Examples

| VM | Interactive? | Rationale |
|----|--------------|-----------|
| `UserCardViewModel` | No | Renders user data |
| `UserRowViewModel` | No | Renders list row |
| `DashboardViewModel` | No | Renders a grid of children |
| `UserFormViewModel` | Yes | Save/Cancel buttons |
| `SettingsViewModel` | Yes | Toggles and pickers |
| `DeviceConnectionViewModel` | Yes | Connect/Disconnect actions |

### What "Operations" Is

Operations is the dispatch seam for user-initiated actions. Every interactive ViewModel has:

- **Protocol** (`{Name}ViewModelOperations: ViewModelOperations`) — declares the actions the View can dispatch.
- **Live implementation** (`{Name}Ops`, struct) — does the real work: calls a server via `ServerRequest`, mutates `@Observable` storage, talks to a device, etc.
- **Stub implementation** (`{Name}StubOps`, `final class`, `@unchecked Sendable`) — records which methods were called and with what arguments, for UI tests.
- **Wiring on the VM** — a private `isStub: Bool` flag plus a `public var operations: any {Name}ViewModelOperations` computed property that returns Ops in production and StubOps in `stub()`.

The protocol + both implementations live together in `{Name}ViewModelOperations.swift`, next to `{Name}ViewModel.swift`.

### Operations Conventions: Client-Hosted vs Server-Backed

Operations split along the same hosting axis as the ViewModel. The canonical rules live in [Architecture Patterns → Ops Conventions](../shared/architecture-patterns.md). The short summary:

**Client-hosted ops.** Mutate one or more `@Observable` storage objects the View holds in `@Environment`. Each mutating method takes scalar inputs first and the write target **last**, labeled `output`:

```swift
func setTheme(_ theme: Theme, output storage: UserSettings)
```

The View reads storage from `@Environment(UserSettings.self)` and hands it to the op at the call site:

```swift
Button("Dark") {
    viewModel.operations.setTheme(.dark, output: settings)
}
```

**Server-backed ops.** The server owns storage (database, via Vapor request context). Ops dispatch a `ServerRequest` and never take an `output:` parameter:

```swift
func disconnect(deviceId: String) async throws
```

**Two rules that apply to both:**

- **`async` only when the body awaits.** Do not mark ops `async` speculatively. An `async` call site becomes `Task { try await op(...) }`; for a body that just mutates state, that introduces arbitrary Task completion ordering — rapid user taps can land out of order and the last write isn't always the last tap. Mark `async` only for genuine I/O (network, device, disk).
- **Never fail silently.** No `try?`, no empty `catch {}`. Surface errors to observable state or a logger. See [Architecture Patterns → Never Fail Silently](../shared/architecture-patterns.md) for the full rationale.

Full reasoning — the asymmetry between client and server storage, why `in storage:` is wrong, projection-edge mechanics — lives in [Architecture Patterns → Ops Conventions](../shared/architecture-patterns.md).

### Full Server-Hosted Interactive Example

**ViewModel file** — `{ViewModelsTarget}/Info/InfoViewModel.swift`:

```swift
@ViewModel
public struct InfoViewModel: RequestableViewModel {
    // MARK: ViewModel Properties

    @LocalizedString public var connectionTitle
    @LocalizedString public var disconnectTitle

    public let deviceId: String

    // MARK: RequestableViewModel Protocol

    public typealias Request = InfoRequest
    public let vmId: ViewModelId

    // MARK: Operations Access

    private let isStub: Bool

    #if canImport(SwiftUI)
    public var operations: any InfoViewModelOperations {
        isStub ? InfoStubOps() : InfoOps()
    }
    #endif

    // MARK: Initialization

    public init(deviceId: String) {
        self.init(isStub: false, deviceId: deviceId)
    }

    private init(isStub: Bool, deviceId: String) {
        self.isStub = isStub
        self.deviceId = deviceId
        self.vmId = .init(type: Self.self)
    }

    public static func stub() -> Self {
        .init(isStub: true, deviceId: "test-device")
    }
}
```

**Operations file** — `{ViewModelsTarget}/Info/InfoViewModelOperations.swift`:

```swift
import FOSFoundation
import FOSMVVM
import Foundation

// MARK: - Protocol

public protocol InfoViewModelOperations: ViewModelOperations {
    func disconnect(deviceId: String) async throws
}

// MARK: - Live Implementation (Server-Backed)

public struct InfoOps: InfoViewModelOperations {
    public init() {}

    public func disconnect(deviceId: String) async throws {
        // Dispatches a ServerRequest. The server owns storage;
        // no `output:` parameter. `async throws` matches the network call.
    }
}

// MARK: - Stub Implementation

#if canImport(SwiftUI)
public final class InfoStubOps: InfoViewModelOperations, @unchecked Sendable {
    public var disconnectCalled: Bool { disconnectCalledWith != nil }
    public private(set) var disconnectCalledWith: String?

    public init() {}

    public func disconnect(deviceId: String) async throws {
        disconnectCalledWith = deviceId
    }
}
#endif
```

No `output storage:` on any method — the server owns storage. The `async throws` is genuine (network I/O). The stub exposes two assertion points: `disconnectCalled` (did the op fire at all?) and `disconnectCalledWith` (was the right data passed?).

### Full Client-Hosted Interactive Example

**ViewModel file** — `{ViewModelsTarget}/Preferences/PreferencesViewModel.swift`:

```swift
@ViewModel(options: [.clientHostedFactory])
public struct PreferencesViewModel {
    // MARK: ViewModel Properties

    @LocalizedString public var pageTitle
    @LocalizedString public var darkModeLabel

    // Scalar projections from @Observable storage (see architecture-patterns.md)
    public let notificationsEnabled: Bool
    public let theme: Theme

    // MARK: Operations Access

    private let isStub: Bool

    #if canImport(SwiftUI)
    public var operations: any PreferencesViewModelOperations {
        isStub ? PreferencesStubOps() : PreferencesOps()
    }
    #endif

    public var vmId = ViewModelId()

    // MARK: Initialization

    // Public init parameters become AppState properties (macro-generated).
    // Do NOT include isStub here — it's an implementation detail, not AppState.
    public init(notificationsEnabled: Bool, theme: Theme) {
        self.init(isStub: false, notificationsEnabled: notificationsEnabled, theme: theme)
    }

    private init(isStub: Bool, notificationsEnabled: Bool, theme: Theme) {
        self.isStub = isStub
        self.notificationsEnabled = notificationsEnabled
        self.theme = theme
    }

    public static func stub() -> Self {
        .init(isStub: true, notificationsEnabled: false, theme: .system)
    }
}
```

**Operations file** — `{ViewModelsTarget}/Preferences/PreferencesViewModelOperations.swift`:

```swift
import FOSFoundation
import FOSMVVM
import Foundation

// MARK: - Protocol

public protocol PreferencesViewModelOperations: ViewModelOperations {
    func setTheme(_ theme: Theme, output storage: UserSettings)
    func setNotificationsEnabled(_ enabled: Bool, output storage: UserSettings)
}

// MARK: - Live Implementation (Client-Hosted)

public struct PreferencesOps: PreferencesViewModelOperations {
    public init() {}

    public func setTheme(_ theme: Theme, output storage: UserSettings) {
        storage.theme = theme
    }

    public func setNotificationsEnabled(_ enabled: Bool, output storage: UserSettings) {
        storage.notificationsEnabled = enabled
    }
}

// MARK: - Stub Implementation

#if canImport(SwiftUI)
public final class PreferencesStubOps: PreferencesViewModelOperations, @unchecked Sendable {
    public private(set) var setThemeCalled: Bool = false
    public private(set) var setNotificationsEnabledCalled: Bool = false

    public init() {}

    public func setTheme(_ theme: Theme, output storage: UserSettings) {
        setThemeCalled = true
        storage.theme = theme
    }

    public func setNotificationsEnabled(_ enabled: Bool, output storage: UserSettings) {
        setNotificationsEnabledCalled = true
        storage.notificationsEnabled = enabled
    }
}
#endif
```

Every mutating method takes `output storage: UserSettings` as its **last** parameter. Ops are **synchronous** — bodies do no awaiting. The client-hosted stub records that the op fired (`Called: Bool = false`) **and** performs the same mutation the live implementation would — so `@Observable` fires, the resolver re-projects, and the View updates under test. Tests assert "was it called?" with `stubOps.setThemeCalled` and "with what value?" by reading `storage.theme` directly; the storage itself holds the `CalledWith` equivalent, so no separate accessor is needed.

This asymmetry with server-backed stubs (which expose `Called` + `CalledWith` accessors and never mutate) is intentional: server-backed tests have no local storage to observe, so the stub must expose both accessors; client-hosted tests have storage right there, so the stub uses it to keep the projection loop intact.

**Note on the AppState/scalar split.** The ViewModel holds scalars (`notificationsEnabled: Bool`, `theme: Theme`), **not** a reference to `UserSettings`. At the call site the View holds `@Environment(UserSettings.self)` and hands the reference directly to the op — the reference never passes through the VM. See [Architecture Patterns → VMs Hold Scalars](../shared/architecture-patterns.md) for why.

---

## When to Use This Skill

- Creating a new page or screen
- Adding a new UI component (card, row, modal, etc.)
- Displaying data from the database in a View
- Following an implementation plan that requires new ViewModels

## What This Skill Generates

**Interactive ViewModels** (those that dispatch user-initiated actions) get an additional `{Name}ViewModelOperations.swift` file co-located with the ViewModel. Display-only ViewModels do **not** get this file — no empty protocols, no operation scaffolding. See **Third Decision: Interactive vs Display-Only** above.

### Server-Hosted: Top-Level ViewModel

| File | Location | Purpose | Interactive only? |
|------|----------|---------|-------------------|
| `{Name}ViewModel.swift` | `{ViewModelsTarget}/` | The ViewModel struct | No |
| `{Name}Request.swift` | `{ViewModelsTarget}/` | The ViewModelRequest type | No |
| `{Name}ViewModel.yml` | `{ResourcesPath}/` | Localization strings | No |
| `{Name}ViewModel+Factory.swift` | `{WebServerTarget}/` | Factory that builds from DB | No |
| `{Name}ViewModelOperations.swift` | `{ViewModelsTarget}/` | Ops protocol + live + stub | **Yes** |

Display-only: 4 files. Interactive: 5 files.

### Client-Hosted: Top-Level ViewModel

| File | Location | Purpose | Interactive only? |
|------|----------|---------|-------------------|
| `{Name}ViewModel.swift` | `{ViewModelsTarget}/` | ViewModel with `clientHostedFactory` option | No |
| `{Name}ViewModel.yml` | `{ResourcesPath}/` | Localization strings (bundled in app) | No |
| `{Name}ViewModelOperations.swift` | `{ViewModelsTarget}/` | Ops protocol + live + stub | **Yes** |

Display-only: 2 files. Interactive: 3 files. *No Request or Factory files needed — macro generates them.*

### Child ViewModels (1-2 files, either mode)

| File | Location | Purpose |
|------|----------|---------|
| `{Name}ViewModel.swift` | `{ViewModelsTarget}/` | The ViewModel struct |
| `{Name}ViewModel.yml` | `{ResourcesPath}/` | Localization (if has `@LocalizedString`) |

Child ViewModels don't own Operations — if a child's rendering has actions, those dispatch through the top-level VM's Operations, or the child is promoted to a top-level ViewModel with its own Operations file.

**Note:** If child is only used by one parent and represents a summary/reference (not a full ViewModel), nest it inside the parent file instead. See **Nested Child Types Pattern** under Key Patterns.

## Project Structure Configuration

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{ViewModelsTarget}` | Shared ViewModels SPM target | `ViewModels` |
| `{ResourcesPath}` | Localization resources | `Sources/Resources` |
| `{WebServerTarget}` | Server-side target | `WebServer`, `AppServer` |

## How to Use This Skill

**Invocation:**
/fosmvvm-viewmodel-generator

**Prerequisites:**
- View requirements understood from conversation context
- Data source determined (server/database vs local state)
- Display vs Form decision made (if user input involved, Fields protocol exists)

**Workflow integration:**
This skill is typically used after discussing View requirements or reading specification files. The skill references conversation context automatically—no file paths or Q&A needed. For Form ViewModels, run fosmvvm-fields-generator first to create the Fields protocol.

## Pattern Implementation

This skill references conversation context to determine ViewModel structure:

### Hosting Mode Detection

From conversation context, the skill identifies:
- **Data source** (server/database vs local state/preferences)
- Server-hosted → Hand-written factory, server-side localization
- Client-hosted → Macro-generated factory, client-side localization

### ViewModel Design

From requirements already in context:
- **View purpose** (page, modal, card, row component)
- **Data needs** (from database query, from AppState, from caught error)
- **Static UI text** (titles, labels, buttons requiring @LocalizedString)
- **Child ViewModels** (nested components)
- **Hierarchy level** (top-level RequestableViewModel vs child ViewModel)

### Property Planning

Based on View requirements:
- **Display properties** (data to render)
- **Localization requirements** (which properties use @LocalizedString)
- **Identity strategy** (singleton vmId vs instance-based vmId)
- **Form adoption** (whether ViewModel adopts Fields protocol)

### File Generation

**Server-Hosted Top-Level:**
1. ViewModel struct (with `RequestableViewModel`)
2. Request type
3. YAML localization
4. Factory implementation

**Client-Hosted Top-Level:**
1. ViewModel struct (with `clientHostedFactory` option)
2. YAML localization

**Child (either mode):**
1. ViewModel struct
2. YAML localization (if needed)

### Context Sources

Skill references information from:
- **Prior conversation**: View requirements, data sources discussed with user
- **Specification files**: If Claude has read UI specs or feature docs into context
- **Fields protocols**: From codebase or previous fosmvvm-fields-generator invocation

## Key Patterns

### The @ViewModel Macro

Always use the `@ViewModel` macro - it generates the `propertyNames()` method required for localization binding.

**Server-Hosted** (basic macro):
```swift
@ViewModel
public struct MyViewModel: RequestableViewModel {
    public typealias Request = MyRequest
    @LocalizedString public var title
    public var vmId: ViewModelId = .init()
    public init() {}
}
```

**Client-Hosted** (with factory generation):
```swift
@ViewModel(options: [.clientHostedFactory])
public struct SettingsViewModel {
    @LocalizedString public var pageTitle
    public var vmId: ViewModelId = .init()

    public init(theme: Theme, notifications: NotificationSettings) {
        // Init parameters become AppState properties
    }
}

// Macro auto-generates:
// - typealias Request = ClientHostedRequest
// - struct AppState { let theme: Theme; let notifications: NotificationSettings }
// - class ClientHostedRequest: ViewModelRequest { ... }
// - static func model(context:) async throws -> Self { ... }
```

**Interactive variants.** Both examples above are **display-only**. Interactive ViewModels add an `isStub: Bool` flag, a `public var operations: any ...` computed property, and a private `init(isStub:, ...)` that the public init and `stub()` both delegate to. Full shape (both server-hosted and client-hosted): see **Third Decision: Interactive vs Display-Only** above.

### Stubbable Pattern

All ViewModels must support `stub()` for testing and SwiftUI previews:

```swift
public extension MyViewModel {
    static func stub() -> Self {
        .init(/* default values */)
    }
}
```

### Identity: vmId

Every ViewModel needs a `vmId` for SwiftUI's identity system:

**Singleton** (one per page): `vmId = .init(type: Self.self)`
**Instance** (multiple per page): `vmId = .init(id: id)` where `id: ModelIdType`

### Localization

Static UI text uses `@LocalizedString`:

```swift
@LocalizedString public var pageTitle
```

With corresponding YAML:
```yaml
en:
  MyViewModel:
    pageTitle: "Welcome"
```

### Dates and Numbers

Never send pre-formatted strings. Use localizable types:

```swift
public let createdAt: LocalizableDate    // NOT String
public let itemCount: LocalizableInt     // NOT String
```

The client formats these according to user's locale and timezone.

### Enum Localization Pattern

For dynamic enum values (status, state, category), use a **stored `LocalizableString`** - NOT `@LocalizedString`.

`@LocalizedString` always looks up the same key (the property name). A stored `LocalizableString` carries the dynamic key from the enum case.

```swift
// Enum provides localizableString
public enum SessionState: String, CaseIterable, Codable, Sendable {
    case pending, running, completed, failed

    public var localizableString: LocalizableString {
        .localized(for: Self.self, propertyName: rawValue)
    }
}

// ViewModel stores it (NOT @LocalizedString)
@ViewModel
public struct SessionCardViewModel {
    public let state: SessionState                // Raw enum for data attributes
    public let stateDisplay: LocalizableString   // Localized display text

    public init(session: Session) {
        self.state = session.state
        self.stateDisplay = session.state.localizableString
    }
}
```

```yaml
# YAML keys match enum type and case names
en:
  SessionState:
    pending: "Pending"
    running: "Running"
    completed: "Completed"
    failed: "Failed"
```

**Constraint:** `LocalizableString` only works in ViewModels encoded with `localizingEncoder()`. Do not use in Fluent JSONB fields or other persisted types.

### Child ViewModels

Top-level ViewModels contain their children:

```swift
@ViewModel
public struct BoardViewModel: RequestableViewModel {
    public let columns: [ColumnViewModel]
    public let cards: [CardViewModel]
}
```

The Factory builds all children when building the parent.

#### Nested Child Types Pattern

When a child type is **only used by one parent** and represents a summary or reference (not a full ViewModel), nest it inside the parent:

```swift
@ViewModel
public struct GovernancePrincipleCardViewModel: Codable, Sendable, Identifiable {
    // Properties come first
    public let versionHistory: [GovernancePrincipleVersionSummary]?
    public let referencingDecisions: [GovernanceDecisionReference]?

    // MARK: - Nested Types

    /// Summary of a principle version for display in version history.
    public struct GovernancePrincipleVersionSummary: Codable, Sendable, Identifiable, Stubbable {
        public let id: ModelIdType
        public let version: Int
        public let createdAt: Date

        public init(id: ModelIdType, version: Int, createdAt: Date) {
            self.id = id
            self.version = version
            self.createdAt = createdAt
        }
    }

    /// Reference to a decision that cites this principle.
    public struct GovernanceDecisionReference: Codable, Sendable, Identifiable, Stubbable {
        public let id: ModelIdType
        public let title: String
        public let decisionNumber: String
        public let createdAt: Date

        public init(id: ModelIdType, title: String, decisionNumber: String, createdAt: Date) {
            self.id = id
            self.title = title
            self.decisionNumber = decisionNumber
            self.createdAt = createdAt
        }
    }

    // vmId and parent init follow
    public let vmId: ViewModelId
    // ...
}
```

**Reference:** `Sources/KairosModels/Governance/GovernancePrincipleCardViewModel.swift`

**Placement rules:**
1. Nested types go AFTER the properties that reference them
2. Before `vmId` and the parent's init
3. Use `// MARK: - Nested Types` section marker
4. Each nested type gets its own doc comment

**Conformances for nested types:**
- `Codable` - for ViewModel encoding
- `Sendable` - for Swift 6 concurrency
- `Identifiable` - for SwiftUI ForEach if used in arrays
- `Stubbable` - for testing/previews

**Two-Tier Stubbable Pattern:**

Nested types use fully qualified names in their extensions:

```swift
public extension GovernancePrincipleCardViewModel.GovernancePrincipleVersionSummary {
    // Tier 1: Zero-arg convenience (ALWAYS delegates to tier 2)
    static func stub() -> Self {
        .stub(id: .init())
    }

    // Tier 2: Full parameterized with defaults
    static func stub(
        id: ModelIdType = .init(),
        version: Int = 1,
        createdAt: Date = .now
    ) -> Self {
        .init(id: id, version: version, createdAt: createdAt)
    }
}

public extension GovernancePrincipleCardViewModel.GovernanceDecisionReference {
    static func stub() -> Self {
        .stub(id: .init())
    }

    static func stub(
        id: ModelIdType = .init(),
        title: String = "A Title",
        decisionNumber: String = "DEC-12345",
        createdAt: Date = .now
    ) -> Self {
        .init(id: id, title: title, decisionNumber: decisionNumber, createdAt: createdAt)
    }
}
```

**Why two tiers:**
- Tests often just need `[.stub()]` without caring about values
- Other tests need specific values: `.stub(name: "Specific Name")`
- Zero-arg ALWAYS calls parameterized version (single source of truth)

**When to nest vs keep top-level:**

| Nest Inside Parent | Keep Top-Level |
|-------------------|----------------|
| Child is ONLY used by this parent | Child is shared across multiple parents |
| Child represents subset/summary | Child is a full ViewModel |
| Child has no @ViewModel macro | Child has @ViewModel macro |
| Child is not RequestableViewModel | Child is RequestableViewModel |
| Example: VersionSummary, Reference | Example: CardViewModel, ListViewModel |

**Examples:**

Card with nested summaries:
```swift
@ViewModel
public struct TaskCardViewModel {
    public let assignees: [AssigneeSummary]?

    public struct AssigneeSummary: Codable, Sendable, Identifiable, Stubbable {
        public let id: ModelIdType
        public let name: String
        public let avatarUrl: String?
        // ...
    }
}
```

List with nested references:
```swift
@ViewModel
public struct ProjectListViewModel {
    public let relatedProjects: [ProjectReference]?

    public struct ProjectReference: Codable, Sendable, Identifiable, Stubbable {
        public let id: ModelIdType
        public let title: String
        public let status: String
        // ...
    }
}
```

### Codable and Computed Properties

Swift's synthesized `Codable` only encodes **stored properties**. Since ViewModels are serialized (for JSON transport, Leaf rendering, etc.), computed properties won't be available.

```swift
// Computed - NOT encoded, invisible after serialization
public var hasCards: Bool { !cards.isEmpty }

// Stored - encoded, available after serialization
public let hasCards: Bool
```

**When to pre-compute:**

For Leaf templates, you can often use Leaf's built-in functions directly:
- `#if(count(cards) > 0)` - no need for `hasCards` property
- `#count(cards)` - no need for `cardCount` property

Pre-compute only when:
- Direct array subscripts needed (`firstCard` - array indexing not documented in Leaf)
- Complex logic that's cleaner in Swift than in template
- Performance-sensitive repeated calculations

See [fosmvvm-leaf-view-generator](../fosmvvm-leaf-view-generator/SKILL.md) for Leaf template patterns.

## File Templates

See [reference.md](reference.md) for complete file templates.

## Naming Conventions

| Concept | Convention | Example |
|---------|------------|---------|
| ViewModel struct | `{Name}ViewModel` | `DashboardViewModel` |
| Request class | `{Name}Request` | `DashboardRequest` |
| Factory extension | `{Name}ViewModel+Factory.swift` | `DashboardViewModel+Factory.swift` |
| YAML file | `{Name}ViewModel.yml` | `DashboardViewModel.yml` |

## See Also

- [Architecture Patterns](../shared/architecture-patterns.md) - Mental models (errors are data, type safety, etc.)
- [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md) - Full FOSMVVM architecture
- [fosmvvm-fields-generator](../fosmvvm-fields-generator/SKILL.md) - For form validation
- [fosmvvm-fluent-datamodel-generator](../fosmvvm-fluent-datamodel-generator/SKILL.md) - For Fluent persistence layer
- [fosmvvm-leaf-view-generator](../fosmvvm-leaf-view-generator/SKILL.md) - For Leaf templates that render ViewModels
- [reference.md](reference.md) - Complete file templates

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2024-12-24 | Initial skill |
| 2.0 | 2024-12-26 | Complete rewrite from architecture; generalized from Kairos-specific |
| 2.1 | 2024-12-26 | Added Client-Hosted mode support; per-ViewModel hosting decision |
| 2.2 | 2024-12-26 | Added shaping responsibility, @LocalizedSubs/@LocalizedCompoundString, anti-pattern |
| 2.3 | 2025-12-27 | Added Display vs Form ViewModels section; clarified Fields adoption |
| 2.4 | 2026-01-08 | Added Codable/computed properties section. Clarified when to pre-compute vs use Leaf built-ins. |
| 2.5 | 2026-01-19 | Added Enum Localization Pattern section. Clarified @LocalizedString is for static text only; stored LocalizableString for dynamic enum values. |
| 2.6 | 2026-01-24 | Update to context-aware approach (remove file-parsing/Q&A). Skill references conversation context instead of asking questions or accepting file paths. |
| 2.7 | 2026-01-25 | Added Nested Child Types Pattern section with two-tier Stubbable pattern, placement rules, conformances, and decision criteria for when to nest vs keep top-level. |
| 2.8 | 2026-04-22 | Added Third Decision (Interactive vs Display-Only) — Operations trio generation for interactive VMs. Full server-hosted and client-hosted interactive examples with `isStub` flag, `operations` property, private init. Documented client-hosted `output storage:` convention and server-backed no-output convention. Added Templates 10 and 11 to reference.md (interactive VM + Operations file pairs). |
