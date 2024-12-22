# Getting Started With FOSMVVM in Server Applications

Add support for MVVM clients to your **Vapor** servers in no time!

## Server Initialization

### Vapor Web Servers

#### Initializing Localization

To initialize FOS-MVVM in your [Vapor](https://docs.vapor.codes) server add the following code
to your application's initialization routine:

```swift
app.initYamlLocalization(
    bundle: Bundle.module,
    resourceDirectoryName: "Localization"
)
```


#### Initialize the Server Version

The version of the server should be set by adding the following code to your application's initialization routine.  As the version is updated, make sure to update the values.

```swift
SystemVersion.setCurrentVersion(.currentApplicationVersion)

// This setting makes the server *fully* backwards compatible, but
// can be moved forward as older versions are no longer supported. 
SystemVersion.setMinimumSupportedVersion(.vInitial)
```

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

