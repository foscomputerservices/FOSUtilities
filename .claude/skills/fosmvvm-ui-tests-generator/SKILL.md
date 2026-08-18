---
name: fosmvvm-ui-tests-generator
description: Generate UI tests for FOSMVVM SwiftUI views using XCTest and FOSTestingUI. Covers accessibility identifiers, ViewModelOperations, and test data transport.
homepage: https://github.com/foscomputerservices/FOSUtilities
metadata: {"clawdbot": {"emoji": "🖥️", "os": ["darwin"]}}
---

# FOSMVVM UI Tests Generator

> **Read [`shared/functional-discipline.md`](../shared/functional-discipline.md) before proceeding.** Every rule below derives from it.

Generate comprehensive UI tests for ViewModelViews in FOSMVVM applications.

## Conceptual Foundation

> For full architecture context, see [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md) | [OpenClaw reference]({baseDir}/references/FOSMVVMArchitecture.md)

> **API catalog:** check [`../shared/api-catalog/FOSTesting.md`](../shared/api-catalog/FOSTesting.md) § FOSTestingUI before hand-writing helpers.

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

Tag the view with `.uiTestingIdentifier()` and find it with `.uiTestingElement()`:

> **`.uiTestingIdentifier(_:)` is a FOSMVVM `View` modifier — `import FOSMVVM`.** It ships
> in FOSMVVM (`SwiftUI Support/View+Testing.swift`); you do **not** define it yourself and
> you must **not** copy a private version into your app. It is **DEBUG-only** — in a
> release build it compiles to a no-op (`self`), so tagging carries **no** test scaffolding
> into shipping binaries. Because it self-gates, apply it **unconditionally** (do not wrap
> it in `#if DEBUG` — only `.testDataTransporter` needs that guard).
>
> **`app.uiTestingElement(_:)` is its counterpart — `import FOSTestingUI`.** The identifier
> is the entire contract on both sides.

```swift
// View  (import FOSMVVM)
Text(viewModel.title)
    .uiTestingIdentifier("dashboardTitle")

// Test  (import FOSTestingUI)
XCTAssertTrue(app.uiTestingElement("dashboardTitle").exists)
```

**Do not write `XCUIApplication` accessor extensions**, and do not name XCUITest element
types (`buttons`, `staticTexts`, `otherElements`) for tagged views. An accessor keyed on
an element type bakes a rendering detail into the test, so the test breaks when a `Button`
becoming a `Menu` — and it is exactly the boilerplate `uiTestingElement()` exists to delete.

A gesture against an identifier no view carries fails the test naming that
identifier, so a typo reads as a typo rather than as an XCUITest snapshot error.

`uiTestingElement(_:)` offers `exists` (present in the hierarchy, on screen or not),
`isVisible` (on screen and tappable), `waitForExistence()`, `waitForDisappearance()`,
`waitForStableFrame()`, `tap()`, `setText(_:expecting:)`, `type(_:)`,
`selectPickerItem(_:)`, `isEnabled`,
`label`, `value`, and `xcuiElement` as the escape hatch for anything else:

```swift
app.uiTestingElement("nameField").setText("Fern")
app.uiTestingElement("saveButton").tap()

XCTAssertTrue(app.uiTestingElement("savedBanner").waitForExistence())
```

**Generate the verified interaction, not the gesture.** The verified APIs do not return
until their effect is observable, which is what lets the very next assertion run without
a wait — and what lets consuming suites delete retry heuristics instead of growing them
(each verified postcondition is a race a generated test can no longer lose):

- `setText(_:)` when the test's intent is *the field ending up with an exact value* —
  it replaces (no caret assumptions) and verifies the read-back. Formatter-backed fields
  declare their rendering: `setText("45", expecting: "45.00")`. `type(_:)` remains only
  for genuine append-at-caret, which is honestly unverified.
- `selectPickerItem(_:)` for a `Picker` — it returns only after the selection committed,
  so selection-derived state (a dependent button's enablement) is readable immediately.
  A `Menu` of action buttons has no selection to verify: drive it with `tap()` and assert
  the action's effect.
- `tap()` settles a mid-animation frame and aims at the control a composite tag spans on
  its own; `waitForStableFrame()` is for interactions that bypass it (a native gesture
  through `xcuiElement`, a frame assertion).

**Assert displayed text against the ViewModel, never a literal.** `XCTAssertEqual` accepts a
`Localizable` directly, so there is no `try`, no `localizedString`, and no throwing test:

```swift
let viewModel: DashboardViewModel = try localizedViewModel()
let app = try presentView(viewModel: viewModel)

XCTAssertEqual(app.uiTestingElement("dashboardTitle").label, viewModel.title)
XCTAssertEqual(app.uiTestingElement("emailField").value, viewModel.email)
```

A `Localizable` whose translation was never realized cannot match any displayed text, so the
assertion fails and names that as the cause instead of reading as a wrong label.

**Tag whatever you need, wherever you need it.** The tag holds on controls that bridge to a
native element (`Picker`, `DatePicker`, `TextField`, `ColorPicker`), on a container whose
sub-views carry their own tags, at any nesting depth, and at any position in the modifier
chain. A composed view and each of its sub-views can each carry their own tag and each be
verified by their own test suite. A tag that spans a composite — a row holding a caption
and a field — reads and taps the control the composite contains; when it holds several,
the first in document order answers, so tag the control itself to address one precisely.

### Tier 2: Localized ViewModel Text (When Identifiers Are Insufficient)

When you must match by display text (e.g., verifying a label's content, or an element that can't carry a unique identifier), use `localizedViewModel()` to resolve the text from the same source of truth as the UI:

```swift
let viewModel: PrimaryParametersViewModel = try localizedViewModel()
let app = try presentView(viewModel: viewModel)

// Match against ViewModel's resolved localized text — never a hardcoded string
XCTAssertTrue(try app.staticTexts[viewModel.amplitudeLabel.localizedString].exists)
XCTAssertEqual(app.uiTestingElement("stepperValueText").label, viewModel.value)
```

This keeps tests locale-correct and refactor-safe — if the YAML translation changes, the test still passes because it reads from the same source of truth.

### Never Allowed: Hardcoded Display Strings

```swift
// ❌ WRONG — breaks on locale change, copy change, or duplicate text
XCTAssertTrue(app.staticTexts["Settings"].exists)
XCTAssertEqual(app.label.text, "Welcome back!")

// ✅ RIGHT — Tier 1: identifier
XCTAssertTrue(app.uiTestingElement("settingsLabel").exists)

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
        XCTAssertTrue(app.uiTestingElement("myButtonIdentifier").isVisible)
    }

    // Operation Tests - verify operations were called
    func testButtonTap() async throws {
        let app = try presentView(configuration: .requireSomeState())
        app.uiTestingElement("myButtonIdentifier").tap()

        let stubOps = try viewModelOperations()
        XCTAssertTrue(stubOps.myOperationCalled)
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
        XCTAssertTrue(app.uiTestingElement("titleLabel").exists)
    }
}
```

Do not invent an empty `ViewModelOperations` protocol for display-only views. The display-only path was designed specifically to avoid this — `ViewModelDisplayTestCase<VM>` takes one generic parameter, and no Operations file should exist for display-only ViewModels.

**When to use each:**
- **With operations**: Interactive views that perform actions (forms, buttons that call APIs, toggles, etc.) — use `MyAppViewModelViewTestCase<VM, VMO>`.
- **Without operations**: Display-only views (cards, detail views, static content) — use `MyAppViewModelDisplayTestCase<VM>`.

### 3. Element Helpers — Not Needed

Do **not** write `XCUIElement` extensions for typing, reading text, or tapping menus.
`uiTestingElement(_:)` already covers them:

| Hand-rolled helper | Use instead |
|---|---|
| `var text: String?` | `.value` |
| `typeTextAndWait(_:)` / `selectTypeTextAndWait(_:)` / clear-then-type helpers | `.setText(_:)` — replaces and verifies the read-back; `.type(_:)` only for genuine append |
| `tapMenu()` | `.tap()` — it falls back to a coordinate tap for menus that report themselves as not hittable |
| open-menu → tap-row → poll-selection ceremonies | `.selectPickerItem(_:)` — returns only after the selection committed |
| frame-settling / two-equal-samples polls | `.waitForStableFrame()` — and `tap()` settles on its own |


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
        XCTAssertTrue(app.uiTestingElement("titleLabel").exists)
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
    XCTAssertFalse(app.uiTestingElement("submitButton").isEnabled)
}

func testButtonEnabledWhenReady() async throws {
    let app = try presentView(viewModel: .stub(ready: true))
    XCTAssertTrue(app.uiTestingElement("submitButton").isEnabled)
}
```

### Operation Tests

Verify that user interactions invoke the correct operations:

```swift
func testSubmitButtonInvokesOperation() async throws {
    let app = try presentView(configuration: .requireAuth())
    app.uiTestingElement("submitButton").tap()

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
    app.uiTestingElement("itemRow").tap()

    XCTAssertTrue(app.uiTestingElement("detailView").exists)
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
- **App bundle identifier** (for launching test host)

### Test File Generation

For the specific view:
1. Test class inheriting from base test case
2. UI state tests (verify display based on ViewModel)
3. Operation tests (verify user interactions invoke operations)

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

### Element Lookup Pattern

Find each tagged view by its identifier, at the point of use:

```swift
app.uiTestingElement("submitButton").tap()
app.uiTestingElement("cancelButton").tap()

XCTAssertTrue(app.uiTestingElement("emptyStateMessage").isVisible)
```

Do **not** define `XCUIApplication` accessor extensions for tagged views. They add a second
name for every element, and they name an XCUITest element type — which is a rendering
detail, not a contract. `uiTestingElement(_:)` takes the identifier and nothing else.

### Operation Verification Pattern

After user interactions, verify operations were called:

```swift
func testDecrementButton() async throws {
    let app = try presentView(configuration: .requireDevice())
    app.uiTestingElement("decrementButton").tap()

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
    app.uiTestingElement("loadButton").tap()

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

    app.uiTestingElement("emailTextField").setText("user@example.com")

    app.uiTestingElement("submitButton").tap()

    let stubOps = try viewModelOperations()
    XCTAssertTrue(stubOps.submitCalled)
}
```

### Testing Error States

```swift
func testErrorDisplay() async throws {
    let viewModel: MyViewModel = try localizedViewModel(.stub(hasError: true))
    let app = try presentView(viewModel: viewModel)

    XCTAssertTrue(app.alerts["errorAlert"].exists)
    XCTAssertEqual(app.uiTestingElement("errorMessage").label, viewModel.errorMessage)
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
| UI testing identifier | `{elementName}` — the view's role, not its control | `"submitButton"`, `"emailTextField"` |

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
| 1.5 | 2026-08-12 | `.uiTestingIdentifier(_:)` reworked so a tag holds on bridged controls (`Picker`, `DatePicker`, `TextField`, `ColorPicker`), on containers whose sub-views carry their own tags, at any depth, and at any position in the modifier chain. Tests now find tagged views with `app.uiTestingElement(_:)` (FOSTestingUI): `XCUIApplication` accessor extensions, XCUITest element-type queries, and the hand-rolled `typeTextAndWait`/`tapMenu`/`text` helpers are all removed in favour of it. |
| 1.6 | 2026-08-18 | The verified-interaction layer: generate `setText(_:expecting:)` for exact-value text entry (replaces + verifies read-back; `type(_:)` only for genuine append), `selectPickerItem(_:)` for Picker selection (returns only after the selection committed — the next read needs no wait), `waitForStableFrame()` for interactions that bypass `tap()`. `tap()` now settles in-flight frames and aims at the control a composite tag spans; reads resolve the same way, so a row-spanning tag answers with its field. Legacy-helper table routes replacement intent to `setText`. |
