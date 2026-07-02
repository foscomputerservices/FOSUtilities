---
name: fosmvvm-ui-tests-generator
description: Generate UI tests for FOSMVVM SwiftUI views using XCTest and FOSTestingUI. Covers accessibility identifiers, ViewModelOperations, and test data transport.
homepage: https://github.com/foscomputerservices/FOSUtilities
metadata: {"clawdbot": {"emoji": "🖥️", "os": ["darwin"]}}
---

# FOSMVVM UI Tests Generator

Generate comprehensive UI tests for ViewModelViews in FOSMVVM applications.

## Conceptual Foundation

> For full architecture context, see [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md) | [OpenClaw reference]({baseDir}/references/FOSMVVMArchitecture.md)

UI testing in FOSMVVM follows a specific pattern that leverages:
- **FOSTestingUI** framework for test infrastructure
- **ViewModelOperations** for verifying business logic was invoked
- **Accessibility identifiers** for finding UI elements
- **Test data transporter** for passing operation stubs to the app

```
┌─────────────────────────────────────────────────────────────┐
│                    UI Test Architecture                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Test File (XCTest)                 App Under Test          │
│  ┌──────────────────┐              ┌──────────────────┐     │
│  │ MyViewUITests    │              │ MyView           │     │
│  │                  │              │                  │     │
│  │ presentView() ───┼─────────────►│ Show view with   │     │
│  │   with stub VM   │              │   stubbed data   │     │
│  │                  │              │                  │     │
│  │ Interact via ────┼─────────────►│ UI elements with │     │
│  │   identifiers    │              │   .uiTestingId   │     │
│  │                  │              │                  │     │
│  │ Assert on UI     │              │ .testData────────┼──┐  │
│  │   state          │              │   Transporter    │  │  │
│  │                  │              └──────────────────┘  │  │
│  │ viewModelOps() ◄─┼─────────────────────────────────────┘  │
│  │   verify calls   │              Stub Operations          │
│  └──────────────────┘                                        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Element Matching Rules

UI tests must follow a strict hierarchy for finding and matching elements. **Never use hardcoded display strings.**

### Tier 1: Accessibility Identifiers (Preferred)

Use `.uiTestingIdentifier()` on the view and match via `XCUIApplication` extension accessors:

> **`.uiTestingIdentifier(_:)` is a FOSMVVM `View` modifier — `import FOSMVVM`.** It ships
> in FOSMVVM (`SwiftUI Support/View+Testing.swift`); you do **not** define it yourself and
> you must **not** copy a private version into your app. It is **DEBUG-only** — in a
> release build it compiles to a no-op (`self`), so tagging carries **no** test scaffolding
> into shipping binaries. Because it self-gates, apply it **unconditionally** (do not wrap
> it in `#if DEBUG` — only `.testDataTransporter` needs that guard). Pair each identifier
> with an `XCUIApplication` accessor keyed on the **same** string.

```swift
// View  (import FOSMVVM)
Text(viewModel.title)
    .uiTestingIdentifier("dashboardTitle")

// Test — accessor uses identifier
private extension XCUIApplication {
    var dashboardTitle: XCUIElement {
        staticTexts.element(matching: .staticText, identifier: "dashboardTitle")
    }
}

// Test — usage
XCTAssertTrue(app.dashboardTitle.exists)
```

### Tier 2: Localized ViewModel Text (When Identifiers Are Insufficient)

When you must match by display text (e.g., verifying a label's content, or an element that can't carry a unique identifier), use `localizedViewModel()` to resolve the text from the same source of truth as the UI:

```swift
let viewModel: PrimaryParametersViewModel = try localizedViewModel()
let app = try presentView(viewModel: viewModel)

// Match against ViewModel's resolved localized text — never a hardcoded string
XCTAssertTrue(try app.staticTexts[viewModel.amplitudeLabel.localizedString].exists)
XCTAssertEqual(app.stepperValueText.label, try viewModel.value.localizedString)
```

This keeps tests locale-correct and refactor-safe — if the YAML translation changes, the test still passes because it reads from the same source of truth.

### Never Allowed: Hardcoded Display Strings

```swift
// ❌ WRONG — breaks on locale change, copy change, or duplicate text
XCTAssertTrue(app.staticTexts["Settings"].exists)
XCTAssertEqual(app.label.text, "Welcome back!")

// ✅ RIGHT — Tier 1: identifier
XCTAssertTrue(app.settingsLabel.exists)

// ✅ RIGHT — Tier 2: localized ViewModel
XCTAssertTrue(try app.staticTexts[viewModel.settingsLabel.localizedString].exists)
```

## Core Components

### 1. Base Test Case Classes

FOSTestingUI provides two parallel base classes that align with the two kinds of ViewModel. Pick the base class that matches the view under test — do not invent an empty Operations type to satisfy a generic parameter.

| Path | Base class | When to use |
|------|------------|-------------|
| **Display-only** | `ViewModelDisplayTestCase<VM>` | View has no user-initiated actions — no Operations file exists for this VM |
| **Interactive** | `ViewModelViewTestCase<VM, VMO>` | View dispatches to Operations — test verifies operation calls |

Every project should have a **pair** of project-level base classes — one for each path — that pin `setUp` for the app bundle. Both paths are needed because most apps have both kinds of views.

> **Version floor for `ViewModelDisplayTestCase<VM>`.** The single-generic display base
> class ships in recent FOSTestingUI — the release where `ViewModelViewTestCase<VM, VMO>`
> was refactored to **inherit from** `ViewModelDisplayTestCase<VM>`
> (`Sources/FOSTestingUI/ViewModelViewTestCase.swift`). **If your FOS ref predates it**
> (older refs expose only the two-generic `ViewModelViewTestCase<VM, VMO>`), the clean
> display-only path doesn't exist yet — fall back to subclassing the two-generic base with
> a file-scoped **no-op `ViewModelOperations`** for the `VMO` slot. On a current ref, use
> `ViewModelDisplayTestCase<VM>` directly and do **not** invent the empty ops type.

**Display-only base class:**

```swift
class MyAppViewModelDisplayTestCase<VM: ViewModel>:
    ViewModelDisplayTestCase<VM>, @unchecked Sendable {

    @MainActor func presentView(
        configuration: TestConfiguration,
        viewModel: VM = .stub(),
        timeout: TimeInterval = 3
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
            appBundleIdentifier: "com.example.MyApp"
        )

        continueAfterFailure = false
    }
}
```

**Interactive base class:**

```swift
class MyAppViewModelViewTestCase<VM: ViewModel, VMO: ViewModelOperations>:
    ViewModelViewTestCase<VM, VMO>, @unchecked Sendable {

    @MainActor func presentView(
        configuration: TestConfiguration,
        viewModel: VM = .stub(),
        timeout: TimeInterval = 3
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
            appBundleIdentifier: "com.example.MyApp"
        )

        continueAfterFailure = false
    }
}
```

**Key points:**
- Display-only base has **one** generic parameter — `VM`. No stub Operations type.
- Interactive base has **two** — `VM` and `VMO`. The `viewModelOperations()` helper is available only on this path.
- Both wrap FOSTestingUI's `presentView()` and pin the bundle / bundle identifier.
- `continueAfterFailure = false` stops tests immediately on failure.

### 2. Individual UI Test Files

Each ViewModelView gets a corresponding UI test file.

**For views WITH operations:**

```swift
final class MyViewUITests: MyAppViewModelViewTestCase<MyViewModel, MyViewOps> {
    // UI Tests - verify UI state
    func testButtonEnabled() async throws {
        let app = try presentView(viewModel: .stub(enabled: true))
        XCTAssertTrue(app.myButton.isEnabled)
    }

    // Operation Tests - verify operations were called
    func testButtonTap() async throws {
        let app = try presentView(configuration: .requireSomeState())
        app.myButton.tap()

        let stubOps = try viewModelOperations()
        XCTAssertTrue(stubOps.myOperationCalled)
    }
}

private extension XCUIApplication {
    var myButton: XCUIElement {
        buttons.element(matching: .button, identifier: "myButtonIdentifier")
    }
}
```

**For views WITHOUT operations** (display-only):

Subclass the display-only base — no stub Operations type needed:

```swift
final class MyViewUITests: MyAppViewModelDisplayTestCase<MyViewModel> {
    // UI Tests only - no operation verification
    func testDisplaysCorrectly() async throws {
        let app = try presentView(viewModel: .stub(title: "Test"))
        XCTAssertTrue(app.titleLabel.exists)
    }
}
```

Do not invent an empty `ViewModelOperations` protocol for display-only views. The display-only path was designed specifically to avoid this — `ViewModelDisplayTestCase<VM>` takes one generic parameter, and no Operations file should exist for display-only ViewModels.

**When to use each:**
- **With operations**: Interactive views that perform actions (forms, buttons that call APIs, toggles, etc.) — use `MyAppViewModelViewTestCase<VM, VMO>`.
- **Without operations**: Display-only views (cards, detail views, static content) — use `MyAppViewModelDisplayTestCase<VM>`.

### 3. XCUIElement Helper Extensions

Common helpers for interacting with UI elements:

```swift
extension XCUIElement {
    var text: String? {
        value as? String
    }

    func typeTextAndWait(_ string: String, timeout: TimeInterval = 2) {
        typeText(string)
        _ = wait(for: \.text, toEqual: string, timeout: timeout)
    }

    func tapMenu() {
        if isHittable {
            tap()
        } else {
            coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }
}
```

### 4. View Requirements

**For views WITH operations:**

```swift
public struct MyView: ViewModelView {
    #if DEBUG
    @State private var repaintToggle = false
    #endif

    private let viewModel: MyViewModel
    private let operations: MyViewModelOperations

    public var body: some View {
        Button(action: doSomething) {
            Text(viewModel.buttonLabel)
        }
        .uiTestingIdentifier("myButtonIdentifier")
        #if DEBUG
        .testDataTransporter(viewModelOps: operations, repaintToggle: $repaintToggle)
        #endif
    }

    public init(viewModel: MyViewModel) {
        self.viewModel = viewModel
        self.operations = viewModel.operations
    }

    private func doSomething() {
        operations.doSomething()
        toggleRepaint()
    }

    private func toggleRepaint() {
        #if DEBUG
        repaintToggle.toggle()
        #endif
    }
}
```

**For views WITHOUT operations** (display-only):

```swift
public struct MyView: ViewModelView {
    private let viewModel: MyViewModel

    public var body: some View {
        VStack {
            Text(viewModel.title)
            Text(viewModel.description)
        }
        .uiTestingIdentifier("mainContent")
    }

    public init(viewModel: MyViewModel) {
        self.viewModel = viewModel
    }
}
```

**Critical patterns (for views WITH operations):**
- `@State private var repaintToggle = false` for triggering test data transport
- `.testDataTransporter(viewModelOps:repaintToggle:)` modifier in DEBUG
- `toggleRepaint()` called after every operation invocation
- `operations` stored as property from `viewModel.operations`

**Display-only views:**
- No `repaintToggle` needed
- No `.testDataTransporter()` modifier needed
- Just add `.uiTestingIdentifier()` to elements you want to test

## ViewModelOperations: Optional

Not all views need ViewModelOperations. The Operations trio (protocol + live Ops + StubOps) is generated by [fosmvvm-viewmodel-generator](../fosmvvm-viewmodel-generator/SKILL.md) — **only for interactive ViewModels**. This skill consumes whatever exists; it does not generate Operations itself.

**Views that NEED operations** (the viewmodel-generator emits an Operations file):
- Forms with submit/cancel actions
- Views that call business logic or APIs
- Interactive views that trigger app state changes
- Views with user-initiated async operations

**Views that DON'T NEED operations** (no Operations file exists):
- Display-only cards or detail views
- Static content views
- Pure navigation containers
- Server-hosted views that just render data

**For views without operations**, no scaffolding is created — no protocol, no stub class, no `ViewModelOperations` subtype of any kind. Tests subclass the display-only base class (`MyAppViewModelDisplayTestCase<VM>`), which takes no Operations generic parameter:

```swift
final class MyDisplayViewUITests: MyAppViewModelDisplayTestCase<MyDisplayViewModel> {
    // Only test UI state, no operation verification
    func testDisplaysTitle() async throws {
        let app = try presentView(viewModel: .stub(title: "Test"))
        XCTAssertTrue(app.titleLabel.exists)
    }
}
```

The view itself also doesn't need:
- `repaintToggle` state
- `.testDataTransporter()` modifier
- `operations` property
- `toggleRepaint()` function

If you find yourself reaching for an empty `ViewModelOperations` protocol to satisfy a generic parameter, stop — use the display-only path. The whole reason `ViewModelDisplayTestCase<VM>` exists is to eliminate that workaround.

Just add `.uiTestingIdentifier()` to elements you want to verify.

## Test Categories

### UI State Tests

Verify that the UI displays correctly based on ViewModel state:

```swift
func testButtonDisabledWhenNotReady() async throws {
    let app = try presentView(viewModel: .stub(ready: false))
    XCTAssertFalse(app.submitButton.isEnabled)
}

func testButtonEnabledWhenReady() async throws {
    let app = try presentView(viewModel: .stub(ready: true))
    XCTAssertTrue(app.submitButton.isEnabled)
}
```

### Operation Tests

Verify that user interactions invoke the correct operations:

```swift
func testSubmitButtonInvokesOperation() async throws {
    let app = try presentView(configuration: .requireAuth())
    app.submitButton.tap()

    let stubOps = try viewModelOperations()
    XCTAssertTrue(stubOps.submitCalled)
    XCTAssertFalse(stubOps.cancelCalled)
}
```

### Navigation Tests

Verify navigation flows work correctly:

```swift
func testNavigationToDetailView() async throws {
    let app = try presentView()
    app.itemRow.tap()

    XCTAssertTrue(app.detailView.exists)
}
```

## When to Use This Skill

- Adding UI tests for a new ViewModelView
- Setting up UI test infrastructure for a FOSMVVM project
- Following an implementation plan that requires test coverage
- Validating user interaction flows

## What This Skill Generates

### Initial Setup (once per project)

| File | Location | Purpose |
|------|----------|---------|
| `{ProjectName}ViewModelViewTestCase.swift` | `Tests/UITests/Support/` | Base test case for all UI tests |
| `XCUIElement.swift` | `Tests/UITests/Support/` | Helper extensions for XCUIElement |

### Per ViewModelView

| File | Location | Purpose |
|------|----------|---------|
| `{ViewName}ViewModelOperations.swift` | `Sources/{ViewModelsTarget}/{Feature}/` | Operations protocol and stub (if view has interactions) |
| `{ViewName}UITests.swift` | `Tests/UITests/Views/{Feature}/` | UI tests for the view |

**Note:** Views without user interactions use an empty operations file with just the protocol and minimal stub.

### UI-Test Target Wiring (Xcode project)

For the Xcode-project layout the app-setup skill recommends, wire the **UI-test target**
differently from the app-hosted unit tests — three points:

1. **Link `FOSFoundation` / `FOSMVVM` / `FOSTestingUI` DIRECTLY — NOT via `SPMLibraries`.**
   UI tests run in a **separate process** and drive the app over the XCUI proxy (JSON over
   `launchEnvironment`, never live objects). So the `SPMLibraries` type-identity trap — which
   *forces* the umbrella for app-hosted **unit** tests — **does not apply here**; the UI-test
   bundle links the FOS products directly. Do **not** add them to `SPMLibraries` (that
   framework is embedded in the shipping app, and a testing framework must not ride along).
2. **Source-include the shared contract module.** Under Option A the app has no separate
   ViewModels framework to import, so the UI-test target must **also source-include**
   `Sources/{ViewModelsModule}` to get the ViewModel type + its `.stub()` in-process (the
   test encodes the stub before handing it to the app).
3. **Copy the server-side localization tree into the test bundle.**
   `presentView` localizes the stub *before* handing it to the app (which decodes an
   already-localized VM). Since release client apps don't bundle `*.yml`, the UI-test target
   copies `Sources/Resources` in as a folder reference and `setUp` passes
   `resourceDirectoryName:` accordingly (mirrors the SPM unit test's
   `.copy("../../Sources/Resources")` + `resourceDirectoryName: "Resources"`).

## Project Structure Configuration

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{ProjectName}` | Your project/app name | `MyApp`, `TaskManager` |
| `{ViewName}` | The ViewModelView name (without "View" suffix) | `TaskList`, `Dashboard` |
| `{Feature}` | Feature/module grouping | `Tasks`, `Settings` |

## How to Use This Skill

**Invocation:**
/fosmvvm-ui-tests-generator

**Prerequisites:**
- View and ViewModel structure understood from conversation context
- ViewModelOperations type identified (or confirmed as display-only)
- Interactive elements and user flows discussed

**Workflow integration:**
This skill is typically used after implementing ViewModelViews. The skill references conversation context automatically—no file paths or Q&A needed. Often follows fosmvvm-swiftui-view-generator or fosmvvm-react-view-generator.

## Pattern Implementation

This skill references conversation context to determine test structure:

### Test Type Detection

From conversation context, the skill identifies:
- **First test vs additional test** (whether base test infrastructure exists)
- **ViewModel type** (from prior discussion or View implementation)
- **ViewModelOperations type** (from View implementation or context)
- **Interactive vs display-only** (whether operations need verification)

### View Analysis

From requirements already in context:
- **Interactive elements** (buttons, fields, controls requiring test coverage)
- **User flows** (navigation paths, form submission, drag-and-drop)
- **State variations** (enabled/disabled, visible/hidden, error states)
- **Operation triggers** (which UI actions invoke which operations)

### Infrastructure Planning

Based on project state:
- **Base test case** (create if first test, reuse if exists)
- **XCUIElement extensions** (helper methods for common interactions)
- **App bundle identifier** (for launching test host)

### Test File Generation

For the specific view:
1. Test class inheriting from base test case
2. UI state tests (verify display based on ViewModel)
3. Operation tests (verify user interactions invoke operations)
4. XCUIApplication extension with element accessors

### View Requirements

Ensure test identifiers and data transport:
1. `.uiTestingIdentifier()` on all interactive elements
2. `@State private var repaintToggle` (if has operations)
3. `.testDataTransporter()` modifier (if has operations)
4. `toggleRepaint()` calls after operations (if has operations)

### Context Sources

Skill references information from:
- **Prior conversation**: View requirements, user flows discussed
- **View implementation**: If Claude has read View code into context
- **ViewModelOperations**: From codebase or discussion

## Key Patterns

### Test Configuration Pattern

Use `TestConfiguration` for tests that need specific app state:

```swift
func testWithSpecificState() async throws {
    let app = try presentView(
        configuration: .requireAuth(userId: "123")
    )
    // Test with authenticated state
}
```

### Element Accessor Pattern

Define element accessors in a private extension:

```swift
private extension XCUIApplication {
    var submitButton: XCUIElement {
        buttons.element(matching: .button, identifier: "submitButton")
    }

    var cancelButton: XCUIElement {
        buttons.element(matching: .button, identifier: "cancelButton")
    }

    var firstItem: XCUIElement {
        buttons.element(matching: .button, identifier: "itemButton").firstMatch
    }
}
```

### Operation Verification Pattern

After user interactions, verify operations were called:

```swift
func testDecrementButton() async throws {
    let app = try presentView(configuration: .requireDevice())
    app.decrementButton.tap()

    let stubOps = try viewModelOperations()
    XCTAssertTrue(stubOps.decrementCalled)
    XCTAssertFalse(stubOps.incrementCalled)
}
```

### Orientation Setup Pattern

Set device orientation in `setUp()` if needed:

```swift
override func setUp() async throws {
    try await super.setUp()

    #if os(iOS)
    XCUIDevice.shared.orientation = .portrait
    #endif
}
```

## View Testing Checklist

**All views:**
- [ ] `.uiTestingIdentifier()` on all elements you want to test

**Views WITH operations (interactive views):**
- [ ] `@State private var repaintToggle = false` property
- [ ] `.testDataTransporter(viewModelOps:repaintToggle:)` modifier
- [ ] `toggleRepaint()` helper function
- [ ] `toggleRepaint()` called after every operation invocation
- [ ] `operations` stored from `viewModel.operations` in init

**Views WITHOUT operations (display-only):**
- [ ] No `repaintToggle` needed
- [ ] No `.testDataTransporter()` needed
- [ ] No `operations` property needed
- [ ] Subclass `ViewModelDisplayTestCase<VM>` (not the two-generic interactive base)

## Common Test Patterns

### Testing Async Operations

```swift
func testAsyncOperation() async throws {
    let app = try presentView()
    app.loadButton.tap()

    // Wait for UI to update
    _ = app.waitForExistence(timeout: 3)

    let stubOps = try viewModelOperations()
    XCTAssertTrue(stubOps.loadCalled)
}
```

### Testing Form Input

```swift
func testFormInput() async throws {
    let app = try presentView()

    let emailField = app.emailTextField
    emailField.tap()
    emailField.typeTextAndWait("user@example.com")

    app.submitButton.tap()

    let stubOps = try viewModelOperations()
    XCTAssertTrue(stubOps.submitCalled)
}
```

### Testing Error States

```swift
func testErrorDisplay() async throws {
    let viewModel: MyViewModel = try localizedViewModel(.stub(hasError: true))
    let app = try presentView(viewModel: viewModel)

    XCTAssertTrue(app.errorAlert.exists)
    XCTAssertEqual(app.errorMessage.text, try viewModel.errorMessage.localizedString)
}
```

## File Templates

See [reference.md](reference.md) for complete file templates.

## Naming Conventions

| Concept | Convention | Example |
|---------|------------|---------|
| Base test case | `{ProjectName}ViewModelViewTestCase` | `MyAppViewModelViewTestCase` |
| UI test file | `{ViewName}UITests` | `TaskListViewUITests` |
| Test method (UI state) | `test{Condition}` | `testButtonEnabled` |
| Test method (operation) | `test{Action}` | `testSubmitButton` |
| Element accessor | `{elementName}` | `submitButton`, `emailTextField` |
| UI testing identifier | `{elementName}Identifier` or `{elementName}` | `"submitButton"`, `"emailTextField"` |

## See Also

- [Architecture Patterns](../shared/architecture-patterns.md) - Mental models and patterns
- [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md) - Full FOSMVVM architecture
- [fosmvvm-viewmodel-generator](../fosmvvm-viewmodel-generator/SKILL.md) - For creating ViewModels
- [fosmvvm-swiftui-app-setup](../fosmvvm-swiftui-app-setup/SKILL.md) - For app test host setup
- [reference.md](reference.md) - Complete file templates

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-23 | Initial skill for UI tests |
| 1.1 | 2026-01-24 | Update to context-aware approach (remove file-parsing/Q&A). Skill references conversation context instead of asking questions or accepting file paths. |
| 1.2 | 2026-03-30 | Add Element Matching Rules section (identifier > localizedViewModel > never hardcoded strings). Fix hardcoded string in error state example. |
| 1.3 | 2026-07-02 | Note that `.uiTestingIdentifier(_:)` is a FOSMVVM `View` modifier (`import FOSMVVM`, `SwiftUI Support/View+Testing.swift`), DEBUG-only (no-op in release), applied unconditionally; don't define/copy it yourself. (backlog D1) |
| 1.4 | 2026-07-02 | Version-floor note for `ViewModelDisplayTestCase<VM>` (recent FOSTestingUI where `ViewModelViewTestCase` inherits it) + older-ref no-op-ops fallback (D2). Added "UI-Test Target Wiring (Xcode project)": link FOS directly NOT via `SPMLibraries` (separate process — trap doesn't apply), source-include the shared contract module, copy the localization tree + `resourceDirectoryName:` (D3). Fixed a copy-paste bug in the View Testing Checklist (display-only list wrongly required `operations` stored from `viewModel.operations`). |
