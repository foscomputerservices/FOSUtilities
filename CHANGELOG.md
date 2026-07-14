# Changelog

All notable changes to **FOSUtilities** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_Nothing yet._

## [0.7.0] - 2026-07-14

### Added

- **`CredentialRejectedError`** (FOSMVVM / FOSMVVMVapor). A credential rejection from
  `ClientCredentialMiddleware` now crosses the wire as a typed, `Codable` error and is
  rethrown by `processRequest(mvvmEnv:)` — catch it to recover (`.missing` /
  `.invalid`); it always throws to the caller (never `requestErrorHandler`). Requires
  FOS `ErrorMiddleware.default` (already the documented configuration). Retires the
  `DataFetchError.badStatus(401)` client contract and the documented `EmptyError`
  rejection-swallow. `TestingServerRequestResponse` gains `credentialRejection`.

### Changed

- **`ErrorMiddleware`**: an error conforming to both `Encodable` and `AbortError` is
  now served with **both** its typed body and its own status/headers (previously such errors
  were served `400 Bad Request`). Plain `Encodable` errors are unchanged.
- **`ClientCredentialMiddleware`**: any verifier throw that is not a
  `CredentialRejectedError` is now wrapped as one (`.invalid`) — a custom
  verifier that previously threw an `Abort` with its own status/reason now
  rejects as `401` with the typed body. Throw `CredentialRejectedError`
  directly to carry intent; `CancellationError` propagates unchanged.

## [0.6.0] - 2026-07-09

### Added

- **Live ViewModel invalidation — `@ViewModel(options: [.live])`** (FOSMVVM / FOSMVVMVapor).
  Opt a screen in with the one macro option and any view bound with `.bind()` re-fetches
  automatically whenever another actor commits a change to the data that ViewModel was served
  from — no polling, no manual invalidation, nothing else to write. Where no live connection is
  configured the ViewModel behaves exactly like a non-live one (fetch once on appear), so adding
  `.live` to a shipped screen is purely additive. The macro synthesizes a **`LiveViewModel`**
  marker; `.live` combined with `.clientHostedFactory` is a macro diagnostic (a client-hosted VM
  has no server response to derive registrations from).
- **`Application.useLiveInvalidation(on:)`** (FOSMVVMVapor) — the server boot switch. Call once,
  passing the route group your clients authenticate against; every registered container model then
  nudges connected clients after each committed change. Registrations made before or after the
  call are both honored.
- **`Request.liveTransaction` / `Application.liveTransaction`** (FOSMVVMVapor) — the sanctioned
  replacement for a bare `database.transaction { }` in a live application: every write inside the
  closure nudges live clients if — and only if — the transaction commits (a throw/rollback nudges
  nothing). Inside a bare `transaction { }` the framework cannot know whether your writes commit,
  so it stays silent and logs a warning.
- **`InvalidationChannel` / `InvalidationEvent` + `MVVMEnvironment.invalidationChannel`** (FOSMVVM)
  — the transport seam. Most apps configure nothing (leave `invalidationChannel` `nil` and the
  standard channel is synthesized over your deployment URLs, with `invalidationBaseURL` defaulting
  to `serverBaseURL`); conform your own `InvalidationChannel` only to replace the transport
  wholesale. The invalidation nudge carries opaque `ModelIdentity` values only — **never** any
  ViewModel data. Contract: the client authenticates the stream through your
  `ClientCredentialProvider` at connect, and a reconnect refreshes every live screen.
- **`withServedFluentTestApp`** (FOSTestingVapor) — a Fluent test harness that serves the app on
  an ephemeral local port and hands the test a base URL, for exercising long-lived streaming
  endpoints that outlast the in-process `app.test(...)` responder.
- Served responses now carry an **`X-FOS-Registrations`** response header alongside `X-FOS-Version`
  (the data a live client registers to watch). Treat it as opaque — do not parse or hand-construct
  it; only the live resolver reads it.

### Fixed

- **`X-FOS-Version` attaches exactly once** to a served response (FOSMVVMVapor). The version header
  was being appended twice on the served response; `addSystemVersion()` now replaces-or-adds, so
  exactly one value is present. Clients reading the first value were unaffected — this removes a
  latent duplicate on the wire.

- **`ClientCredentialProvider`** (FOSMVVM) — supplies the authentication headers that
  accompany every `ServerRequest`; consulted per request, so a rotating credential is
  picked up on the next call. The dynamic sibling of the static
  `MVVMEnvironment.requestHeaders`. Ships with the stock **`BearerCredentialProvider`**
  (`Authorization: Bearer <token>`; a `nil` token sends the request unauthenticated).
- **`MVVMEnvironment.clientCredentialProvider`** — register a `ClientCredentialProvider`
  once (defaulted parameter on every initializer; additive) and
  `processRequest(mvvmEnv:)` attaches its headers to every request, after the static
  `requestHeaders` so the per-request credential wins on a duplicate field.
- **`ClientCredentialMiddleware` + `ServerCredentialVerifier`** (FOSMVVMVapor) — the
  server half of the credential pair: route groups run an app-supplied
  `ServerCredentialVerifier` before each route; throw to reject, return to admit.
  Consulted per request, so a credential revoked server-side takes effect on the next
  call. Ships with the stock **`BearerCredentialVerifier`** — the matched pair of
  `BearerCredentialProvider` — which extracts `Authorization: Bearer` and asks the
  app whether that token is currently valid (missing or invalid → `401` with
  `WWW-Authenticate: Bearer`, never echoing the presented token). On a FOSMVVM client
  a rejection surfaces as `DataFetchError.badStatus(httpStatusCode: 401)` — this
  requires an error serializer that forwards the `Abort`'s status and headers (FOS
  `ErrorMiddleware.default` does). Known limitation: a request whose `ResponseError`
  decodes from the rejection body swallows the `401` into a typed error instead —
  `EmptyError` always does (its synthesized decode is a no-op, accepting any
  valid-JSON body); pre-existing `DataFetch` behavior.
- **Complete generated `Localizable` overload surface** — every SwiftUI
  initializer and modifier that takes a `LocalizedStringKey` now has a
  `some Localizable`-accepting twin with a `defaultValue:` fallback: 253
  overloads across 44 SwiftUI types (inits and modifiers). Call the twin exactly
  like Apple's API — `Text(viewModel.title)`, `Button(viewModel.cta) { … }`,
  `EmptyView().navigationTitle(viewModel.title)` — passing the ViewModel's
  `Localizable` where the string key goes. The surface is regenerated per SDK by
  `scripts/localizable-overload-sweep.swift`, and a CI staleness gate fails the
  build if the checked-in overloads drift from a fresh sweep. The swept,
  generated, and rejected-candidate coverage ledger lives in
  `Sources/FOSMVVM/SwiftUI Support/SweepCoverage.md`.

### Changed

- **BREAKING: `defaultTitle:` → `defaultValue:` on `TextField` Localizable
  overloads.** The fallback-label argument is now spelled `defaultValue:`,
  uniform with every other overload in the surface. A caller passing the old
  label renames the argument.
- **BREAKING: `any Localizable` → `some Localizable` on the Localizable
  overloads.** The generated inits and modifiers take an opaque `some
  Localizable` rather than an existential `any Localizable`. Ordinary call sites
  are source-compatible; only callers who spelled the parameter type explicitly
  are affected — replace `any Localizable` with `some Localizable` in the
  parameter type annotation.
- **BREAKING: `ContentUnavailableView` `defaultValue:` moved to second
  position.** The Localizable overload `init(_:systemImage:defaultValue:)` is now
  `init(_:defaultValue:systemImage:description:)` — `defaultValue:` follows the
  localizable slot uniformly across the surface. Source-breaking only for callers
  who passed `defaultValue` explicitly.
- **The `Text(_:defaultValue:)` Localizable inits, `Localizable.text`, and
  `LabeledContent(_:defaultValue:value:)` (String value) are unchanged** — no
  source change for callers.

## [0.5.0] - 2026-07-08

### Added

- **`Container` protocol** (`Container: Model`) with `containedRecordTypes` — a
  model that owns and authorizes other records.
- **`ContainerOperation`** — the authorization verb vocabulary
  (`readRecords`/`writeRecords`/`createRecords`/`deleteRecords`/`destroyRecords`/
  `anyOperation`) with `authorizes…Records` intent accessors on the enum and on
  `Sequence`.
- **Client-chosen sort** — `SortCriteria`/`SortKey`/`SortDirection`/`SortTerm`
  and `ServerRequestSort`. `ServerRequest` gains a defaulted `Sort` associated
  type (additive; existing requests are unaffected).
- **`PaginatedQuery`** — an opt-in query trait carrying a `Pagination` window.
- **`ModelIdentity`** — a sealed, opaque, non-generic identity rooted in a `Model`'s stable id
  (`Hashable`/`Codable`/`Sendable`), with `ModelNamespace` (minted only from a type, never a raw
  string), `Model.modelIdentity` / `Model.modelIdentityNamespace`, the opt-in
  `ModelIdentifiedViewModel` protocol, `ModelIdentity.viewModelId`, and `ModelIdentity == some Model`
  filtering sugar. Treat the value as opaque — its encoded form is version-stable and round-trips, and
  changes only on a library major version; do not parse or hand-construct it.
- **`ViewModelId.Freshness`** — an opaque, order-only version clock (a canonical-GMT birth moment)
  carried on every `ViewModelId` under the short wire key `fsh`. Orthogonal to identity: `==`/`hash`
  stay `id`-only and `ViewModelId` is deliberately not `Comparable`.
- **`ContainerDataModel` + `ContainmentRelation`** (FOSMVVMVapor) — declare a container's
  authorization-bearing relationships from its own Fluent `@Children`/`@Siblings`/`@Parent`
  KeyPaths; cardinality and joins come from Fluent, never restated.
- **`Application.register(_:migration:)`** (FOSMVVMVapor) — registering a container's migration
  also registers its identity descriptor; misconfigurations (duplicate namespace, foreign
  KeyPaths, containment drift vs `containedRecordTypes`) throw at boot.
- **`withFluentTestApp`** (FOSTestingVapor) — a scoped in-memory SQLite + Vapor application harness
  for Fluent-backed tests.
- **`ContainerAuthorization`** (FOSMVVM) + **`Sequence<ContainerOperation>.authorizes(_:)`** — the
  shared authorization contract: conform a value type your persisted grant projects to answer "may
  this subject touch these records?"; the operation-set helper honors the wildcard grant so app
  code doesn't drift to a raw `contains(_:)` check that silently ignores it.
- **`SortableDataModel` + `SortMapping`** (FOSMVVMVapor) — declare how a model's published sort
  *meanings* become database ordering, once, applied everywhere the framework sorts that model.
- **`Request.serverRequestSort(ofType:)`** (FOSMVVMVapor) — the server-side parse surface that
  recovers a request's sort criteria, mirroring the existing `serverRequestQuery(ofType:)`.
- **`ContainerAuthorizationProvider`** (FOSMVVMVapor) — conform once to supply the current subject's
  complete `ContainerAuthorization` set for a request; the framework fetches through it when first
  needed and reuses the result for every load in that request.
- **`Application.useContainerAuthorizationProvider(_:)`** (FOSMVVMVapor) — boot-time registration of
  the app's authorization provider; registering a second provider throws rather than silently
  replacing the first.
- **`ComposableFactory`** (FOSMVVM) — the opt-in trait that makes "a composable body declares the
  data it needs" true and automatic: `dataRequirements` lists a factory's own loads, `children` lists
  the child factories it composes. A child that doesn't declare its data can't be listed — composing
  an undeclared child fails to compile. Any `ServerRequestBody` may adopt it (not only ViewModels), so
  a CLI's plain manifest body composes the same machinery. Declarations are aggregated automatically
  at boot and loaded once, before the body is built.
- **`DataRequirement` + `LoadRequirement`** (FOSMVVM) — the typed load a factory declares.
  `DataRequirement` is a sealed public marker (mint through `LoadRequirement`; a foreign conformance
  is rejected at boot with "unknown requirement kind"). `LoadRequirement.read(_:in:via:)` names the
  record type, where it roots (`in:`), and the intermediate containment hops to it (`via:`, terminal
  hop always implicit — a parameter pack, so call sites carry no `any`); `.refinedByRequest` marks the
  one requirement per plan the request's own sort/pagination axes apply to. The write-family verbs
  `.write` / `.create` / `.delete` load a write request's candidate set (`.create` takes no `via:`
  intermediates — the root container is the create scope).
- **`ComposedChild`** (FOSMVVM) — declares one composed child factory: `.child(_:)` shares the
  parent's containment scope (the common case); `.child(_:via:)` descends further; `.child(_:rootedAt:)`
  starts a fresh root (e.g. an apex-rooted sibling tree alongside a request-rooted detail).
- **`RootScope` / `RootSource`** (FOSMVVM) — where a requirement or composed child roots
  (`.parentRoot` / `.newRoot(RootSource)`) and where a fresh root's identity comes from
  (`.query` — the request's own `RootedQuery`; `.apex` — the app's registered apex-container
  resolver), giving every load a rooted, apex-pattern scope.
- **`RootedQuery`** (FOSMVVM) — a `ServerRequestQuery` that vends the container identity its
  request is rooted in, for requirements/children declared with `.newRoot(.query)`.
- **`AuthorityFlow` + `Container.authorityFlow`** (FOSMVVM) — whether authority granted on an
  ancestor container flows through to a container's own records (`.inherits`, the default — one
  grant anywhere above covers the descent) or must be granted anchored at that container itself
  (`.guards`).
- **Boot-time load-plan derivation and validation** (FOSMVVMVapor) — `register(request:)` derives
  each composable request's aggregated data-load plan once, at route registration, and validates it
  against the app's registered containers: composition cycles, duplicate `.refinedByRequest` marks,
  unresolvable containment hops, and `.query`/`.apex` roots missing their required conformance/resolver
  all fail fast at boot, never at request time.
- **`ResponseBodyFactory` (FOSMVVM) + `VaporResponseBodyFactory` (FOSMVVMVapor) + `ProjectionContext`
  (FOSMVVM)** — the one author-facing server factory for every request's `ResponseBody`, ViewModel or
  not. Authored **once on the body**: `static func body<R: ServerRequest>(context:) where
  R.ResponseBody == Self` is generic over the request, so a single factory serves **every** request
  that returns that body — a read *and* the writes that return the same value. `body` is
  **synchronous** (`throws`, never `async`) and is handed a `ProjectionContext` — the typed request,
  the app-declared `AppState`, and typed record reads by the same static handle the factory declared —
  never a `Vapor.Request` or `Database`. Reading a handle that never reached the plan throws (naming
  the handle and request), never returns `[]`; the projection *couldn't* load if it wanted to.
- **`Application.register(request:)`** (FOSMVVMVapor) — one Application-only registration door for
  every request (there is no grouped/`Routes`-level door). Write requests (`CreateRequest` /
  `UpdateRequest` / `DeleteRequest`) get their own overloads picked by Swift; a write request that
  reaches the read door, or a `ReplaceRequest`/destroy conformer, fails fast at boot rather than
  registering GET-only. Boot checks fail-fast on: a non-`Void` `AppState` with no builder; a duplicate
  `useAppState` type; a write request's candidate root-source missing its `RootedQuery`/apex resolver.
- **The write path** (FOSMVVM + FOSMVVMVapor) — `TargetedQuery` (FOSMVVM) names which loaded record a
  write targets, by the opaque `ModelIdentity` the client received (the form body carries no
  `ModelIdType`; the server resolves the selector against the candidate set it loaded itself —
  not-yours is indistinguishable from not-found). `WriteTargetProviding` + `DataModelWriter`
  (FOSMVVMVapor) are adopted by a write request's `RequestBody`: `candidates` declares the auth-scoped
  set (exactly one per write request), and `apply(to:)` is a **sealed synchronous** field application
  that cannot touch the database (create reuses the same `apply` on a fresh `Target()`; delete needs
  no `apply`). Each write protocol constrains its `ResponseBody` to a marker
  (`Create`/`Update`/`Delete`/`Replace`/`Destroy` `ResponseBody`; `EmptyBody` conforms to each). After
  a write commits and the mutated containers' records are invalidated, the server re-serves the **write
  request itself** through the genuine read pipeline to build its `ResponseBody` — normally the
  container's updated children, the same value a read of that container returns. No separate refresh
  request: the body factory is generic over the request that returns it, so the write reuses its own
  `ResponseBody`'s factory. Create is gated on the authorization grant directly (a denied create throws
  the same not-found shape as a nonexistent destination — no authorization oracle).
- **`Application.useAppState(_:builder:)`** (FOSMVVMVapor) — registers the one load-phase builder for a
  factory's `AppState` (session-derived display data), computed with full request power and handed to
  the synchronous projection as a plain value. Keyed by the `AppState` type; `Void` needs no
  registration.
- **`Application.useApexContainerResolver(_:)`** (FOSMVVMVapor) — now public: registers the resolver
  that binds `.apex`-rooted loads' root identity per request, making `.apex` roots usable by apps.
- **`SupplementalRecordLoading`** (FOSMVVMVapor) — now public: the load-phase escape hatch for data
  that cannot be declared as containment tuples. Runs after the declarative plan (its records already
  readable) with full request power; a thrown error fails the request, never swallowed to an empty
  result.
- **Boot-time Sort-bridge warning** (FOSMVVMVapor) — a `.refinedByRequest` plan whose request `Sort` is
  neither `EmptySort` nor `SortCriteria`-based logs a warning at registration naming the request and the
  ignored `Sort` type, so the silent zero-terms no-op becomes visible.
- **`@LocalizedDate`** — a localized, locale-formatted `Date` property wrapper
  (`LocalizableDate`), completing the family alongside `@LocalizedInt` and
  `@LocalizedDouble`. `dateStyle`/`timeStyle`/`dateFormat` pass through to
  `LocalizableDate` (`.medium` date style when nothing is specified); `value:`
  is required.
- **`FOSNetworkSecurity`** — a new module for hardening client↔server transport.
  `ServerCertPinning` pins a server by its SPKI public-key hash (`SPKIPin`), applied through a
  `URLSession` extension so a pinned session drops in wherever `URLSession` is used; `MutualTLS`
  + `ClientIdentityProvider` supply a client certificate for mutual-TLS handshakes.
- **Paginated total-count** — `ProjectionContext.totalCount(for:)` and
  `ContainmentRelation.memberCount` (FOSMVVMVapor): the size of the authorized set a
  `PaginatedQuery` window is a view into, so a client can render window position (e.g.
  "40–65 of 1,204,882"). Counted via `.count()` (no fetch), computed after the grant check so it
  never counts unauthorized rows, and cached per window (0 for an unplanned or denied load).
- **Query-driven filtering** — `FilterableDataModel` (FOSMVVMVapor): a searchable model declares
  the one `ServerRequestQuery` type it reads and hand-writes `apply(filter:to:)` as a database
  `WHERE`. A query *is* a filter, so there is no separate filter type or wire vocabulary; the
  request's query rides the containment refinement into the load, the count, and the cache key, so
  counts and windows reflect the narrowed set. Opportunistic — a non-filterable model, or a query
  that isn't the model's declared type, is simply not narrowed (nothing is dropped or thrown).
- **Server-hosted localization in view previews** — `previewHost(serverHostedResourcesPath:)` loads
  YAML localization from a filesystem directory served by the server, so a server-localized view
  can be previewed against those resources; adds `URL.yamlLocalizationStore()`.

### Changed

- **Authorized container loads can be anchored independently of the container being loaded from.**
  When a load descends through a `.guards` container (see `AuthorityFlow` above), the authorization
  check — and the framework's request-scoped cache — now key off that container's instance rather
  than the record's immediate container, so a grant on one guarded branch can never authorize, or
  share a cached result with, a differently-anchored branch. Existing loads (no `.guards` container
  on the path) are unaffected — the default anchor is unchanged.

- **BREAKING: `ServerRequest.init` now takes `sort:`.** The canonical initializer is
  `init(query:sort:fragment:requestBody:responseBody:)`; a protocol-extension convenience
  (`sort` defaulting to none) keeps existing 4-parameter call sites compiling unchanged. Sort
  criteria, when present, now travel alongside the query in the request's URL; pre-existing
  requests and URLs (no sort) are unaffected and round-trip unchanged.

- **BREAKING (FOSTestingVapor): `VaporServerRequestTest`'s `Request.ResponseBody` constraint is now
  `VaporResponseBodyFactory`** (was `VaporViewModelFactory`). ServerRequest tests whose response body
  adopts the renamed factory compile unchanged; the constraint name is the only change.

- **BREAKING: `ServerRequestController` is the one general dispatch layer.**
  `ActionProcessor` is now `@Sendable (Vapor.Request, TRequest) async throws ->
  TRequest.ResponseBody` — the typed request arrives bound (query + sort parsed
  once by the request middleware; a body verb decodes `requestBody` onto it). All
  six `ServerRequestAction`s now map to HTTP methods (`.show` GET, `.delete`/
  `.destroy` DELETE join POST/PUT/PATCH); `register(request:)` and the write
  overloads are unchanged sugar that pre-specialize this mechanism with the
  framework's guarded pipelines. A controller listing both `.delete` and
  `.destroy` fails fast at boot (one URL, one DELETE handler).

### Removed

- **BREAKING: `Model.modelType`** — the dormant, unused, stringly-typed namespace is removed in favor
  of the opaque `ModelNamespace`. Downstream code referencing `modelType` migrates to
  `modelIdentityNamespace`.
- **BREAKING: `VaporViewModelFactory` + `VaporModelFactoryContext`** (FOSMVVMVapor) — the server factory
  that handed the projection the raw `Vapor.Request` (and thus `req.db`) is removed in favor of
  `VaporResponseBodyFactory` + `ProjectionContext`. The projection intentionally loses `Vapor.Request`
  and the database handle — it can no longer load — and `body(context:)` is synchronous. Conformers
  move their loading to declared requirements (`ComposableFactory`) or `SupplementalRecordLoading`.
- **BREAKING: `Application.register(viewModel:)`** (FOSMVVMVapor) — removed in favor of
  `register(request:)` (which serves every request, ViewModel-bodied or not, and hosts the write
  overloads). Registration is Application-only; grouped/`Routes`-level registration is gone.

### Fixed

- **`EmptyBody` responses are content-agnostic on fetch (PL-8)** — a request whose `ResponseBody`
  is `EmptyBody` no longer requires (or inspects) response content, so a bodyless server response
  decodes cleanly.
- `FOSVaporServerError.debugDescription` now correctly labels itself (it
  previously printed `FOSLocalizableError:`).
- Corrected stale documentation examples: `PDFRenderer.render` shown with
  `try` (both overloads are synchronous), `register(viewModel:)` label,
  `FormFieldView` example includes the required `focusField:` parameter,
  `hexString()` example values, and two `@Localized*` example typos.

## [0.4.0] - 2026-07-03

### Added

- **WebAssembly (WASM) platform support**, including a WASI `URLSession`
  implementation (with JavaScript wrapper functions that preserve `this`
  context) so `FOSFoundation` networking works in the browser.
- **Custom `URLSession` injection** — an application can now supply its own
  `URLSession` through `MVVMEnvironment`.
- **`@LocalizedDouble`** — a localized, locale-formatted `Double` property
  wrapper (`LocalizableDouble`), alongside the existing `@LocalizedInt`.
- **Localizable array access** — localized array properties (`@LocalizedStrings`)
  for binding collections of localized values.
- **`OperationBus`** — a mechanism for dispatching ViewModel operations.
- **`Localizable` support for SwiftUI `Label` and `LabeledContent`.**
- **`ViewModelDisplayTestCase`** (FOSTestingUI) — a display-only ViewModel UI
  test base class that does not require a `ViewModelOperations` type.
- **FOSMVVM React runtime resources** are served from `FOSMVVMVapor` at
  `/fosmvvm/react/` under a global namespace.
- **`ReplaceRequest` protocol** — the PUT verb of the write-request family
  (`Create` / `Update` / `Delete` / `Destroy` / **`Replace`**). It mirrors
  `UpdateRequest` (`RequestBody: ValidatableModel`, `action == .replace`) and
  adds the `ReplaceResponseBody` marker. The generic `ServerRequestController`
  already routes `.replace` to `PUT`, so no server-side change is required to
  serve one.
- **`@ViewModel` synthesizes the `Stubbable` witness.** When a type provides a
  fully-defaulted parameterized `stub(...)` but no zero-argument `stub()`, the
  macro now generates `static func stub() -> Self`, forwarding each parameter's
  default explicitly (so the call binds to the parameterized overload rather than
  recursing into the witness). Types no longer need to hand-write the boilerplate
  witness alongside a parameterized stub.

### Changed

- **Yams dependency now points at the official `jpsim/Yams`** (the WASM support
  is kept dormant).

### Fixed

- **Server-hosted ViewModels are now served localized.** `VaporViewModelFactory`
  gained a default `AsyncResponseEncodable.encodeResponse(for:)` that encodes the
  ViewModel through the request's `Accept-Language` locale (via the shared
  `ServerRequestBody.buildResponse(_:)` / `localizingEncoder` path, which also
  stamps the `SystemVersion` header). A conformer now supplies only
  `model(context:)` — previously the required async `encodeResponse` conformance
  was missing entirely, so no in-repo type could conform and the documented
  pattern would not compile. The docc example is corrected to match.
- **`VaporServerRequestTest` (FOSTestingVapor) boots and tears down correctly.**
  It now runs a full application lifecycle per `test(...)` call — `Application.make()`
  → `asyncBoot()` → dispatch → `asyncShutdown()`. Previously it called `startup()`
  (which launched the `serve` command and left it un-shut, tripping
  `ServeCommand did not shutdown before deinit`) and paired it with a synchronous
  `deinit` shutdown that cannot satisfy the async serve command. Booting with
  `asyncBoot()` also avoids Vapor's console argument parser, resolving the
  long-standing `-NSTreatUnknownArgumentsAsOpen` failure that kept the end-to-end
  serve test disabled. The response is now decoded as the request's `ResponseBody`
  (it was mistakenly decoded as `RequestBody`).
- **`FormFieldView`** now preserves typed whitespace and uses the current
  `onNewValue` closure, and resolves a debounce race and a `FocusState`
  field-clear bug observed on iOS 18.
- **FOSMVVM React resources** are served from the correct bundle root.
- A missing Linux `import` was added.
- **Versioned ViewModel baselines are persisted beside the calling test**, not
  inside FOSTesting's own source. `expectFullViewModelTests` now forwards
  `#filePath` / `#line` to `expectVersionedViewModel`, so the baseline directory
  is resolved at the developer's test file. Previously the convenience wrapper
  resolved `#filePath` to FOSTesting's source and wrote baselines to an
  ephemeral, ignored location, defeating cross-version drift detection.
- **Version-baseline directories anchor on the SwiftPM test-target root**
  (`Tests/<Target>/.VersionedTestJSON`), independent of how deeply the calling
  test file is nested. This keeps equally-named types in sibling test targets
  from colliding on a shared baseline file. Non–SwiftPM layouts fall back to the
  previous behavior.
  - **⚠ Migration (downstream apps that commit baselines):** the baseline path
    changed. If you committed version baselines at the old location, move them to
    `Tests/<Target>/.VersionedTestJSON/`. A baseline left at the old path is not
    found, silently **regenerated**, and the test **passes** — so cross-version
    drift detection is quietly lost until the files are moved. (FOSUtilities' own
    baselines are now git-ignored, so only downstream consumers are affected.)

## Prior releases

Releases up to and including **0.3.7** are recorded as
[Git tags](https://github.com/foscomputerservices/FOSUtilities/tags) and GitHub
Releases. This changelog begins tracking notable changes from the next release
onward.

[Unreleased]: https://github.com/foscomputerservices/FOSUtilities/compare/0.7.0...HEAD
[0.7.0]: https://github.com/foscomputerservices/FOSUtilities/compare/0.6.0...0.7.0
[0.6.0]: https://github.com/foscomputerservices/FOSUtilities/compare/0.5.0...0.6.0
[0.5.0]: https://github.com/foscomputerservices/FOSUtilities/compare/0.4.0...0.5.0
[0.4.0]: https://github.com/foscomputerservices/FOSUtilities/compare/0.3.7...0.4.0
