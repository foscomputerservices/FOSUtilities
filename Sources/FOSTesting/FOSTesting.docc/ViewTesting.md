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

Finally, each View that inherits from ViewModelView must be registered by implementing
the *registerTestingViews* function of *MVVMEnvironment*.

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
}

private extension MyApp {
    var mvvmEnv: MVVMEnvironment {
        let env = MVVMEnvironment(
            appBundle: Bundle.main,
            deploymentURLs: [ /* ... */ ]
        )

        #if DEBUG
        env.registerTestingView()
        #endif

        return env
    }
}

#if DEBUG
private extension MVVMEnvironment {
    // *Every* ViewModelView is listed here to enable individualized
    // testing of each view
    @MainActor func registerTestingViews() {
        registerTestView(MyMainView.self)
        registerTestView(View2.self)

        // ...
        registerTestView(ViewN.self)
    }
}
#endif
```

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
                .accessibilityIdentifier("titleLabel")
            Text(viewModel.summary)
                .accessibilityIdentifier("summaryLabel")
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
    let app = try presentView(viewModel: .stub(title: "Hello"))

    XCTAssertTrue(app.titleLabel.exists)
}

func testShowsSummary() async throws {
    let app = try presentView(viewModel: .stub(summary: "A summary"))

    XCTAssertTrue(app.summaryLabel.exists)
}

private extension XCUIApplication {
    var titleLabel: XCUIElement { staticTexts["titleLabel"] }
    var summaryLabel: XCUIElement { staticTexts["summaryLabel"] }
}
```

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
        .accessibilityIdentifier("dataTextField")

      Button(action: save) {
        Text("Tap Me")
      }
      .accessibilityIdentifier("saveButton")
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
    let app = try await presentView()

    app.dataTextField.tap()
    app.dataTextField.typeText("some text")

    app.saveButton.tap()

    let stubOps = try viewModelOperations()

    XCTAssertTrue(stubOps.saveDataCalled)
    XCTAssertEqual(stubOps.data, "some text")
}

private extension XCUIApplication {
    var dataTextField: XCUIElement {
        textFields.element(matching: .textField, identifier: "dataTextField")
    }

    var saveButton: XCUIElement {
        buttons.element(matching: .button, identifier: "saveButton")
    }
}
```
