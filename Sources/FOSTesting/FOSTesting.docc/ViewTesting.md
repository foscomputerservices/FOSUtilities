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

## Configuring The Application

### Background

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

## Configure the View Model View 

The *testDataTransporter* view modifier is provided to transmit the *ViewModelOperations*
structure back to the test harness.  This modifier should be added to the top of each
*ViewModelView* implementation:

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

## Configuring a Test Base Class

To begin, each framework should configure a base class that contains the configuration
for testing the framework.  This base class should extend the ViewModelViewTestCase
class.

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

## Implementing View Model View Tests

> While there are many ways to implement XCUITests, the patterns presented here
> have proven to provide stable tests over time.

Begin by creating a subclass of the test base class created in the previous step.

```swift
final class MyViewUITests: MyLibraryViewModelViewTestCase<MyViewModel, MyViewModelStubOps>, @unchecked Sendable { }
```

Tests can then be added to test that each button/action calls the expected view model
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
