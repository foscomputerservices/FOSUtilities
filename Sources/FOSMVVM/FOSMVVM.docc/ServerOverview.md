# Getting Started With FOSMVVM in Server Applications

Add support for MVVM clients to your **Vapor** servers in no time!

## Server Initialization

### Vapor Web Servers

#### Initializing Localization and Versioning

To initialize FOS-MVVM in your [Vapor](https://docs.vapor.codes) server add the following code
to your application's *configure()* routine:

```swift
public func configure(_ app: Application) async throws {
    SystemVersion.setCurrentVersion(.currentApplicationVersion)

    // This setting makes the server *fully* backwards compatible, but
    // can be moved forward as older versions are no longer supported. 
    SystemVersion.setMinimumSupportedVersion(.vInitial)

    try app.initYamlLocalization(
        bundle: Bundle.module,

        // See: 'Locating the Resource Directory Name' below
        resourceDirectoryName: "Localization"
    )
}
```

> NOTE: It is suggested that your client and server applications have a shared location to store the current version (see: <doc:Versioning>).

#### Initializing Routes

Register each ``ServerRequest`` whose `ResponseBody` is a `VaporResponseBodyFactory` on a route group,
passing the `Application` — one door for every request. The group you register on decides the middleware
that guards the route: mount privileged requests behind your credential group, public ones on the
`Application` itself (an `Application` is a `RoutesBuilder`):

```swift
func routes(_ app: Application) throws {
    let authed = app.grouped(ClientCredentialMiddleware(verifier: myVerifier))
    try authed.register(request: DashboardPageRequest.self, app: app)
    try app.register(request: LandingPageRequest.self, app: app)
}
```

Registration derives and validates each composable request's data-load plan at boot, so a forgotten or
unresolvable data need fails fast at startup rather than at request time. Write requests
(`CreateRequest`/`UpdateRequest`/`DeleteRequest`) register the same way — Swift selects the write door.
Where a request mounts is your decision; that its plan is derived is not.

Mount only on **middleware-only** groups (`app.grouped(middleware)`): a path-prefixing group
(`app.grouped("admin")`) would change the served URL while clients derive it from the request type, so
registration rejects that at boot.

**Data-scoping still applies:** the framework loads only the records the current subject is
authorized for, through the app's registered `ContainerAuthorizationProvider` — the projection is handed
an already-auth-scoped, read-only cache and cannot load anything else. Register the provider (and the
app's containers) before registering requests.

### Manual Initialization

To initialize FOS-MVVM in non-Vapor servers, add the following code
to your application's initialization routine:

```swift
SystemVersion.setCurrentVersion(.currentApplicationVersion)

// This setting makes the server *fully* backwards compatible, but
// can be moved forward as older versions are no longer supported. 
SystemVersion.setMinimumSupportedVersion(.vInitial)

let localizationStore = try await Bundle.module.yamlLocalization(
    resourceDirectoryName: "Localization"
)
```

### Locating the Resource Directory Name

The *resourceDirectoryName* should be set to the same name as specified in the application's Package.swift target:

```swift
.target(
    name: "MyApp",
    dependencies: [
        // ...
    ],
    resources: [
        .copy("Localization") // <--- resourceDirectoryName
    ]
)
```

> This example shows that all localization (YAML) files can be found under Sources/MyApp/Localization.

## Interactive ViewModels

When a ``ViewModel`` the server publishes backs an interactive View (buttons, forms,
toggles that dispatch user actions), its client-side companion is a
``ViewModelOperations`` implementation that dispatches a ``ServerRequest`` back to the
server. Server-backed operations take **no** `output:` parameter — the server owns storage
through the Vapor request context — and are typically `async throws` because the body
awaits network I/O. See <doc:Operations> for the complete server-backed Operations shape,
contrasted with the client-hosted shape.

## Topics

- <doc:Operations>
- <doc:ViewModelandViewModelRequest>

