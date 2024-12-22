# Getting Started With Versioning

Full support for application and View versioning

## Overview


## Thoughts...

What does "versioning" mean?
    - We need to have Application Versions (``SystemVersion``).
    - We need to be able to support different ViewModel layouts (e.g. new/removed properties as the View changes over time).
    - We need to be able to support ViewModels being added and removed over time (e.g. Entire new views and retired views). 

- Possibly versioned ViewModelRequest routes (e.g. /v1/MyViewModel)
    - This is how REST API versioning would normally work, however generally /vxx is thought of as the versioned REST API across all endpoints, no just a single endpoint.
    - What does the route registration look like in this case?

- Possibly add the versioning to the request header and have the controller sort it out
    - Not normally how REST APIs work
    - Does solve the route registration complications

- View Model specification
    - Are ViewModels versioned?
        - No, only properties are versioned.  Since a property can refer to another ViewModel, then, in a sense, VMs can be versioned, but only because the property is versioned; there is no version specification on a ViewModel struct.
    - Is the App Versioned?
        - This must be true as Apple requires App Versions
    - Is the Server API point versioned?
        - No

- Where do we "version"?
    - Application ✅
    - ViewModel? ⛔️
    - ViewModel Property? ✅

- How/when can a VM property be removed from the VM struct?
    - Only on Major version changes.  At this time the end user will be forced to update his application.  The tests will ensure that all properties deprecated in the previous major version will be removed.

## Application / Server Versioning

Versioning stems from ``SystemVersion``, which is the version of the client application that is presented to the end user.  The ``SystemVersion`` is also given to the server application.

At times, the client application and the server application will not be the exact same version.  Here are some reasons why this occurs:

- Client version < Server Version
    - User has not yet updated their application

- Client version > Server Version
    - This can happen when the client application is being approved by the App Store, but not yet released to the customers
    - *If the newest server application is backwards-compatible, it can be deployed before the new app is released.  Thus it is possible to deploy the server before the app is released unless the server is not backwards compatible with all apps in the field.*

## Versioned View Model

extension SystemVersion {
    // My application's versions
    static var v1_0_0: Self { .vInitial }
    static var v2_0_0: Self { .init(major: 2) }
    static var v2_1_0: Self { .init(major: 2, minor: 1) }
    static var v3_0_0: Self { .init(major: 3) }
}

struct UserViewModel: ViewModel {
    @LocalizedString(propertyName: "titles", index: 0, vLast: .v1_0_0) public var firstTitle
    @Versioned(vLast .v1_0_0) public var p1: P1
    @Versioned(vFirst: .v2_0_0) public var p2: P2
    @Versioned(vFirst: .v2_1_0) public var p3: P3
    @Versioned(vFirst: .v3_0_0) public var p4: P4

    let vmId: FOSMVVM.ViewModelId

    // Latest (v3.0.0) initializer
    public init(p2: P2, p3: P3) {
        self.vmid = .init()
        self.p2 = p2
        self.p3 = p3
    } 
}

extension UserViewModel {
    // v1.0.0 Initializer
    init(p1: P1) {
        self.vmId = .init()
        self.p1 = p1
    }

    // v2.0.0 Initializer
    init(p2: P2) {
        self.vmId = .init()
        self.p1 = p1
    } 

    // v2.1.0 Initializer
    init(p2: P2, p3: P3) {
        self.vmId = .init()
        self.p1 = p1
    } 

    // v3.0.0 Initializer
    init(p4: P4) {
        self.vmId = .init()
        self.p4 = p4
    } 
}

## Versioned ViewModel Factory

@VersionedFactory
struct UserViewModel: ViewModelFactory {

// Q: Can we use macros to have versioned builders?  Will that help???
//
// - When VMs are constructed, the initializers change over versions (e.g. new/redacted parameters)
// - There are 2 stages: 1) gathering the parameter values, 2) calling the initializer with those values


    @Version(.v3_0_0)
    static func model(_ req: Vapor.Request, vmRequest: UserVMRequest) async throws -> Self {
        init(p4: try await P4.model(req))
    }

    @Version(.v2_1_0)
    static func model(_ req: Vapor.Request, vmRequest: UserVMRequest) async throws -> Self {
        init(
            p2: try await P2.model(req),
            p3: try await P3.model(req) 
        )
    }

    @Version(.v2_0_0)
    static func model(_ req: Vapor.Request, vmRequest: UserVMRequest) async throws -> Self {
        .init(p2: try await P2.model(req)
    }

    @Version(.v1_0_0)
    static func model(_ req: Vapor.Request, vmRequest: UserVMRequest) async throws -> Self {
        .init(p1: try await P1.model(req))
    }

}

## Versioned Testing

