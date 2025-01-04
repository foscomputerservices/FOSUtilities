# Getting Started With Versioning

Full support for application and View versioning

## Overview

As applications evolve over time, user interfaces change.  Sometimes the changes are small and incremental and other
times the changes are large and revolutionary.  At the same time, users do not always (and sometimes cannot) update
the application on their devices.  So, while the application provider can ensure that the servers are always
up-to-date, they cannot directly ensure that of their customers.  This is where application versioning is important.

## What Is a Version?

Versioning is a formal specification of the configuration of the application and its related systems.  Versioning
provides for the ability to ensure compatibility between these systems.  This compatibility is ensured not just
at run time, but also during the development and testing phases of the various systems.  This provides for robust
automated [Continuous Integration](https://en.wikipedia.org/wiki/Continuous_integration) testing and deployment.

## Formally Specifying Versions

The *SystemVersion* type in FOSFoundation provides a mechanism for specifying versions.  By extending this type
with static properties, formal definitions of versions can be specified.

It is suggested that your client and server applications have a shared location to access the current version.
Typically this would be accomplished in a library that is shared between them. 

```swift
import FOSFoundation

public extension SystemVersion {
    // My application's current version
    public static var currentApplicationVersion: Self { .v3_0_0 }

    // My application's versions
    public static var v1_0_0: Self { .vInitial }
    public static var v2_0_0: Self { .init(major: 2) }
    public static var v2_1_0: Self { .init(major: 2, minor: 1) }
    public static var v3_0_0: Self { .init(major: 3, patch: 1) }
}
```

The naming of these properties is only suggested.  If there are more appropriate names in your domain, feel free
to use your own naming scheme.

## Application / Server Versioning

Versioning stems from *SystemVersion* (FOSFoundation), which is the version of the client application that
is presented to the end user.  The *SystemVersion* is also given to the server application, which defines the
latest version of the apis supported by the server.

At times, the client application and the server application will not be the exact same version.  Here are some reasons why this occurs:

- Client version < Server Version
    - User has not yet updated their application

- Client version > Server Version
    - This can happen when the client application is being approved by the App Store, but not yet released to the customers
    - *If the newest server application is backwards-compatible, it can be deployed before the new app is released.  Thus it is possible to deploy the server before the app is released unless the server is not backwards compatible with all applications in the field.*

> The client application's UI/Views can **always** expect to use the latest version when they
> are being written.  The UI/Views **never** need to be backwards compatible.
>
> This does **not** apply to the ``ViewModel``s, however, because the ``ViewModel`` implementations are used
> by the server to deliver backwards compatible versions of the ``ViewModel``s.

## Versioned View Model

As applications evolve, their user interfaces will change accordingly.  This necessitates that the ``ViewModel``s
change accordingly.  However it is important to remember that ``ViewModel``s are contracts between the client and
the server and that the client and server might have differing version requirements.

### Versioned Properties

Since the ``ViewModel``s are used by the server to generate the JSON that is sent to the client, the ``ViewModel``s
need to support all of the versions of the ``ViewModel`` that the server needs to support to support older
clients that have not yet been updated.  To enable this support, the *@Localized...* property wrappers have
*vFirst* and *vLast* properties that can be specified to indicate for which version that property is needed.
For non-localized properties, the *@Versioned* property wrapper is available to specify the versions.

It is not required to use either of these property wrappers, in which case, the property will be assumed
to be required by all versions of the ``ViewModel``.  If at some version in the future the property is no
longer needed, the *@Versioned* property wrapper can be added indicating the last version that requires
the property.

### Versioned Initializers

Each concrete version of the ``ViewModel`` must maintain an *init* method that initializes that
version of the ``ViewModel``.

> There's no need for the initializer to set versioned properties
> that are not used by that version; they'll be automatically initialized by the versioned property wrapper
> using the *Stubbable* protocol.  Additionally only property values that are required by the version
> will be transmitted between the server and the client.

```swift
public struct UserViewModel: ViewModel {
    @LocalizedString(propertyName: "titles", index: 0, vLast: .v1_0_0) public var firstTitle
    @Versioned(vLast .v1_0_0) public var p1: P1
    @Versioned(vFirst: .v2_0_0, vLast: .v2_1_0) public var p2: P2
    @Versioned(vFirst: .v2_1_0) public var p3: P3
    @Versioned(vFirst: .v3_0_0) public var p4: P4
    public let pRequired: PRequired

    public let vmId: FOSMVVM.ViewModelId

    // Latest (v3.0.0) initializer
    public init(p3: P3, p4: P4, pRequired: PRequired) {
        self.vmId = .init()
        self.p3 = p3
        self.p4 = p4
        self.Required = pRequired
    } 
}

public extension UserViewModel {
    // v1.0.0 Initializer
    init(p1: P1, pRequired: PRequired) {
        self.vmId = .init()
        self.p1 = p1
        self.Required = pRequired
    }

    // v2.0.0 Initializer
    init(p2: P2, pRequired: PRequired) {
        self.vmId = .init()
        self.p1 = p1
        self.Required = pRequired
    } 

    // v2.1.0 Initializer
    init(p2: P2, p3: P3, pRequired: PRequired) {
        self.vmId = .init()
        self.p1 = p1
        self.Required = pRequired
    } 
}
```

## Versioned ViewModel Factory

``ViewModelFactory``s implement the functionality in the server to create the correct version of the
``ViewModel`` instance that is required by the client.  This is accomplished much in the same way as
in the ``ViewModel``.  Versioned overloads of static methods are maintained for each version of the
``ViewModel``.

The ``VersionedFactory()`` and ``Version(_:)`` macros are provided to keep an orderly progression
of the versioned methods.  They work together to generate the ``ViewModelFactory/model(_:vmRequest:)``
method in a way that will respect the versioning requirements of the requesting client application.

> There is no absolute naming scheme requirement for the versions or method names, but keeping
> them aligned makes for more readable and understandable code.

```swift
@VersionedFactory
extension UserViewModel: ViewModelFactory {

    // NOTE: No direct implementation of ViewModelFactory.  The implementation is generated by
    //       the @VersionedFactory macro.

    @Version(.v3_0_0)
    static func model_3_0_0(_ req: Vapor.Request, vmRequest: UserVMRequest) async throws -> Self {
        init(p4: try await P4.model(req))
    }

    // NOTE: All older factory methods **must** remain in the extension marked with the
    //       @VersionedFactory macro.

    @Version(.v2_1_0)
    static func model_2_1_0(_ req: Vapor.Request, vmRequest: UserVMRequest) async throws -> Self {
        init(
            p2: try await P2.model(req),
            p3: try await P3.model(req) 
        )
    }

    @Version(.v2_0_0)
    static func model_2_0_0(_ req: Vapor.Request, vmRequest: UserVMRequest) async throws -> Self {
        .init(p2: try await P2.model(req)
    }

    @Version(.v1_0_0)
    static func model1_0_0(_ req: Vapor.Request, vmRequest: UserVMRequest) async throws -> Self {
        .init(p1: try await P1.model(req))
    }

}
```

> At first glance this might seem like a lot of work.  However, in practice, when new versions are introduced,
> the existing method is maintained and a new one is added.  Thus, the work is incremental in nature
> and, if the guidance here is followed, it's completely composable.

## Versioned Testing

Tools are provided in **FOSTesting** to automatically ensure that all versions of a ``ViewModel`` are usable. 

## Application Versions

### iOS, iPadOS, tvOS, visionOS, macOS

Apple expects App Store applications to set their version numbers in their corresponding .xcodeproj files.
It is required that these values be manually specified in the application's .xcodeproj.

This can be accomplished in Xcode by selecting the application at the top of Xcode's Project Navigator tab.  Then
by selecting the General tab.  At the left, under TARGETS select the application target.  Finally update the
Version field in the Identity section.

This value is available from the application's bundle via *Bundle.main.appleOSVersion*.  ``MVVMEnvironment``
automatically sets the client application's *SystemVersion.currentVersion* to this value.

![Xcode Example](SettingApplicationVersion)

It is recommended that the Build number be automatically maintained.  There are numerous ways to accomplish this
and each team will have differing requirements.  Some ideas can be found on
[StackOverflow](https://stackoverflow.com/q/9258344).
