# Getting Started With Application State in Client Applications

Communication Between Views

## Overview

This document discusses SwiftUI applications that store state locally as opposed to on a
remote web service.  If your application stores all of its state in a web service, this material
can be skipped.

## What is Application State (App State)?

Application state consists of any data that is used by the application to determine
which views should be presented and even the data that is presented in the views.

```swift
@Observable final class AppState: Codable {
    var deviceId: String?
    var isDeviceConnected: Bool { deviceId != nil }
}

struct MyView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.isDeviceConnected {
            // Show device screen
        } else {
            // Show connect to device screen
        }
    }
}
```

This application state can even be persisted on the application device so that
each time the application launches, the application returns to the state that it
was in when the user quit the application.

```swift
struct MyView: View {
    @SceneStorage("MyScene") private var appState = AppState()

    var body: some View {
        if appState.isDeviceConnected {
            // Show device screen
        } else {
            // Show connect to device screen
        }
    }
}
```

## Communicating Between Views

### SwiftUI Challenges

SwiftUI provides the  [Environment](https://developer.apple.com/documentation/swiftui/environment) - Communication "down" the view hierarchy.  When employing MVVM techniques, however, using these mechanisms leads to a few issues:

- There are now multiple sources of "truth" for the view
    1. The ViewModel
    1. The Environment
- Server-state-based applications cannot rely on the environment as they have no access to the environment.  Thus, for applications that have a combination of client-side and server-side views, there will be two different methods being employed for surfacing this state, which will not compose well.
    1. Client-side views - SwiftUI Environment
    1. Server-side views - ``ViewModel``
- Testing the view in isolation becomes more challenging as there are, again, multiple sources of data and can no longer rely solely on *Stubbable*
    - **Corollary**: SwiftUI Previews become more challenging to configure/maintain 
- Localization of the values can be bypassed

### MVVM AppState

To solve these issues, ``FOSMVVM`` suggests surfacing all Application State to the
view in the ``ViewModel`` and avoid using the SwiftUI Environment.  This state is
provided to the ``ViewModel`` via the ``ViewModelFactory``.

Here is an example of a view that wants to display some App State in a localizable
string:

```swift
struct DeviceView: View {
    let viewModel: DeviceViewModel

    var body: some View {
        Text(viewModel.deviceTitle) // Displays: "Device Id: device-123"
            .accessibilityIdentifier("deviceText", isEnabled: true)
    }
}


#Preview {
    DeviceView
        .previewHost() // <- No environment necessary
}
```

The ``ViewModel`` for this would be as follows:

```swift
@ViewModel(options: [.clientHostedFactory]) struct DeviceViewModel {
    @LocalizedSubs(substitutions: \.subs) public var deviceTitle
    private let substitutions: [String: LocalizableString]

    init(deviceId: String) {
        self.substitutions = [
            "deviceId": LocalizableString.constant(deviceId)
        ]
    }

    static func stub() -> Self {
        .stub(deviceId: "test-1234")
    }

    static func stub(deviceId: String) -> Self {
        .init(deviceId: deviceId)
    }
}

```

And the corresponding YAML:

```yaml
en:
  DeviceViewModel:
    deviceTitle: "Device Id: %{deviceId}"
```

The ``ViewModelFactory`` for DeviceViewModel would be as follows:

> @ViewModel Macro
>
> By using the @ViewModel(options: [.clientHostedFactory]) macro, the 
> ``ClientHostedViewModelFactory`` and ``ViewModelRequest`` are generated
> automatically for you and there is no need to code them by hand.
> These examples are provided only to demonstrate what is going on behind
> the scenes.

```swift
extension DeviceViewModel: ClientHostedViewModelFactory {
    public struct AppState: Hashable, Sendable {
        public let deviceId: String

        public init(deviceId: String) {
            self.deviceId = deviceId
        }
    }

    public static func model(
        context: ClientHostedModelFactoryContext<Request, AppState>
    ) async throws -> DeviceViewModel {
        .init(deviceId: context.appState.deviceId)
    }
}

public final class DeviceViewModelRequest: ViewModelRequest {
    public let responseBody: DeviceViewModel?

    public init(
        query: EmptyQuery?,
        fragment: EmptyFragment? = nil,
        requestBody: EmptyBody? = nil,
        responseBody: DeviceViewModel?
    ) {
        self.responseBody = responseBody
    }
}
```

Finally, the call site that hosts this view:

```swift
@Observable final class AppState: Codable {
    var deviceId: String?
}

struct MyView: View {
    @SceneStorage("MyScene") private var appState = AppState()

    var body: some View {
        if let deviceId = appState.deviceId {
            DeviceView.bind(
                appState: .init(deviceId: deviceId)
            )
        } else {
            // Show connect to device screen
        }
    }
}
```

When testing the view, the application state can now be provided via the
stub:

```swift
final class MyViewUITests: MyViewModelViewTestCase<DeviceViewModel, DeviceViewModelStubOperations>, @unchecked Sendable {
    func testShowDeviceId() async throws {
        let testId = "test-abc-1234"
        let app = try await presentView(viewModel: .stub(deviceId: testId))

        let text = app.staticTexts.element(matching: .staticText, identifier: "deviceText")
        XCTAssertEqual(text.value as? String, testId)
    }
}
```
