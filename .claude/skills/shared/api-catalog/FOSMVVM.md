# FOSMVVM API Catalog

Curated map of FOSMVVM's public API, organized by task. Before hand-rolling a
ViewModel, localization lookup, server request, form field, or version check —
check here first; the pattern almost certainly already exists. Most of this
surface is reached through the macros (`@ViewModel`, `@FieldValidationModel`,
`@VersionedFactory`) rather than by conforming to the protocols directly.

## Extensions

One extension: the localizing JSONEncoder — the engine that resolves every
`Localizable` value at encode time. The server and `bind()` pipelines call it
for you; reach for it directly only when localizing by hand.

### Localize values during JSON encoding — `localizingEncoder()`
Reach for this when: a ViewModel or `Localizable` must be resolved to concrete
strings outside the standard pipelines (tests, tools, custom factories).
Localization *is* encoding: values stay `localizationPending` until they
round-trip through this encoder.
Don't localize by string lookup against the store — the encoder resolves
property-name bindings, substitutions, and compound values in one pass.

```swift
let encoder = JSONEncoder.localizingEncoder(locale: locale, localizationStore: store)
let localized: MyViewModel = try viewModel.toJSON(encoder: encoder).fromJSON()
```

## Forms

Declarative form-field descriptions, co-located with a Fields protocol and
rendered by `FormFieldView`: field specs, control/keyboard selection, input
options, the ViewModel-side property wrapper, and field-membership helpers.
The `fosmvvm-fields-generator` skill scaffolds the full pattern.

### Describe a form field once — `FormField` / `FormFieldBase` / `FormFieldIdentifier`
Reach for this when: declaring how a user-editable field is presented and
constrained — title, placeholder, control type, and input options — as a static
member of a Fields protocol.
Don't scatter keyboard types, autocapitalization, and length limits across
views — declare them once here and every platform renders them consistently.

```swift
static var emailField: FormField<String?> { .init(
    fieldId: .init(id: "email"),
    title: .localized(for: Self.self, parentKeys: "email", propertyName: "title"),
    type: .text(inputType: .emailAddress),
    options: [.required(value: true), .maxLength(value: 254)]
)}
```

### Choose the control and keyboard — `FormFieldType` / `FormInputType`
Reach for this when: picking how a field is presented (`text`, `textArea`,
`checkbox`, `colorPicker`, `select`) and which data type the input carries.
`FormInputType` mirrors HTML input types plus Apple content types — it drives
keyboard layout, auto-complete, and OS data suggestions.

```swift
type: .text(inputType: .newPassword)
type: .textArea(inputType: .text)
```

### Constrain and configure input — `FormInputOption`
Reach for this when: attaching requirements to a field — `required`,
`minLength`/`maxLength` (or `rangeLength()`), `minValue`/`maxValue`,
`minDate`/`maxDate`, `autocomplete`, `autocapitalize`, `disabled`, `size`.
Options are mutable so date bounds and the like can be tailored to ViewModel
data just before rendering.

```swift
options: [.required(value: true), .minLength(value: 4), .maxLength(value: 254)]
fieldModel.formField.options += [.minDate(date: viewModel.userDateOfBirth)]
```

### Bind field values into a ViewModel — `FormFieldModel`
Reach for this when: a ViewModel hosts editable form data. The wrapper joins a
`FormField` spec with an observable value; set `initialValue` in the
initializer (never the value directly) so `resetFields()` restores it.

```swift
@FormFieldModel(UserFormModel.emailField) public var email: String?

public init(email: String?) {
    self.$email.initialValue = email
}
```

### Scope validation to specific fields — `contains()`
Reach for this when: a `validate(fields:validations:)` implementation must skip
properties that aren't in the requested field set — works on collections of
`FormFieldBase` and of `FormFieldIdentifier`.

```swift
guard fields?.contains(Self.emailField) ?? true else { return nil }
```

## Localization

YAML-backed localization bound to properties by the Swift compiler. Values are
declared with property wrappers, carried as `Localizable` types, and resolved
during encoding (see `localizingEncoder()` under Extensions) — so the server
localizes ViewModels before they ever reach the client. Stores load from
`.yml` resources; errors surface as typed enums.

### Bind properties to YAML values — `LocalizedString` / `LocalizedInt` / `LocalizedDouble` / `LocalizedDate` / `LocalizedStrings` / `LocalizedCompoundString` / `LocalizedSubs`
Reach for this when: declaring localized properties on an `@ViewModel` or
`@FieldValidationModel` type. The property name is the YAML key by default;
`parentKey(s)`, `propertyName`, and `index` navigate nested and array values.
`@LocalizedDate` passes `dateStyle`/`timeStyle`/`dateFormat` through to
`LocalizableDate` (`.medium` date style when nothing is specified); its
`value:` is required — a date has no zero.
Don't concatenate or format localized strings in Swift — bind them.

```swift
@ViewModel public struct UserViewModel {
    @LocalizedString public var pageTitle // UserViewModel.pageTitle in YAML
    @LocalizedString(parentKey: "email") public var emailTitle
    @LocalizedDate(value: user.createdAt, dateStyle: .short) public var createdAt
    @LocalizedStrings public var bulletPoints // YAML array
    public var vmId = ViewModelId()
}
```

### The localizable contract — `Localizable` / `LocalizableStatus`
Reach for this when: writing code generic over localized values, or checking
whether a value has been resolved. `localizedString` throws until the value has
passed through a localizing encode (`localizationStatus == .localized`);
`localizedArray` exposes compound pieces individually.

```swift
if viewModel.title.localizationStatus == .localized {
    let text = try viewModel.title.localizedString
}
```

### Carry a string through localization — `LocalizableString`
Reach for this when: a ViewModel property, error message, or field title is a
string that may be locale-dependent. `.constant` passes fixed text through
untouched (ideal for stubs); `.localized(key:)` references the YAML store.
`defaultOkTitle` / `defaultCancelTitle` / `defaultSaveTitle` cover stock
button labels.

```swift
let fixed = LocalizableString.constant("42")
let greeting = LocalizableString.localized(key: "landing.greeting")
let title: LocalizableString = .localized(for: Self.self, propertyName: "title")
```

### Locale-formatted values — `LocalizableInt` / `LocalizableDouble` / `LocalizableDate` / `LocalizableValue`
Reach for this when: a number or date must display with the *user's* grouping
separators, fraction digits, or date style. The raw value stays available via
`value`; the formatted string comes from localization.
Don't format with NumberFormatter/DateFormatter in a view — the server has the
request's Locale, the view may not.

```swift
let count = LocalizableInt(value: 42_495) // "42,495" / "42.495" per Locale
let price = LocalizableDouble(value: 3.14159, maximumFractionDigits: 2)
let due = LocalizableDate(value: .now, dateStyle: .medium)
```

### Combine localizable pieces — `LocalizableCompoundValue` / `joined()`
Reach for this when: joining localized parts (name components, sentence
fragments) into one value. Locale semantics — including right-to-left ordering
— are handled during localization, so never pre-order or concatenate manually.

```swift
let fullName = [firstName, lastName].joined(separator: .constant(" "))
```

### Substitute values into localized text — `LocalizableSubstitutions`
Reach for this when: a localized string has dynamic holes, written as
`%{key}` in the YAML. Bind each key to any `Localizable`. On ViewModels,
prefer the `@LocalizedSubs(substitutions:)` wrapper bound to a keypath.

```swift
// YAML: quotaExceeded: "Requested %{requested} exceeds %{maximum}"
let message = LocalizableSubstitutions(
    baseString: .localized(key: "MyError.quotaExceeded"),
    substitutions: ["requested": LocalizableInt(value: 12),
                    "maximum": LocalizableInt(value: 10)]
)
// On a ViewModel, the wrapper form:
@LocalizedSubs(substitutions: \.substitutions) var message
private var substitutions: [String: any Localizable] { ["requested": LocalizableInt(value: 12)] }
```

### Localizable collections — `LocalizableArray`
Reach for this when: a property carries a YAML block sequence (a list of
strings) or a fixed array of localizable values — `.localized(key:)` for
store-backed arrays, `.constant` for fixed ones. `@LocalizedStrings` wraps
this for ViewModel properties.

```swift
let steps: LocalizableArray<LocalizableString> = .localized(key: "Onboarding.steps")
```

### Reference YAML keys directly — `LocalizableRef` / `LocalizableId`
Reach for this when: the property wrappers can't express the binding — nested
types (`parentType:`), enum-case messages, or indexed array values. This is
the low-level key language the wrappers compile down to.

```swift
let ref = LocalizableRef.value(keys: "level1", "level2", "value")
let display = LocalizableString.localized(.init(
    for: Self.self, parentType: ParentViewModel.self, propertyName: rawValue))
```

### Load YAML localization stores — `yamlLocalization()` / `LocalizationStore` / `YamlStoreError`
Reach for this when: an application hosts its own YAML resources (client-hosted
ViewModels, tools, tests) and needs a store to hand to `localizingEncoder()`
or `MVVMEnvironment`. Works on a single Bundle or a collection of Bundles;
`translate()`/`value()` (and the `t()`/`v()` shorthands) do raw lookups.
Don't parse YAML yourself — the store flattens, merges, and locale-falls-back
for you, and failures arrive as typed `YamlStoreError` cases.

```swift
let store = try Bundle.main.yamlLocalization(resourceDirectoryName: "Resources")
let title = store.t("MyViewModel.title", locale: Locale(identifier: "en"))
```

### Diagnose localization failures — `LocalizerError` / `LocalizedPropertyError` / `LocalizedArrayPropertyError`
Reach for this when: catching localization errors — `localizationUnbound`
means a value was read before encoding resolved it; `localizationStoreMissing`
means the encoder wasn't created via `localizingEncoder()`.

```swift
catch let error as LocalizerError { logger.error("\(error.debugDescription)") }
```

## Macros

The macro surface — how ViewModels, validation-message models, and versioned
factories are actually declared. The macros generate the
`RetrievablePropertyNames` plumbing and protocol conformances so you never
write them by hand; `ViewModelOptions` tunes `@ViewModel`'s output.

### Declare a ViewModel — `@ViewModel` / `ViewModelOptions`
Reach for this when: creating any View-Model — always the macro, never bare
protocol conformance (the macro generates the `propertyNames()` localization
bindings; hand conformance breaks OCP and silently unbinds `@LocalizedString`).
Tune the output through `options:`: `.clientHostedFactory` generates
`ClientHostedViewModelFactory` support; `.live` makes the ViewModel refresh
automatically when its server data changes (`LiveViewModel`, under Protocols).
Scaffolded by `fosmvvm-viewmodel-generator`.

```swift
@ViewModel
public struct LandingPageViewModel: RequestableViewModel {
    public typealias Request = LandingPageRequest
    @LocalizedString public var pageTitle
    public var vmId = ViewModelId()
    public init() {}
}
```

### Generate validation-message models — `@FieldValidationModel`
Reach for this when: grouping the localized messages a Fields protocol's
validators emit — the macro binds each `@LocalizedString` to its YAML key and
provides `stub()`/`init()`. Scaffolded by `fosmvvm-fields-generator`.

```swift
@FieldValidationModel
public struct UserFieldsMessages {
    @LocalizedString(parentKeys: "email", "validationMessages") public var emailRequired
}
```

### Version a ViewModel factory — `@VersionedFactory` / `@Version`
Reach for this when: a ViewModel's shape has changed across releases and the
server must build the variant the *requesting client* understands. Mark each
factory method with its first-valid version; the macro generates the
`model(context:)` dispatch (newest compatible wins, else
`ViewModelFactoryError.versionNotSupported`).

```swift
@VersionedFactory
extension UserViewModel: ViewModelFactory {
    @Version(SystemVersion(major: 2))
    static func model_v2_0_0(context: Context) async throws -> Self { ... }
}
```

## Protocols

The contracts of the MVVM pattern: the ViewModel role and its identity, the
HTTP-aligned `ServerRequest` hierarchy and its CRUD refinements, the factory
protocols that project data into ViewModels, and the Model/validation roles —
plus the view-operations contract and the macro-generated localization
plumbing. This folder also declares the model-identity and containment surface
the server side loads through: opaque `ModelIdentity`, the `Container` /
authorization vocabulary, client-chosen sort and pagination, the rooted/targeted
query traits, and the composable-factory data-requirement declarations. Those
declarations are executed by FOSMVVMVapor (see `FOSMVVMVapor.md § Containment`,
`§ Protocols`). Most conformances are generated by the macros or scaffolded by
the `fosmvvm-*-generator` skills.

### The ViewModel contract — `ViewModel` / `ViewModelConfiguration`
Reach for this when: understanding what `@ViewModel` generates — a Codable
`ServerRequestBody` with a `vmId` identity, `Stubbable`, and localization
bindings. A ViewModel is a *projection of* data, never the data (SRP).
Don't conform directly — apply the `@ViewModel` macro (see Macros).

```swift
@ViewModel public struct UserViewModel {
    public let firstName: String
    public var vmId = ViewModelId()
}
```

### Stable rendering identity — `ViewModelId`
Reach for this when: giving a ViewModel its `vmId`. Bind it to the underlying
model's identity whenever possible; use the type for singleton ViewModels.
`vmId` is *rendering* identity (SwiftUI `ForEach`/`.id`) — data identity is a
separate `id: ModelIdType` property that round-trips through requests.
Don't default to the random initializer casually — random identity churns
SwiftUI's view cache on every update.

```swift
self.vmId = .init(id: user.id) // bound to model identity
self.vmId = .init(type: Self.self) // singleton ViewModel
```

### Make a ViewModel requestable — `RequestableViewModel` / `ViewModelRequest`
Reach for this when: a ViewModel is fetched from the web service — the
ViewModel names its `Request`, and the request (a `ShowRequest` returning the
ViewModel) carries an optional `Query` for parameters. `request.viewModel`
returns the response body (or a stub before processing). Scaffolded by
`fosmvvm-serverrequest-generator`.

```swift
@ViewModel public struct UserViewModel: RequestableViewModel {
    public typealias Request = UserViewModelRequest
    // ...
}
```

### The HTTP request contract — `ServerRequest` / `ServerRequestAction` / `ServerRequestQuery` / `ServerRequestFragment` / `ServerRequestBody` / `ServerRequestError`
Reach for this when: defining any client↔server interaction — every client
(SwiftUI, CLI, web) goes through a `ServerRequest`; nothing talks to endpoints
by URL string. The pieces map onto HTTP: `action` (`.show`/`.create`/`.update`/
`.replace`/`.delete`/`.destroy` → GET/POST/PATCH/PUT/DELETE), `Query`,
`Fragment`, `RequestBody`, `ResponseBody`; a unique path is derived from the
type names automatically. `ResponseError` carries the operation's *thrown*
error across the wire — the error the operation would throw as a local call;
the server throws it and `processRequest` rethrows the same `Codable` error
client-side. It is not an HTTP-status mapping: branch by catching the typed
case, never by reading a status.
Don't hand-build URLs or raw URLSession calls — that is the stringly-typed
encapsulation break this hierarchy exists to prevent.

```swift
final class UserViewModelRequest: ViewModelRequest, @unchecked Sendable {
    typealias Fragment = EmptyFragment
    let query: Query?
    var responseBody: UserViewModel?

    struct Query: ServerRequestQuery { let userId: Int }
    // init(query:fragment:requestBody:responseBody:)...
}
```

### Catch a credential rejection typed — `CredentialRejectedError`
Reach for this when: a request to a protected route may be rejected before the
operation runs — catch the typed error (`.missing` = no credential configured;
`.invalid` = presented and refused → refresh and retry, safe because the
operation never ran); never branch on an HTTP status. It always throws to the
caller (never `requestErrorHandler`).

```swift
} catch let error as CredentialRejectedError {
    switch error.code {
    case .missing: ... // check the MVVMEnvironment's clientCredentialProvider
    case .invalid: ... // refresh the credential and retry
    }
}
```

### Placeholders for unused pieces — `EmptyQuery` / `EmptyFragment` / `EmptyBody` / `EmptyError`
Reach for this when: a request has no query, fragment, body, or well-defined
error — typealias the slot to the Empty type and the protocol's default
implementations return nil for you.

```swift
typealias Query = EmptyQuery
typealias ResponseError = EmptyError
```

### Send a request and read the response — `processRequest()` / `requestURL()` / `appending()` / `ServerRequestProcessingError`
Reach for this when: executing a `ServerRequest`. The `mvvmEnv:` overload picks
the deployment's base URL, applies versioning headers, and routes failures to
the environment's error handler; the `baseURL:` overload is for tools and
tests. `requestURL(baseURL:)` / `URL.appending(serverRequest:)` expose the
composed URL without sending.

```swift
let request = UserViewModelRequest(query: .init(userId: id))
try await request.processRequest(mvvmEnv: mvvmEnv)
let viewModel = request.viewModel
```

### CRUD write requests — `CreateRequest` / `UpdateRequest` / `ReplaceRequest` / `DeleteRequest` / `DestroyRequest` / `CreateResponseBody` / `UpdateResponseBody` / `ReplaceResponseBody` / `DeleteResponseBody` / `DestroyResponseBody`
Reach for this when: an entity supports writes — adopt only the verbs it
supports (that's why they're separate protocols). Each sets `action` and path
naming for you; create/update/replace require the `RequestBody` to be a
`ValidatableModel` so the Fields contract validates at every layer. `delete`
is a soft delete; `destroy` is permanent removal. Scaffolded by
`fosmvvm-serverrequest-generator`; tests by
`fosmvvm-serverrequest-test-generator`.

```swift
final class UserCreateRequest: CreateRequest, @unchecked Sendable {
    typealias ResponseError = ValidationError
    let requestBody: UserFormFields? // a ValidatableModel
    var responseBody: NewUserBody? // a CreateResponseBody
    // ...
}
```

### Lightweight reads — `ShowRequest` / `ShowResponseBody`
Reach for this when: retrieving plain data that doesn't warrant full ViewModel
machinery (lookups, exports). `ViewModelRequest` is the ViewModel-returning
refinement of this protocol.

```swift
final class PingRequest: ShowRequest {
    struct ResponseBody: ShowResponseBody { let serverTime: Date }
    // ...
}
```

### Validated writes that return a ViewModel — `ValidatableViewModelRequest` / `ValidatableViewModelRequestError`
Reach for this when: submitting form data and re-rendering from the response —
a POST-by-default request whose body is a `ValidatableModel` and whose error
type carries `[ValidationResult]` back to the form.

```swift
public struct ResponseError: ValidatableViewModelRequestError {
    public let validations: [ValidationResult]
    public init(validations: [ValidationResult]) { self.validations = validations }
}
```

### Attach a credential to every request — `ClientCredentialProvider` / `BearerCredentialProvider`
Reach for this when: the app must authenticate its ServerRequests (a bearer
token, an API key) without per-call header plumbing — set a provider once on
`MVVMEnvironment` and `processRequest(mvvmEnv:)` consults it on every request,
so a credential that rotates mid-session is picked up on the next call. A `nil`
token sends no header (the request proceeds unauthenticated). The server-side
complement is `ClientCredentialMiddleware` (see `FOSMVVMVapor.md § Middleware`).
To recover from a *server-side* rotation — the credential you presented was
refused — implement `credentialHeaders(afterRejection:)` on your own conforming
type: refresh, return replacement headers, and the request is retried exactly
once (the live-invalidation channel nudges the same seam on an SSE 401 — there
it always reports `.invalid` and may nudge once per failed reconnect, not just
once); returning `nil` — the default — rethrows the `CredentialRejectedError`
to the caller. Persist the refreshed credential — the retry headers apply once; every
later request and every reconnect consults `credentialHeaders()` again.
`BearerCredentialProvider` does not refresh (a refused token throws).
Don't bake a token into the static `requestHeaders` — a rotating credential
goes stale there; the provider is the dynamic sibling.

```swift
let env = MVVMEnvironment(
    appBundle: .main,
    clientCredentialProvider: BearerCredentialProvider { await tokens.current },
    deploymentURLs: deploymentURLs
)
```

### Cap upload sizes — `ServerRequestBodySize`
Reach for this when: a request body can be large (file uploads) — set
`maxBodySize` on the `ServerRequestBody` so the server collects the whole
body before processing.

```swift
struct FileUploadBody: ServerRequestBody {
    static var maxBodySize: ServerRequestBodySize? { .mb(50) }
    let fileData: Data
}
```

### Project data into ViewModels — `ViewModelFactory` / `ViewModelFactoryContext` / `ViewModelFactoryError`
Reach for this when: building the server-side factory that maps stores to a
ViewModel — the DIP seam: the ViewModel module never imports the domain
module; the factory adapts. Version the factory with `@VersionedFactory`
(see Macros).

```swift
extension UserViewModel: ViewModelFactory {
    static func model(context: Context) async throws -> Self {
        // query the stores via context, then project into the ViewModel
        .init(user: user)
    }
}
```

### Host ViewModels in the client — `ClientHostedViewModelFactory` / `ClientHostedModelFactoryContext`
Reach for this when: a ViewModel is composed locally (no web service) — pure
UI state, previews, offline features. The context supplies the locale, a
client-side `LocalizationStore`, the request, and your `AppState`; localization
happens on-device. Generated by `@ViewModel(options: [.clientHostedFactory])`;
the client `bind(appState:)` overloads consume it.

```swift
extension MyViewModel: ClientHostedViewModelFactory {
    public struct AppState: Hashable, Sendable { public let isExpanded: Bool }
    public static func model(
        context: ClientHostedModelFactoryContext<Request, AppState>
    ) async throws -> Self {
        .init(isExpanded: context.appState.isExpanded)
    }
}
```

### Mark the Model role — `Model` / `ModelError`
Reach for this when: declaring a type as the **Model** in M-V-VM — Codable,
identity-based equality/hashing, and an optional `id: ModelIdType` (see
FOSFoundation's Data section) with `requireId()` for the not-yet-persisted case.

```swift
let userId = try user.requireId() // throws ModelError.missingId when id is nil
```

### The data-validation contract — `ValidatableModel`
Reach for this when: a Fields protocol or request body owns validation rules.
Implement one `validate(fields:validations:)`; the convenience overloads
validate everything, a single field, or return a throwable `ValidationError`.
Fields protocols define the form contract *only* — never ModelIdType fields.

```swift
if let error = userFields.validate() { throw error }
_ = userFields.validate(field: Self.emailField, validations: validations)
```

### Reset fields to their initial values — `ResettableModel`
Reach for this when: implementing form cancel/revert — the default
implementation mirrors through the model and resets every nested
`ResettableModel`, including `@FormFieldModel` values back to `initialValue`.

```swift
formModel.resetFields()
```

### Mockable view actions — `ViewModelOperations`
Reach for this when: a view triggers behavior (button taps, saves) — factor
the actions behind an operations protocol so UI tests substitute a recording
stub. Pairs with `testDataTransporter()` (see SwiftUI Support) to assert calls
from XCUITests. Scaffolded by `fosmvvm-viewmodel-generator`.

```swift
public protocol ButtonViewModelOperations: ViewModelOperations {
    func buttonClicked()
}
```

### Localization plumbing — `RetrievablePropertyNames`
Reach for this when: reading macro-generated code — it binds each localized
property wrapper to its property name for YAML lookup.
Don't implement it by hand; `@ViewModel` and `@FieldValidationModel` generate
the conformance.

```swift
// Generated by @ViewModel — never written manually:
func propertyNames() -> [LocalizableId: String]
```

### Identify which entity a model is — `ModelIdentity` / `ModelNamespace`
Reach for this when: you need to compare, route on, key a dictionary/set by, or
persist *which* entity a `Model` is — without touching its raw id or type. Get one
from `model.modelIdentity`; it is opaque and value-comparable. `ModelNamespace`
identifies the *kind* (`Model.modelIdentityNamespace` supplies a default; override
it only to survive a future rename of the model type).
Don't stringly-type an identity — a `ModelIdentity` cannot be forged, parsed, or
read back out, and that is the point.

```swift
let identity = try user.modelIdentity           // opaque, Hashable, Codable
if identity == changedModel { refresh() }         // compare to a live model of any type
self.vmId = try user.modelIdentity.viewModelId    // derive a stable ViewModelId
```

Contract: treat it as opaque — encode/decode it *as a whole* to persist or transmit
it (the encoding is stable within a library major version and always round-trips);
never parse or hand-construct its encoded form.

### A ViewModel that knows its model — `ModelIdentifiedViewModel`
Reach for this when: a ViewModel projects one specific entity (a user, a document,
a list row) and you want identity-based behavior (e.g. live refresh) keyed to it.
Singleton or ephemeral ViewModels don't conform — they keep only `vmId`.

```swift
@ViewModel
struct UserViewModel: RequestableViewModel, ModelIdentifiedViewModel {
    let modelIdentity: ModelIdentity
    let vmId: ViewModelId
    init(user: User) throws {
        self.modelIdentity = try user.modelIdentity
        self.vmId = modelIdentity.viewModelId
    }
}
```

### Refresh a screen when its server data changes — `LiveViewModel`
Reach for this when: a bound screen must re-fetch automatically after another
actor mutates the data it was served from — opt in with
`@ViewModel(options: [.live])` (never conform `LiveViewModel` directly; the
macro generates the conformance). Any view bound with `.bind()` then refreshes
on each server change — no polling, no manual invalidation. Where no live
connection is configured the ViewModel behaves exactly like a non-live one
(fetch once on appear), so adding `.live` to a shipped screen is purely
additive. The server half lives in `FOSMVVMVapor.md § Live Invalidation`.

```swift
@ViewModel(options: [.live])
public struct DocksViewModel: RequestableViewModel { /* ... */ }
```

### Replace the live-invalidation transport — `InvalidationChannel` / `InvalidationEvent`
Reach for this when: the standard live-invalidation transport won't do (a shared
push socket, a custom connection) and you must supply your own — conform a
`Sendable` type whose `events()` yields an `InvalidationEvent` stream and hand it
to `MVVMEnvironment(invalidationChannel:)`. Yield `.connected` each time your
transport (re)establishes — FOSMVVM refreshes every live screen — and
`.invalidated` with each identity set the server pushes. Most apps never conform
this: leave `invalidationChannel` nil and FOSMVVM synthesizes the standard
channel over the deployment URLs.
Don't hand-wire per-screen refresh — one channel feeds every
`@ViewModel(options: [.live])` screen at once.

```swift
struct MyChannel: InvalidationChannel {
    func events() -> AsyncStream<InvalidationEvent> { myStream }
}
let env = MVVMEnvironment(
    appBundle: .main,
    invalidationChannel: MyChannel(),
    deploymentURLs: deploymentURLs
)
```

### Own and authorize contained records — `Container` / `AuthorityFlow`
Reach for this when: a model owns other records (a `Dock` owns its `Berth`s) and
those records need authorized loading and live-invalidation membership. List what it
contains; declare `authorityFlow` only to anchor authority at a container rather than
inherit it from an ancestor. A model that owns nothing needs no override.
The Fluent-backed conformance and per-relation joins live in
`FOSMVVMVapor.md § Containment` (`ContainerDataModel` / `ContainmentRelation`).

```swift
struct Dock: Container {
    static var containedRecordTypes: [any Model.Type] { [Berth.self] }
    // .inherits by default; declare .guards to require a grant anchored here
    static var authorityFlow: AuthorityFlow { .guards }
}
```

### Authorization verbs and grant checks — `ContainerOperation` / `authorizes()` / `authorizesReadRecords` / `authorizesWriteRecords` / `authorizesCreateRecords` / `authorizesDeleteRecords` / `authorizesDestroyRecords`
Reach for this when: checking what a granted operation set permits. Check by
**intent**, never by comparing cases — the intent accessors (and `authorizes(_:)`
on a set) honor the `.anyOperation` wildcard, which grants everything *except*
`.destroyRecords`.
Don't use `contains(_:)` on the set — it silently ignores the wildcard grant.

```swift
if grantedOperations.authorizesReadRecords { /* load */ }
grantedOperations.authorizes(.createRecords)     // wildcard-aware
```

### Answer whether a subject may touch records — `ContainerAuthorization`
Reach for this when: modeling one persisted grant your app resolves per subject —
conform a `Sendable` value type (project it from a Fluent grant row) that answers
"may this operation, on this record type, in this container, proceed?". The framework
never sees your role or user types; it only asks each authorization. A subject with no
covering authorization simply loads an empty set — routes are never where data access
is enforced. Registered and invoked via `FOSMVVMVapor.md § Containment`
(`ContainerAuthorizationProvider`).

```swift
struct DockGrant: ContainerAuthorization {
    let authorizedContainer: ModelIdentity
    let operations: [ContainerOperation]
    let recordTypes: [ModelNamespace]
    func authorizes(_ operation: ContainerOperation,
                    ofType recordType: any Model.Type,
                    in container: ModelIdentity) -> Bool {
        container == authorizedContainer
            && operations.authorizes(operation)
            && recordTypes.contains(recordType.modelIdentityNamespace)
    }
}
```

### Client-chosen ordering — `ServerRequestSort` / `SortCriteria` / `SortKey` / `SortTerm` / `SortDirection` / `EmptySort`
Reach for this when: a request lets the client choose an ordering. Publish the
sortable *meanings* as a `SortKey` enum (never storage columns); the client sends a
`SortCriteria` of ordered `SortTerm`s. `ServerRequest`'s `Sort` associated type
defaults to `EmptySort` for requests that expose no ordering. The server maps each
meaning to database columns via `FOSMVVMVapor.md § Containment` (`SortableDataModel`).

```swift
enum BerthSortKey: String, SortKey { case number, dockName }
let sort = SortCriteria<BerthSortKey>([
    .init(key: .dockName, direction: .ascending),
    .init(key: .number, direction: .descending),
])
```

### Page through a large result set — `PaginatedQuery` / `Pagination`
Reach for this when: a request's query needs a result window. Conform the query to
`PaginatedQuery` and vend a `Pagination` (`startIndex` / `maxResults`, both optional);
non-paginated queries stay as they are. The load engine applies the window only when
the query conforms.

```swift
struct BerthsQuery: PaginatedQuery {
    var pagination: Pagination { .init(startIndex: 0, maxResults: 25) }
    // ...ServerRequestQuery requirements...
}
```

### Root a request's containment scope — `RootedQuery`
Reach for this when: a request opens a fresh containment scope and the client names
the root container — the trait-overlay idiom used by `PaginatedQuery`. A load declared
`.newRoot(.query)` reads `rootIdentity` to resolve its scope. A request roots at most
one `.query`-vended container.

```swift
struct HarborBerthsQuery: RootedQuery {
    let rootIdentity: ModelIdentity   // the Harbor this request is scoped to
}
```

### Where a load roots — `RootScope` / `RootSource`
Reach for this when: declaring a `LoadRequirement` or `ComposedChild` and stating where
its scope roots. Read it as the preposition at the call site: `.parentRoot` shares the
declaring factory's scope (the common case); `.newRoot(.query)` roots at the request's
`RootedQuery` value; `.newRoot(.apex)` roots at the app's apex container (server-resolved,
no query — registered via `FOSMVVMVapor.md § Containment`).

```swift
.read(Berth.self, in: .parentRoot)               // shares the factory's scope
.read(HarborBanner.self, in: .newRoot(.apex))     // a fresh tree at the apex
```

### Declare and compose a factory's data — `ComposableFactory` / `ComposedChild`
Reach for this when: a server-rendered `ServerRequestBody` (ViewModel or not) needs data
loaded before it is built, and/or composes child factories. `dataRequirements` lists this
factory's own loads; `children` lists child factories — only `ComposableFactory`-conforming
types can appear, so an undeclared child cannot be composed (it won't compile). Declarations
are aggregated at boot and loaded once. Adopting the trait and declaring nothing fails fast
at boot. Executed by `FOSMVVMVapor.md § Protocols` (`VaporResponseBodyFactory`).

```swift
extension BerthsViewModel: ComposableFactory {
    static let berths = LoadRequirement.read(Berth.self, in: .parentRoot).refinedByRequest
    static var dataRequirements: [any DataRequirement] { [berths] }
    static var children: [ComposedChild] {
        [.child(BerthCellViewModel.self),
         .child(HarborBannerViewModel.self, rootedAt: .apex)]
    }
}
```

### Declare a typed, authorized load — `DataRequirement` / `LoadRequirement`
Reach for this when: naming one data need of a `ComposableFactory`. Mint requirements
with the `LoadRequirement` verbs — never conform to `DataRequirement` directly (it is a
sealed marker; a foreign conformance is rejected at boot). Declare each as a stored
`static let` (a computed property mints a fresh identity per access and breaks the
projection read-back). `read()` is a factory load; `write()` / `create()` / `delete()`
load a write request's candidate set; `via:` lists *intermediate* containment hops only
(the terminal hop is implicit); `refinedByRequest` marks the one requirement the request's
own sort/pagination axes apply to.

```swift
static let berths = LoadRequirement.read(Berth.self, in: .parentRoot).refinedByRequest
static let slips  = LoadRequirement.read(SlipAssignment.self, in: .parentRoot, via: Berth.self)
```

### Name which loaded record a write targets — `TargetedQuery`
Reach for this when: an update/delete request must say which loaded record it acts on.
The selector is the record's opaque `ModelIdentity` — the identity the client received
inside the ViewModel it displayed, echoed back verbatim; the form body never carries a
raw id. The server resolves it against the auth-scoped candidate set it loaded itself, so
a submit cannot retarget, and resolution failure is indistinguishable from not-found.
The candidate set and field application live in `FOSMVVMVapor.md § Protocols`
(`WriteTargetProviding` / `DataModelWriter`).

```swift
struct UpdateBerthQuery: TargetedQuery, RootedQuery {
    let rootIdentity: ModelIdentity   // the scope root
    let target: ModelIdentity         // which berth
}
```

## SwiftUI Support

Binding ViewModels to SwiftUI: app configuration, the `ViewModelView`
pattern, binding invalidation/refresh, form rendering, the operation buses
for coordinating multi-view actions, the generated `Localizable` overload
surface (every SwiftUI initializer and modifier that takes a
`LocalizedStringKey` has a `Localizable`-accepting twin), preview hosting, and
the UI-testing bridge. Platform-gated to targets where SwiftUI is available.

### Configure the app for MVVM — `MVVMEnvironment` / `MVVMEnvironmentError`
Reach for this when: setting up the `@main` App — register an
`MVVMEnvironment` in the SwiftUI environment with per-`Deployment` server
URLs; it also establishes the app's SystemVersion at startup. Missing
deployment URLs throw `MVVMEnvironmentError` when a request resolves.
For live-updating screens, `invalidationChannel:` overrides the invalidation
transport (see `InvalidationChannel` under Protocols) and a `URLPackage`'s
`invalidationBaseURL` overrides where the default channel connects (defaults to
the server base URL). Scaffolded by `fosmvvm-swiftui-app-setup`.

```swift
WindowGroup { RootView() }
    .environment(MVVMEnvironment(
        appBundle: Bundle.main,
        deploymentURLs: [
            .production: URL(string: "https://api.example.com")!,
            .debug: URL(string: "http://localhost:8080")!
        ]
    ))
```

### Bind a ViewModel to a view — `ViewModelView` / `bind()` / `ViewModelViewError` <!-- apple-only -->
Reach for this when: writing any SwiftUI view over a ViewModel — conform to
`ViewModelView` (not bare View) and let the parent call `bind()`: it shows the
environment's loading view, fetches via the ViewModel's `Request` (or the
client-hosted factory / `appState:` overloads), and rebinds when the query
changes. Scaffolded by `fosmvvm-swiftui-view-generator`.
Don't fetch ViewModels in `onAppear`/`task` by hand.

```swift
struct UserView: ViewModelView {
    let viewModel: UserViewModel
    var body: some View { Text(viewModel.pageTitle) }
}
// In the parent:
UserView.bind(query: .init(userId: id))
```

### Localizable twins for SwiftUI inits and modifiers — `navigationTitle()` / `navigationSubtitle()` / `searchable()` / `help()` / `badge()` / `alert()` / `confirmationDialog()` / `dismissalConfirmationDialog()` / `dialogSuppressionToggle()` / `typeSelectEquivalent()` / `fileDialogMessage()` / `fileDialogConfirmationLabel()` / `fileExporterFilenameLabel()` / `text` <!-- apple-only -->
Reach for this when: showing or labeling with a ViewModel's `Localizable` value
anywhere SwiftUI expects a `LocalizedStringKey`. Every Apple initializer and
modifier that takes a `LocalizedStringKey` has a `some Localizable`-accepting
twin — call it exactly like Apple's, passing the ViewModel property in the
string-key slot; an optional `defaultValue:` follows that slot as the fallback
shown when localization hasn't completed.
Don't resolve a `Localizable` to a `String` and hand it to Apple's initializer —
the twin resolves it for you and keeps the call site declarative.

```swift
Button(viewModel.cta) { save() }               // init twin
ContentUnavailableView(viewModel.emptyTitle, systemImage: "tray")
Text(viewModel.pageTitle)                      // init twin
    .navigationTitle(viewModel.navTitle)       // modifier twin
```

The twin surface spans 44 SwiftUI types (inits and modifiers): init twins on
Text, Button, Label, TextField, Toggle, Picker, Link, Menu, Section, Tab,
ContentUnavailableView, and more; modifier twins on View, ModifiedContent,
Scene, Text, and TabContent. The accessibility modifiers have their own entry
below.
`localizable.text` resolves a still-pending value on the client against the
environment's store — for a stubbed or locally-built value that never
round-tripped the server; a server-localized value uses `Text(localizable)`.
Contract: the twins mirror Apple's own signatures (labels, arity, generic
constraints), inserting `defaultValue:` immediately after each localizable slot.
Not sure a specific call has a twin? The coverage ledger is
`Sources/FOSMVVM/SwiftUI Support/SweepCoverage.md`.

### Localizable accessibility modifiers — `accessibilityLabel()` / `accessibilityHint()` / `accessibilityValue()` / `accessibilityAction()` / `accessibilityRotor()` / `accessibilityCustomContent()` / `accessibilityDragPoint()` / `accessibilityDropPoint()` / `accessibilityScrollStatus()` <!-- apple-only -->
Reach for this when: labeling accessibility surfaces with a ViewModel's
`Localizable` — the same twin pattern as the entry above (Apple's signature,
`defaultValue:` after the localizable slot) on every accessibility modifier
that takes a `LocalizedStringKey`, on View, ModifiedContent, Text, and
TabContent.

```swift
Button(viewModel.cta) { save() }
    .accessibilityLabel(viewModel.saveLabel)
    .accessibilityHint(viewModel.saveHint)
```

### Refresh a stale ViewModel binding — `invalidateBinding()` / `refreshedViewModel()` <!-- apple-only -->
Reach for this when: a mutation makes a bound ViewModel out of date —
`invalidateBinding($flag)` re-pulls from the server when the flag turns true;
`refreshedViewModel($vm)` swaps in a replacement you already have (e.g., a
mutation response) without a second round trip.

```swift
UserSubView.bind()
    .invalidateBinding($userOutOfDate)
```

### Present form fields — `FormFieldView` <!-- apple-only -->
Reach for this when: rendering a `FormFieldModel` — it selects the
platform-appropriate control, keyboard, and autocomplete from the `FormField`
spec, debounces `onNewValue`, and runs the field validator on blur/submit.

```swift
@FocusState private var focusField: FormFieldIdentifier?

Form {
    FormFieldView(fieldModel: viewModel.$email, focusField: $focusField)
}
```

### Coordinate multi-view form actions — `SyncOperationBus` / `AsyncOperationBus`
Reach for this when: a parent view collects data or triggers work across many
child `ViewModelView`s (one Save button, several sections). Children register
per-`vmId` operations (re-registration replaces, so view reappearance is
safe); the parent invokes them all — synchronously with an `inout` value, or
concurrently via task group.

```swift
let saveBus = SyncOperationBus<FormData>()
saveBus.addOperation(for: viewModel) { formData in formData.name = name }
var data = FormData()
saveBus.invoke(&data)
```

### Preview with localized stub data — `previewHost()` <!-- apple-only -->
Reach for this when: writing a #Preview for a `ViewModelView` — hosts the view
with `VM.stub()` (or a supplied ViewModel), resolves `@LocalizedString`
bindings from the bundle's YAML, and can set `@State` via `setStates:`.

```swift
#Preview { UserView.previewHost() }
```

### Host views for UI tests — `testHost()` / `testHostRequest` / `registerTestView()` <!-- apple-only -->
Reach for this when: wiring an app target for FOSTestingUI's
ViewModelViewTestCase — wrap the root view in `testHost()` (optionally
decorating the view under test with test bindings) and register each testable
view type on the `MVVMEnvironment`. DEBUG-only; release builds compile it away.
Scaffolded by `fosmvvm-ui-tests-generator`.

```swift
WindowGroup {
    RootView()
    #if DEBUG
    .testHost()
    #endif
}
// at startup: mvvmEnv.registerTestView(UserView.self)
```

### Assert operations from XCUITests — `TestDataTransporter` / `testDataTransporter()` <!-- apple-only -->
Reach for this when: verifying that UI interactions called your
`ViewModelOperations` — the modifier serializes the (stub) operations into a
hidden accessibility element that the test case reads back and decodes.
DEBUG-only. Toggle `repaintToggle` after each recorded call so the transported
JSON refreshes.

```swift
VStack { /* fields and buttons */ }
    .testDataTransporter(viewModelOps: operations, repaintToggle: $repaintToggle)
```

### Tag elements for XCUITest — `uiTestingIdentifier()` <!-- apple-only -->
Reach for this when: an XCUITest must locate an element — sets the
accessibility identifier in DEBUG builds only, on both View and (iOS 18/
macOS 15) TabContent.
Don't localize-and-match on display text in tests — it breaks every
translation run.

```swift
Button(action: save) { Text(viewModel.saveTitle) }
    .uiTestingIdentifier("saveButton")
```

## Validation

The result side of validation: individual outcomes, collection aggregation,
observable form state, and the wire-format error. The rules themselves live on
`ValidatableModel` (Protocols) with messages from `@FieldValidationModel`
(Macros).

### Report a validation outcome — `ValidationResult`
Reach for this when: a validator finds something to say — `.info`, `.warning`,
or `.error` with localized, field-correlated messages the UI displays next to
the offending control(s).

```swift
results.append(.init(
    status: .error,
    field: Self.emailField,
    message: messages.emailRequired
))
```

### Aggregate outcomes across fields — `isValid` / `hasError` / `aggregate`
Reach for this when: reducing a collection of `ValidationResult`s to one
answer — `aggregate` returns the most severe status (nil when empty means "no
issues"); `isValid` only checks for errors, so warnings still pass.

```swift
guard validationResults.isValid else { return validationResults.aggregate }
```

### Observable form validation state — `Validations`
Reach for this when: driving SwiftUI from live validation — an `@Observable`
box of results that `FormFieldView` updates per-field. `replace(with:)` swaps
results for just the re-validated fields; `validationError` converts an error
state into a throwable.

```swift
let validations = Validations()
_ = userFields.validate(validations: validations)
if validations.hasError { /* disable Save */ }
```

### Send validation failures over the wire — `ValidationError`
Reach for this when: a server-side validator rejects a CRUD/form submission —
the stock `ValidatableViewModelRequestError` that carries the
`[ValidationResult]` back to the client's form.

```swift
if let error = userFields.validate() { throw error }
```

## Versioning

Deployment selection and client/server version negotiation, building on
FOSFoundation's SystemVersion (catalogued there). Covers the environment enum,
property-level versioning of ViewModels, and the HTTP version handshake.

### Choose the server per environment — `Deployment`
Reach for this when: anything differs between production, staging, debug,
test, or a custom environment — most visibly which base URL `MVVMEnvironment`
resolves. Detection priority: programmatic override → `FOS-DEPLOYMENT` env var
→ Info.plist → TestFlight ⇒ staging → DEBUG ⇒ debug → production.

```swift
switch await Deployment.current {
case .production: enableAnalytics()
default: break
}
await Deployment.overrideDeployment(to: .staging) // testing
```

### Version ViewModel properties — `Versionable` / `Versioned`
Reach for this when: a ViewModel's properties come and go across releases —
mark spans with `vFirst`/`vLast` on the localized wrappers, and wrap versioned
child ViewModels with `@Versioned`. Pair with `@VersionedFactory` (Macros) so
each client version gets the shape it understands.

```swift
@ViewModel struct ProfileViewModel {
    @LocalizedString(vFirst: SystemVersion(major: 2)) var newTitle
    @Versioned(vLast: SystemVersion(major: 2)) var legacyChild: LegacyChildViewModel
    // ...
}
```

### Negotiate versions over HTTP — `addSystemVersioningHeader()` / `versioningHeaders` / `systemVersion` / `requireCompatibleSystemVersion()` / `httpHeader`
Reach for this when: making or checking versioned HTTP traffic outside
`processRequest()` (which stamps the header for you) — add the header to a
URLRequest or `URL.fetch(headers:)`, read the server's version off a response,
or reject incompatible responses in one call.

```swift
urlRequest.addSystemVersioningHeader(systemVersion: .current)
try httpResponse.requireCompatibleSystemVersion() // throws on mismatch
```
