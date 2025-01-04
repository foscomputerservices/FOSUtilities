# Getting Started With FOSMVVM in Client Applications

Quickly connect your MVVM clients to their corresponding servers

## Client Application Initialization

### SwiftUI Environment Configuration

In order to access the server from a client SwiftUI application, an ``MVVMEnvironment`` instance needs to be configured and added to the [SwiftUI Environment](https://developer.apple.com/documentation/swiftui/environment).

#### Application Version

It is suggested that your client and server applications have a shared location to store the current version (see: <doc:Versioning>).

``MVVMEnvironment`` will automatically default the current version to
 [Bundle](https://developer.apple.com/documentation/foundation/bundle).appleOSVersion on platforms built
from an xcodeproj.  For other applications, the current version must be supplied to ``MVVMEnvironment``
during initialization.

#### Base URLs

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
// Add the following line if the application is not built from an xcodeproj
//             currentVersion: .currentApplicationVersion,
               appBundle: Bundle.main,
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
            let vmBinding = $viewModel

            LandingPageView.bind(
                viewModel: vmBinding
            )
        }
        .environment(
             MVVMEnvironment(
                 appBundle: Bundle.main,
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

That is all that needs to be done to allow a client application to retrieve ``ViewModel``s
from a server application!

## Topics

- <doc:ServerOverview>
- <doc:ViewModelandViewModelRequest>
- ``ViewModel``
- ``ViewModelRequest``
- ``RequestableViewModel``
- ``ViewModelFactory``
