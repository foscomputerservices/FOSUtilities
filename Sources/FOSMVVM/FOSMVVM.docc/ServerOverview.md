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

For each ``ViewModel``, an entry needs to be added to the servers [Routing](https://docs.vapor.codes/basics/routing/):

```swift
func routes(_ app: Application) throws {
    let routes = app.routes

    try routes.register(model: LandingPageViewModel.self)

    let secureRoutes = routes
        .grouped(AuthMiddleware())
    try secureRoutes.register(model: DashboardPagePageViewModel.self)
}
```

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

