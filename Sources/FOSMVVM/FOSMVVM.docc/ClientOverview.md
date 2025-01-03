# Getting Started With FOSMVVM in Client Applications

Quickly and easily connect your MVVM clients to their corresponding servers

## Client Application Initialization

### SwiftUI Environment Configuration

In order to access the server from a client SwiftUI application, an ``MVVMEnvironment`` instance needs to be configured and added to the [SwiftUI Environment](https://developer.apple.com/documentation/swiftui/environment).

#### Application Version

It is suggested that your client and server applications have a shared location to store the current version (see: <doc:Versioning>).

```swift
public extension SystemVersion {
    // My application's current version
    static var currentApplicationVersion: Self { .v3_0_0 }

    // My application's versions
    static var v1_0_0: Self { .vInitial }
    static var v2_0_0: Self { .init(major: 2) }
    static var v2_1_0: Self { .init(major: 2, minor: 1) }
    static var v3_0_0: Self {
      .init(
          major: 3,
          patch: (try? Bundle.main.appleOSVersion.patch) ?? 0
      )
    }
}
```

The *SystemVersion* startup code will automatically ensure that the application's build number and
the patch number are equal.  Thus, the patch must be set correctly when setting the **current version** number.
Setting the patch number can be done by using the *appleOSVersion.patch* property that is provided as
an extension on [Bundle](https://developer.apple.com/documentation/foundation/bundle).  The 
*appleOSVersion.patch* will only be successful on Apple applications built from an xcodeproj.  For
other applications, the patch needs to be incremented manually.

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
               currentVersion: .currentApplicationVersion,
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
                 currentVersion: .currentApplicationVersion,
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
