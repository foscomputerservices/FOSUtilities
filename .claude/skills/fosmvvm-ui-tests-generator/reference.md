# FOSMVVM UI Tests Generator - Reference Templates

Complete file templates for generating UI tests for FOSMVVM ViewModelViews.

> **Conceptual context:** See [SKILL.md](SKILL.md) for when and why to use this skill.
> **Architecture context:** See [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md) for full FOSMVVM understanding.

## Placeholders

| Placeholder | Replace With | Example |
|-------------|--------------|---------|
| `{ProjectName}` | Your project/app name | `MyApp`, `TaskManager` |
| `{ViewName}` | ViewModelView name (without "View" suffix) | `TaskList`, `Dashboard` |
| `{ViewModel}` | Full ViewModel type name | `TaskListViewModel` |
| `{Operations}` | Full ViewModelOperations type name | `TaskListViewModelOperations` |
| `{Feature}` | Feature/module grouping | `Tasks`, `Settings` |
| `{BundleId}` | App bundle identifier | `com.example.MyApp` |

---

# Template 1: Base Test Case Class

**One per project** - All UI tests inherit from this.

**Location:** `Tests/UITests/Support/{ProjectName}ViewModelViewTestCase.swift`

```swift
// {ProjectName}ViewModelViewTestCase.swift
//
// Copyright (c) 2026 Your Organization. All rights reserved.
// License: Your License

import FOSFoundation
import FOSMVVM
import FOSTestingUI
import Foundation
import XCTest

class {ProjectName}ViewModelViewTestCase<VM: ViewModel, VMO: ViewModelOperations>:
    ViewModelViewTestCase<VM, VMO>, @unchecked Sendable {

    @MainActor func presentView(
        configuration: TestConfiguration,
        viewModel: VM = .stub(),
        timeout: TimeInterval = 10
    ) throws -> XCUIApplication {
        try presentView(
            testConfiguration: configuration.toJSON(),
            viewModel: viewModel,
            timeout: timeout
        )
    }

    override func setUp() async throws {
        try await super.setUp(
            bundle: Bundle.main,
            resourceDirectoryName: "",
            appBundleIdentifier: "{BundleId}"
        )

        continueAfterFailure = false // Stop the test and move on
    }
}
```

---


# ViewModelOperations: When to Use

Not all views need ViewModelOperations. The decision depends on whether the view has user interactions that trigger business logic.

**Views that NEED operations:**
- Forms with submit/cancel actions
- Views that call business logic or APIs
- Interactive views that trigger app state changes
- Views with user-initiated async operations

**Views that DON'T NEED operations:**
- Display-only cards or detail views
- Static content views
- Pure navigation containers
- Server-hosted views that just render data

**For views without operations**, no scaffolding exists — no protocol, no stub class, no `ViewModelOperations` subtype. Tests subclass `ViewModelDisplayTestCase<VM>` (via your project-level display base class), which takes no Operations generic parameter. See **Template 2: Display-Only View Test** below for the test structure.

---

# Template 2: Display-Only View Test (No Operations)

**For views that don't have ViewModelOperations** - Display-only, no user interactions.

**Location:** `Tests/UITests/Views/{Feature}/{ViewName}UITests.swift`

```swift
// {ViewName}UITests.swift
//
// Copyright (c) 2026 Your Organization. All rights reserved.
// License: Your License

import FOSFoundation
import FOSMVVM
import FOSTestingUI
import Foundation
import ViewModels
import XCTest

final class {ViewName}UITests: {ProjectName}ViewModelDisplayTestCase<
    {ViewModel}
>, @unchecked Sendable {
    // MARK: UI Tests

    func testDisplaysTitle() async throws {
        let app = try presentView(
            viewModel: .stub(title: "Test Title")
        )

        XCTAssertTrue(app.uiTestingElement("titleLabel").exists)
    }

    func testDisplaysContent() async throws {
        let app = try presentView(
            viewModel: .stub(content: "Test Content")
        )

        XCTAssertTrue(app.uiTestingElement("contentText").exists)
    }

    func testDisplaysImage() async throws {
        let app = try presentView()

        XCTAssertTrue(app.uiTestingElement("mainImage").exists)
    }

    // MARK: Setup

    override func setUp() async throws {
        try await super.setUp()

        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        #endif
    }
}

```

---

# Template 3: Basic UI Test File (With Operations)

**One per ViewModelView** - Tests for a simple interactive view.

**Location:** `Tests/UITests/Views/{Feature}/{ViewName}UITests.swift`

```swift
// {ViewName}UITests.swift
//
// Copyright (c) 2026 Your Organization. All rights reserved.
// License: Your License

import FOSFoundation
import FOSMVVM
import FOSTestingUI
import Foundation
import ViewModels
import XCTest

final class {ViewName}UITests: {ProjectName}ViewModelViewTestCase<
    {ViewModel},
    {Operations}
>, @unchecked Sendable {
    // MARK: UI Tests

    func testInitialState() async throws {
        let app = try presentView()

        XCTAssertTrue(app.uiTestingElement("mainContent").exists)
    }

    func testButtonEnabled() async throws {
        let app = try presentView(
            viewModel: .stub(enabled: true)
        )

        XCTAssertTrue(app.uiTestingElement("actionButton").isEnabled)
    }

    func testButtonDisabled() async throws {
        let app = try presentView(
            viewModel: .stub(enabled: false)
        )

        XCTAssertFalse(app.uiTestingElement("actionButton").isEnabled)
    }

    // MARK: Operation Tests

    func testActionButton() async throws {
        let app = try presentView(
            configuration: .default
        )

        app.uiTestingElement("actionButton").tap()

        let stubOps = try viewModelOperations()
        XCTAssertTrue(stubOps.actionCalled)
    }

    // MARK: Setup

    override func setUp() async throws {
        try await super.setUp()

        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        #endif
    }
}

```

---

# Template 4: Advanced UI Test File (With Operations)

**For views with multiple interactions** - Comprehensive test coverage.

**Location:** `Tests/UITests/Views/{Feature}/{ViewName}UITests.swift`

```swift
// {ViewName}UITests.swift
//
// Copyright (c) 2026 Your Organization. All rights reserved.
// License: Your License

import FOSFoundation
import FOSMVVM
import FOSTestingUI
import Foundation
import ViewModels
import XCTest

final class {ViewName}UITests: {ProjectName}ViewModelViewTestCase<
    {ViewModel},
    {Operations}
>, @unchecked Sendable {
    // MARK: UI State Tests

    func testEmptyState() async throws {
        let app = try presentView(
            viewModel: .stub(items: [])
        )

        XCTAssertTrue(app.uiTestingElement("emptyStateMessage").exists)
        XCTAssertFalse(app.uiTestingElement("itemList").exists)
    }

    func testItemsDisplayed() async throws {
        let app = try presentView(
            viewModel: .stub(
                items: [
                    .stub(id: .init(), title: "Item 1"),
                    .stub(id: .init(), title: "Item 2")
                ]
            )
        )

        XCTAssertFalse(app.uiTestingElement("emptyStateMessage").exists)
        XCTAssertTrue(app.uiTestingElement("itemList").exists)
    }

    func testLoadingState() async throws {
        let app = try presentView(
            viewModel: .stub(isLoading: true)
        )

        XCTAssertTrue(app.uiTestingElement("loadingIndicator").exists)
    }

    // MARK: Interaction Tests

    func testSelectItem() async throws {
        let app = try presentView()

        XCTAssertFalse(app.uiTestingElement("detailButton").isEnabled)

        app.uiTestingElement("itemButton").tap()

        XCTAssertTrue(app.uiTestingElement("detailButton").isEnabled)
    }

    func testFormInput() async throws {
        let app = try presentView()

        app.uiTestingElement("nameTextField").type("Test Name")

        app.uiTestingElement("emailTextField").type("test@example.com")

        app.uiTestingElement("submitButton").tap()

        let stubOps = try viewModelOperations()
        XCTAssertTrue(stubOps.submitCalled)
    }

    // MARK: Operation Tests

    func testRefresh() async throws {
        let app = try presentView(
            configuration: .requireAuth()
        )

        app.uiTestingElement("refreshButton").tap()

        let stubOps = try viewModelOperations()
        XCTAssertTrue(stubOps.refreshCalled)
    }

    func testDelete() async throws {
        let app = try presentView(
            configuration: .requireAuth()
        )

        app.uiTestingElement("itemButton").tap()
        app.uiTestingElement("deleteButton").tap()

        let stubOps = try viewModelOperations()
        XCTAssertTrue(stubOps.deleteCalled)
        XCTAssertFalse(stubOps.submitCalled)
    }

    func testCancel() async throws {
        let app = try presentView()

        app.uiTestingElement("cancelButton").tap()

        let stubOps = try viewModelOperations()
        XCTAssertTrue(stubOps.cancelCalled)
    }

    // MARK: Navigation Tests

    func testNavigationToDetail() async throws {
        let app = try presentView()

        app.uiTestingElement("itemButton").tap()
        app.uiTestingElement("viewDetailButton").tap()

        XCTAssertTrue(app.uiTestingElement("detailView").exists)
    }

    // MARK: Error Handling Tests

    func testErrorDisplayed() async throws {
        let app = try presentView(
            viewModel: .stub(hasError: true)
        )

        XCTAssertTrue(app.alerts["errorAlert"].exists)
    }

    func testErrorDismissal() async throws {
        let app = try presentView(
            viewModel: .stub(hasError: true)
        )

        app.uiTestingElement("dismissErrorButton").tap()

        XCTAssertFalse(app.alerts["errorAlert"].exists)
    }

    // MARK: Setup

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUp() async throws {
        try await super.setUp()

        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        #endif
    }
}

```

---

# Template 5: Display-Only View (No Operations)

**For views that only display data** - No user interactions, no operations.

**Location:** `Sources/{ViewsTarget}/{Feature}/{ViewName}View.swift`

```swift
// {ViewName}View.swift
//
// Copyright (c) 2026 Your Organization. All rights reserved.
// License: Your License

import FOSFoundation
import FOSMVVM
import Foundation
import SwiftUI
import ViewModels

public struct {ViewName}View: ViewModelView {
    private let viewModel: {ViewModel}

    public var body: some View {
        VStack {
            Text(viewModel.title)
                .font(.headline)
                .uiTestingIdentifier("titleLabel")

            Text(viewModel.description)
                .uiTestingIdentifier("descriptionText")

            if let imageURL = viewModel.imageURL {
                AsyncImage(url: imageURL)
                    .uiTestingIdentifier("mainImage")
            }
        }
        .padding()
    }

    public init(viewModel: {ViewModel}) {
        self.viewModel = viewModel
    }
}

#if DEBUG
#Preview {
    {ViewName}View.previewHost(
        bundle: MyAppResourceAccess.localizationBundle
    )
}
#endif
```

---

# Template 6: View with Test Infrastructure (With Operations)

**The view being tested** - Includes test support for operations.

**Location:** `Sources/{ViewsTarget}/{Feature}/{ViewName}View.swift`

```swift
// {ViewName}View.swift
//
// Copyright (c) 2026 Your Organization. All rights reserved.
// License: Your License

import FOSFoundation
import FOSMVVM
import Foundation
import SwiftUI
import ViewModels

public struct {ViewName}View: ViewModelView {
    #if DEBUG
    @State private var repaintToggle = false
    #endif

    private let viewModel: {ViewModel}
    private let operations: {Operations}

    public var body: some View {
        VStack {
            Text(viewModel.title)
                .font(.headline)

            Button(action: performAction) {
                Text(viewModel.actionButtonLabel)
            }
            .uiTestingIdentifier("actionButton")

            Button(role: .cancel, action: cancel) {
                Text(viewModel.cancelButtonLabel)
            }
            .uiTestingIdentifier("cancelButton")
        }
        #if DEBUG
        .testDataTransporter(viewModelOps: operations, repaintToggle: $repaintToggle)
        #endif
    }

    public init(viewModel: {ViewModel}) {
        self.viewModel = viewModel
        self.operations = viewModel.operations
    }
}

private extension {ViewName}View {
    func performAction() {
        operations.performAction()
        toggleRepaint()
    }

    func cancel() {
        operations.cancel()
        toggleRepaint()
    }

    func toggleRepaint() {
        #if DEBUG
        repaintToggle.toggle()
        #endif
    }
}

#if DEBUG
#Preview {
    {ViewName}View.previewHost(
        bundle: MyAppResourceAccess.localizationBundle
    )
}
#endif
```

---

# Template 7: View with Async Operations

**For views with async operations** - Includes error handling.

**Location:** `Sources/{ViewsTarget}/{Feature}/{ViewName}View.swift`

```swift
// {ViewName}View.swift
//
// Copyright (c) 2026 Your Organization. All rights reserved.
// License: Your License

import FOSFoundation
import FOSMVVM
import Foundation
import SwiftUI
import ViewModels

public struct {ViewName}View: ViewModelView {
    @State private var error: Error?
    @State private var isLoading = false

    #if DEBUG
    @State private var repaintToggle = false
    #endif

    private let viewModel: {ViewModel}
    private let operations: {Operations}

    public var body: some View {
        VStack {
            if isLoading {
                ProgressView()
                    .uiTestingIdentifier("loadingIndicator")
            } else {
                contentView
            }
        }
        .task(errorBinding: $error) {
            try await loadData()
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

    private var contentView: some View {
        VStack {
            Text(viewModel.title)

            Button(errorBinding: $error, asyncAction: submit) {
                Text(viewModel.submitButtonLabel)
            }
            .uiTestingIdentifier("submitButton")
        }
    }

    public init(viewModel: {ViewModel}) {
        self.viewModel = viewModel
        self.operations = viewModel.operations
    }
}

private extension {ViewName}View {
    func loadData() async throws {
        isLoading = true
        try await operations.loadData()
        isLoading = false
        toggleRepaint()
    }

    @Sendable func submit() async throws {
        try await operations.submit()
        toggleRepaint()
    }

    func toggleRepaint() {
        #if DEBUG
        repaintToggle.toggle()
        #endif
    }
}

#if DEBUG
#Preview {
    {ViewName}View.previewHost(
        bundle: MyAppResourceAccess.localizationBundle
    )
}
#endif
```

---

# Template 8: View with Form and List

**Complex view example** - Form input and list display.

**Location:** `Sources/{ViewsTarget}/{Feature}/{ViewName}View.swift`

```swift
// {ViewName}View.swift
//
// Copyright (c) 2026 Your Organization. All rights reserved.
// License: Your License

import FOSFoundation
import FOSMVVM
import Foundation
import SwiftUI
import ViewModels

public struct {ViewName}View: ViewModelView {
    @State private var items: [ItemViewModel] = []
    @State private var selectedId: ModelIdType?
    @State private var error: Error?

    #if DEBUG
    @State private var repaintToggle = false
    #endif

    private let viewModel: {ViewModel}
    private let operations: {Operations}

    public var body: some View {
        VStack {
            Text(viewModel.title)
                .font(.headline)

            if items.isEmpty {
                Text(viewModel.emptyStateMessage)
                    .uiTestingIdentifier("emptyStateMessage")
            } else {
                ScrollView {
                    VStack {
                        ForEach(items) { item in
                            Button { selectItem(item.id) } label: {
                                HStack {
                                    Text(item.title)
                                    if item.id == selectedId {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            .uiTestingIdentifier("itemButton")
                        }
                    }
                }
                .uiTestingIdentifier("itemList")
            }

            Spacer()

            HStack {
                Button(role: .cancel, action: cancel) {
                    Text(viewModel.cancelButtonLabel)
                }
                .uiTestingIdentifier("cancelButton")

                Spacer()

                Button(errorBinding: $error, asyncAction: submit) {
                    Text(viewModel.submitButtonLabel)
                }
                .buttonStyle(PrimaryButtonStyle())
                .uiTestingIdentifier("submitButton")
                .disabled(selectedId == nil)
            }
        }
        .task(errorBinding: $error) {
            try await loadItems()
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

    public init(viewModel: {ViewModel}) {
        self.viewModel = viewModel
        self.operations = viewModel.operations
    }
}

private extension {ViewName}View {
    func loadItems() async throws {
        let stream = operations.loadItems()
        toggleRepaint()

        for try await item in stream {
            items.append(item)
        }
    }

    func selectItem(_ id: ModelIdType) {
        if selectedId == id {
            selectedId = nil
        } else {
            selectedId = id
        }
        toggleRepaint()
    }

    @Sendable func submit() async throws {
        guard let selectedId else { return }
        try await operations.submit(itemId: selectedId)
        toggleRepaint()
    }

    func cancel() {
        operations.cancel()
        toggleRepaint()
    }

    func toggleRepaint() {
        #if DEBUG
        repaintToggle.toggle()
        #endif
    }
}

#if DEBUG
#Preview {
    {ViewName}View.previewHost(
        bundle: MyAppResourceAccess.localizationBundle
    )
}
#endif
```

---

# Template 9: ViewModelOperations File (Reference Shape)

**The Operations file is generated by [fosmvvm-viewmodel-generator](../fosmvvm-viewmodel-generator/SKILL.md)**, not by this skill. It exists only for interactive ViewModels — display-only ViewModels have no Operations file. The template below is shown here for reference so tests can see the shape of the `StubOps` they will instantiate via `viewModelOperations()`.

For the canonical templates with full rationale, see:
- [fosmvvm-viewmodel-generator — Template 10: Interactive Server-Hosted ViewModel](../fosmvvm-viewmodel-generator/reference.md)
- [fosmvvm-viewmodel-generator — Template 11: Interactive Client-Hosted ViewModel](../fosmvvm-viewmodel-generator/reference.md)

The Operations protocol takes one of two shapes, matching the hosting mode:

**Client-hosted ops** — mutate `@Observable` storage. Each mutating method takes scalar inputs first and the write target last, labeled `output`. Sync by default. The stub records that the op fired **and mirrors the mutation** so projection fires under test:

```swift
public protocol {ViewName}ViewModelOperations: ViewModelOperations {
    func {action}(_ {input}: {InputType}, output storage: {StorageType})
}

public struct {ViewName}Ops: {ViewName}ViewModelOperations {
    public init() {}

    public func {action}(_ {input}: {InputType}, output storage: {StorageType}) {
        storage.{property} = {input}
    }
}

public final class {ViewName}StubOps: {ViewName}ViewModelOperations, @unchecked Sendable {
    public private(set) var {action}Called: Bool = false

    public init() {}

    public func {action}(_ {input}: {InputType}, output storage: {StorageType}) {
        {action}Called = true
        storage.{property} = {input}
    }
}
```

Tests assert "was it called?" via `stubOps.{action}Called`; "with what value?" by reading `storage.{property}` directly — the storage itself holds the `CalledWith` equivalent, so no separate accessor is needed.

**Server-backed ops** — dispatch a `ServerRequest`; no `output:` parameter (server owns storage). `async throws` matches the network call. The stub exposes both `Called` and `CalledWith` accessors because there is no local storage for tests to observe:

```swift
public protocol {ViewName}ViewModelOperations: ViewModelOperations {
    func {action}({scalarInputs}) async throws
}

public struct {ViewName}Ops: {ViewName}ViewModelOperations {
    public init() {}

    public func {action}({scalarInputs}) async throws {
        // Dispatches a ServerRequest.
    }
}

public final class {ViewName}StubOps: {ViewName}ViewModelOperations, @unchecked Sendable {
    public var {action}Called: Bool { {action}CalledWith != nil }
    public private(set) var {action}CalledWith: {InputType}?

    public init() {}

    public func {action}({scalarInputs}) async throws {
        {action}CalledWith = {input}
    }
}
```

**Rules that must hold on both shapes** (see [Architecture Patterns → Ops Conventions](../shared/architecture-patterns.md)):
- `async` only when the body genuinely awaits. Sync state mutations should be sync; gratuitous async introduces out-of-order Task completion on rapid interactions.
- Never fail silently. No `try?`, no empty `catch {}`. Surface errors to observable state.
- Every stub exposes a `{action}Called: Bool` accessor so UI tests can assert the operation fired. Client-hosted stubs also mirror the live mutation on `storage`, keeping the projection loop intact under test; server-backed stubs cannot (no server in test env) and expose a `{action}CalledWith` accessor instead.

### Note for display-only ViewModels

There is no "empty Operations file" template. Display-only ViewModels have no Operations file at all. Their tests subclass `ViewModelDisplayTestCase<VM>` via the project's display-only base class — see **Template 2: Display-Only View Test** above.

---

# Quick Reference

## Test Infrastructure Checklist

**All Views:**
- [ ] `.uiTestingIdentifier()` on ALL elements you want to test

**Views WITH Operations (interactive views):**
- [ ] `#if DEBUG` block with `@State private var repaintToggle = false`
- [ ] `.testDataTransporter(viewModelOps:repaintToggle:)` modifier on body
- [ ] `operations` property stored from `viewModel.operations`
- [ ] `toggleRepaint()` helper function
- [ ] `toggleRepaint()` called after EVERY operation invocation

**Views WITHOUT Operations (display-only):**
- [ ] No `repaintToggle` needed
- [ ] No `.testDataTransporter()` needed
- [ ] No `operations` property needed
- [ ] No `toggleRepaint()` needed

## UI Testing Identifier Conventions

The identifier is the entire contract. A test never names an XCUITest element type, because
there is one accessor for every kind of view:

```swift
app.uiTestingElement("submitButton")
```

Name an identifier for the **role the view plays**, never for the control that renders it —
`submitButton`, `emailTextField`, `errorMessage`, `loadingIndicator`, `itemList`,
`mainContent`. A name that encodes the control has to change when the control does, which is
exactly the coupling the tag removes.

## Common Patterns

```swift
// Wait for a view to appear
XCTAssertTrue(app.uiTestingElement("savedBanner").waitForExistence())

// Wait for a view to go away — not `exists`, which answers before it has
XCTAssertTrue(app.uiTestingElement("errorBanner").waitForDisappearance())

// A view that was never there at all — no wait
XCTAssertFalse(app.uiTestingElement("errorBanner").exists)

// In the hierarchy vs. on screen
XCTAssertTrue(app.uiTestingElement("itemList").exists)
XCTAssertTrue(app.uiTestingElement("itemList").isVisible)

// Enabled state
XCTAssertFalse(app.uiTestingElement("submitButton").isEnabled)

// Displayed text — against the localized ViewModel, never a literal
XCTAssertEqual(app.uiTestingElement("titleLabel").label, viewModel.title)

// Field contents
app.uiTestingElement("emailTextField").type("test@example.com")
XCTAssertEqual(app.uiTestingElement("emailTextField").value, "test@example.com")

// A tag repeated by a ForEach resolves to the first match
app.uiTestingElement("itemButton").tap()

// A Picker's options are taggable, and that is how a selection is asserted
Picker(viewModel.programLabel, selection: $selection) {
    Text(viewModel.optionA).uiTestingIdentifier("optionA").tag(0)
    Text(viewModel.optionB).uiTestingIdentifier("optionB").tag(1)
}
.uiTestingIdentifier("programPicker")

app.uiTestingElement("programPicker").tap()   // opens the menu
app.uiTestingElement("optionB").tap()         // selects the option

// A system-presented alert is not a tagged view — query it directly
XCTAssertTrue(app.alerts["errorAlert"].exists)

// Anything this doesn't cover — the escape hatch
app.uiTestingElement("photo").xcuiElement.press(forDuration: 1.0)
```

## Operation Verification Pattern

```swift
func testSomeOperation() async throws {
    let app = try presentView(configuration: .default)

    // Perform UI interaction
    app.uiTestingElement("actionButton").tap()

    // Verify operation was called
    let stubOps = try viewModelOperations()
    XCTAssertTrue(stubOps.actionCalled)
    XCTAssertFalse(stubOps.otherActionCalled)
}
```

## Test Configuration Pattern

```swift
// Basic presentation
let app = try presentView()

// With custom ViewModel
let app = try presentView(
    viewModel: .stub(enabled: false, items: [])
)

// With test configuration
let app = try presentView(
    configuration: .requireAuth(userId: "123")
)

// Both ViewModel and configuration
let app = try presentView(
    configuration: .requireDevice(),
    viewModel: .stub(connected: true)
)
```

---

# Checklists

## Base Setup (Once Per Project):
- [ ] Base test case class created
- [ ] App bundle identifier configured
- [ ] Test target created in Xcode

## Per View Test:
- [ ] Test file created with correct generic parameters
- [ ] UI state tests added
- [ ] Operation tests added
- [ ] setUp() method configured if needed
- [ ] Every element the test touches is tagged with `.uiTestingIdentifier()` and found with `app.uiTestingElement()`

## View Preparation:
- [ ] `@State private var repaintToggle` property
- [ ] `.testDataTransporter()` modifier
- [ ] `operations` stored from `viewModel.operations`
- [ ] `toggleRepaint()` helper function
- [ ] `toggleRepaint()` called after operations
- [ ] All interactive elements have `.uiTestingIdentifier()`

---

# Common Patterns

## Pattern 1: Testing Button States

```swift
func testButtonDisabledInitially() async throws {
    let app = try presentView()
    XCTAssertFalse(app.uiTestingElement("submitButton").isEnabled)
}

func testButtonEnabledAfterInput() async throws {
    let app = try presentView()

    app.uiTestingElement("nameField").type("Test")

    XCTAssertTrue(app.uiTestingElement("submitButton").isEnabled)
}
```

## Pattern 2: Testing Async Operations

```swift
func testLoadData() async throws {
    let app = try presentView()

    // Wait for loading to complete
    XCTAssertTrue(app.waitForExistence(timeout: 3))

    let stubOps = try viewModelOperations()
    XCTAssertTrue(stubOps.loadDataCalled)
}
```

## Pattern 3: Testing Error States

```swift
func testErrorHandling() async throws {
    let app = try presentView(
        viewModel: .stub(hasError: true)
    )

    XCTAssertTrue(app.alerts["errorAlert"].exists)
    app.uiTestingElement("dismissButton").tap()
    XCTAssertFalse(app.alerts["errorAlert"].exists)
}
```

## Pattern 4: Testing Navigation

```swift
func testNavigation() async throws {
    let app = try presentView()

    app.uiTestingElement("itemRow").tap()
    XCTAssertTrue(app.uiTestingElement("detailView").waitForExistence())

    app.uiTestingElement("backButton").tap()
    XCTAssertTrue(app.uiTestingElement("listView").waitForExistence())
}
```
