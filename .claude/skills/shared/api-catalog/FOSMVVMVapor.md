# FOSMVVMVapor API Catalog

Curated map of FOSMVVMVapor's public API, organized by task — the server side
of FOSMVVM (macOS/Linux only): registering ViewModel routes, wiring the YAML
localization store into the application lifecycle, extracting typed
ServerRequest pieces from Vapor requests, and binding Fluent models to the
MVVM roles. Before hand-writing a route, query parser, version check, or error
response — check here first. The through-line: localization *is* encoding, so
ViewModels are localized while the response is built — every JSON serving path
here funnels through the request's localizing encoder.

## Extensions

FOSMVVM's wiring grafted onto Vapor's Application, Request, Response, and
Environment: boot-time localization-store and MVVMEnvironment initialization,
deployment selection, per-request typed query / CRUD-action / client-version /
locale extraction plus the request-scoped localizing encoder, localized JSON
response building with version headers, Fluent schema naming and
save-time validation for Model types, body-size bridging into Vapor's types,
and Leaf rendering of Localizable values. (An internal string pluralizer
backs the schema derivation.)

### Wire the localization store at boot — `initYamlLocalization()` / `localizationStore` / `requireLocalizationStore()`
Reach for this when: configuring the Vapor application — every localized
response needs the store, so call this in `configure(_:)`. It registers a
lifecycle handler that loads the YAML store before boot and also arranges the
FOSMVVM React/WASM client-integration files to be served; afterwards the store
hangs off the Application (`requireLocalizationStore()` throws
`YamlStoreError.noLocalizationStore` when it's absent).
Gotcha: loading happens in an *async* lifecycle handler — VaporTesting's tester
boots synchronously, so tests must call `app.asyncBoot()` first.

```swift
try app.initYamlLocalization(bundle: .module, resourceDirectoryName: "Localization")
let store = try app.requireLocalizationStore() // after boot
```

### Establish the MVVMEnvironment at boot — `initMVVMEnvironment()` / `mvvmEnvironment` / `serverBaseURL`
Reach for this when: the server itself needs an MVVMEnvironment (catalogued in
FOSMVVM's SwiftUI Support) — e.g. a WebApp whose pages issue ServerRequests.
Registers a lifecycle handler; after boot `serverBaseURL` is the
deployment-resolved base URL. Accessing `serverBaseURL` before initialization
is a programmer error and traps.

```swift
try await app.initMVVMEnvironment(mvvmEnvironment)
let baseURL = app.serverBaseURL // after boot
```

### Select the server's deployment — `deployment`
Reach for this when: server code branches on production/staging/debug — the
Vapor Environment carries FOSMVVM's Deployment (catalogued in FOSMVVM's
Versioning). Process-wide and defaults to `.debug`; assign it during
`configure(_:)`. Unlike the client side, there is no automatic detection here —
the server states its deployment explicitly.

```swift
app.environment.deployment = .production
```

### Read the typed query off a Vapor request — `serverRequestQuery()` / `requireServerRequestQuery()`
Reach for this when: a hand-written route handler needs the request's
ServerRequestQuery — decodes the URL's query exactly as the client's
`processRequest()` encoded it. Requests whose Query is EmptyQuery yield nil;
`require...` turns a missing query into `Abort(.badRequest)`.
Don't parse `req.url.query` yourself — and note that routes registered via
`register()` (see Vapor Support) already bind the query for you.

```swift
let query = try req.requireServerRequestQuery(ofType: UserViewModelRequest.Query.self)
```

### Map a Vapor request to its CRUD action — `requestAction()` / `ServerRequestActionError`
Reach for this when: shared middleware or a multi-action controller must know
*which* ServerRequestAction (FOSMVVM's Protocols) an incoming request is —
the HTTP method and URI map onto `.show`/`.create`/`.update`/`.replace`/
`.delete`/`.destroy`; unroutable methods throw `ServerRequestActionError`.

```swift
switch try req.requestAction() {
case .create: // ...
```

### Check the calling client's version — `applicationVersion()` / `requireCompatibleAppVersion()`
Reach for this when: a route or factory needs the *client's* SystemVersion
(catalogued in FOSFoundation) — `applicationVersion()` reads it from the
versioning header; `requireCompatibleAppVersion()` rejects incompatible
clients with a typed SystemVersionError. Prefer gating whole route groups with
`RequireVersionedAppMiddleware` (see Middleware); reach for these directly in
versioned factories.

```swift
try req.requireCompatibleAppVersion()
let clientVersion = try req.applicationVersion()
```

### Localize per the request — `locale` / `requireLocale()` / `localizingEncoder`
Reach for this when: serving anything Localizable by hand — `locale` converts
the Accept-Language header to a Locale (nil when missing;
`requireLocale()` throws), and `localizingEncoder` combines that locale with
the application's store into FOSMVVM's localizing encoder.
Don't build the encoder from parts — and note `buildResponse()` (below) and
the default ViewModel serving path already encode through it for you.

```swift
let locale = try req.requireLocale()
let encoder = try req.localizingEncoder
```

### Build a localized JSON response — `buildResponse()` / `addSystemVersion()` / `addJSONContentType()`
Reach for this when: a route handler produced a ServerRequestBody (FOSMVVM's
Protocols) and must return a Vapor Response — `buildResponse(req)` encodes it
through the request's localizing encoder, stamps the server's SystemVersion
header, and sets the JSON content type. The `add...` helpers decorate
hand-built Responses the same way.
Don't encode a ViewModel with a plain encoder — the client would receive
still-`localizationPending` values.

```swift
return try responseBody.buildResponse(req)
```

### Fluent table names and save-time validation — `schema` / `validateModel()`
Reach for this when: a type carries both FOSMVVM's Model role and Fluent's —
`schema` is derived automatically (pluralized snake_case: UserAccount →
"user_accounts"; declare `static let schema` to override, as the
`fosmvvm-fluent-datamodel-generator` skill does), and `validateModel(on:)`
runs the ValidatableModel rules and throws *before* you persist.

```swift
try await user.validateModel(on: db).save(on: db)
```

### Render Localizable values in Leaf — `leafData`
Reach for this when: a Leaf template (WebApp pages; see the
`fosmvvm-leaf-view-generator` skill) prints a ViewModel property — every
Localizable value type (LocalizableString, LocalizableDate, LocalizableInt,
LocalizableDouble, LocalizableArray, LocalizableCompoundValue,
LocalizableSubstitutions — all catalogued in FOSMVVM) renders as its localized
string. Values that were never localized render as an empty string — localize
the ViewModel before handing it to the template by round-tripping it through
the request's localizing encoder (FOSMVVM's `localizingEncoder()` entry shows
the round-trip).

```swift
// In the Leaf template — renders the localized string, not a debug dump:
// <h1>#(viewModel.pageTitle)</h1>
```

### Bridge body-size limits into Vapor — `vaporByteCount`
Reach for this when: a hand-written route must honor a ServerRequestBody's
`maxBodySize` (FOSMVVM's Protocols) — converts it to Vapor's ByteCount for a
body-collection strategy. `ServerRequestController` routes (see Vapor Support)
apply the limit for you.

```swift
routes.on(.POST, body: .collect(maxSize: FileUploadBody.maxBodySize?.vaporByteCount)) { req in ... }
```

## Middleware

Two middlewares that belong on every FOSMVVM route group: typed, localized
error responses and client-version gating.

### Serve errors typed and localized — `ErrorMiddleware`
Reach for this when: configuring the application's error handling — use
`.default(environment:)` in place of Vapor's stock error middleware. Encodable
errors (ValidationError, a request's ResponseError) are encoded through the
request's localizing encoder and returned as the response body, so the client
decodes them back into the ServerRequest's typed `ResponseError` and throws
them in context (form validation, for example); other errors degrade to
status + reason, hiding details in release builds.
Don't keep Vapor's stock ErrorMiddleware — it flattens typed ResponseErrors
into plain-text reasons the client cannot decode.

```swift
app.middleware.use(ErrorMiddleware.default(environment: app.environment))
```

### Gate routes on client version — `RequireVersionedAppMiddleware`
Reach for this when: a route group must only serve version-compatible clients —
wraps `requireCompatibleAppVersion()` (see Extensions) so out-of-date
applications are rejected before any handler runs.

```swift
let versionedGroup = app.grouped(RequireVersionedAppMiddleware())
try versionedGroup.register(viewModel: LandingPageViewModel.self)
```

## Protocols

The server-side contracts: the Vapor ViewModel factory and its context,
self-resolving ViewModel requests, hand-rolled controllers with derived
routing paths, and the Fluent-backed Model role.

### Project the database into a ViewModel — `VaporViewModelFactory` / `VaporModelFactoryContext`
Reach for this when: writing the server-side factory for a
RequestableViewModel (FOSMVVM's Protocols) — the DIP seam where Fluent models
become ViewModels. The context carries the Vapor Request (`req` — database,
auth), the typed `vmRequest` (its query), and the client's `appVersion` for
versioned factories (`@VersionedFactory`, FOSMVVM's Macros). The default
`encodeResponse` serves the ViewModel *localized* to the request's
Accept-Language via `buildResponse()`. Scaffolded by
`fosmvvm-viewmodel-generator`; tested end-to-end by FOSTestingVapor's
VaporServerRequestTest.
Don't write a per-type `encodeResponse` — localization-on-serve has exactly
one home, and re-implementing it is the red flag that it leaked.

```swift
extension UserViewModel: VaporViewModelFactory {
    public static func model(context: VaporModelFactoryContext<Request>) async throws -> Self {
        let db = context.req.db
        // query Fluent via context, then project into the ViewModel
        return .init(user: user)
    }
}
```

### Let a request resolve itself — `ResolvableViewModelRequest`
Reach for this when: a ViewModelRequest is served through a hand-rolled
`Controller` (below) rather than `register()` — the request itself knows how
to produce its ResponseBody from the Vapor Request.

```swift
extension UserViewModelRequest: ResolvableViewModelRequest {
    func model(req: Request) async throws -> UserViewModel { /* fetch + project */ }
}
```

### Hand-rolled controllers with derived paths — `Controller` / `ControllerRouting`
Reach for this when: a RouteCollection needs custom route layouts that
`register()` and `ServerRequestController` don't cover — `ControllerRouting`
derives each action's path from the controller's `baseURL` (create/delete/
destroy gain their own segment; an Encodable query can be appended), and
`Controller.modelResponse()` serves a `ResolvableViewModelRequest`'s ViewModel
as a localized response.

```swift
let path = try UserController.path(for: .show, userId)
return try await Self.modelResponse(req, for: resolvableRequest)
```

### The Fluent persistence role — `DataModel`
Reach for this when: declaring a database-backed entity — composes FOSMVVM's
Model + ValidatableModel with Fluent's Model, so one class is the persistence
type behind the ViewModel factories, with derived `schema` naming and
`validateModel()` (see Extensions). Scaffolded — with migrations and tests —
by the `fosmvvm-fluent-datamodel-generator` skill. Remember: ModelIdType
belongs only at `@ID`; other references go through junction tables.

```swift
final class User: DataModel, UserFields, Hashable, @unchecked Sendable {
    static let schema = "users"
    @ID(key: .id) var id: ModelIdType?
    @Field(key: "name") var name: String
    // init()s, validate(fields:validations:), ...
}
```

## Vapor Support

The routing layer that turns request types into live routes: one-line
ViewModel registration for reads, and the write-side controller protocol
(the request-binding host and middleware behind them are internal).

### Register a ViewModel route — `register()`
Reach for this when: exposing a RequestableViewModel over HTTP — one line per
ViewModel in `routes(_:)`. The ViewModel must be a `VaporViewModelFactory`;
the route's path derives from the request type, so client and server can never
disagree on it, and the handler binds the typed query and serves the factory's
ViewModel localized.
Don't register GET routes with string paths for ViewModels — and gate access
with `.grouped(SomeMiddleware())`, never `.grouped("path")`, which adds a
segment the type-derived client resolver cannot reproduce.

```swift
try app.routes.register(viewModel: LandingPageViewModel.self)
```

### Host CRUD writes — `ServerRequestController` / `ServerRequestControllerError`
Reach for this when: serving a CreateRequest/UpdateRequest/ReplaceRequest
(FOSMVVM's Protocols) — declare the request type and map each action to a
processor; `boot()` registers the POST/PATCH/PUT route at the request's
derived path, decodes the RequestBody (honoring `maxBodySize`), and returns
the processor's ResponseBody localized. Only `.create`, `.update`, and
`.replace` are hostable — reads go through `register()` above; anything else
throws `ServerRequestControllerError.invalidAction`. Scaffolded by
`fosmvvm-serverrequest-generator`; tests by
`fosmvvm-serverrequest-test-generator`.

```swift
final class UserCreateController: ServerRequestController {
    typealias TRequest = UserCreateRequest
    let actions: [ServerRequestAction: ActionProcessor] = [
        .create: UserCreateRequest.performCreate
    ]
}
// in routes(_:): try app.routes.register(collection: UserCreateController())
```
