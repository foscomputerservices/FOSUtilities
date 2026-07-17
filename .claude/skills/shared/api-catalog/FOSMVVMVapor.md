# FOSMVVMVapor API Catalog

Curated map of FOSMVVMVapor's public API, organized by task — the server side
of FOSMVVM (macOS/Linux only): registering request routes, wiring the YAML
localization store into the application lifecycle, extracting typed
ServerRequest pieces from Vapor requests, binding Fluent models to the MVVM
roles, and executing the container-load engine (authorized, sorted, paginated
loads projected into response bodies through a read-only context). Before
hand-writing a route, query parser, version check, containment load, or error
response — check here first. The through-line: localization *is* encoding, so
response bodies are localized while the response is built — every JSON serving
path here funnels through the request's localizing encoder.

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

### Read the client's chosen sort off a Vapor request — `serverRequestSort()`
Reach for this when: a hand-written route handler needs the request's sort — the
mirror of `serverRequestQuery(ofType:)` for FOSMVVM's `ServerRequestSort`. Requests
whose Sort is `EmptySort` yield nil; the value round-trips exactly as the client
encoded it. Routes registered via `register()` (see Vapor Support) bind the sort for
you.

```swift
let sort = try req.serverRequestSort(ofType: SortCriteria<BerthSortKey>.self)
```

### Register a container and the authorization provider — `useContainerAuthorizationProvider`
Reach for this when: wiring containment in `configure(_:)`. `register(_:migration:)`
adds a `ContainerDataModel`'s Fluent migration **and** its identity descriptor in one
call — declaring the migration *is* registering the type. `useContainerAuthorizationProvider(_:)`
installs the app's `ContainerAuthorizationProvider` (see Protocols) so every framework
load is auth-scoped. Both throw at boot on misconfiguration (duplicate namespace,
containment drift, a second provider) rather than at first request.

```swift
try app.register(Dock.self, migration: Dock.CreateDock())
try app.useContainerAuthorizationProvider(GrantProvider())
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

Three middlewares for FOSMVVM route groups: typed, localized error
responses, client-version gating, and client-credential verification.

### Serve errors typed and localized — `ErrorMiddleware`
Reach for this when: configuring the application's error handling — use
`.default(environment:)` in place of Vapor's stock error middleware. Encodable
errors (ValidationError, a request's ResponseError) are encoded through the
request's localizing encoder and returned as the response body, so the client
decodes them back into the ServerRequest's typed `ResponseError` and throws
them in context (form validation, for example); other errors degrade to
status + reason, hiding details in release builds. An error that is both
`Encodable` and `AbortError` is served with its typed body and its own status
and headers (e.g. `CredentialRejectedError` → 401 + `WWW-Authenticate`).
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
try versionedGroup.register(collection: ReplaceBerthController())
```

### Verify the caller's credential — `ClientCredentialMiddleware` / `ServerCredentialVerifier` / `BearerCredentialVerifier`
Reach for this when: a route group must reject unauthenticated callers and the
app owns the validity rule — the server complement of FOSMVVM's
`ClientCredentialProvider` (the client attaches the credential, this verifies
it). Supply the rule as a `ServerCredentialVerifier` (throw to reject, return
to admit); the stock `BearerCredentialVerifier` extracts `Authorization:
Bearer` and asks your `isValid` closure (compare digests or constant-time —
never `==` on raw secrets). Missing or invalid → 401 with `WWW-Authenticate`.
A rejection reaches a FOSMVVM client as the typed `CredentialRejectedError`
(requires FOS `ErrorMiddleware.default`, the documented configuration) — catch
it, never branch on the 401. Verifiers throw it directly (code + challenge);
any other verifier throw is wrapped as `.invalid`; a thrown `CancellationError`
propagates unchanged, never as `.invalid`.

```swift
let protected = app.grouped(ClientCredentialMiddleware(
    verifier: BearerCredentialVerifier { token in await tokens.isCurrent(token) }))
```

## Containment

The container-load engine's author-facing surface: the Fluent-backed container
declaration and its authorization-bearing relations, the sort-mapping
declaration, the read-only projection context handed to a factory's
`body(context:)`, and the boot-time registration of per-request app state and
the apex-container root resolver. These execute the declarations authored with
FOSMVVM's `Container` / `ComposableFactory` / `LoadRequirement` surface (see
`FOSMVVM.md § Protocols`).

### Read the loaded records inside a projection — `ProjectionContext`
Reach for this when: writing a `VaporResponseBodyFactory`'s `body(context:)` (see
Protocols) — the context is everything the projection may see: the typed `vmRequest`,
the app-declared `appState`, the client's `appVersion`, and `records(_:)` — typed reads
of what the plan loaded, keyed by the SAME static `LoadRequirement` handle the factory
declared (a parent may read a child's handle — that is how composition works). A handle
that never reached the plan **throws** (naming the handle and request), never returns
`[]`. Treat the records as read-only.
Don't let the context escape the projection (no capturing it in a spawned `Task`) — its
reads are contracted to the request's handler task.

```swift
let berths = try context.records(Self.berths)              // own handle
let crew   = try context.records(CrewListViewModel.crew)   // a child's
return .init(..., signedInAs: context.appState.userName)
```

### Declare a Fluent container's authorization-bearing relations — `ContainerDataModel` / `ContainmentRelation`
Reach for this when: a Fluent `DataModel` is also a `Container` (FOSMVVM's Protocols)
and you must state which of its relationships are authorization-bearing containment.
Build each relation from the model's own `@Children` / `@Siblings` / `@Parent` KeyPath —
cardinality and joins come from Fluent, so you never restate a foreign key or pivot
table. List only the relationships a subject can be *authorized to*. The declared record
types must match `Container.containedRecordTypes` — `register(_:migration:)` (see
Extensions) verifies both agree at boot.
Don't list every Fluent relationship — not all of them are containment.

```swift
extension Dock: ContainerDataModel {
    static var containment: [ContainmentRelation] {
        [.children(\Dock.$berths), .siblings(\Dock.$crew)]   // Dock owns Berths (FK) and Crew (pivot)
    }
}
```

`.parent(_:)` declares a to-one containment (the record references its parent by
foreign key); a `.parent` relation is not a create scope.

### Map published sort meanings to database ordering — `SortableDataModel` / `SortMapping`
Reach for this when: the framework must turn a request's `SortCriteria` (FOSMVVM's
Protocols) into database ordering for a model. Declare, once, how each published
`SortKey` meaning becomes one or more Fluent field orderings; several mappings make a
composite/tiebreak order. Column names never reach the wire, so renaming a field is
invisible to clients. `RequestSortKey` is the model's single published sort vocabulary,
shared by every request that sorts it.

```swift
extension Berth: SortableDataModel {
    static func sortMappings(for key: BerthSortKey) -> [SortMapping<Berth>] {
        switch key {
        case .number:   [.keyPath(\Berth.$number)]
        case .dockName: [.keyPath(\Berth.$dockName), .keyPath(\Berth.$number)]  // tiebreak
        }
    }
}
```

### Narrow a container load by the request's query — `FilterableDataModel`
Reach for this when: a request should load only the records matching its query (a
search box, a filtered list) instead of the whole container — conform the Fluent
model and translate the request's own `ServerRequestQuery` (FOSMVVM's Protocols)
to a Fluent `WHERE`, by hand, in `apply(filter:to:)`. The framework rides that
filter into the one query it counts, paginates, and caches, so counts and windows
reflect the narrowed set. `Filter` is the single query type this model narrows by —
a request whose query is a different type loads the model unfiltered. Return the
query unchanged when there's nothing to narrow by — never a silent match-nothing.
Don't invent a filter vocabulary or leak column names to the wire — the request's
query *is* the filter, and your Fluent columns stay server-side.

```swift
extension Berth: FilterableDataModel {
    static func apply(filter: BerthQuery, to query: QueryBuilder<Berth>) -> QueryBuilder<Berth> {
        guard let name = filter.dockName else { return query }
        return query.filter(\.$dockName == name)   // your Fluent, your columns
    }
}
```

### Register per-request app state for projections — `useAppState`
Reach for this when: a projection needs session-derived display data ("signed in
as…") that isn't a loaded record. Register one builder per `AppState` type in
`configure(_:)`; it runs in the load phase with full request power and is handed to the
synchronous `body(context:)` as a plain value (read via `ProjectionContext.appState`).
Register it **before** the requests that project it — a non-`Void` `AppState` with no
builder fails fast at `register(request:app:)`. `Void` (the default) needs no registration.

```swift
try app.useAppState(SessionBanner.self) { req in
    SessionBanner(userName: try req.auth.require(User.self).displayName)
}
```

### Resolve apex-rooted loads' root — `useApexContainerResolver`
Reach for this when: any load or child roots at `.newRoot(.apex)` (FOSMVVM's
`RootSource`) — register the resolver that answers "who is the top container for this
caller?". Constant apps return a constant; multi-tenant apps resolve per request. A
plan with `.apex` roots and no registered resolver fails validation at boot. Exactly
one resolver per application — a second registration throws.

```swift
try app.useApexContainerResolver { req in
    try await req.auth.require(User.self).harborIdentity
}
```

## Live Invalidation

Server-push refresh for `@ViewModel(options: [.live])` screens (FOSMVVM's
`LiveViewModel`): enable it once at boot, and every committed change to a
registered container model nudges connected clients to re-fetch. The moving parts
behind it — the fan-out hub, the per-model emit middleware, and the SSE stream
route — are all internal; the calls below are the entire author-facing surface.
Fluent-persisted container models refresh automatically (their saves notify, see
`register(_:migration:)` under Extensions). The `registerDependency()` /
`invalidateProjections()` pair covers what Fluent doesn't own — state an
`Application`-hosted actor or a computed aggregate holds.

### Enable server-push refresh at boot — `useLiveInvalidation()`
Reach for this when: turning on live invalidation for the server — call once in
`configure(_:)`, passing the route group clients authenticate against. Every
registered container model (`register(_:migration:)`, see Extensions) then nudges
connected clients to re-fetch after each committed change; registrations made
before or after this call are both honored. Screens refresh only after a change
commits, and a client with no live connection degrades to fetch-once — so enabling
it is purely additive.
Limitation: fan-out is single-process — one server instance notifies the clients
connected to it. Enable exactly once — a second call throws at boot.

```swift
let authed = app.grouped(MyAuthMiddleware())
try app.useLiveInvalidation(on: authed)
```

### Writes that notify live clients — `liveTransaction`
Reach for this when: a mutation you run yourself must refresh live screens — wrap
the writes in `req.liveTransaction { db in … }` (route handlers) or
`app.liveTransaction { db in … }` (background jobs, other app-level work). Every
write inside the closure nudges live clients if — and only if — the transaction
commits; a throw rolls back and notifies no one. With live invalidation not
enabled the wrapper is just a plain Fluent transaction.
Don't reach for a bare `database.transaction { }` on a live model — FOSMVVM can't
tell whether those writes commit, so it stays silent (and warns once). The
framework's own guarded write path (`DataModelWriter`, see Protocols) already
notifies; `liveTransaction` is for the writes you drive by hand.

```swift
try await req.liveTransaction { db in
    dock.status = .closed
    try await dock.save(on: db)
}
```

### Nudge live clients from a non-Fluent source — `invalidateProjections()`
Reach for this when: state a live screen shows lives outside Fluent and just changed — an
`Application`-hosted actor mutating its own data, a computed aggregate going stale — and you
must refresh the projections built from it. Call `req.invalidateProjections(of: model)` in a
route handler, or `app.invalidateProjections(of: model)` from an actor or background job. It
composes with `liveTransaction`: called inside one, the nudge reaches clients only if the
transaction commits. With live invalidation not enabled it is a no-op. Pair it with
`registerDependency()` on the read side — a nudge refreshes only the projections that
registered a dependency on the same model. v1 emits the changed model's own identity only; a
screen that must refresh on a container's change registers a dependency on that container.
Don't reach for it for Fluent-persisted models — their saves already notify live clients.

```swift
// actor mutates its own state, then nudges the screens built from it
activeSessions += 1
try await app.invalidateProjections(of: snapshot())
```

### Register a live dependency the plan can't see — `registerDependency()`
Reach for this when: a `body(context:)` projection reads state the load plan can't see — an
`appState` snapshot of an `Application`-hosted actor, a computed value — and its screen is
`@ViewModel(options: [.live])`. Plan-loaded records register automatically (that is what
`records(_:)` reads); call `context.registerDependency(on: model)` for the rest. The
registered identity rides to the client with the response, so a later
`invalidateProjections()` for the same model refreshes the screen. Register a dependency on
what you read; invalidate projections of what you changed — the two must name the same
entity, and that pairing *is* the live contract.
Don't reach for it for records the plan already loaded, or for Fluent saves the framework
already notifies.

```swift
let status = context.appState.status
try context.registerDependency(on: status)
```

## Protocols

The server-side contracts: the response-body factory that projects loaded
records into a request's answer, the write-path contracts (candidate set and
field application), the per-request authorization provider, the load-phase
escape hatch, self-resolving ViewModel requests, hand-rolled controllers with
derived routing paths, and the Fluent-backed Model role.

### Produce a request's response body on the server — `VaporResponseBodyFactory`
Reach for this when: writing the server-side factory for any request's
`ResponseBody` — ViewModel or not — the DIP seam where loaded records become the
value the client receives. Authored once **on the body**; its generic
`body<R: ServerRequest>(context:)` serves every request that returns that body —
a read *and* the writes that return the same value (so a write reuses its own
`ResponseBody`'s factory, with no separate refresh request). Refines the
transport-agnostic `ResponseBodyFactory` (FOSMVVM). `body(context:)` is
**synchronous** (`throws`, never `async`): the records were loaded BEFORE projection began (auth-scoped, per the
factory's declared requirements — see FOSMVVM's `ComposableFactory` /
`LoadRequirement`), so projection reads them, never loads them. The factory is
handed a `ProjectionContext` (see Containment) — never a `Vapor.Request`, never a
`Database`. A zero-data body conforms to the factory alone (no
`ComposableFactory`). Registered with `register(request:app:)` (see Vapor Support);
the default `encodeResponse` serves the body *localized* to the request's
Accept-Language via `buildResponse()`. Data the factory can't declare as tuples
loads through `SupplementalRecordLoading` (see Protocols).
Don't write a per-type `encodeResponse`, and don't make `body` `async` — an
awaitable projection is the hole this type exists to close; declare the load
instead.

```swift
extension DockPageViewModel: VaporResponseBodyFactory {
    static func body<R: ServerRequest>(context: ProjectionContext<R, Void>) throws -> Self
        where R.ResponseBody == Self {
        .init(berthCells: try context.records(Self.berths)
            .map { BerthCellViewModel(berth: $0) })
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

### Declare a write's candidate set and field application — `WriteTargetProviding` / `DataModelWriter`
Reach for this when: serving an update/create/delete — adopt these on the write
request's `RequestBody` in the server target. `WriteTargetProviding.candidates`
(a stored `static let LoadRequirement`) declares the auth-scoped set the submitted
`TargetedQuery` target (FOSMVVM's Protocols) must resolve to — not-yours is
indistinguishable from not-found. A `DeleteRequest` body conforms to
`WriteTargetProviding` **alone** (deletion is framework-owned). An update or create
adds `DataModelWriter.apply(to:)` — a **synchronous** field application that
**cannot touch the database**: the framework owns all I/O (load, save, the container
foreign key, invalidation, and re-serving the refresh). Create reuses the same
`apply` on a fresh `Target()`.
Don't fetch, save, or set foreign keys inside `apply` — it is field assignment only;
reaching for the database there is the red flag that write I/O leaked out of the
framework.

```swift
extension UpdateBerthRequest.RequestBody: DataModelWriter {
    static let candidates = LoadRequirement.write(Berth.self, in: .parentRoot)
    func apply(to berth: Berth) throws {
        berth.name = name
        berth.capacity = capacity
    }
}
```

### Supply a request's authorizations — `ContainerAuthorizationProvider`
Reach for this when: telling the framework what the current subject may touch —
conform once, register at boot with `useContainerAuthorizationProvider(_:)` (see
Extensions), and every framework load is scoped by what you return. Return the
**complete** grant set (never a per-container slice); the framework fetches through
you once per request and reuses it. Return `[]` for an unauthenticated subject —
they load empty sets. The value type you return conforms to FOSMVVM's
`ContainerAuthorization`.

```swift
struct GrantProvider: ContainerAuthorizationProvider {
    func containerAuthorizations(for request: Request) async throws -> [DockGrant] {
        let userId = try request.auth.require(SessionUser.self).id
        return try await UserDockGrantRow.query(on: request.db)
            .filter(\.$user.$id == userId).all()
            .map(\.snapshot)   // project Sendable value snapshots
    }
}
```

### Load data the plan can't declare — `SupplementalRecordLoading`
Reach for this when: a `ComposableFactory` needs data that can't be expressed as a
containment tuple. Conform and load it yourself in `loadSupplementalRecords(for:)` —
it runs AFTER the declarative plan (whose records are already readable) with full
request power. What you load here is NOT readable through
`ProjectionContext.records(_:)` — store and consume it through your own
request-scoped means (e.g. `request.storage`). A thrown error fails the request; it
is never swallowed to an empty result.

```swift
extension DockPageViewModel: SupplementalRecordLoading {
    static func loadSupplementalRecords(for request: Vapor.Request) async throws {
        // load what couldn't be declared; stash it in request.storage
    }
}
```

## Vapor Support

The routing layer that turns request types into live routes: the one
`RoutesBuilder` registration door for every request (reads and the guarded CRUD
writes), and the general dispatch controller for operations outside the guarded
verbs (the request-binding host and middleware behind them are internal).

### Register a request's route — `register()`
Reach for this when: exposing any `ServerRequest` over HTTP — one line per request
in `routes(_:)`. Its `ResponseBody` must be a `VaporResponseBodyFactory` (see
Protocols); the route's path derives from the request type, so client and server can
never disagree on it. A read registers GET; write requests (CreateRequest /
UpdateRequest / DeleteRequest, FOSMVVM's Protocols) have their own overloads Swift
picks by their Query/RequestBody constraints. It is a `RoutesBuilder` method taking
the `Application` as a parameter: register on the route group whose middleware you want
guarding the route — a credential group for privileged requests, the `Application`
itself (which is a `RoutesBuilder`) for public ones. Where a request mounts is your
decision; that its plan is derived is not. Register the app's containers
(`register(_:migration:)`, see Extensions) **before** calling this: a composable
body's load plan is derived and validated here, at boot. Mount only on
middleware-only groups — a path-prefixing group (`app.grouped("admin")`) is rejected
at boot, because the client derives the served URL from the request type.
Don't reach for a removed `register(viewModel:)` — there is one `register(request:app:)`
door; a `ReplaceRequest`/`DestroyRequest`, or a write request that reaches the read
door, fails fast at boot rather than registering GET-only.

```swift
func routes(_ app: Application) throws {
    let authed = app.grouped(ClientCredentialMiddleware(verifier: myVerifier))
    try authed.register(request: DockPageRequest.self, app: app)   // guarded read (GET)
    try authed.register(request: UpdateBerthRequest.self, app: app) // write door, picked by Swift
    try app.register(request: LandingPageRequest.self, app: app)   // public (Application is a RoutesBuilder)
}
```

### General request dispatch — `ServerRequestController` / `ServerRequestControllerError`
Reach for this when: an operation falls outside the guarded verbs
`register(request:app:)` covers (e.g. a `ReplaceRequest`, multi-record operations) —
conform, supply one processor per `ServerRequestAction`, and register the controller
as a route collection. Grouping, HTTP-method mapping (`.show` GET · `.create` POST ·
`.replace` PUT · `.update` PATCH · `.delete`/`.destroy` DELETE), body decoding
(honoring `maxBodySize`), and typed request binding are derived once. Each processor
receives `(req, bound)` — the raw `Vapor.Request` (full power) plus the **bound**
typed request (query and sort parsed; `requestBody` decoded on a body verb). `.delete`
and `.destroy` both ride DELETE at one URL, so a controller registers only one —
the other throws `ServerRequestControllerError.invalidAction`; a body verb whose body
is absent throws `.missingRequestBody`.
Prefer `register(request:app:)` — it instantiates this same mechanism pre-specialized
with the framework's guarded pipelines (declared loads, write gates, refresh
fall-through). Scaffolded by `fosmvvm-serverrequest-generator`.

```swift
final class ReplaceBerthController: ServerRequestController {
    typealias TRequest = ReplaceBerthRequest
    let actions: [ServerRequestAction: ActionProcessor] = [
        .replace: { req, bound in
            guard let body = bound.requestBody else {
                throw ServerRequestControllerError.missingRequestBody
            }
            return try await BerthPage(replacing: body, on: req.db)
        }
    ]
}
// in routes(_:): try app.routes.register(collection: ReplaceBerthController())
```
