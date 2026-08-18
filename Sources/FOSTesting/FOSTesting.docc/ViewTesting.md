# Getting Started With View (UI) Testing

Quickly, thoroughly and robustly test your SwiftUI Views

## Overview

Often writing UI tests goes quickly at first and then degrades into a jumbled mess
that is difficult to maintain and generally anything but robust.  This is often
caused by the fact that views cannot be tested independently and that multiple
levels of UI must be traversed in order to reach the view that is being tested.

FOSMVVM completely avoids this by allowing each view to be tested independently
of all other views.  This allows for simple, targeted tests that and robust CI test
runs.

> As of the writing of this documentation, 
> [swift-testing](https://github.com/swiftlang/swift-testing.git) does not support UI
> testing ([Issue \#516](https://github.com/swiftlang/swift-testing/issues/516#issuecomment-2201208834))
> and thus, all UI tests are expected to be written using
> [XCTest](https://developer.apple.com/documentation/xctest) and
> [XCUIAutomattion](https://developer.apple.com/documentation/xcuiautomation).

## Two Paths: Display-Only vs Interactive

FOSMVVM separates UI testing into two paths, matching the two kinds of views you write:

| View kind | Has user-initiated actions? | Base class | Has `ViewModelOperations`? |
|-----------|-----------------------------|------------|----------------------------|
| **Display-only** | No — just renders data | ``ViewModelDisplayTestCase`` | No |
| **Interactive** | Yes — buttons, forms, toggles, etc. | ``ViewModelViewTestCase`` | Yes |

Pick the path based on the view, not the test. A card that only displays data
belongs on the display-only path. A form with a Save button belongs on the
interactive path. The two paths diverge in what scaffolding the view needs
(`.testDataTransporter()`, stub operations) and what the test can verify
(UI state vs UI state *plus* operation dispatch).

If your view has **no** user-initiated actions, use the display-only path — do
not invent an empty `ViewModelOperations` type just to satisfy the generic
parameter. The display-only path doesn't require one.

## Configuring The Application

[XCUIAutomation](https://developer.apple.com/documentation/xcuiautomation) testing is
composed of two applications:

1. The application under test (your application)
1. A test driver application (your tests)

Communication between these two applications is performed using a proxy,
[XCUIApplication](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication)
that orchestrates everything using various automation APIs.  This communication is
completely hidden from the test application, however it is very important to understand
that the tests do not have direct access to the application's instances.

### Application Configuration

As mentioned in the introduction, in order to robustly test ``FOSTesting`` provides
services to enable testing of each view independently.  This can be done because
each view's data and state are specified declaratively (See also [Getting Started With Application State in Client Applications](https://swiftpackageindex.com/foscomputerservices/fosutilities/main/documentation/fosmvvm/applicationstate)).

``FOSTesting`` provides the ``testHost`` view modifier, which provides support for
the test client to display each view with a provided ``ViewModel`` for testing.
This view modifier should be added at the top of the the application's view hierarchy.

Finally, each View that inherits from ViewModelView must be registered with
``MVVMEnvironment/registerTestView(_:scrollable:)`` from the application's `init()`.

> Important: `init()` is the only supported place for these calls. ``testHost``
> resolves the view under test *before the first render*, so registering from a
> computed property, from `.onAppear`, or from `.task` arrives too late. When that
> happens the application stops with a diagnostic — written to stderr so it shows up
> in `xcodebuild` and CI logs — naming the ViewModel the test asked for, listing the
> ViewModels that are registered, and showing the `init()` call that fixes it.

> Future work will provide a macro that will eliminate the need for this
> boiler plate code.

This setup applies to **both** the display-only and interactive paths.

#### Example

```swift
@main MyApp: App {

    var body: some Scene {
        WindowGroup {
            MyMainView.bind( /* ... */)
            #if DEBUG
            .testHost()
            #endif
        }
        .environment(mvvmEnv)
    }

    init() {
        MVVMEnvironment.registerTestingViews()
    }
}

private extension MyApp {
    @MainActor var mvvmEnv: MVVMEnvironment {
        MVVMEnvironment(
            appBundle: Bundle.main,
            deploymentURLs: [ /* ... */ ]
        )
    }
}

private extension MVVMEnvironment {
    // *Every* ViewModelView is listed here to enable individualized
    // testing of each view
    @MainActor static func registerTestingViews() {
        #if DEBUG
        registerTestView(MyMainView.self)
        registerTestView(View2.self)

        // ...
        registerTestView(ViewN.self)
        #endif
    }
}
```

Only the *body* of ``MVVMEnvironment/registerTestView(_:scrollable:)`` is `#if DEBUG`, so the
whole helper compiles away to a no-op in release builds — keeping the `#if DEBUG` inside it,
rather than around the call in `init()`, is the tidier of the two. Either is correct.

### Views Designed for a Scrolling Parent

A view that lives inside a scrolling parent in production — a form card inside a
`ScrollView`, a section of a longer page — is taller than any window when presented
bare: content compresses and overlaps, controls end up buried where no tap can reach
them, and keyboard avoidance displaces the whole content instead of scrolling. Declare
the design fact where the view is registered, and the harness presents it inside a
vertical `ScrollView`, as production does:

```swift
registerTestView(DeviceCardView.self, scrollable: true)
```

The declaration also restores XCUITest's automatic scroll-to-visible — the harness
finally has something to scroll — so off-screen elements come to a tap on their own.
Views registered without it present bare, exactly as before.

> Important: `scrollable: true` states the view's *designed* production environment. It
> is not an escape hatch for a view that overflows its production container too — that
> is a layout bug the harness should keep surfacing.

## Display-Only Path

Use this path when the view only renders data and has no user-initiated actions
(cards, rows, detail views, static content).

### View Requirements

A display-only view has none of the operation-testing scaffolding — no
`.testDataTransporter()`, no `operations` property, no `repaintToggle`:

```swift
struct MyDetailView: ViewModelView {
    let viewModel: MyDetailViewModel

    var body: some View {
        VStack {
            Text(viewModel.title)
                .uiTestingIdentifier("titleLabel")
            Text(viewModel.summary)
                .uiTestingIdentifier("summaryLabel")
        }
    }
}
```

### Configuring a Display-Only Test Base Class

Each framework should configure a base class that pins `setUp` for the app bundle:

```swift
class MyLibraryViewModelDisplayTestCase<VM: ViewModel>: ViewModelDisplayTestCase<VM>,
    @unchecked Sendable {
    override func setUp() async throws {
        try await super.setUp(
            bundle: Bundle.main,
            resourceDirectoryName: "",
            appBundleIdentifier: "<com.my-company.my-app>"
        )

        continueAfterFailure = false // Stop the test and move on
    }
}
```

### Implementing Display-Only Tests

Subclass your framework base class with the specific `ViewModel`:

```swift
final class MyDetailViewUITests: MyLibraryViewModelDisplayTestCase<MyDetailViewModel>,
    @unchecked Sendable { }
```

Tests then verify UI state only:

```swift
func testShowsTitle() async throws {
    let viewModel: MyDetailViewModel = try localizedViewModel(.stub())
    let app = try presentView(viewModel: viewModel)

    let titleLabel = app.uiTestingElement("titleLabel")

    XCTAssertTrue(titleLabel.waitForExistence())
    XCTAssertEqual(titleLabel.label, viewModel.title)
}

func testShowsSummary() async throws {
    let app = try presentView(viewModel: .stub(summary: "A summary"))

    XCTAssertTrue(app.uiTestingElement("summaryLabel").waitForExistence())
}
```

Views are tagged with `uiTestingIdentifier(_:)` (**FOSMVVM**) and found with
`XCUIApplication.uiTestingElement(_:)` (**FOSTestingUI**). The identifier is all a
test names — there is no XCUITest element type to choose, and no `XCUIApplication`
accessor extension to write and keep in step. Compare displayed text against the
localized *ViewModel*, never a literal, so the test holds in every locale —
`XCTAssertEqual` takes a `Localizable` directly:

```swift
let emailField = app.uiTestingElement("emailField")

XCTAssertTrue(emailField.waitForExistence())
XCTAssertEqual(emailField.value, viewModel.email)
XCTAssertFalse(app.uiTestingElement("saveButton").isEnabled)
```

## Synchronizing With the Screen

`presentView` launches the application fresh, and gestures push views on and
off the screen — the view a test asks about may still be *arriving* or
*departing*. `UITestingElement` separates its API into **questions** that
answer about the screen as it is *now* (`exists`, `isVisible`, `label`,
`value`, `isEnabled`) and **waits** that synchronize with it
(`waitForExistence()`, `waitForDisappearance()`, `waitForStableFrame()`).

The first assertion after a launch or a gesture is a wait; once one element
has arrived, the screen is synchronized and questions answer reliably:

```swift
let banner = app.uiTestingElement("savedBanner")

XCTAssertFalse(banner.exists)                 // never presented — nothing in flight
app.uiTestingElement("saveButton").tap()
XCTAssertTrue(banner.waitForExistence())      // arriving — wait
app.uiTestingElement("dismissBanner").tap()
XCTAssertTrue(banner.waitForDisappearance())  // departing — wait
```

> Important: Mind the polarity on departure. `waitForDisappearance()` returns
> `true` when the view **left**, so a disappearance is proven with
> `XCTAssertTrue` — the opposite of the instinctive
> `XCTAssertFalse(...exists)`, which races a view that is still dismissing.
> `XCTAssertFalse(...exists)` is only for a view that was never presented at
> all.

Gestures synchronize themselves — `tap()` and `type(_:)` wait for the view to
arrive before acting, so no explicit wait precedes them. `tap()` also waits
for a moving frame to stop: a menu row mid-presentation already *exists*, so
an existence wait passes, but a tap computed from its in-flight frame lands
where the row *was*.

`waitForStableFrame()` is that same settling for interactions that bypass
`tap()` — a native double-tap through `xcuiElement`, addressing a control's
child elements, asserting a frame:

```swift
let amount = app.uiTestingElement("amountField")

XCTAssertTrue(amount.waitForStableFrame())
amount.xcuiElement.doubleTap()
```

## Tagging a Composite

A tag often spans a row rather than a single control — a caption beside a
field is a natural authoring unit:

```swift
HStack {
    Text(duration.label)
    TextField("seconds", text: $duration.value)
}
.uiTestingIdentifier("durationRow")
```

Reading and tapping both resolve to the control the composite contains:
`value` answers with the field's value, and `tap()` lands on the field rather
than the row's midpoint — which can fall on the caption, or in the gap
between the two, depending on nothing more than the device's width.

```swift
app.uiTestingElement("durationRow").tap()                    // taps the field
XCTAssertEqual(app.uiTestingElement("durationRow").value, viewModel.duration)
```

When a composite holds several controls, the first in document order answers —
tag the control itself to address one precisely.

## Selecting a Picker Item

Driving a menu-style `Picker` by hand is a ceremony — open the menu, wait for the
row, tap it, and *verify the selection committed* — and skipping the verification is
a race: state SwiftUI derives from the selection is not yet readable when the tap
returns. `selectPickerItem(_:)` owns the whole ceremony and does not return until
the selection is observably committed, so the very next read needs no wait:

```swift
app.uiTestingElement("programPicker").selectPickerItem("optionB")

XCTAssertFalse(app.uiTestingElement("saveButton").isEnabled) // no wait needed
```

The receiver is the tagged `Picker`; the argument is the `uiTestingIdentifier` of
the item inside the Picker's content. A missed gesture is retried once and
re-verified — the postcondition, not the tap, is what lets the call return.

> Important: This serves `Picker` only. A `Menu` of action buttons has no selection
> to verify — the menu departs whether the tap hit the row or the scrim, so there is
> no generic commit signal. Drive a `Menu` with `tap()` and assert the action's
> effect instead.

## Dismissing the Keyboard

Typing raises the software keyboard, and a raised keyboard covers the lower
part of the screen — a tap aimed at a covered control lands on the keyboard
instead, and the test fails downstream with no visible error at the tap.
XCUITest offers no way to put the keyboard away, and a `.numberPad` keyboard
has no Return key to tap.

`dismissKeyboard()` is the way down. Call it after typing, before tapping
anything the keyboard might cover:

```swift
app.uiTestingElement("quantityField").type("42")
app.dismissKeyboard()
app.uiTestingElement("saveButton").tap()
```

With no keyboard up the call is a no-op, so call sites stay unconditional —
no platform or keyboard-type checks. It rides an invisible control that
``testHost`` plants, so it works for every keyboard type and needs nothing
from the application beyond the `.testHost()` this article already
configured. If the keyboard cannot be dismissed, the test fails naming the
cause rather than carrying on.

> Important: Tapping a neutral view — a title, some empty space — does *not*
> dismiss the keyboard, however much the idiom looks like it should. A static
> `Text` is not interactive, so the tap resigns nothing and the keyboard
> stays up; the workaround reads as correct and silently does nothing. Use
> `dismissKeyboard()`.

## Interactive Path

Use this path when the view has buttons, forms, toggles, or other user-initiated
actions that dispatch to a ``ViewModelOperations`` protocol.

### Configure the View Model View

The *testDataTransporter* view modifier is provided to transmit the *ViewModelOperations*
structure back to the test harness. This modifier should be added to the top of each
interactive *ViewModelView* implementation. Display-only views do not need it.

```swift
struct MyView: ViewModelView {
   @State private var data = ""

   let myViewModel: MyViewModel
   private let operations: any MyViewModelOperations

   #if DEBUG
   @State private var repaintToggle = false
   #endif

  var body: some View {
    VStack {
      TextField("", text: $data)
        .uiTestingIdentifier("dataTextField")

      Button(action: save) {
        Text("Tap Me")
      }
      .uiTestingIdentifier("saveButton")
    }
    #if DEBUG
    .testDataTransporter(viewModelOps: operations, repaintToggle: $repaintToggle)
    #endif
  }

  private func save() {
    operations.saveData(data: data)
    toggleRepaint()
  }

  private func toggleRepaint() {
    #if DEBUG
    repaintToggle.toggle()
    #endif
  }
}

public final class MyViewModelStubOps: MyViewModelOperations, @unchecked Sendable {
    public private(set) var data: String?
    public private(set) var saveDataCalled: Bool
    public func saveData(data: String) {
        self.data = data
        saveDataCalled = true
    }
    public init() {
        self.data = nil
        self.saveDataCalled = false
    }
}
```

### Configuring an Interactive Test Base Class

Each framework should configure a base class that contains the configuration
for testing the framework. This base class should extend ``ViewModelViewTestCase``.

```swift
class MyLibraryViewModelViewTestCase<VM: ViewModel, VMO: ViewModelOperations>: ViewModelViewTestCase<VM, VMO>,
    @unchecked Sendable {
    override func setUp() async throws {
        try await super.setUp(
            bundle: Bundle.main,
            resourceDirectoryName: "",
            appBundleIdentifier: "<com.my-company.my-app>"
        )

        continueAfterFailure = false // Stop the test and move on
    }
}
```

### Implementing Interactive Tests

> While there are many ways to implement XCUITests, the patterns presented here
> have proven to provide stable tests over time.

Begin by creating a subclass of the test base class created in the previous step.

```swift
final class MyViewUITests: MyLibraryViewModelViewTestCase<MyViewModel, MyViewModelStubOps>, @unchecked Sendable { }
```

Tests can then verify both UI state and that each button/action calls the expected view model
operation method:

```swift
func testSomething() async throws {
    let app = try presentView()

    app.uiTestingElement("dataTextField").type("some text")

    app.uiTestingElement("saveButton").tap()

    let stubOps = try viewModelOperations()

    XCTAssertTrue(stubOps.saveDataCalled)
    XCTAssertEqual(stubOps.data, "some text")
}
```
