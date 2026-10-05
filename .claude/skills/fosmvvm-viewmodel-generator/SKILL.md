---
name: fosmvvm-viewmodel-generator
description: Generate FOSMVVM ViewModels for SwiftUI screens, pages, and components. Scaffolds RequestableViewModel, localization bindings, and stub factories.
homepage: https://github.com/foscomputerservices/FOSUtilities
metadata: {"clawdbot": {"emoji": "🏗️", "os": ["darwin", "linux"]}}
---

# FOSMVVM ViewModel Generator

> **Read [`shared/functional-discipline.md`](../shared/functional-discipline.md) before proceeding.** Every rule below derives from it.

Generate ViewModels following FOSMVVM architecture patterns.

## Conceptual Foundation

> For full architecture context, see [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md) | [OpenClaw reference]({baseDir}/references/FOSMVVMArchitecture.md)

> **API catalog:** check [`../shared/api-catalog/FOSMVVM.md`](../shared/api-catalog/FOSMVVM.md) § Protocols, § Localization, § Macros and [`../shared/api-catalog/FOSFoundation.md`](../shared/api-catalog/FOSFoundation.md) § Coding (`Stubbable`) before hand-writing helpers.

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
// Specific ViewModel for IdeaMoveRequest errors
@ViewModel(options: [.clientHostedFactory])
struct IdeaMoveErrorViewModel {
    let message: LocalizableString
    let errorCode: String

    public var vmId: ViewModelId = .init(type: Self.self)  // shown once — singleton

    // Takes the specific ResponseError
    init(responseError: IdeaMoveRequest.ResponseError) {
        self.message = responseError.message
        self.errorCode = responseError.code.rawValue
    }
}
```

Usage:
```swift
catch let error as IdeaMoveRequest.ResponseError {
    let vm = IdeaMoveErrorViewModel(responseError: error)
    return try await req.view.render("Shared/ToastView", vm)
}
```

**Each error scenario gets its own ViewModel:**
- `IdeaMoveErrorViewModel` for `IdeaMoveRequest.ResponseError`
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
│ IdeaMoveErrorViewModel      → Client-Hosted   │  ← Error display
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
| Displayed enum word | `LocalizableCase<Enum>` (stored) | `priority: LocalizableCase<Priority>`; pickers via `includingAllCases: true` (see Enum Localization Pattern) |
| Dynamic data in text | `@LocalizedSubs` | "Welcome, %{name}!" with substitutions |
| Composed text | `@LocalizedCompoundString` | Full name from pieces (locale-aware order) |
| Formatted dates | `LocalizableDate` | `createdAt: LocalizableDate` |
| Formatted numbers | `LocalizableInt` | `totalCount: LocalizableInt` |
| Dynamic data | Plain properties | `content: String`, `count: Int` |
| **Locale-independent value** (version, hostname, identity) | **Typed property — NOT localized** | `version: SystemVersion` (View renders via `.versionString`), `host: String` |
| Nested components | Child ViewModels | `cards: [CardViewModel]` |

> **A version or an identity/hostname is NOT localizable text — do not wrap it in
> `LocalizableString`.** A contract/release version is a `SystemVersion` (the View renders
> it with `.versionString`); a hostname or other machine identity is a plain `String`.
> These values are the *same in every locale*, so localizing them is a category error —
> it adds a translation key that can never legitimately differ, and (for a version) throws
> away the typed comparison FOSMVVM relies on. The default reflex to "localize every
> string-ish field" is wrong here: **localize human-facing text; type everything else.**

### What a ViewModel Does NOT Contain

- Database relationships (`@Parent`, `@Siblings`)
- Business logic or validation (that's in Fields protocols)
- Raw database IDs exposed to templates (use typed properties)
- Unlocalized strings that Views must look up
- **Domain / wire types** (a `DataModel`/`Channel` type as a property or init param) — see below

### The ViewModel Module Must NOT Depend on Domain Types (Dependency Inversion) — HARD RULE

**The ViewModel module never imports the domain/wire module.** A ViewModel target
(`{App}ViewModels`, client-facing) depends on **FOSMVVM + Foundation + simple or
ViewModel-owned types only** — *not* on the DataModel/`Channel` module. A domain type as a
ViewModel field is a **category error**, not merely an unwanted dependency: **a ViewModel
is a _projection of_ the data, never the data itself.** A field like `guestOS: Platform`
(where `Platform` is a `Channel` domain type) is wrong on its face — and once the domain
import is correctly absent, it won't even compile.

This is **Dependency Inversion**: the high-level projection (ViewModel) does not depend on
the low-level wire detail (`Channel`). Get it wrong and FOSMVVM breaks in the ways the
firm principles warn about — leaked persistence types, existential-shaped seams, and a
client module that drags server/host-only code onto iOS.

**How to model a domain value correctly:**

1. **The ViewModel init takes simple types** (`String`, `Int`, a ViewModel-owned enum) —
   never a domain type.
2. **For a value the View switches on, define a ViewModel-owned display enum** (raw-less,
   per the Enum Localization Pattern) — e.g. a `CardLiveness` in the ViewModel module,
   *distinct from* any same-named domain type (see [Naming Dictionary](../shared/NAMES.md)).
3. **The `ViewModelFactory` performs the projection.** It is the **one** component that
   imports *both* the domain module and the ViewModel module, and it maps
   domain → display (`Channel.Platform → GuestPlatform`) when building the VM. Factories
   are **server-side**; the ViewModel module stays domain-free.
4. **Which entity it is crosses as an opaque `ModelIdentity`.** The factory reads
   `model.modelIdentity` and passes it to the ViewModel's init — never the model itself,
   never its raw id. See *An Entity's Identity Passes Through the ViewModel Opaquely*
   under *2. Child (plain ViewModel)* below.

**SOLID ergonomic (optional).** The Factory's *own* library may add a `private`/`internal`
**extension on the ViewModel with a domain-typed initializer** that maps domain → simple
and calls the public simple `init`:

```swift
// In the SERVER/Factory module only — never in the ViewModel module:
extension NodeViewModel {
    init(_ node: Channel.Node) {                 // domain-typed convenience init
        self.init(host: node.hostname,           // → public simple init
                  guestOS: GuestPlatform(node.platform))
    }
}
```

The adaptation lives **with the adapter**; the ViewModel's public API stays domain-free.
This is the dual of keeping wire types FOSMVVM-free — the boundary is clean in **both**
directions.

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
    public var vmId: ViewModelId = .init(type: Self.self)  // singleton — one per screen
}
```

> **One top-level VM per page/screen, composing children — never a mega-VM.** A
> multi-section surface (dashboard, board detail, settings) is a top-level
> `RequestableViewModel` that **composes child VMs** (`cards: [CardViewModel]`), one child
> per section. Do **not** flatten a many-section screen into a single giant ViewModel:
> that fuses independent concerns into one type (an **SRP** violation) and makes every
> section share one localization/versioning/identity surface.
>
> **Scaffold one file per VM type** — the top-level VM and every composed child each in
> its own file, grouped in a container-named directory. Full rules:
> [app-setup → File Organization Conventions](../fosmvvm-swiftui-app-setup/SKILL.md#file-organization-conventions).

### 2. Child (plain ViewModel)

Nested components built by their parent's factory. No Request type.

```swift
@ViewModel
public struct CardViewModel: ModelIdentifiedViewModel {
    public let modelIdentity: ModelIdentity   // opaque — transported, never read
    public let title: String
    public let createdAt: LocalizableDate
    public let vmId: ViewModelId       // instance (list row) — rooted in the identity

    // Init takes the identity + PLAIN Swift types; the init wraps them + owns formatting.
    public init(modelIdentity: ModelIdentity, title: String, createdAt: Date) {
        self.modelIdentity = modelIdentity
        self.title = title
        self.createdAt = LocalizableDate(value: createdAt)
        self.vmId = modelIdentity.viewModelId   // per-row stable — NEVER .init() on a list row
    }

    public static func stub(
        modelIdentity: ModelIdentity = .stub(),
        title: String = "Sample Card",
        createdAt: Date = .now
    ) -> Self {
        .init(modelIdentity: modelIdentity, title: title, createdAt: createdAt)
    }
}
```

The factory is the one place that touches the `Card` model:

```swift
// Server/Factory module — imports both the domain and the ViewModel module
CardViewModel(
    modelIdentity: try card.modelIdentity,
    title: card.title,
    createdAt: card.createdAt ?? .now
)
```

> **`vmId` derives from the data's identity — bind it, don't reach past it.** The row's `vmId` comes from `modelIdentity.viewModelId`, so the same entity ⇒ the same SwiftUI identity on every re-fetch. The derivation lives **on the identity**; never read the identity's contents to build the token yourself, and never provide a second spelling of the derivation. See [Architecture Patterns → Derive on the Owner](../shared/architecture-patterns.md).

#### An Entity's Identity Passes Through the ViewModel Opaquely

A ViewModel that represents an entity — a card, a board, a checklist item, a list row — carries that entity's `ModelIdentity` so the chain *data model → ViewModel → View → action → Operation → ServerRequest → server → database change* can say **which** entity it means. The ViewModel treats the identity as **opaque**: it only transports it through the ViewModel / View / Operation chain and roots its `vmId` in it for stability in the view hierarchy.

- **Carry** `public let modelIdentity: ModelIdentity` and conform to `ModelIdentifiedViewModel`.
- **The init takes the `ModelIdentity`, never a `Model`.** The factory reads `model.modelIdentity` and passes it in.
- **Root `vmId`** with `self.vmId = modelIdentity.viewModelId`.
- **Never build, parse, or read inside it.** Hand it unchanged to the Operation that acts on the entity (`operations.delete(modelIdentity)`).
- **Stub it** with a defaulted `modelIdentity: ModelIdentity = .stub()` parameter. Each `ModelIdentity.stub()` is a new identity, so the rows of a stubbed list stay distinct.

> **Red flag: a `Model` in a ViewModel's init** (`init(card: Card)`). **SOLID protected: DIP** — the ViewModel module never imports the domain module; the factory adapts. **And encapsulation** — the identity stays opaque, so nothing downstream can mint, parse, or route on it. **What breaks on deviation:** a `Model` parameter drags the persistence type into the shared module and onto every client, and leaves the ViewModel unable to write a `stub()` without inventing an entity. A raw `ModelIdType`/`UUID`/`String` id in place of the identity loses the type it names and invites parsing and forging; the coupling then surfaces far from the crack. Full rule: [Architecture Patterns → Identities Pass Through ViewModels Opaquely](../shared/architecture-patterns.md#identities-pass-through-viewmodels-opaquely).

> **Don't restate `Codable`/`Sendable` — the macro adds them.** `@ViewModel`
> synthesizes `ViewModel` conformance, which *already* provides `Codable` **and**
> `Sendable`. A child VM is just `@ViewModel public struct X { … }` — **no conformance
> clause**. Only add a clause for a conformance the macro does *not* supply: a **top-level**
> requestable VM adds `: RequestableViewModel`, a form VM adds its `Fields` protocol, and
> a genuinely-needed extra like `: Identifiable` stays. Restating `Codable, Sendable` is
> redundant noise (**DRY** — don't repeat what the macro guarantees).

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
public struct MemberCardViewModel: ModelIdentifiedViewModel {
    public let modelIdentity: ModelIdentity
    public let name: String
    @LocalizedString public var roleDisplayName
    public let createdAt: LocalizableDate
    public let vmId: ViewModelId       // instance (list row) — rooted in the identity

    public init(modelIdentity: ModelIdentity, name: String, createdAt: Date) {
        self.modelIdentity = modelIdentity
        self.name = name
        self.createdAt = LocalizableDate(value: createdAt)  // init wraps the plain Date
        self.vmId = modelIdentity.viewModelId
        // roleDisplayName is @LocalizedString — bound by the macro, not set here
    }
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
    public var vmId: ViewModelId = .init(type: Self.self)  // one form per screen — singleton
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
- **Stub implementation** (`{Name}StubOps`, `final class`, `@unchecked Sendable`) — records which methods were called and with what arguments, for UI tests. **A stub records; it never performs the operation's work** (ratified 2026-08-25): no `await` on real calls, no `Task.sleep`, no network or storage reach — a UI test proves the button is *wired* to the operation, not that the operation does something, and a stub that "does work" turns that wiring test into a timing-dependent behavior test. (Writing the `output` storage it is handed is recording's client-hosted twin, not work; an `async throws` signature with no `await` is the protocol's shape, not a smell.)
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

    public static func stub(deviceId: String = "test-device") -> Self {
        .init(isStub: true, deviceId: deviceId)
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

    public var vmId: ViewModelId = .init(type: Self.self)  // singleton page VM

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

    public static func stub(
        notificationsEnabled: Bool = false,
        theme: Theme = .system
    ) -> Self {
        .init(isStub: true, notificationsEnabled: notificationsEnabled, theme: theme)
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

> ← **Functional discipline:** a captured mutable reference inside a "value" breaks referential transparency — the projection becomes a function of WHEN YOU LOOK, so equality, memoization, and serialization all quietly lie: a closure masquerading as data. A cache that references the thing it caches is not a cache.

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
    public var vmId: ViewModelId = .init(type: Self.self)  // singleton
    public init() {}
}
```

**Client-Hosted** (with factory generation):
```swift
@ViewModel(options: [.clientHostedFactory])
public struct SettingsViewModel {
    @LocalizedString public var pageTitle
    public var vmId: ViewModelId = .init(type: Self.self)  // singleton

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

**Interactive variants.** Both examples above are **display-only**. Interactive ViewModels add an `isStub: Bool` flag, a `public var operations: any ...` computed property, and a private `init(isStub:, ...)` that the public init and the defaulted `stub(...)` both delegate to. Full shape (both server-hosted and client-hosted): see **Third Decision: Interactive vs Display-Only** above.

### Stubbable Pattern

All ViewModels must satisfy the `Stubbable` witness `stub()` for testing and SwiftUI previews. The pattern has two parts:

1. **`static func stub(<defaulted init parameters>) -> Self { .init(<parameters>) }`** — every parameter defaulted. A child-valued parameter may instead be the value that chains down into the child's `stub(...)` (`stub(number: Int = 0) { .init(sub: .stub(number: number)) }`).
2. **`static func stub() -> Self { .stub(<one argument, passed explicitly>) }`** — the `Stubbable` witness. With no argument, `.stub()` resolves to itself and recurses forever, so it names one.

**Why:** a test or preview passes just the tiniest amount of information that matters to it and still receives a fully valid, often multi-level, highly structured ViewModel. **Chain values down:** when a value passed at the top must reach the children, forward it into the children's `stub(...)` calls so the entire hierarchy is valid.

```swift
@ViewModel
public struct BoardViewModel: RequestableViewModel, ModelIdentifiedViewModel {
    public typealias Request = BoardRequest

    @LocalizedString public var title
    public let modelIdentity: ModelIdentity
    public let cards: [CardViewModel]
    public let cardCount: LocalizableInt
    public let vmId: ViewModelId

    public init(modelIdentity: ModelIdentity, cards: [CardViewModel]) {
        self.modelIdentity = modelIdentity
        self.cards = cards
        self.cardCount = .init(value: cards.count)
        self.vmId = modelIdentity.viewModelId
    }

    // Lives IN THE TYPE BODY so `@ViewModel` can see it (see below).
    public static func stub(
        modelIdentity: ModelIdentity = .stub(),
        numberOfCards: Int = 2,
        cardTitle: String = "Sample Card"
    ) -> Self {
        .init(
            modelIdentity: modelIdentity,
            cards: (0..<numberOfCards).map { _ in .stub(title: cardTitle) }   // chained down; each row gets its own identity
        )
    }
}

// A test that cares only about an empty board says only that:
let emptyBoard = BoardViewModel.stub(numberOfCards: 0)
```

**With `@ViewModel` you don't hand-write part 2.** When the type's body declares a fully-defaulted `stub(...)` and no zero-arg `stub()`, the macro synthesizes the witness, passing every default explicitly — part 2 of the pattern, written for you. Hand-writing it anyway (`static func stub() -> Self { .stub(modelIdentity: .stub()) }`) is also correct; the macro then steps aside.

**SOLID protected: SRP** — sample data is the type's own responsibility, declared once beside the type, not rebuilt in every test target. **What breaks on deviation:** hand-built instances in each test go stale when the init changes and produce partly valid hierarchies; a top value that doesn't chain down leaves parent and children disagreeing; a `stub()` that passes no argument recurses forever. Full rule: [Architecture Patterns → The Stubbable Pattern](../shared/architecture-patterns.md#the-stubbable-pattern-specify-little-receive-a-valid-whole).

> **The parameterized `stub(...)` must be in the type's body — NOT in an `extension`.**
> `@ViewModel` is a member macro: Swift hands it only the struct declaration, so a
> `stub(...)` sitting in `extension MyViewModel { … }` is invisible to it and **no witness
> is synthesized** → `does not conform to 'Stubbable'`. (A hand-written zero-arg `stub()`
> *may* live in an extension — it's a real witness — but a `stub(...)` you expect the macro
> to forward to cannot.)

Hand-write the zero-arg `stub()` yourself only when the macro has nothing to forward to: a no-argument `init()` (`stub() { .init() }` — a type with no init parameters has only `stub()`, as `ModelIdentity` does), or a **nested type that is plain `Stubbable` without `@ViewModel`** (see Two-Tier Stubbable Pattern). An interactive VM's defaulted `stub(...)` calls its private `init(isStub: true, …)`, and the macro still synthesizes the zero-arg witness from it. A parameterized `stub(...)` with any non-defaulted parameter is also not forwardable — the macro leaves such types to surface the normal `Stubbable` conformance error.

### Identity: vmId — stable data identity, never a throwaway

`vmId` parameterizes SwiftUI's `.id()` on the view that renders the ViewModel, so it
governs view stabilization (whether SwiftUI reuses or tears down the view on refresh). It
must be **stable across re-fetches of the same logical thing** — never a fresh random
value.

**The rule: the `vmId` must uniquely identify this ViewModel from the values it was
projected from.** Everything below follows from that — including why "I used an init
parameter" is not on its own an answer.

**1. The entity's identity, if the ViewModel represents one.** A ViewModel that projects a
model carries its `ModelIdentity` and roots `vmId` in it:

```swift
self.vmId = modelIdentity.viewModelId
```

For an id that is not a model's — a `nodeId: String` from a device, a host name — use that
id: `self.vmId = .init(id: nodeId)`.

**2. Otherwise, a value derived from the init parameters that uniquely identifies this
projection.** Compose the parameters that together distinguish it, or hash across all of
them:

```swift
self.vmId = .init(id: "\(host)-\(version.versionString)")   // composed
```

**3. Type based — `.init(type: Self.self)` — when the ViewModel is singleton in identity.**
Not a separate strategy so much as rule 2's degenerate case: when the parameter values are
always the same, the type is what uniquely identifies it. One instance per screen.

**4. Random — a bare `ViewModelId()` / `.init()`. Almost never desirable.** It is random
under the hood (`isRandom`, `String.unique()`), so every re-fetch mints a new identity,
SwiftUI treats the view as new, and it tears down and rebuilds — taking selection, scroll
position, and focus with it. Reach for it only where identity genuinely cannot matter, and
expect to justify it.

> **Using *an* init parameter is not the test — uniqueness is.** A display label is an init
> parameter and identifies nothing: two Boards the operator named "Studio A" collide on one
> `vmId`, and renaming one churns its row. If the init also carries a real id, that is the
> one to use; if it does not, compose or hash the parameters that actually distinguish the
> projection.

Note that `ViewModelId` stores `isRandom` alongside the id: the framework itself treats a
random identity as the exceptional case, not an ordinary one.

**Singleton — one instance per screen** (a top-level page VM, or a once-only child such as
a header/summary panel). Constant per type = maximally stable:

```swift
public var vmId: ViewModelId = .init(type: Self.self)
```

A VM that already has an `init` may equivalently declare `public let vmId: ViewModelId`
and assign `self.vmId = .init(type: Self.self)` **in the init**. Do **not** write
`let vmId: ViewModelId = .init(type: Self.self)` as a property *default* — an immutable
property with a default is excluded from `Codable` decoding (the compiler warns); use `var`
with a default, or `let` assigned in `init`.

**Instance — many per screen, ESPECIALLY `List`/`ForEach` rows.** The `vmId` MUST carry the
row's **stable data identity**, assigned in `init`. A row that represents an entity roots it
in the entity's `ModelIdentity`:

```swift
public let modelIdentity: ModelIdentity
public let vmId: ViewModelId
public init(modelIdentity: ModelIdentity, /* … */) {
    // …
    self.modelIdentity = modelIdentity
    self.vmId = modelIdentity.viewModelId
}
```

A row that is not a model's uses its own natural id — `ViewModelId` accepts a plain
`String`/`Int`/`UUID` (`self.vmId = .init(id: nodeId)`). When there is **no single natural
id**, merge stable init args into one:

```swift
self.vmId = .init(id: "\(version.versionString)-\(host)")
```

> **Two failure modes on `List` rows — both churn identity / tear the view down on every
> refresh:**
> - a **bare `.init()`** → a new *random* id each fetch, so SwiftUI treats every row as new;
> - a **constant `.init(type: Self.self)`** on a repeated row → every row shares one id and
>   they collide.
>
> A row needs a **per-row stable** id: `modelIdentity.viewModelId` for an entity,
> `.init(id: <the row's natural id>)` otherwise.

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

**The stored property is `Localizable*`; the init PARAMETER is the plain Swift type.** The
initializer takes `Int`/`Date`/`String`, and the init **body wraps it** and **owns the
formatting policy** — declared once, in the ViewModel:

```swift
public let totalCards: LocalizableInt          // stored — self-localizes on encode
public let lastSeen: LocalizableDate

public init(totalCards: Int, lastSeen: Date) {  // params are plain Swift types
    self.totalCards = .init(value: totalCards, showGroupingSeparator: true)  // policy lives here
    self.lastSeen = .init(value: lastSeen)
}
```

Callers — the Factory, stubs, previews — pass **plain values** (`.stub(totalCards: 12)`)
and **never construct a `Localizable*` themselves**. This is **Single Responsibility**:
formatting policy is the ViewModel's job, stated in one place, not smeared across every
call site.

### Enum Localization Pattern

**A displayed enum word is a `LocalizableCase`.** For a dynamic enum value the View shows as a word (status, state, priority, category), store a `LocalizableCase<TheEnum>`, NOT `@LocalizedString` and NOT a computed string on the enum. One stored value carries both the case (the View switches on `.value`) and its localized word (`Text(viewModel.state)`).

```swift
// NO `: String` raw backing — the case name IS the YAML key.
public enum SessionState: CaseIterable, Codable, Hashable, Sendable {
    case pending, running, completed, failed
}

@ViewModel
public struct SessionCardViewModel {
    public let state: LocalizableCase<SessionState>   // case + localized word
    public var vmId: ViewModelId

    public init(state: SessionState, vmId: ViewModelId) {
        self.state = LocalizableCase(state)
        self.vmId = vmId
    }
}

// View
Text(viewModel.state)
    .foregroundStyle(viewModel.state.value == .failed ? .red : .primary)
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

**A nested enum** sits under every type that encloses it, outermost first (`Board.Visibility` → `Board: { Visibility: { … } }`; `Board.Card.Status` → `Board: { Card: { Status: { … } } }`). The library derives the path from the type; you pass nothing.

**A picker over an enum** builds the value with `includingAllCases: true`; the localized value then carries every case's word as `choices`, in `allCases` order:

```swift
self.visibility = LocalizableCase(board.visibility, includingAllCases: true)

// View
Picker(selection: $selection) {
    ForEach(viewModel.visibility.choices, id: \.value) { choice in
        Text(choice.localizedString).tag(choice.value)
    }
} label: { Text(viewModel.visibilityTitle) }
```

> **SOLID: SRP.** The enum stays pure vocabulary; the word is a projection the ViewModel carries. A computed `displayName` on the enum, or a second `stateDisplay: LocalizableString` stored beside `state`, splits one responsibility across two places that drift apart, and a computed string never reaches the client at all (the localizing encoder resolves only what a ViewModel stores). One `LocalizableCase` is the case and its word.

> **Testing proves every case.** `expectFullViewModelTests()` checks that *every* case of the enum has a word in every locale, not only the case the stub holds. A missing `failed:` key fails the test even when the stub is `.pending`.

**Constraint:** Localizable values only resolve in ViewModels encoded with `localizingEncoder(in:store:)`. Do not use them in Fluent JSONB fields or other persisted types.

> **ViewModel enums carry no `String`/`Int` raw backing when avoidable.** Write
> `enum CardLiveness: Codable, Sendable, CaseIterable`, **not** `: String`. `Codable`
> synthesizes for a raw-value-less enum (it encodes by case name), and the localization
> key is the case name via `String(describing:)` — so a raw type buys nothing. A
> `String`/`Int` raw backing actively invites mayhem: `init?(rawValue:)` from arbitrary
> input, a `.rawValue` that tempts stringly-typed comparisons, and it silently couples the
> wire format to the case spelling. **Model the vocabulary; don't back it with a
> primitive.** (A View-switched discriminator enum — one the View renders per case, with
> no localized text — is likewise raw-less and needs no `LocalizableCase` at all.)

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
public struct CardDetailViewModel: ModelIdentifiedViewModel {
    // Properties come first
    public let modelIdentity: ModelIdentity
    public let checklistItems: [ChecklistItemSummary]?
    public let assignments: [AssignmentReference]?

    // MARK: - Nested Types

    /// One checklist item, as the card's detail lists it.
    public struct ChecklistItemSummary: Codable, Sendable, Identifiable, Stubbable {
        public let modelIdentity: ModelIdentity
        public let title: String
        public let isDone: Bool

        public var id: ViewModelId { modelIdentity.viewModelId }

        public init(modelIdentity: ModelIdentity, title: String, isDone: Bool) {
            self.modelIdentity = modelIdentity
            self.title = title
            self.isDone = isDone
        }
    }

    /// A member assigned to this card.
    public struct AssignmentReference: Codable, Sendable, Identifiable, Stubbable {
        public let modelIdentity: ModelIdentity
        public let memberName: String
        public let assignedAt: Date

        public var id: ViewModelId { modelIdentity.viewModelId }

        public init(modelIdentity: ModelIdentity, memberName: String, assignedAt: Date) {
            self.modelIdentity = modelIdentity
            self.memberName = memberName
            self.assignedAt = assignedAt
        }
    }

    // vmId and parent init follow
    public let vmId: ViewModelId
    // ...
}
```

**Placement rules:**
1. Nested types go AFTER the properties that reference them
2. Before `vmId` and the parent's init
3. Use `// MARK: - Nested Types` section marker
4. Each nested type gets its own doc comment

**Conformances for nested types:**
- `Codable` - for ViewModel encoding
- `Sendable` - for Swift 6 concurrency
- `Identifiable` - for SwiftUI ForEach if used in arrays; a nested type that represents an entity derives `id` from its identity (`modelIdentity.viewModelId`), the same way a ViewModel roots `vmId`
- `Stubbable` - for testing/previews

A nested type that represents an entity follows the same transport rule as a ViewModel: it carries the opaque `ModelIdentity`, its init takes the identity (never a `Model`), and the parent's factory reads `model.modelIdentity` and passes it in.

**Two-Tier Stubbable Pattern (nested, non-`@ViewModel` types):**

Nested child types are plain `Stubbable` structs — they have **no `@ViewModel` macro**, so nothing synthesizes their `stub()`. Hand-write both parts of the Stubbable pattern. (An `@ViewModel` parent, by contrast, hand-writes only the fully-defaulted parameterized `stub(...)`; its zero-arg `stub()` is macro-synthesized.) Nested types use fully qualified names in their extensions:

```swift
public extension CardDetailViewModel.ChecklistItemSummary {
    // Tier 1: the Stubbable witness — forwards ONE argument explicitly (no argument would recurse)
    static func stub() -> Self {
        .stub(modelIdentity: .stub())
    }

    // Tier 2: every parameter defaulted
    static func stub(
        modelIdentity: ModelIdentity = .stub(),
        title: String = "A Checklist Item",
        isDone: Bool = false
    ) -> Self {
        .init(modelIdentity: modelIdentity, title: title, isDone: isDone)
    }
}

public extension CardDetailViewModel.AssignmentReference {
    static func stub() -> Self {
        .stub(modelIdentity: .stub())
    }

    static func stub(
        modelIdentity: ModelIdentity = .stub(),
        memberName: String = "A Member",
        assignedAt: Date = .now
    ) -> Self {
        .init(modelIdentity: modelIdentity, memberName: memberName, assignedAt: assignedAt)
    }
}
```

**Why two tiers:**
- Tests often just need `[.stub()]` without caring about values — and each `.stub()` row gets its own identity, so a `ForEach` over them never collides
- Other tests need specific values: `.stub(title: "Buy paint")`
- Zero-arg ALWAYS calls parameterized version (single source of truth)

**When to nest vs keep top-level:**

| Nest Inside Parent | Keep Top-Level |
|-------------------|----------------|
| Child is ONLY used by this parent | Child is shared across multiple parents |
| Child represents subset/summary | Child is a full ViewModel |
| Child has no @ViewModel macro | Child has @ViewModel macro |
| Child is not RequestableViewModel | Child is RequestableViewModel |
| Example: ChecklistItemSummary, AssignmentReference | Example: CardViewModel, BoardViewModel |

**Examples:**

Card with nested summaries:
```swift
@ViewModel
public struct CardViewModel: ModelIdentifiedViewModel {
    public let assignees: [AssigneeSummary]?

    public struct AssigneeSummary: Codable, Sendable, Identifiable, Stubbable {
        public let modelIdentity: ModelIdentity
        public let name: String
        public let avatarUrl: String?
        // ...
    }
}
```

Workspace with nested board references:
```swift
@ViewModel
public struct WorkspaceViewModel: ModelIdentifiedViewModel {
    public let boards: [BoardReference]?

    public struct BoardReference: Codable, Sendable, Identifiable, Stubbable {
        public let modelIdentity: ModelIdentity
        public let title: String
        public let cardCount: Int
        // ...
    }
}
```

### Codable and Computed Properties

Swift's synthesized `Codable` only encodes **stored properties**. Since ViewModels are serialized (for JSON transport, Leaf rendering, etc.), computed properties won't be available.

> ← **Functional discipline:** derived values are projected INTO the artifact at projection time; the wire carries the function's output, not the function.

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
| Request class (screen read) | `{Name}Request` — **no verb** | `DashboardRequest`, `DocksRequest` |
| Factory extension | `{Name}ViewModel+Factory.swift` | `DashboardViewModel+Factory.swift` |
| YAML file | `{Name}ViewModel.yml` | `DashboardViewModel.yml` |

A screen/page ViewModel's read request drops the verb — the noun alone *is* the read
(`DocksRequest`, not `DocksShowRequest`). Write/action requests are noun-first with a
verb (`UserCreateRequest`). Full rules: [Naming Dictionary](../shared/NAMES.md).

**Duplicate type names across modules are fine — the module *is* the namespace.** Don't
contort a ViewModel display type's name to avoid colliding with a same-named domain type.
`CatalogChannel.Tier` (domain) and a ViewModel `Tier` (display projection) coexist as
distinct types; the `ViewModelFactory` maps between them. The display type is a
*projection of* the data, not the data — a same-named-but-distinct type is correct, not a
smell. Name a display type for what it **means**, not to dodge a collision. (This is the
naming corollary of Dependency Inversion — see "The ViewModel Module Must NOT Depend on
Domain Types" above: the ViewModel module never imports the domain module, so the two
same-named types can't actually clash in one file.) See
[Naming Dictionary → Duplicate type names](../shared/NAMES.md).

## See Also

- [Naming Dictionary](../shared/NAMES.md) - Canonical naming rules (read requests, duplicate type names across modules)
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
| 2.9 | 2026-07-02 | Fold in `@ViewModel` synthesized `Stubbable` witness: `@ViewModel` types now scaffold only the fully-defaulted parameterized `stub(...)` (macro synthesizes zero-arg `stub()`). Nested non-`@ViewModel` types still hand-write both tiers. Updated Templates 2, 4, and the full example in reference.md plus the Stubbable/Two-Tier sections here. |
| 2.10 | 2026-07-02 | Naming Conventions: screen read requests are verb-less (`DocksRequest`); added duplicate-type-names-across-modules guidance + [Naming Dictionary](../shared/NAMES.md) cross-ref. (backlog A2/A3) |
| 2.11 | 2026-07-02 | Quick conventions: child VMs drop redundant `: Codable, Sendable` (macro adds them) — B9; ViewModel enums are raw-value-less (`String(describing:)` key, not `: String rawValue`) — B6; added `SystemVersion`/locale-independent field-type row + anti-pattern (version/hostname are typed, never `LocalizableString`) — B8. |
| 2.12 | 2026-07-02 | Conceptual set: one top-level VM per screen composing children, never a mega-VM + one-file-per-VM pointer to app-setup — B1/B2; `Localizable*` init takes the plain Swift type and wraps it (formatting policy owned by init) — B3; **rewrote Identity: vmId** — stable data identity, singleton `.init(type: Self.self)` vs list-row `.init(id:)` (String/Int/UUID/merged), List-churn warning; reconciled all `.init()` throwaways in SKILL.md + reference.md (verified against `ViewModelId`) — B4; added **"ViewModel Module Must NOT Depend on Domain Types (Dependency Inversion)"** hard-rule section with Factory-adapter ergonomic — B5. |
| 2.13 | 2026-10-05 | Entity identity is an opaque `ModelIdentity`: rows and entity ViewModels carry `modelIdentity` (not `id: ModelIdType`), take it in the init (never a `Model`), root `vmId` in `modelIdentity.viewModelId`, and the factory reads `model.modelIdentity`; transport rule section with DIP + encapsulation red flag. Stubbable pattern stated in full (defaulted `stub(...)` + `stub()` forwarding one explicit argument, motivation, chaining rule, SRP); stubs default `modelIdentity: ModelIdentity = .stub()`; interactive examples use a defaulted `stub(...)`. Nested-type examples moved to the showcase vocabulary. |
| 2.14 | 2026-10-05 | Enum Localization Pattern rewritten: a displayed enum word is a stored `LocalizableCase<Enum>` (case + word in one value; nested enums keyed under every enclosing type, derived; `includingAllCases: true` + `choices` for pickers), replacing the computed `localizableString` + second `LocalizableString` field; SRP named; `expectFullViewModelTests()` proves every case. |
