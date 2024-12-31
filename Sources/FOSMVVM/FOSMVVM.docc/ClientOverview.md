# Getting Started With FOSMVVM in Client Applications

Quickly and easily connect your MVVM clients to their corresponding servers

## Client Application Initialization

### SwiftUI Environment Configuration

In order to access the server from a client SwiftUI application, an ``MVVMEnvironment`` instance needs to be configured and added to the [SwiftUI Environment](https://developer.apple.com/documentation/swiftui/environment).

#### Base URLs and Application Version

> NOTE: It is suggested that your client and server applications have a shared location to store the current version (see: <doc:Versioning>).
>
> ```swift
> public extension SystemVersion {
>     // My application's current version
>     public static var currentApplicationVersion: Self { .v3_0_0 }
> 
>     // My application's versions
>     public static var v1_0_0: Self { .vInitial }
>     public static var v2_0_0: Self { .init(major: 2) }
>     public static var v2_1_0: Self { .init(major: 2, minor: 1) }
>     public static var v3_0_0: Self { .init(major: 3) }
> }
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

- <doc:ServerOverview>
- <doc:ViewModelandViewModelRequest>
- ``ViewModel``
- ``ViewModelRequest``
- ``RequestableViewModel``
- ``ViewModelFactory``
