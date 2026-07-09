# FOSTesting API Catalog

Curated map of the testing modules' public API, organized by task — three
modules in one file: **FOSTesting** (platform-neutral helpers for Swift Testing
suites), **FOSTestingUI** (XCTest base classes that drive ViewModelViews through
XCUITest; Apple platforms only), and **FOSTestingVapor** (in-process
ServerRequest testing against a real Vapor application; macOS/Linux only).
Before hand-rolling a codable round-trip, a translation sweep, a mock
network session, or a test HTTP request — check here first.

## FOSTesting

Expectation functions and suite infrastructure for Swift Testing: the
`LocalizableTestCase` suite protocol (store loading, localizing encoders) and
its pre-minted test locales, the one-call ViewModel/field-model/form-field
verifications, the individual codable / version-stability / translation
expectations they compose, a mock URLSession for network-free tests, and the
typed errors the expectations throw.

### Localization-aware test suites — `LocalizableTestCase` / `loadLocalizationStore()` / `encoder()`
Reach for this when: a Swift Testing suite touches anything Localizable —
conform, load the store once in `init`, and declare the locales under test;
`encoder(locale:)` then hands out localizing encoders and every expectation
below becomes available on the suite.
Don't load YAML stores or build localizing encoders per-test by hand.

```swift
@Suite("User ViewModel Tests", .serialized)
struct UserViewModelTests: LocalizableTestCase {
    let locStore: LocalizationStore
    var locales: Set<Locale> { [Self.en, Self.es] }
    init() throws {
        self.locStore = try Self.loadLocalizationStore(bundle: .module)
    }
}
```

### Standard test locales — `en` / `enUS` / `enGB` / `es`
Reach for this when: passing a Locale to an expectation or encoder — the common
test locales are pre-minted as both static and instance properties on
`LocalizableTestCase`, on FOSTestingUI's test cases, and on FOSTestingVapor's
application tester.

```swift
var locales: Set<Locale> { [Self.en, Self.enGB, Self.es] }
try expectTranslations(UserViewModel.self, locales: [en])
```

### The whole ViewModel contract in one call — `expectFullViewModelTests()` / `expectFullFieldValidationModelTests()` / `expectFullFormFieldTests()`
Reach for this when: writing the standard test for a ViewModel, a
`@FieldValidationModel` messages type, or a FormField. Coverage differs per
call: `expectFullViewModelTests()` runs the codable round-trip,
version-stability, and translation checks below;
`expectFullFieldValidationModelTests()` runs the codable round-trip and
translation checks (no version-stability); `expectFullFormFieldTests()` runs
only the translation check, on the field's title and placeholder. This is
what the `fosmvvm-viewmodel-test-generator` skill scaffolds; prefer it over
calling the pieces individually.

```swift
try expectFullViewModelTests(UserViewModel.self)
try expectFullFieldValidationModelTests(UserFieldsMessages.self)
try expectFullFormFieldTests(UserFormModel.emailField)
```

### Codable round-trip check — `expectCodable()`
Reach for this when: any Codable & Stubbable type must survive encode → decode
(request bodies, queries, models) — it encodes the stub and decodes it back,
failing with a `FOSCodableError` that names the type and the offending JSON.
Pass `encoder:` when the type needs a localizing encoder (ViewModels).

```swift
try expectCodable(UserQuery.self)
try expectCodable(UserViewModel.self, encoder: encoder())
```

### Old payloads still decode — `expectVersionedViewModel()`
Reach for this when: guarding a ViewModel against breaking previously-shipped
clients — the first run at each SystemVersion writes a JSON baseline under the
test target's `.VersionedTestJSON` directory; every run decodes *all* stored
baselines with today's type. Commit the baselines — a failure means a shipped
shape no longer decodes. Client-hosted ViewModels are skipped (they rebuild
with the app and cannot be stale). Included in `expectFullViewModelTests()`.

```swift
try expectVersionedViewModel(UserViewModel.self, encoder: encoder())
```

### Translations exist in every locale — `expectTranslations()`
Reach for this when: verifying no localized property is missing a YAML value —
encodes the stub once per locale and fails on empty or still-pending values.
Overloads take a ViewModel-like type or a single Localizable (a FormField
title, an error message). Included in `expectFullViewModelTests()`.

```swift
try expectTranslations(UserViewModel.self)
try expectTranslations(field.title, locales: [en, es])
```

### Mock the network — `MockURLSession`
Reach for this when: testing code that fetches through FOSFoundation's
DataFetch / URL extensions without touching the network — `init(model:url:)`
cans a 200 JSON response for any Codable; `init(data:error:response:)` scripts
failure cases. Conforms to URLSessionProtocol (catalogued in FOSFoundation).
Don't call `session(config:)` on the mock — it is unimplemented; construct with
the initializers.

```swift
let session = try MockURLSession(model: TestUser.stub(), url: url)
let user: TestUser = try await DataFetch(urlSession: session).fetch(url)
```

### Typed expectation failures — `FOSCodableError` / `FOSLocalizableError`
Reach for this when: reading or asserting on failures from the expectation
functions — both are message-carrying errors whose `debugDescription` names
the failing type, property, or locale.

```swift
catch let error as FOSCodableError { print(error.debugDescription) }
```

## FOSTestingUI

The XCTest exception to the repo's Swift Testing convention: two open base
classes that launch the application under test via XCUITest, inject a localized
ViewModel through the launch environment, and — for interactive views — read
the recorded operations back out; plus the harness error enum they throw.
Requires app-side wiring: `testHost()` and `registerTestView()` from FOSMVVM
(catalogued there). The `fosmvvm-ui-tests-generator` skill scaffolds both
sides.

### UI-test a display-only view — `ViewModelDisplayTestCase` / `presentView()` / `localizedViewModel()` <!-- apple-only -->
Reach for this when: XCUITest-driving a ViewModelView that only displays data —
no operations to verify. Create one project-level subclass that pins
`setUp(bundle:resourceDirectoryName:appBundleIdentifier:locales:)`; each test
then calls `presentView()` with a stub ViewModel (localized for you; the
suite's `localizationStore` and locale shorthands are available) and asserts on
the returned XCUIApplication. `presentView(testConfiguration:)` names a
configuration the app's `testHost` closure can decorate the view with;
`localizedViewModel()` localizes a ViewModel without launching.
Don't locate elements by display text — tag them with `uiTestingIdentifier()`
(FOSMVVM) and match the identifier.

```swift
final class MyDisplayViewUITests: AppDisplayTestCase<MyDisplayViewModel>, @unchecked Sendable {
    func testShowsTitle() throws {
        let app = try presentView(viewModel: .stub())
        XCTAssertTrue(app.staticTexts["titleLabel"].exists)
    }
}
```

### UI-test an interactive view — `ViewModelViewTestCase` / `viewModelOperations()` <!-- apple-only -->
Reach for this when: the view dispatches user actions to a ViewModelOperations
protocol — drive the UI, then `viewModelOperations()` reads the recorded stub
operations back out of the running app (transported via FOSMVVM's
TestDataTransporter), so you assert what the view *called*, not just what it
showed. Same setup as the display case, plus the stub-operations type
parameter.

```swift
final class MyViewUITests: AppViewTestCase<MyViewModel, MyViewModelStubOps>, @unchecked Sendable {
    func testSave() throws {
        let app = try presentView()
        app.buttons["saveButton"].tap()
        let ops = try viewModelOperations()
        XCTAssertTrue(ops.dataSaved)
    }
}
```

### Diagnose harness failures — `RunError` <!-- apple-only -->
Reach for this when: a UI test throws before asserting anything —
`setupNotCalled` means the subclass never called the base `setUp`;
`didntStart` means the app never reached the foreground;
`cannotRetrieveOperationsData` means no transporter data was found (check the
view applies `testDataTransporter()` and toggles its repaint flag).

```swift
catch RunError.cannotRetrieveOperationsData { /* transporter missing or stale */ }
```

## FOSTestingVapor

In-process, full-pipeline testing of ServerRequests against a Vapor application
(macOS/Linux only): the typed `test()` extension on VaporTesting's
application tester with its `TestingServerRequestResponse`, a one-shot harness
that boots a fresh application per request, a scoped Fluent + in-memory SQLite
application harness, `LocalizableTestCase` fixtures for localized Vapor
Application/Request instances, Codable⇄ByteBuffer JSON bridges, and the harness
error type. The standard test locales (see FOSTesting) are mirrored onto the
application tester.

### End-to-end ServerRequest tests — `test()` / `TestingServerRequestResponse`
Reach for this when: verifying a route serves a typed ServerRequest —
`app.testing().test(request, locale:)` derives the path, HTTP method, query
string, and version/locale headers from the request type, and hands the
callback a `TestingServerRequestResponse` carrying the status, headers, decoded
`ResponseBody`, and decoded `ResponseError`. Scaffolded by
`fosmvvm-serverrequest-test-generator`.
Don't hand-build paths with `app.test(.GET, "/my_request?...")` — that is the
stringly-typed break the ServerRequest hierarchy exists to prevent.
Gotcha: the tester boots synchronously — if the app registers async lifecycle
handlers (middleware, YAML loading), call `try await app.asyncBoot()` first.

```swift
let request = UserViewModelRequest(query: .init(userId: id))
try await app.testing().test(request, locale: en) { response in
    #expect(response.status == .ok)
    #expect(response.body != nil)
}
```

### Test Fluent-backed code against a fresh database — `withFluentTestApp()`
Reach for this when: a test needs a real database — register containers and add
migrations in the `configure` closure, then use the `Application` and `Database`
handed to the body closure. Each call owns a private in-memory SQLite database and a
full application lifecycle (migrations run, async boot, guaranteed shutdown), so tests
stay isolated and run in parallel.

```swift
let berths = try await withFluentTestApp { app in
    try app.register(Dock.self, migration: CreateDock())
    app.migrations.add(CreateBerth())
} _: { app, db in
    try await Dock(name: "5").save(on: db)
    return try await Berth.query(on: db).all()
}
```

### Test a streaming / SSE endpoint over a real socket — `withServedFluentTestApp()`
Reach for this when: a test must hold open a genuine HTTP connection that
`app.test(...)` can't — a streaming response, a live-invalidation SSE feed.
Configure the application in `configure` (register containers, enable live
invalidation), then use the `Application` and the base `URL` handed to `body` to
open a real socket to it. The server binds to `127.0.0.1` on an ephemeral port;
each call owns a private in-memory SQLite database, a bound port, and a full
lifecycle (always shut down), so tests stay isolated and run in parallel.
Don't reach for `app.test(...)` for a stream — it drives the request in-process
and cannot keep a socket open.

```swift
try await withServedFluentTestApp { app in
    try app.register(Dock.self, migration: CreateDock())
    try app.useLiveInvalidation(on: app.routes)
} _: { app, baseURL in
    let url = baseURL.appending(path: "invalidations")
    let (bytes, _) = try await URLSession(configuration: .ephemeral).bytes(from: url)
    for try await line in bytes.lines where line.hasPrefix("data:") {
        break   // a connected client received a pushed nudge
    }
}
```

### Serve one request through a fresh server — `VaporServerRequestTest`
Reach for this when: testing a ViewModel factory end-to-end without owning any
application configuration — each `test(request:locale:)` boots a fresh Vapor
application, loads your YAML localization, hosts the request's route, serves it
through the real route + localization pipeline, and shuts the application back
down, returning the typed response body. The request's ResponseBody must be a
VaporViewModelFactory (FOSMVVMVapor). DEBUG builds only.

```swift
let harness = try await VaporServerRequestTest(
    for: UserViewModelRequest.self, bundle: .module, resourceDirectoryName: "TestYAML")
let viewModel = try await harness.test(request: .init(), locale: Locale(identifier: "en"))
```

### Localized Vapor fixtures — `vaporApplication()` / `vaporRequest()` / `testServerPort`
Reach for this when: a unit test needs a Vapor Application carrying the suite's
LocalizationStore, or a Request bound to a locale (testing `localizingEncoder`,
factories that read the request's locale) — without registering routes.
Available on `LocalizableTestCase` suites; the store defaults to the suite's
`locStore`, and the application is configured for `testServerPort`.

```swift
let app = try await vaporApplication()
let req = try await vaporRequest(application: app, locale: es)
```

### JSON bodies as ByteBuffers — `toJSONByteBuffer()` / `fromJSON()`
Reach for this when: bridging Codable values to and from Vapor body buffers
with the library's standard coding strategy — encode a request body into a
ByteBuffer, or decode a response's ByteBuffer body into a typed value. The
typed `test()` above does both for you; reach for these when driving Vapor's
tester directly.

```swift
let body = try newUser.toJSONByteBuffer()
let user: User = try response.body.fromJSON()
```

### Typed harness failures — `FOSVaporServerError`
Reach for this when: `VaporServerRequestTest` throws — URL derivation failures,
non-OK statuses, and empty response bodies arrive as a message-carrying error
with a readable `debugDescription`.

```swift
catch let error as FOSVaporServerError { print(error.debugDescription) }
```
