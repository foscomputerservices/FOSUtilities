# FOSMVVM ViewModel Generator - Reference Templates

Complete file templates for generating ViewModels.

> **Conceptual context:** See [SKILL.md](SKILL.md) for when and why to use this skill.
> **Architecture context:** See [ViewModelArchitecture.md](../../docs/ViewModelArchitecture.md) for full FOSMVVM understanding.

## Placeholders

| Placeholder | Replace With | Example |
|-------------|--------------|---------|
| `{Name}` | ViewModel name (PascalCase, without "ViewModel" suffix) | `Dashboard`, `Card` |
| `{ViewModelsTarget}` | Your ViewModels SPM target | `ViewModels` |
| `{ResourcesPath}` | Your localization resources path | `Sources/Resources` |
| `{WebServerTarget}` | Your server-side target (server-hosted only) | `WebServer` |

---

# Server-Hosted Templates

Use these templates for apps with a backend server.

---

## Template 1: Top-Level ViewModel (RequestableViewModel)

For pages or screens that are fetched directly via API.

**Location:** `Sources/{ViewModelsTarget}/{Feature}/{Name}ViewModel.swift`

```swift
import FOSFoundation
import FOSMVVM
import Foundation

/// ViewModel for the {Name} screen.
///
/// This is a top-level ViewModel - it has an associated Request type
/// and is built by a ViewModelFactory on the server.
@ViewModel
public struct {Name}ViewModel: RequestableViewModel {
    public typealias Request = {Name}Request

    // MARK: - Localized UI Text

    @LocalizedString public var pageTitle
    // Add more @LocalizedString properties for static UI text

    // MARK: - Data

    // Add data properties the View needs to display
    // public let items: [ItemViewModel]

    // MARK: - Child ViewModels

    // Add nested ViewModels for components
    // public let createModal: CreateModalViewModel

    // MARK: - Identity

    public var vmId: ViewModelId = .init(type: Self.self)  // singleton

    // MARK: - Initialization

    public init(/* parameters */) {
        // Initialize all properties
    }

    // MARK: - Stubbable

    // Every parameter defaulted, IN THE BODY: `@ViewModel` synthesizes
    // the zero-arg `stub()` witness from it. Forward top-level values into the
    // children's `stub(...)` calls so the whole hierarchy is valid.
    public static func stub(/* defaulted parameters; a child-valued one may be the value that chains down */) -> Self {
        .init(/* parameters */)
    }
}
```

---

## Template 2: Child ViewModel (Instance)

For components that appear multiple times (cards, rows, list items).

**Location:** `Sources/{ViewModelsTarget}/{Feature}/{Name}ViewModel.swift`

```swift
import FOSFoundation
import FOSMVVM
import Foundation

/// ViewModel for a {Name} component.
///
/// This is a child ViewModel - built by its parent's Factory.
/// Each instance represents a different data entity.
@ViewModel
public struct {Name}ViewModel: ModelIdentifiedViewModel {
    // MARK: - Data Identity

    /// Opaque: transported to the Operations that act on this entity; roots `vmId`.
    public let modelIdentity: ModelIdentity

    // MARK: - Content

    public let title: String
    // Add more content properties

    // MARK: - Formatted Values

    public let createdAt: LocalizableDate  // NOT String - formatted client-side

    // MARK: - Identity

    public let vmId: ViewModelId

    // MARK: - Initialization

    // Takes the identity, never the Model — the Factory reads `model.modelIdentity`.
    public init(
        modelIdentity: ModelIdentity,
        title: String,
        createdAt: Date
    ) {
        self.modelIdentity = modelIdentity
        self.title = title
        self.createdAt = LocalizableDate(value: createdAt)
        self.vmId = modelIdentity.viewModelId
    }

    // MARK: - Stubbable

    // The fully-defaulted parameterized stub lives IN THE BODY so `@ViewModel`
    // synthesizes the zero-arg `stub()` witness from it. A member macro cannot
    // see a stub declared in an `extension`.
    public static func stub(
        modelIdentity: ModelIdentity = .stub(),
        title: String = "Sample Title",
        createdAt: Date = .now
    ) -> Self {
        .init(
            modelIdentity: modelIdentity,
            title: title,
            createdAt: createdAt
        )
    }
}
```

**Why the identity, and why opaque:** the identity is how *data model → ViewModel → View → action → Operation → ServerRequest → server → database change* names the entity, so the ViewModel transports it unchanged and roots `vmId` in it — nothing more. **SOLID protected: DIP** (the ViewModel module never imports the domain; the Factory adapts) **and encapsulation** (no one can mint, parse, or route on the identity). A `Model` in the init, or a raw `ModelIdType`/`UUID`/`String` id, is the red flag. See SKILL.md → *An Entity's Identity Passes Through the ViewModel Opaquely*.

---

## Template 3: Child ViewModel (Singleton)

For components that appear once (modals, headers, toolbars).

**Location:** `Sources/{ViewModelsTarget}/{Feature}/{Name}ViewModel.swift`

```swift
import FOSFoundation
import FOSMVVM
import Foundation

/// ViewModel for the {Name} component.
///
/// This is a singleton child ViewModel - only one instance per parent.
@ViewModel
public struct {Name}ViewModel: Codable, Sendable {
    // MARK: - Localized UI Text

    @LocalizedString public var title
    @LocalizedString public var submitButtonLabel
    @LocalizedString public var cancelButtonLabel

    // MARK: - Identity

    public var vmId: ViewModelId = .init(type: Self.self)  // singleton

    // MARK: - Initialization

    public init() {}
}

// MARK: - Stubbable

public extension {Name}ViewModel {
    static func stub() -> Self {
        .init()
    }
}
```

---

## Template 4: ViewModel with Nested Child Types

For ViewModels that contain child types used only by this parent. Shows proper placement, conformances, and the Stubbable pattern: the `@ViewModel` parent's zero-arg `stub()` is macro-synthesized from its parameterized stub, while nested non-`@ViewModel` types hand-write both stub tiers.

**File:** `Sources/{Module}/{Feature}/{Name}ViewModel.swift`

```swift
// {Name}ViewModel.swift
//
// Copyright 2026 {YourOrganization}
// Licensed under the Apache License, Version 2.0

import FOSFoundation
import FOSMVVM
import Foundation

@ViewModel
public struct {Name}ViewModel: ModelIdentifiedViewModel {
    // MARK: - Localized Strings

    @LocalizedString public var {field}Label

    // MARK: - Data Identity

    public let modelIdentity: ModelIdentity

    // MARK: - Content

    public let title: String
    public let description: String

    // MARK: - Collections (referencing nested types)

    /// Array of child summaries (only populated when expanded).
    public let childSummaries: [ChildSummary]?

    /// Related items that reference this entity.
    public let relatedItems: [RelatedItemReference]?

    // MARK: - Nested Types

    /// Summary of a child item for display in lists.
    public struct ChildSummary: Codable, Sendable, Identifiable, Stubbable {
        public let modelIdentity: ModelIdentity
        public let name: String
        public let createdAt: Date

        public var id: ViewModelId { modelIdentity.viewModelId }

        public init(modelIdentity: ModelIdentity, name: String, createdAt: Date) {
            self.modelIdentity = modelIdentity
            self.name = name
            self.createdAt = createdAt
        }
    }

    /// Reference to a related item.
    public struct RelatedItemReference: Codable, Sendable, Identifiable, Stubbable {
        public let modelIdentity: ModelIdentity
        public let title: String
        public let status: String

        public var id: ViewModelId { modelIdentity.viewModelId }

        public init(modelIdentity: ModelIdentity, title: String, status: String) {
            self.modelIdentity = modelIdentity
            self.title = title
            self.status = status
        }
    }

    // MARK: - View Identity

    public let vmId: ViewModelId

    public init(
        modelIdentity: ModelIdentity,
        title: String,
        description: String,
        childSummaries: [ChildSummary]? = nil,
        relatedItems: [RelatedItemReference]? = nil
    ) {
        self.vmId = modelIdentity.viewModelId
        self.modelIdentity = modelIdentity
        self.title = title
        self.description = description
        self.childSummaries = childSummaries
        self.relatedItems = relatedItems
    }

    // MARK: - Parent Stubbable
    // Parent is `@ViewModel`: the fully-defaulted parameterized stub lives IN THE
    // BODY so the macro synthesizes the zero-arg `stub()` witness from it (a member
    // macro cannot see a stub declared in an extension).
    public static func stub(
        modelIdentity: ModelIdentity = .stub(),
        title: String = "A Title",
        description: String = "A Description",
        childSummaries: [ChildSummary]? = [.stub(), .stub()],
        relatedItems: [RelatedItemReference]? = [.stub()]
    ) -> Self {
        .init(
            modelIdentity: modelIdentity,
            title: title,
            description: description,
            childSummaries: childSummaries,
            relatedItems: relatedItems
        )
    }
}

// MARK: - Nested Type Stubbable Extensions (fully qualified names)
// Nested types are plain `Stubbable` (no `@ViewModel`), so nothing synthesizes
// their witness — hand-write both tiers.

public extension {Name}ViewModel.ChildSummary {
    // Tier 1: the witness forwards ONE argument explicitly — `.stub()` alone recurses
    static func stub() -> Self {
        .stub(modelIdentity: .stub())
    }

    // Tier 2: every parameter defaulted
    static func stub(
        modelIdentity: ModelIdentity = .stub(),
        name: String = "A Name",
        createdAt: Date = .now
    ) -> Self {
        .init(modelIdentity: modelIdentity, name: name, createdAt: createdAt)
    }
}

public extension {Name}ViewModel.RelatedItemReference {
    static func stub() -> Self {
        .stub(modelIdentity: .stub())
    }

    static func stub(
        modelIdentity: ModelIdentity = .stub(),
        title: String = "A Title",
        status: String = "Active"
    ) -> Self {
        .init(modelIdentity: modelIdentity, title: title, status: status)
    }
}
```

**Key Points:**
- Nested types placed AFTER properties that reference them
- Nested types placed BEFORE `vmId` and parent init
- Each nested type conforms to: `Codable, Sendable, Identifiable, Stubbable`
- A nested type that represents an entity carries the opaque `ModelIdentity` and derives `id` from it
- Extensions use fully qualified names: `{Parent}.{NestedType}`
- Parent (`@ViewModel`): hand-write only the fully-defaulted `stub(...)`; the macro synthesizes zero-arg `stub()`
- Nested types (plain `Stubbable`, no `@ViewModel`): hand-write both tiers — zero-arg forwards one explicit argument to the parameterized stub
- Each `ModelIdentity.stub()` is a new identity, so `[.stub(), .stub()]` rows stay distinct
- Section markers: `// MARK: - Nested Types`

---

## Template 5: ViewModelRequest

For top-level ViewModels - the Request type for fetching from server.

**Location:** `Sources/{ViewModelsTarget}/{Feature}/{Name}Request.swift`

```swift
import FOSFoundation
import FOSMVVM
import Foundation

/// Request to fetch the {Name}ViewModel from the server.
public final class {Name}Request: ViewModelRequest, @unchecked Sendable {
    public typealias Query = EmptyQuery
    public typealias ResponseError = EmptyError

    public var responseBody: {Name}ViewModel?

    public init(
        query: EmptyQuery? = nil,
        fragment: EmptyFragment? = nil,
        requestBody: EmptyBody? = nil,
        responseBody: {Name}ViewModel? = nil
    ) {
        self.responseBody = responseBody
    }
}
```

---

## Template 6: ViewModelFactory

For top-level ViewModels - builds the ViewModel from database.

**Location:** `Sources/{WebServerTarget}/ViewModelFactories/{Name}ViewModel+Factory.swift`

```swift
import Fluent
import FOSFoundation
import FOSMVVM
import FOSMVVMVapor
import Foundation
import Vapor
import ViewModels

/// Factory that builds {Name}ViewModel from database.
extension {Name}ViewModel: VaporViewModelFactory {
    public typealias VMRequest = {Name}Request

    public static func model(context: VaporModelFactoryContext<VMRequest>) async throws -> Self {
        let db = context.req.db

        // Query database for required data
        // let items = try await Item.query(on: db).all()

        // Build child ViewModels — the Factory reads the identity; the ViewModel never sees the Model
        // let itemViewModels = try items.map { item in
        //     ItemViewModel(
        //         modelIdentity: try item.modelIdentity,
        //         title: item.title,
        //         createdAt: item.createdAt ?? .now
        //     )
        // }

        return .init(
            // Pass built children
        )
    }
}
```

---

## Template 7: Localization YAML

**Location:** `{ResourcesPath}/ViewModels/{Feature}/{Name}ViewModel.yml`

```yaml
en:
  {Name}ViewModel:
    pageTitle: "Page Title"
    headerText: "Welcome"
    submitButtonLabel: "Submit"
    cancelButtonLabel: "Cancel"
```

---

# Client-Hosted Templates

Use these templates for standalone apps without a backend server.

---

## Template 8: Client-Hosted Top-Level ViewModel

For standalone apps - the macro generates the factory automatically.

**Location:** `Sources/{ViewModelsTarget}/{Feature}/{Name}ViewModel.swift`

```swift
import FOSFoundation
import FOSMVVM
import Foundation

/// ViewModel for the {Name} screen.
///
/// Client-hosted: Factory is auto-generated from init parameters.
/// The AppState struct is derived from the init signature.
@ViewModel(options: [.clientHostedFactory])
public struct {Name}ViewModel {
    // MARK: - Localized UI Text

    @LocalizedString public var pageTitle
    // Add more @LocalizedString properties for static UI text

    // MARK: - Data (from AppState)

    // Properties populated from init parameters
    // public let settings: UserSettings
    // public let items: [ItemViewModel]

    // MARK: - Identity

    public var vmId: ViewModelId = .init(type: Self.self)  // singleton

    // MARK: - Initialization

    /// Parameters here become AppState properties.
    /// The macro generates:
    /// - struct AppState { let settings: UserSettings; let items: [ItemViewModel] }
    /// - static func model(context:) that builds Self from context.appState
    public init(settings: UserSettings, items: [ItemViewModel]) {
        self.settings = settings
        self.items = items
    }

    // MARK: - Stubbable

    // IN THE BODY: `@ViewModel` synthesizes the zero-arg `stub()` witness from it.
    public static func stub(
        settings: UserSettings = .stub(),
        items: [ItemViewModel] = [.stub()]
    ) -> Self {
        .init(settings: settings, items: items)
    }
}
```

**What the macro generates:**

```swift
// Auto-generated by @ViewModel(options: [.clientHostedFactory])
extension {Name}ViewModel {
    public typealias Request = ClientHostedRequest

    public struct AppState: Hashable, Sendable {
        public let settings: UserSettings
        public let items: [ItemViewModel]

        public init(settings: UserSettings, items: [ItemViewModel]) {
            self.settings = settings
            self.items = items
        }
    }

    public final class ClientHostedRequest: ViewModelRequest, @unchecked Sendable {
        public var responseBody: {Name}ViewModel?
        public typealias ResponseError = EmptyError
        public init(...) { ... }
    }

    public static func model(
        context: ClientHostedModelFactoryContext<Request, AppState>
    ) async throws -> Self {
        .init(
            settings: context.appState.settings,
            items: context.appState.items
        )
    }
}
```

---

## Template 9: Client-Hosted Complete Example

A settings screen for a standalone iPhone app.

### SettingsViewModel.swift

```swift
import FOSFoundation
import FOSMVVM
import Foundation

@ViewModel(options: [.clientHostedFactory])
public struct SettingsViewModel {
    // MARK: - Localized UI Text

    @LocalizedString public var pageTitle
    @LocalizedString public var themeLabel
    @LocalizedString public var notificationsLabel
    @LocalizedString public var saveButtonLabel

    // MARK: - Data

    public let currentTheme: Theme
    public let notificationsEnabled: Bool

    // MARK: - Identity

    public var vmId: ViewModelId = .init(type: Self.self)  // singleton

    // MARK: - Initialization

    public init(currentTheme: Theme, notificationsEnabled: Bool) {
        self.currentTheme = currentTheme
        self.notificationsEnabled = notificationsEnabled
    }

    public static func stub(
        currentTheme: Theme = .light,
        notificationsEnabled: Bool = true
    ) -> Self {
        .init(currentTheme: currentTheme, notificationsEnabled: notificationsEnabled)
    }
}

public enum Theme: Codable, Sendable {
    case light, dark, system
}
```

### SettingsViewModel.yml

```yaml
en:
  SettingsViewModel:
    pageTitle: "Settings"
    themeLabel: "Theme"
    notificationsLabel: "Notifications"
    saveButtonLabel: "Save Changes"
```

### Usage in SwiftUI View

```swift
struct SettingsView: View {
    @State private var viewModel: SettingsViewModel?

    var body: some View {
        // Render viewModel
    }

    func loadViewModel() async {
        // Create AppState from local storage/preferences
        let appState = SettingsViewModel.AppState(
            currentTheme: UserDefaults.standard.theme,
            notificationsEnabled: UserDefaults.standard.notificationsEnabled
        )

        // Build context with localization
        let context = ClientHostedModelFactoryContext<
            SettingsViewModel.Request,
            SettingsViewModel.AppState
        >(appState: appState, localizationStore: myYamlStore)

        // Get localized ViewModel
        viewModel = try await SettingsViewModel.model(context: context)
    }
}
```

---

## Template 10: Interactive Server-Hosted ViewModel (with Operations)

**For interactive top-level ViewModels whose actions dispatch to a server.** This template covers both files the generator emits for an interactive server-hosted VM. See **Third Decision: Interactive vs Display-Only** in `SKILL.md` for when to use this vs a display-only VM.

### {Name}ViewModel.swift

**Location:** `{ViewModelsTarget}/{Feature}/{Name}ViewModel.swift`

```swift
import FOSFoundation
import FOSMVVM
import Foundation

@ViewModel
public struct {Name}ViewModel: RequestableViewModel {
    // MARK: ViewModel Properties

    @LocalizedString public var {titleProperty}
    // ... additional @LocalizedString properties and scalar fields

    // MARK: RequestableViewModel Protocol

    public typealias Request = {Name}Request
    public let vmId: ViewModelId

    // MARK: Operations Access

    private let isStub: Bool

    #if canImport(SwiftUI)
    public var operations: any {Name}ViewModelOperations {
        isStub ? {Name}StubOps() : {Name}Ops()
    }
    #endif

    // MARK: Initialization

    public init({initParams}) {
        self.init(isStub: false, {initParamNames})
    }

    private init(isStub: Bool, {initParams}) {
        self.isStub = isStub
        // ... assign all stored properties from init params
        self.vmId = .init(type: Self.self)
    }

    // Every parameter defaulted; `@ViewModel` synthesizes `stub()`.
    public static func stub({initParamsWithDefaults}) -> Self {
        .init(isStub: true, {initParamNames})
    }
}
```

### {Name}ViewModelOperations.swift

**Location:** `{ViewModelsTarget}/{Feature}/{Name}ViewModelOperations.swift` (co-located with the ViewModel)

```swift
import FOSFoundation
import FOSMVVM
import Foundation

// MARK: - Protocol

public protocol {Name}ViewModelOperations: ViewModelOperations {
    // Server-backed ops: no `output:` parameter (server owns storage).
    // `async throws` matches the network call body.
    func {action}({scalarInputs}) async throws
}

// MARK: - Live Implementation (Server-Backed)

public struct {Name}Ops: {Name}ViewModelOperations {
    public init() {}

    public func {action}({scalarInputs}) async throws {
        // Dispatches a ServerRequest. The server owns storage.
    }
}

// MARK: - Stub Implementation

#if canImport(SwiftUI)
public final class {Name}StubOps: {Name}ViewModelOperations, @unchecked Sendable {
    public var {action}Called: Bool { {action}CalledWith != nil }
    public private(set) var {action}CalledWith: {InputType}?

    public init() {}

    public func {action}({scalarInputs}) async throws {
        {action}CalledWith = {input}
    }
}
#endif
```

**Rules that must hold:**

- No `output storage:` parameter on any method — server owns storage.
- `async throws` only when the body genuinely awaits I/O or throws. A method that stores a scalar should not be `async`.
- The stub exposes two accessors per operation: `{action}Called` (did the op fire at all?) and `{action}CalledWith` (what data was passed?). UI tests typically assert on both. The stub does not mutate downstream state — server-backed ops can't because there is no server in the test environment.
- **An action on an entity takes the ViewModel's `modelIdentity`, unchanged.** The VM carries `public let modelIdentity: ModelIdentity` (rooting `vmId` with `modelIdentity.viewModelId`), the View hands it to the op (`try await operations.{action}(modelIdentity)`), and the stub records it (`{action}CalledWith: ModelIdentity?`). A UI test then holds an identity, passes it into `.stub(modelIdentity:)`, taps, and asserts `{action}CalledWith` equals it — see fosmvvm-ui-tests-generator → *Identity Transport Test*. The op never receives the Model or a raw id (**DIP** + encapsulation).

---

## Template 11: Interactive Client-Hosted ViewModel (with Operations)

**For interactive top-level ViewModels whose actions mutate local `@Observable` storage.** This template covers both files the generator emits for an interactive client-hosted VM.

### {Name}ViewModel.swift

**Location:** `{ViewModelsTarget}/{Feature}/{Name}ViewModel.swift`

```swift
import FOSFoundation
import FOSMVVM
import Foundation

@ViewModel(options: [.clientHostedFactory])
public struct {Name}ViewModel {
    // MARK: ViewModel Properties

    @LocalizedString public var {titleProperty}

    // Scalar projections from @Observable storage — no @Observable references here.
    public let {scalarField1}: {Type1}
    public let {scalarField2}: {Type2}

    // MARK: Operations Access

    private let isStub: Bool

    #if canImport(SwiftUI)
    public var operations: any {Name}ViewModelOperations {
        isStub ? {Name}StubOps() : {Name}Ops()
    }
    #endif

    public var vmId: ViewModelId = .init(type: Self.self)  // singleton

    // MARK: Initialization

    // Public init parameters become AppState properties (macro-generated).
    // Do NOT include isStub in the public init — it's an implementation detail.
    public init({scalarField1}: {Type1}, {scalarField2}: {Type2}) {
        self.init(isStub: false, {scalarField1}: {scalarField1}, {scalarField2}: {scalarField2})
    }

    private init(isStub: Bool, {scalarField1}: {Type1}, {scalarField2}: {Type2}) {
        self.isStub = isStub
        self.{scalarField1} = {scalarField1}
        self.{scalarField2} = {scalarField2}
    }

    // Every parameter defaulted; `@ViewModel` synthesizes `stub()`.
    public static func stub(
        {scalarField1}: {Type1} = {stubValue1},
        {scalarField2}: {Type2} = {stubValue2}
    ) -> Self {
        .init(isStub: true, {scalarField1}: {scalarField1}, {scalarField2}: {scalarField2})
    }
}
```

### {Name}ViewModelOperations.swift

**Location:** `{ViewModelsTarget}/{Feature}/{Name}ViewModelOperations.swift` (co-located with the ViewModel)

```swift
import FOSFoundation
import FOSMVVM
import Foundation

// MARK: - Protocol

public protocol {Name}ViewModelOperations: ViewModelOperations {
    // Client-hosted ops: scalar inputs first, write target last, labeled `output`.
    // Sync by default — no async unless the body genuinely awaits.
    func {action}(_ {input}: {InputType}, output storage: {StorageType})
}

// MARK: - Live Implementation (Client-Hosted)

public struct {Name}Ops: {Name}ViewModelOperations {
    public init() {}

    public func {action}(_ {input}: {InputType}, output storage: {StorageType}) {
        storage.{property} = {input}
    }
}

// MARK: - Stub Implementation

#if canImport(SwiftUI)
public final class {Name}StubOps: {Name}ViewModelOperations, @unchecked Sendable {
    public private(set) var {action}Called: Bool = false

    public init() {}

    public func {action}(_ {input}: {InputType}, output storage: {StorageType}) {
        {action}Called = true
        storage.{property} = {input}
    }
}
#endif
```

**Rules that must hold:**

- Scalar inputs first, `output storage: {StorageType}` **last** on every mutating method. `in storage:` is the wrong label — reads like an input, writes like an output.
- Ops are synchronous unless the body awaits. Gratuitous `async` on a synchronous mutation introduces out-of-order Task completion for rapid user interactions (stepper taps can land out of order).
- Ops must not read `storage.foo` for branch decisions. Branches switch on scalar inputs. If you want to read `storage.foo`, promote it to a scalar input.
- Never fail silently. No `try?`, no empty `catch {}`. Surface errors to observable state.
- **Client-hosted stubs mirror the live mutation.** The stub records that the op fired (`{action}Called: Bool = false` → set to `true`) **and** performs the same write the live implementation would (`storage.{property} = {input}`). This keeps the projection loop intact under test: tap → stub mutates storage → `@Observable` fires → re-projection → View updates. UI tests assert "was it called?" with `stubOps.{action}Called`; "with what value?" is read directly from `storage.{property}` — the storage itself holds the `CalledWith` equivalent, so no separate accessor is needed. This asymmetry with server-backed stubs (which expose `Called` + `CalledWith` and never mutate) is intentional: server-backed tests have no local storage to observe.

See [Architecture Patterns → Ops Conventions](../shared/architecture-patterns.md) for the full rationale.

---

# Server-Hosted Complete Example

## Complete Example: Dashboard with Cards

### DashboardViewModel.swift

```swift
import FOSFoundation
import FOSMVVM
import Foundation

@ViewModel
public struct DashboardViewModel: RequestableViewModel {
    public typealias Request = DashboardRequest

    @LocalizedString public var pageTitle
    @LocalizedString public var emptyStateMessage

    public let cards: [CardViewModel]
    public let totalCount: LocalizableInt

    public var vmId: ViewModelId = .init(type: Self.self)  // singleton

    public init(cards: [CardViewModel], totalCount: Int) {
        self.cards = cards
        self.totalCount = LocalizableInt(value: totalCount)
    }

    // `cardCount` chains down: the stub builds that many cards and reports the same
    // total, so the hierarchy is valid whatever the caller asks for.
    public static func stub(cardCount: Int = 2) -> Self {
        .init(
            cards: (0..<cardCount).map { _ in .stub() },
            totalCount: cardCount
        )
    }
}
```

### CardViewModel.swift

```swift
import FOSFoundation
import FOSMVVM
import Foundation

@ViewModel
public struct CardViewModel: ModelIdentifiedViewModel {
    public let modelIdentity: ModelIdentity
    public let title: String
    public let description: String
    public let createdAt: LocalizableDate

    public let vmId: ViewModelId

    public init(
        modelIdentity: ModelIdentity,
        title: String,
        description: String,
        createdAt: Date
    ) {
        self.modelIdentity = modelIdentity
        self.title = title
        self.description = description
        self.createdAt = LocalizableDate(value: createdAt)
        self.vmId = modelIdentity.viewModelId
    }

    // `@ViewModel` synthesizes the zero-arg `stub()` witness from this fully-defaulted
    // parameterized stub — which must be IN THE BODY (a member macro can't see an
    // extension). Do not hand-write `stub()`.
    public static func stub(
        modelIdentity: ModelIdentity = .stub(),
        title: String = "Sample Card",
        description: String = "This is a sample card for previews.",
        createdAt: Date = .now
    ) -> Self {
        .init(
            modelIdentity: modelIdentity,
            title: title,
            description: description,
            createdAt: createdAt
        )
    }
}
```

### DashboardRequest.swift

```swift
import FOSFoundation
import FOSMVVM
import Foundation

public final class DashboardRequest: ViewModelRequest, @unchecked Sendable {
    public typealias Query = EmptyQuery
    public typealias ResponseError = EmptyError

    public var responseBody: DashboardViewModel?

    public init(
        query: EmptyQuery? = nil,
        fragment: EmptyFragment? = nil,
        requestBody: EmptyBody? = nil,
        responseBody: DashboardViewModel? = nil
    ) {
        self.responseBody = responseBody
    }
}
```

### DashboardViewModel+Factory.swift

```swift
import Fluent
import FOSFoundation
import FOSMVVM
import FOSMVVMVapor
import Foundation
import Vapor
import ViewModels

extension DashboardViewModel: VaporViewModelFactory {
    public typealias VMRequest = DashboardRequest

    public static func model(context: VaporModelFactoryContext<VMRequest>) async throws -> Self {
        let db = context.req.db

        let cards = try await Card.query(on: db)
            .sort(\.$createdAt, .descending)
            .all()

        // The one place that touches the `Card` model: it reads the identity and
        // hands the ViewModel plain values.
        let cardViewModels = try cards.map { card in
            CardViewModel(
                modelIdentity: try card.modelIdentity,
                title: card.title,
                description: card.description,
                createdAt: card.createdAt ?? .now
            )
        }

        return .init(
            cards: cardViewModels,
            totalCount: cards.count
        )
    }
}
```

### DashboardViewModel.yml

```yaml
en:
  DashboardViewModel:
    pageTitle: "Dashboard"
    emptyStateMessage: "No cards yet. Create your first one!"
```

---

## Quick Reference: Property Types

| Data Type | ViewModel Property Type | Why |
|-----------|------------------------|-----|
| Static UI text | `@LocalizedString` | Resolved from YAML |
| Dynamic data in text | `@LocalizedSubs` | Substitutions like "Hello, %{name}!" |
| Composed text | `@LocalizedCompoundString` | Joins pieces with locale-aware ordering |
| User content | `String` | Already localized or raw data |
| Entity identity | `ModelIdentity` | Opaque; transported to Operations, roots `vmId` |
| Date/time | `LocalizableDate` | Client formats for locale/timezone |
| Count/number | `LocalizableInt` | Client formats with grouping |
| Child component | `ChildViewModel` | Nested ViewModel |
| List of children | `[ChildViewModel]` | Array of nested ViewModels |

---

## Contextual Localization Examples

### @LocalizedSubs - Dynamic Data in Text

When you need to embed dynamic values in localized text:

```swift
@ViewModel
public struct WelcomeViewModel {
    @LocalizedSubs(substitutions: \.subs) var welcomeMessage

    private let userName: String
    private let userIndex: LocalizableInt

    private var subs: [String: any Localizable] {
        [
            "userName": LocalizableString.constant(userName),
            "userIndex: userIndex
        ],
    }
}
```

```yaml
en:
  WelcomeViewModel:
    welcomeMessage: "Welcome back, %{userName}:%{userIndex}!"

ja:
  WelcomeViewModel:
    welcomeMessage: "お帰りなさい、%{userName}:%{userIndex}さん！"
```

The `%{userName}` and `%{userIndex}` substitution points are placed correctly per locale.
Use LocalizableInt and not Int to ensure proper localization of numbers in all locales.

### @LocalizedCompoundString - Composed Text

When you need to join multiple pieces with locale-aware ordering:

```swift
@ViewModel
public struct UserNameViewModel {
    @LocalizedStrings var namePieces  // Array of strings from YAML
    @LocalizedString var separator
    @LocalizedCompoundString(pieces: \._namePieces, separator: \._separator) var fullName
}
```

This handles RTL languages and locales where name order differs (e.g., family name first).

---

## Checklists

### All ViewModels:
- [ ] `@ViewModel` macro applied
- [ ] `vmId: ViewModelId` property
- [ ] Defaulted `stub(...)` (every parameter defaulted; a child-valued one may be the value that chains down) in the body; zero-arg `stub()` synthesized by `@ViewModel` or hand-written forwarding one explicit argument
- [ ] Top-level stub values chain down into children's `stub(...)` calls
- [ ] `Codable, Sendable` conformance

### Server-Hosted Top-Level:
- [ ] `: RequestableViewModel` conformance
- [ ] `typealias Request = {Name}Request`
- [ ] Request file created
- [ ] Factory file created
- [ ] YAML file created

### Client-Hosted Top-Level:
- [ ] `@ViewModel(options: [.clientHostedFactory])` macro
- [ ] Init parameters define the AppState
- [ ] YAML file created (bundled in app)
- [ ] No Request or Factory files needed

### Instance ViewModels (either mode):
- [ ] Entity rows: `modelIdentity: ModelIdentity` property + `ModelIdentifiedViewModel`
- [ ] Init takes the `ModelIdentity`, never a `Model`; the Factory reads `model.modelIdentity`
- [ ] `vmId = modelIdentity.viewModelId` in init (a non-entity row: `.init(id: <natural id>)`)
- [ ] Stub defaults `modelIdentity: ModelIdentity = .stub()`

### ViewModels with Localization (either mode):
- [ ] `@LocalizedString` for static text
- [ ] YAML file with matching keys
