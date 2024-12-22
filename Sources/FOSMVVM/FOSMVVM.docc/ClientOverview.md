# Getting Started With FOSMVVM in Client Applications

Quickly and easily connect your MVVM clients to their corresponding servers

## Client Application Initialization

### SwiftUI Environment Configuration

In order to access the server from a client SwiftUI application, an ``MVVMEnvironment`` instance needs to be configured and added to the [SwiftUI Environment](https://developer.apple.com/documentation/swiftui/environment).

#### Base URLs and Application Version

> NOTE: It is suggested that your client application and server application have a shared location to store the current version.  This could be accomplished with a global variable in a library that is shared between the applications and also the tests.
>
> ```swift
> public extension SystemVersion {
>     public static var currentApplicationVersion: Self { .init(
>       major: 1,
>       minor: 2,
>       patch: 3
>     ) }
> ```

At a minimum a base URL should be provided for each ``Deployment`` that is expected to be targeted by the application.

```swift
import FOSFoundation
import FOSMVVM
import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Hello World!")
        }
        .environment(
           MVVMEnvironment(
               currentVersion: .currentApplicationVersion,
               deploymentURLs: [
                  .production, .init(serverBaseURL: URL(string: "http://api.mywebserver.com")!),
                  .staging, .init(serverBaseURL: URL(string: "http://staging-api.mywebserver.com")!),
                  .debug, .init(serverBaseURL: URL(string: "http://localhost:8080")!)
                ]
           )
        )
    }
}
```

### Binding a SwiftUI View to a ViewModel

Once the ``MVVMEnvironment`` has been configured, SwiftUI views can be bound to their corresponding ``ViewModel``s via the ``ViewModelView/bind(viewModel:)`` function.  This will load the required ``ViewModel`` from the server and bind it to the ``RequestableViewModel``.

```swift
@main
struct MyApp: App {
    @State private var viewModel: LandingPageViewModel?

    var body: some Scene {
        WindowGroup {
            LandingPageView.bind(
                viewModel: $viewModel
            )
        }
        .environment(
            MVVMEnvironment(
                currentVersion: .init(
                     major: 1,
                     minor: 0,
                     patch: 0
                ),
                deploymentURLs: [
                  .production, .init(serverBaseURL: URL(string: "http://api.mywebserver.com")!),
                  .staging, .init(serverBaseURL: URL(string: "http://staging-api.mywebserver.com")!),
                  .debug, .init(serverBaseURL: URL(string: "http://localhost:8080")!)
                ]
            )
        )
    }
}
```

### Done!

That is all that needs to be done to communicate between the client and server application!

## Topics

- ``serveroverview``
- ``viewmodelandviewmodelrequest``
- ``ViewModel``
- ``ViewModelRequest``
- ``RequestableViewModel``
- ``ViewModelFactory``
