---
name: fosmvvm-swiftui-view-generator
description: Generate SwiftUI views that render FOSMVVM ViewModels. Scaffolds ViewModelView pattern with binding, loading states, and previews.
homepage: https://github.com/foscomputerservices/FOSUtilities
metadata: {"clawdbot": {"emoji": "📱", "os": ["darwin"]}}
---

# FOSMVVM SwiftUI View Generator

Generate SwiftUI views that render FOSMVVM ViewModels.

## Conceptual Foundation

> For full architecture context, see [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md) | [OpenClaw reference]({baseDir}/references/FOSMVVMArchitecture.md)

> **API catalog:** check [`../shared/api-catalog/FOSMVVM.md`](../shared/api-catalog/FOSMVVM.md) § SwiftUI Support before hand-writing helpers.

In FOSMVVM, **Views are thin rendering layers** that display ViewModels:

```
┌─────────────────────────────────────────────────────────────┐
│                    ViewModelView Pattern                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ViewModel (Data)          ViewModelView (SwiftUI)          │
│  ┌──────────────────┐     ┌──────────────────┐             │
│  │ title: String    │────►│ Text(vm.title)   │             │
│  │ items: [Item]    │────►│ ForEach(vm.items)│             │
│  │ isEnabled: Bool  │────►│ .disabled(!...)  │             │
│  └──────────────────┘     └──────────────────┘             │
│                                                              │
│  Operations (Actions)                                        │
│  ┌──────────────────┐     ┌──────────────────┐             │
│  │ submit()         │◄────│ Button(action:)  │             │
│  │ cancel()         │◄────│ .onAppear { }    │             │
│  └──────────────────┘     └──────────────────┘             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Key principle:** Views don't transform or compute data. They render what the ViewModel provides.

---

## View-ViewModel Alignment

**The View filename should match the ViewModel it renders.**

```
Sources/
  {ViewModelsTarget}/
    {Feature}/
      {Feature}ViewModel.swift        ←──┐
      {Entity}CardViewModel.swift     ←──┼── Same names
                                          │
  {ViewsTarget}/                          │
    {Feature}/                            │
      {Feature}View.swift             ────┤  (renders {Feature}ViewModel)
      {Entity}CardView.swift          ────┘  (renders {Entity}CardViewModel)
```

This alignment provides:
- **Discoverability** - Find the view for any ViewModel instantly
- **Consistency** - Same naming discipline across the codebase
- **Maintainability** - Changes to ViewModel are reflected in view location

---

## Core Components

### 1. ViewModelView Protocol

Every view conforms to `ViewModelView`:

```swift
public struct MyView: ViewModelView {
    private let viewModel: MyViewModel

    public var body: some View {
        Text(viewModel.title)
    }

    public init(viewModel: MyViewModel) {
        self.viewModel = viewModel
    }
}
```

**Required:**
- `private let viewModel: {ViewModel}`
- `public init(viewModel:)`
- Conforms to `ViewModelView` protocol

### 2. Operations (Optional)

> **Display-only views skip this entire section.** A View whose ViewModel has no `operations` property is display-only by definition — no Operations files exist on either side of the seam, no `repaintToggle`, no `testDataTransporter`. Do not invent an empty Operations protocol for symmetry; absence of operations is the signal that the View is display-only. (See "View Categories" below for the full distinction.)

#### Operations are an architectural seam

An `Operations` protocol is the framework-side analog of `ServerRequest`: a contract the View calls into without knowing who satisfies it. Three files participate, on two sides of the seam:

| File | Side | Purpose |
|---|---|---|
| `<Name>Operations.swift` | Framework (shared module) | The protocol — what actions the View can dispatch |
| `<Name>StubOps.swift` | Framework (shared module) | Stub implementation — used in previews and `LocalizableTestCase`-driven tests |
| `<Name>Ops.swift` | App target (implementation side) | Live implementation — orchestrates services, writes to storage, dispatches `ServerRequest`s |

For a feature `LandingPage`, these live at:
- `Sources/ViewModels/Operations/LandingPage/LandingPageOperations.swift`
- `Sources/ViewModels/Operations/LandingPage/LandingPageStubOps.swift`
- `Sources/{AppTarget}/Operations/LandingPage/LandingPageOps.swift`

The View imports only the framework side and is unaware of which implementation runs. App Intents, lock-screen transport actions, and other non-View entry points dispatch through the **same** Operations protocol — the View is one entry point of several, not the owner of the action vocabulary.

Two protocol layers to keep distinct:
- **`FOSMVVM.ViewModelOperations`** — the framework's base protocol. Every per-feature operations protocol conforms to it.
- **`<Name>ViewModelOperations`** (e.g., `LandingPageViewModelOperations`) — your project's per-feature protocol; conforms to `FOSMVVM.ViewModelOperations` and lists the actions the View dispatches.

#### Generic over `any` at op method signatures

Per the architecture rule (no existentials at architectural boundaries), Operations *method signatures* take Fields conformers as generic parameters, not `any`:

```swift
// ✅ GOOD — generic specialization preserves the concrete type for the live op.
protocol ConversationOperations: ViewModelOperations {
    func create<F: ConversationFields>(from fields: F) async throws
}

// ❌ BAD — `any` erases the concrete type and pulls existentials through the call graph.
protocol ConversationOperations: ViewModelOperations {
    func create(from fields: any ConversationFields) async throws
}
```

**Storage is a separate decision from method signatures.** The View's `operations` property *is* typed as `any <Name>ViewModelOperations` — that's required, since Apple's API forces a concrete View struct shape and the View has to store the value somehow. This is the exception arch.md §1.5 explicitly carves out for "structural requirements that leave no alternative."

Crucially, **`any` at storage does not infect the protocol's method signatures.** Swift 5.7+ opens the existential implicitly at each call site, so a generic method called on an `any P` value still specializes to a concrete type at the call site:

```swift
private let operations: any ConversationOperations          // ← `any` at storage is fine

private func submit() async throws {
    try await operations.create(from: fields)              // ← F inferred concretely
}
```

The rule to internalize: **`any` is acceptable at single-value storage sites; generics are required at protocol method signatures.** The architecture's anti-existential pressure is about preventing erasure from compounding through the call graph — and a stored `any P` does not compound, because each method call re-specializes.

#### Server-backed example

Interactive views have operations:

```swift
public struct MyView: ViewModelView {
    private let viewModel: MyViewModel
    private let operations: any MyViewModelOperations

    #if DEBUG
    @State private var repaintToggle = false
    #endif

    public var body: some View {
        Button(action: performAction) {
            Text(viewModel.buttonLabel)
        }
        #if DEBUG
        .testDataTransporter(viewModelOps: operations, repaintToggle: $repaintToggle)
        #endif
    }

    public init(viewModel: MyViewModel) {
        self.viewModel = viewModel
        self.operations = viewModel.operations
    }

    private func performAction() {
        operations.performAction()
        toggleRepaint()
    }

    private func toggleRepaint() {
        #if DEBUG
        repaintToggle.toggle()
        #endif
    }
}
```

**When views have operations:**
- Store `operations` from `viewModel.operations` in init
- Add `@State private var repaintToggle = false` (DEBUG only)
- Add `.testDataTransporter(viewModelOps:repaintToggle:)` modifier (DEBUG only)
- Call `toggleRepaint()` after every operation invocation

**Why `toggleRepaint()` exists.** Client-hosted ops mutate `@Observable` storage that test harnesses (and occasionally SwiftUI itself) don't always re-observe in time for the next assertion. Toggling a `@State` flag forces a deterministic re-render at the View boundary, so UI tests see the post-op state instead of the pre-op state. In production builds the toggle is compiled out — it costs nothing at runtime.

**Async vs sync op shape.** Server-backed ops are typically async (`try await operations.performAction()`) and pair with `Button(errorBinding:asyncAction:)` / `.task(errorBinding:)` / `.onAsyncSubmit`. Client-hosted scalar-mutation ops are typically sync — the live op writes a property on `@Observable` storage and returns. Don't add `async` to an op method that doesn't need it; don't omit `async` on one that calls a `ServerRequest`.

The example above shows a **server-backed** op — `operations.performAction()` dispatches a `ServerRequest`. For **client-hosted** ops (those that mutate local `@Observable` storage), the call site shape is different — the View must inject storage from the environment and hand it to the op explicitly. See below.

### 2a. Client-Hosted Operations: `@Environment` Injection and `output:` at the Call Site

**Applies when the ViewModel is client-hosted and its operations mutate one or more `@Observable` storage objects** (e.g., `UserSettings`, `DeviceState`). Server-backed operations use the plain pattern shown in section 2.

Client-hosted ops take their write target as a trailing `output storage:` parameter. The ViewModel does **not** hold a reference to storage (see [Architecture Patterns → VMs Hold Scalars](../shared/architecture-patterns.md)); the View reads storage from `@Environment` and hands the reference to the op at the call site.

```swift
public struct PreferencesView: ViewModelView {
    // The reference to the @Observable lives on the View, not the ViewModel.
    @Environment(UserSettings.self) private var settings

    private let viewModel: PreferencesViewModel
    // Stored as `any` — required at View storage, see §2 "Generic over `any`".
    // The protocol's *method signatures* remain generic; existential opening
    // re-specializes at each call site.
    private let operations: any PreferencesViewModelOperations

    #if DEBUG
    @State private var repaintToggle = false
    #endif

    public var body: some View {
        VStack {
            Toggle(
                viewModel.notificationsLabel,
                isOn: Binding(
                    get: { viewModel.notificationsEnabled },
                    set: { setNotifications($0) }
                )
            )
            Picker(viewModel.themeLabel, selection: Binding(
                get: { viewModel.theme },
                set: { setTheme($0) }
            )) {
                // ... options
            }
        }
        #if DEBUG
        .testDataTransporter(viewModelOps: operations, repaintToggle: $repaintToggle)
        #endif
    }

    public init(viewModel: PreferencesViewModel) {
        self.viewModel = viewModel
        self.operations = viewModel.operations
    }

    private func setNotifications(_ enabled: Bool) {
        // Hand the reference from @Environment to the op at the call site.
        operations.setNotificationsEnabled(enabled, output: settings)
        toggleRepaint()
    }

    private func setTheme(_ theme: Theme) {
        operations.setTheme(theme, output: settings)
        toggleRepaint()
    }

    private func toggleRepaint() {
        #if DEBUG
        repaintToggle.toggle()
        #endif
    }
}
```

**The mental model:**

- `@Environment(UserSettings.self)` puts the reference on the View.
- The VM has **scalars only** (`viewModel.notificationsEnabled: Bool`, `viewModel.theme: Theme`), projected from `settings` by the parent's `.bind(appState: .init(...))` call. The VM never holds the `UserSettings` reference.
- The mutation closure reads `settings` from its own `@Environment` and passes it to the op as `output: settings`. The reference never crosses the VM boundary.

**Common mistakes to avoid:**

| Anti-pattern | Why it's wrong |
|--------------|----------------|
| `@State private var settings = UserSettings()` on the view | View should read storage from `@Environment`, not own it |
| `viewModel.settings = ...` | VMs never hold `@Observable` references (rule 4 of Forward Projection) |
| `operations.setTheme(.dark)` (no `output:`) | Mutation has no target — the op can't write anywhere |
| `operations.setTheme(.dark, in: settings)` | `in` reads like input; `output` is the correct label (conflation anti-pattern) |
| Reading `settings.theme` in this View's body for display | Display reads belong on the VM scalar (`viewModel.theme`); env reads break projection |

Full rationale — why the VM holds scalars, why the reference flows through the call site rather than the VM, what breaks otherwise — lives in [Architecture Patterns → Ops Conventions](../shared/architecture-patterns.md) and [Architecture Patterns → The Four Rules of Forward Projection](../shared/architecture-patterns.md).

### 3. Child View Binding

Parent views bind child views using `.bind(appState:)`:

```swift
public struct ParentView: ViewModelView {
    @Environment(AppState.self) private var appState
    private let viewModel: ParentViewModel

    public var body: some View {
        VStack {
            Text(viewModel.title)

            // Bind child view with subset of parent's data
            ChildView.bind(
                appState: .init(
                    itemId: viewModel.selectedId,
                    isConnected: viewModel.isConnected
                )
            )
        }
    }
}
```

**The `.bind()` pattern:**
- Child views use `.bind(appState:)` to receive data from parent
- Parent creates child's `AppState` from its own ViewModel data
- Enables composition without tight coupling

### 4. Form Views with Validation

Forms use `FormFieldView` and `Validations` environment:

```swift
public struct MyFormView: ViewModelView {
    @Environment(Validations.self) private var validations
    @Environment(\.focusState) private var focusField
    @State private var error: Error?

    private let viewModel: MyFormViewModel
    private let operations: any MyFormViewModelOperations

    public var body: some View {
        Form {
            FormFieldView(
                fieldModel: viewModel.$email,
                focusField: focusField,
                fieldValidator: viewModel.validateEmail,
                validations: validations
            )

            Button(errorBinding: $error, asyncAction: submit) {
                Text(viewModel.submitButtonLabel)
            }
            .disabled(validations.hasError)
        }
        .onAsyncSubmit {
            await submit()
        }
        .alert(
            errorBinding: $error,
            title: viewModel.errorTitle,
            message: viewModel.errorMessage,
            dismissButtonLabel: viewModel.dismissButtonLabel
        )
    }
}
```

**Form patterns:**
- `@Environment(Validations.self)` for validation state
- `FormFieldView` for each input field
- `Button(errorBinding:asyncAction:)` for async actions
- `.disabled(validations.hasError)` on submit button
- Separate handling for validation errors vs general errors

### 5. Previews

Use `.previewHost()` for SwiftUI previews:

```swift
#if DEBUG
#Preview {
    MyView.previewHost(
        bundle: MyAppResourceAccess.localizationBundle
    )
    .environment(AppState())
}

#Preview("With Data") {
    MyView.previewHost(
        bundle: MyAppResourceAccess.localizationBundle,
        viewModel: .stub(title: "Preview Title")
    )
    .environment(AppState())
}
#endif
```

## View Categories

The first decision when generating a View is **interactive vs. display-only** — and that decision is forced by the ViewModel, not chosen by the View author.

| ViewModel has `operations` property? | View kind | Operations files |
|---|---|---|
| **No** | Display-only | None — do not create empty Operations protocol/Stub/Live files |
| **Yes** | Interactive (server-backed or client-hosted) | `<Name>Operations.swift` + `<Name>StubOps.swift` (framework side) + `<Name>Ops.swift` (app side) |

Absence of operations is a positive signal that the View originates no actions. Inventing an empty Operations protocol "for symmetry" is an anti-pattern (arch.md §3.4).

### Display-Only Views

Views that just render data (no user interactions):

```swift
public struct InfoView: ViewModelView {
    private let viewModel: InfoViewModel

    public var body: some View {
        VStack {
            Text(viewModel.title)
            Text(viewModel.description)

            if viewModel.isActive {
                Text(viewModel.activeStatusLabel)
            }
        }
    }

    public init(viewModel: InfoViewModel) {
        self.viewModel = viewModel
    }
}
```

**Characteristics:**
- No `operations` property
- No `repaintToggle` or `testDataTransporter`
- Just renders ViewModel properties
- May have conditional rendering based on ViewModel state

### Interactive Views

Views with user actions:

```swift
public struct ActionView: ViewModelView {
    @State private var error: Error?

    private let viewModel: ActionViewModel
    private let operations: any ActionViewModelOperations

    #if DEBUG
    @State private var repaintToggle = false
    #endif

    public var body: some View {
        VStack {
            Button(action: performAction) {
                Text(viewModel.actionLabel)
            }

            Button(role: .cancel, action: cancel) {
                Text(viewModel.cancelLabel)
            }
        }
        .alert(
            errorBinding: $error,
            title: viewModel.errorTitle,
            message: viewModel.errorMessage,
            dismissButtonLabel: viewModel.dismissButtonLabel
        )
        #if DEBUG
        .testDataTransporter(viewModelOps: operations, repaintToggle: $repaintToggle)
        #endif
    }

    public init(viewModel: ActionViewModel) {
        self.viewModel = viewModel
        self.operations = viewModel.operations
    }

    private func performAction() {
        operations.performAction()
        toggleRepaint()
    }

    private func cancel() {
        operations.cancel()
        toggleRepaint()
    }

    private func toggleRepaint() {
        #if DEBUG
        repaintToggle.toggle()
        #endif
    }
}
```

### Form Views

Views with validated input fields:

- Use `FormFieldView` for each input
- `@Environment(Validations.self)` for validation state
- Button disabled when `validations.hasError`
- Separate error handling for validation vs operation errors

### Container Views

Views that compose child views:

```swift
public struct ContainerView: ViewModelView {
    @Environment(AppState.self) private var appState
    private let viewModel: ContainerViewModel
    private let operations: any ContainerViewModelOperations

    public var body: some View {
        VStack {
            switch viewModel.state {
            case .loading:
                ProgressView()

            case .ready:
                ChildAView.bind(
                    appState: .init(id: viewModel.selectedId)
                )

                ChildBView.bind(
                    appState: .init(
                        isActive: viewModel.isActive,
                        level: viewModel.level
                    )
                )
            }
        }
    }
}
```

## When to Use This Skill

- Creating a new SwiftUI view for a FOSMVVM app
- Building UI to render a ViewModel
- Following an implementation plan that requires new views
- Creating forms with validation
- Building container views that compose child views

## What This Skill Generates

| File | Location | Purpose |
|------|----------|---------|
| `{ViewName}View.swift` | `Sources/{ViewsTarget}/{Feature}/` | The SwiftUI view |

**Note:** The corresponding ViewModel and ViewModelOperations should already exist (use `fosmvvm-viewmodel-generator` skill).

## Project Structure Configuration

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{ViewName}` | View name (without "View" suffix) | `TaskList`, `SignIn` |
| `{ViewsTarget}` | SwiftUI views SPM target | `MyAppViews` |
| `{Feature}` | Feature/module grouping | `Tasks`, `Auth` |

## Pattern Implementation

This skill references conversation context to determine view structure:

### View Type Detection

From conversation context, the skill identifies:
- **ViewModel structure** (from prior discussion or specifications read by Claude)
- **View category**: Display-only, interactive, form, or container
- **Operations needed**: Whether view has user-initiated actions
- **Child composition**: Whether view binds child views

### Component Selection

Based on view type:
- **Display-only**: ViewModelView protocol, viewModel property only
- **Interactive**: Add operations, repaintToggle, testDataTransporter, toggleRepaint()
- **Form**: Add Validations environment, FormFieldView, validation error handling
- **Container**: Add child view `.bind()` calls

### Code Generation

Generates view file with:
1. `ViewModelView` protocol conformance
2. Properties (viewModel, operations if needed, repaintToggle if interactive)
3. Body with rendering logic
4. Init storing viewModel and operations
5. Action methods (if interactive)
6. Test infrastructure (if interactive)
7. Previews for different states

### Context Sources

Skill references information from:
- **Prior conversation**: Requirements discussed with user
- **Specification files**: If Claude has read specifications into context
- **ViewModel definitions**: From codebase or discussion

## Key Patterns

### Error Handling Pattern

```swift
@State private var error: Error?

var body: some View {
    VStack {
        Button(errorBinding: $error, asyncAction: submit) {
            Text(viewModel.submitLabel)
        }
    }
    .alert(
        errorBinding: $error,
        title: viewModel.errorTitle,
        message: viewModel.errorMessage,
        dismissButtonLabel: viewModel.dismissButtonLabel
    )
}

private func submit() async {
    do {
        try await operations.submit()
    } catch {
        self.error = error
    }
    toggleRepaint()
}
```

### Validation Error Pattern

For forms, handle validation errors separately:

```swift
private func submit() async {
    let validations = validations
    do {
        try await operations.submit(data: viewModel.data)
    } catch let error as MyRequest.ResponseError {
        if !error.validationResults.isEmpty {
            validations.replace(with: error.validationResults)
        } else {
            self.error = error
        }
    } catch {
        self.error = error
    }
    toggleRepaint()
}
```

### Async Task Pattern

```swift
var body: some View {
    VStack {
        if isLoading {
            ProgressView()
        } else {
            contentView
        }
    }
    .task(errorBinding: $error) {
        try await loadData()
    }
}

private func loadData() async throws {
    isLoading = true
    try await operations.loadData()
    isLoading = false
    toggleRepaint()
}
```

### Conditional Rendering Pattern

Use ViewModel state for conditionals:

```swift
var body: some View {
    VStack {
        if viewModel.isEmpty {
            Text(viewModel.emptyStateMessage)
        } else {
            ForEach(viewModel.items) { item in
                ItemRow(item: item)
            }
        }
    }
}
```

### Computed View Components Pattern

Extract reusable view fragments as computed properties:

```swift
private var headerView: some View {
    HStack {
        Text(viewModel.title)
        Spacer()
        Image(systemName: viewModel.iconName)
    }
}

var body: some View {
    VStack {
        headerView
        contentView
    }
}
```

### Result/Error Handling Pattern

When a view needs to render multiple possible ViewModels (success, various error types), use an enum wrapper:

**The Wrapper ViewModel:**
```swift
@ViewModel
public struct TaskResultViewModel {
    public enum Result {
        case success(TaskViewModel)
        case notFound(NotFoundViewModel)
        case validationError(ValidationErrorViewModel)
        case permissionDenied(PermissionDeniedViewModel)
    }

    public let result: Result
    public var vmId: ViewModelId = .init(type: Self.self)

    public init(result: Result) {
        self.result = result
    }
}
```

**The View:**
```swift
public struct TaskResultView: ViewModelView {
    private let viewModel: TaskResultViewModel

    public var body: some View {
        switch viewModel.result {
        case .success(let vm):
            TaskView(viewModel: vm)
        case .notFound(let vm):
            NotFoundView(viewModel: vm)
        case .validationError(let vm):
            ValidationErrorView(viewModel: vm)
        case .permissionDenied(let vm):
            PermissionDeniedView(viewModel: vm)
        }
    }

    public init(viewModel: TaskResultViewModel) {
        self.viewModel = viewModel
    }
}
```

**Key principles:**
- Each error scenario has its own ViewModel type
- The wrapper enum associates specific ViewModels with each case
- The view switches on the enum and renders the appropriate child view
- Maintains type safety (no `any ViewModel` existentials)
- No generic error handling - each error type is specific and meaningful

### ViewModelId Initialization - CRITICAL

**IMPORTANT:** `ViewModelId` controls SwiftUI's view identity system via the `.id(vmId)` modifier. Incorrect initialization causes SwiftUI to treat different data as the same view, breaking updates.

**❌ WRONG - Never use this:**
```swift
public var vmId: ViewModelId = .init()  // NO! Generic identity
```

**✅ MINIMUM - Use type-based identity:**
```swift
public var vmId: ViewModelId = .init(type: Self.self)
```
This ensures views of the same type get unique identities.

**✅ IDEAL - Use data-based identity when available:**
```swift
public struct TaskViewModel {
    public let id: ModelIdType
    public var vmId: ViewModelId

    public init(id: ModelIdType, /* other params */) {
        self.id = id
        self.vmId = .init(id: id)  // Ties view identity to data identity
        // ...
    }
}
```

**Why this matters:**
- SwiftUI uses `.id()` modifier to determine when to recreate vs update views
- `vmId` provides this identity for ViewModelViews
- Wrong identity = views don't update when data changes
- Data-based identity (`.init(id:)`) is best because it ties view lifecycle to data lifecycle

## File Organization

```
Sources/{ViewsTarget}/
├── {Feature}/
│   ├── {Feature}View.swift             # Full page → {Feature}ViewModel
│   ├── {Entity}CardView.swift          # Child component → {Entity}CardViewModel
│   ├── {Entity}RowView.swift           # Child component → {Entity}RowViewModel
│   └── {Modal}View.swift               # Modal → {Modal}ViewModel
├── Shared/
│   ├── HeaderView.swift                # Shared components
│   └── FooterView.swift
└── Styles/
    └── ButtonStyles.swift              # Reusable button styles
```

---

## Common Mistakes

### Computing Data in Views

```swift
// ❌ BAD - View is transforming data
var body: some View {
    Text("\(viewModel.firstName) \(viewModel.lastName)")
}

// ✅ GOOD - ViewModel provides shaped result
var body: some View {
    Text(viewModel.fullName)  // via @LocalizedCompoundString
}
```

### Forgetting to Call toggleRepaint()

```swift
// ❌ BAD - Test infrastructure won't work
private func submit() {
    operations.submit()
    // Missing toggleRepaint()!
}

// ✅ GOOD - Always call after operations
private func submit() {
    operations.submit()
    toggleRepaint()
}
```

### Using Computed Properties for Display

```swift
// ❌ BAD - View is computing
var body: some View {
    if !viewModel.items.isEmpty {
        Text("You have \(viewModel.items.count) items")
    }
}

// ✅ GOOD - ViewModel provides the state
var body: some View {
    if viewModel.hasItems {
        Text(viewModel.itemCountMessage)
    }
}
```

### Hardcoding Text

```swift
// ❌ BAD - Not localizable
Button(action: submit) {
    Text("Submit")
}

// ✅ GOOD - ViewModel provides localized text
Button(action: submit) {
    Text(viewModel.submitButtonLabel)
}
```

### Missing Error Binding

```swift
// ❌ BAD - Errors not handled
Button(action: submit) {
    Text(viewModel.submitLabel)
}

// ✅ GOOD - Error binding for async actions
Button(errorBinding: $error, asyncAction: submit) {
    Text(viewModel.submitLabel)
}
```

### Storing Operations in Body Instead of Init

```swift
// ❌ BAD - Recomputed on every render
public var body: some View {
    let operations = viewModel.operations
    Button(action: { operations.submit() }) {
        Text(viewModel.submitLabel)
    }
}

// ✅ GOOD - Store in init
private let operations: any MyOperations

public init(viewModel: MyViewModel) {
    self.viewModel = viewModel
    self.operations = viewModel.operations
}
```

### Mismatched Filenames

```
// ❌ BAD - Filename doesn't match ViewModel
ViewModel: TaskListViewModel
View:      TasksView.swift

// ✅ GOOD - Aligned names
ViewModel: TaskListViewModel
View:      TaskListView.swift
```

### Incorrect ViewModelId Initialization

```swift
// ❌ BAD - Generic identity, views won't update correctly
public var vmId: ViewModelId = .init()

// ✅ MINIMUM - Type-based identity
public var vmId: ViewModelId = .init(type: Self.self)

// ✅ IDEAL - Data-based identity (when id available)
public init(id: ModelIdType) {
    self.id = id
    self.vmId = .init(id: id)
}
```

### Force-Unwrapping Localizable Strings

```swift
// ❌ BAD - Force-unwrapping to work around missing overload
import SwiftUI

Text(try! viewModel.title.localizedString)  // Anti-pattern - don't do this!
Label(try! viewModel.label.localizedString, systemImage: "star")

// ✅ GOOD - Request the proper SwiftUI overload instead
// The correct solution is to add an init extension like this:
extension Text {
    public init(_ localizable: Localizable) {
        self.init(localizable.localized)
    }
}

extension Label where Title == Text, Icon == Image {
    public init(_ title: Localizable, systemImage: String) {
        self.init(title.localized, systemImage: systemImage)
    }
}

// Then views use it cleanly without force-unwraps:
Text(viewModel.title)
Label(viewModel.label, systemImage: "star")
```

**Why this matters:**

FOSMVVM provides the `Localizable` protocol for all localized strings and includes SwiftUI init overloads for common elements like `Text`. However, not every SwiftUI element has a `Localizable` overload yet.

**When you encounter a SwiftUI element that doesn't accept `Localizable` directly:**

1. **DON'T** work around it with `try! localizable.localizedString` - this bypasses the type system and spreads force-unwrap calls throughout the view code
2. **DO** request that we add the proper init overload to FOSUtilities for that SwiftUI element
3. **The pattern is simple:** Extensions that accept `Localizable` and pass `.localized` to the standard initializer

This approach keeps the codebase clean, type-safe, and eliminates force-unwraps from view code entirely.

---

## File Templates

See [reference.md](reference.md) for complete file templates.

## Naming Conventions

| Concept | Convention | Example |
|---------|------------|---------|
| View struct | `{Name}View` | `TaskListView`, `SignInView` |
| ViewModel property | `viewModel` | Always `viewModel` |
| Operations property | `operations` | Always `operations` |
| Error state | `error` | Always `error` |
| Repaint toggle | `repaintToggle` | Always `repaintToggle` |

## Common Modifiers

### FOSMVVM-Specific Modifiers

```swift
// Error alert with ViewModel strings
.alert(
    errorBinding: $error,
    title: viewModel.errorTitle,
    message: viewModel.errorMessage,
    dismissButtonLabel: viewModel.dismissButtonLabel
)

// Async task with error handling
.task(errorBinding: $error) {
    try await loadData()
}

// Async submit handler
.onAsyncSubmit {
    await submit()
}

// Test data transporter (DEBUG only)
.testDataTransporter(viewModelOps: operations, repaintToggle: $repaintToggle)

// UI testing identifier
.uiTestingIdentifier("submitButton")
```

### Standard SwiftUI Modifiers

Apply standard modifiers as needed for layout, styling, etc.

## How to Use This Skill

**Invocation:**
```bash
/fosmvvm-swiftui-view-generator
```

**Prerequisites:**
- ViewModel and its structure are understood from conversation
- Optionally, specification files have been read into context
- View requirements (display-only, interactive, form, container) are clear from discussion

**Output:**
- `{ViewName}View.swift` - SwiftUI view conforming to ViewModelView protocol

**Workflow integration:**
This skill is typically used after discussing requirements or reading specification files. The skill references that context automatically—no file paths or Q&A needed.

## See Also

- [Architecture Patterns](../shared/architecture-patterns.md) - Mental models and patterns
- [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md) - Full FOSMVVM architecture
- [fosmvvm-viewmodel-generator](../fosmvvm-viewmodel-generator/SKILL.md) - For creating ViewModels
- [fosmvvm-ui-tests-generator](../fosmvvm-ui-tests-generator/SKILL.md) - For creating UI tests
- [reference.md](reference.md) - Complete file templates

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-23 | Initial skill for SwiftUI view generation |
| 1.1 | 2026-05-03 | Operations section rewrite to align with `ConversationPractice/docs/architecture.md`: surface the framework/app-side seam (`<Name>Operations.swift` / `<Name>StubOps.swift` / `<Name>Ops.swift` file convention), distinguish `FOSMVVM.ViewModelOperations` from per-feature protocols, note App Intents/transport actions share the same protocol, document `toggleRepaint()` motivation, clarify async vs sync op shape, promote display-only-no-Operations decision to a top-level rule. Clarify the storage-vs-method-signature distinction: `any` is acceptable at single-value View storage (Swift 5.7+ implicit existential opening preserves generic specialization at call sites); generics are required at protocol method signatures. All View examples updated to `private let operations: any <Name>ViewModelOperations`. |
