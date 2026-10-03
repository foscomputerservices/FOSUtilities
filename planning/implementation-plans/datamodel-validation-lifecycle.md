# DataModel validation and save lifecycle — implementation plan

Work item: `planning/stream/feat-datamodel-validation-lifecycle.md`. Rulings ledger lives there. This plan is the fosmvvm-planning gate's output: design first, then customer DocC, then contract tests, then decomposition. Sections after Design are written only once the names are ratified.

Status: **Squashed (8 commits). Review round 2 (Part 3d): group A fixes in flight as fixups; OQ33–OQ40 await David; then his read → PR. Release 0.18.0 after merge.**

---

## Part 1 — Design

Concepts first. Names are in the naming table at the end and are David's to arbitrate; every name in the prose below is the candidate from that table.

### 1.1 One protocol carries the hooks; `DataModel` conforms to it

The hooks live in their own protocol, `DataModelLifecycle`, and `DataModel` conforms to it. Every hook is a requirement with a default, so a model that declares none of them saves exactly as today, and a model that wants one declares that one.

Ruled this way for testability and precision: each hook's signature states only what it needs, and a test exercises a hook by calling it with a context built from the Vapor test application. Adoption is one call the developer makes anyway: `register(_:migration:)` with the model's migration wires the lifecycle (1.9, OQ19).

Every hook is a requirement plus a default, never an extension-only method. An extension-only hook would let a model's override compile and silently never run through the middleware's generic call.

### 1.2 The data-model action

Ruled. The phase every hook receives is the action Fluent has already chosen for the row.

```swift
public enum DataModelAction: Sendable, Hashable {
    case create
    case update
    case archive
    case destroy
    case restore
}
```

`DataModelAction` is a new type, the third of three vocabularies, one per layer:

- `HTTPMethod` is transport. Vapor's.
- `ServerRequestAction` is what the client asked for. After the rename: show, create, update, replace, archive, destroy. It rides in the URL and method.
- `DataModelAction` is what Fluent is about to do to one row. Fluent's middleware has five events; a hook needs to know which it is in.

The write route maps each request action to a Fluent call, and Fluent's dispatch (`Model+Concurrency.swift:80` in FluentKit) fixes the action:

- create request → `create(on:)` → `.create`
- update request → `save(on:)` → `.update`
- replace request → `save(on:)` → `.update`
- archive request → `delete(on:)`, guaranteed soft by the delete-timestamp check at route registration (1.11) → `.archive`
- destroy request → `delete(force: true, on:)` → `.destroy`
- show request → no write, no action
- no request yet → `restore(on:)` → `.restore`

A hand-written save outside any request reaches the same five actions through the same Fluent calls.

### 1.3 The sequence, per action

One lifecycle middleware instance per `DataModel`, wired by `register(_:migration:)` (1.9). For each Fluent event it runs, in order:

1. **Will-write.** The model's pre-save hook, `willWrite(in:)`. May mutate itself (derived dates, trimming, flags). May throw, and a throw is an error, never a validation.
2. **Field validation.** The existing `validate(fields: nil, validations:)`. Runs for create and update only. Archive, destroy and restore do not write the model's own columns, so validating them in isolation is meaningless.
3. **Gate.** Errors, or warnings under a blocking policy, stop here with a `ValidationError` carrying everything collected so far. Model validation never runs when field validation failed.
4. **Model validation.** The model judged against other rows in the database. Runs for every action. Receives the `DataModelWriteContext`: the action, the database the middleware was handed (the write route's transaction when the write came through the route), and the `Application`. Returns its results and the middleware appends them (OQ21a); every rule runs; nothing short-circuits inside model validation.
5. **Gate** again, same rule.
6. **Next.** Fluent applies the action. A driver constraint failure raised here is offered to the model (1.7); if the model claims it, it becomes a `ValidationError`; if not, it stays the error it was.
7. **After-write.** `didWrite(in:)`. Same database, so same transaction when there is one. May write rows. A throw rolls the transaction back and propagates as an error.
8. **After-commit.** `didCommit(in:)`, `async` and non-throwing (OQ23). Side effects only. Routed the way the emit middleware already routes: inside a `liveTransaction`, collected and run when the transaction commits; inside a bare transaction, suppressed with the once-per-type warning; auto-commit save, run immediately after step 7. It cannot throw; the author handles their own failures, because the request already succeeded.

Steps 1, 2, 4, 7 and 8 are the hooks (`willWrite`, the `Fields` rules, `validateModel`, `didWrite`, `didCommit`). Steps 3, 5 and 6 belong to the middleware.

### 1.4 What a hook receives

`willWrite` and `didWrite` receive a context value carrying the action, the database, and the `Vapor.Application`. After-commit receives the action and the Application, and no database, because there is no transaction left to be inside. Model validation receives the same `DataModelWriteContext` plus the `Validations` accumulator. That validation does no side effects is a rule of the review check, not of the signature; configuration and metadata on the `Application` are legitimately read there.

The middleware holds the Application weakly, the way the emit middleware holds its registry reader. A context is built per hook call and holds the Application strongly for that call only. After shutdown no hook runs.

`any Database` is Fluent's own currency for a connection and appears here on that basis alone.

### 1.5 Accumulation

Ruled append-only. The middleware creates one `Validations` per event and hands it to field validation and then model validation. Every level appends. Nothing in the framework or the templates assigns `validations.validations` again; the template and the DocC example switch to appending. `Validations` gains nothing; `append(contentsOf:)` on its array is already reachable.

### 1.6 Model-level messages

Ruled first-class. A `ValidationResult.Message` whose field list is empty addresses the model. That is the contract, stated in DocC, not a representation: "a message with no fields is about the model as a whole".

Surface added:

- `ValidationResult(status:message:)`, no field argument, builds a model-level result.
- `ValidationResult.Message.addressesModel`, a computed Bool.
- `Validations.modelMessages`, the model-level messages across all results, for a view that shows them at the top of a form.

Nothing else changes on the wire beyond an empty array being legal where it already was.

A model-level message reaches the client inside the same `ValidationError` as field messages, so it lands in the environment `Validations` the same way, or the request maps it to a `LocalizableError` and `.alert(error:)` shows it. Nothing new on the wire or the client contract.

One view is missing. `FieldValidationsView` shows the first message whose field list contains its field; a message with no field has no view. This work adds a `View` modifier in FOSMVVM's SwiftUI support, `withFormValidations()`, that shows the model-level messages of the environment `Validations` where the form author applies it (OQ6, OQ27).

### 1.7 Constraint violations

Ruled: typed model-level results, with an opt-out to a plain error.

FluentKit's `DatabaseError` protocol (`Database.swift:99`) exposes `isConstraintFailure` on every driver's error, so the middleware can recognise a constraint failure without depending on any driver. It cannot tell which constraint. So the mechanism is:

- The middleware catches a constraint failure around step 6 and wraps it as a `ConstraintViolation` value: the action, and the underlying error for inspection.
- It asks the model, through `validationResult(for:)`, for a `ValidationResult` describing it. The default returns nil.
- nil: the original error is rethrown unchanged. This is the ruled opt-out; a model that does not claim a violation leaves it an internal error.
- A result: the middleware throws `ValidationError` with that result, model-level unless the model chose fields.

The hook is synchronous and receives no database. Classifying a violation is a decision about the model's own schema, not a query.

The consuming project's task-claim case (a create that wins or loses on a unique index) is served, with one honest limit: the claim row also carries a foreign key to its task, and FluentKit cannot tell a uniqueness failure from a foreign-key failure portably. The model inspects `underlyingError` to tell them apart and says so; a best-effort kind on `ConstraintViolation` is not in this work.

### 1.8 Warning policy

Ruled: on the type. A defaulted static on `DataModelLifecycle` returning a two-case policy, advisory or blocking. Advisory is the default: warnings never stop a write. Blocking: a warning at either gate stops the write with a `ValidationError` that carries the warnings, so the client sees them.

**Named consequence, needs your sign-off.** Under the advisory policy a warning collected at the middleware has no channel to the client, because the write succeeds and the response is the refreshed ViewModel. This work logs advisory warnings at info and drops them. Carrying them on a successful response is a wire change to `ResponseBody` and is not proposed here.

### 1.9 Registration

Automatic, by the existing sweep. `useLiveInvalidation(on:)` and `register(_:migration:)` already wire one emit middleware per type reached from every registered container: the container, each contained type, each pivot, one per type. The lifecycle middleware is wired for the same set, in the same two places, with its own coverage set so a type reached through several descriptors gets one instance.

The lifecycle middleware is installed before the emit middleware, so it is the outer one (FluentKit chains in registration order, first installed outermost): prepare and both validations run before anything else touches the row, and the emit fires inside its `next`.

The lifecycle middleware does not depend on live invalidation being enabled. `liveTransaction` always installs the after-commit collector (OQ14), so `didCommit` runs on commit inside `liveTransaction` with or without live invalidation; inside a bare `database.transaction` it is suppressed with a once-per-type warning, because nothing can observe that commit; on an auto-commit save it runs after step 7.

**A `DataModel` no registered container declares.** Ruled: a registration API. It is the existing call with a second overload:

```swift
try app.register(Task.self, migration: Task.Create())
```

where `Task` is a `DataModel`, not a `ContainerDataModel`. The overload is constrained `where IDValue == ModelIdType` (FluentKit's `find` takes `IDValue`; `ContainerDataModel` already carries that constraint, `DataModel` does not). It enters the registry as a descriptor with `containment: []`, `authorityFlow: .inherits`, and a flag marking it as not a container, so `InvalidationIdentitySet.staleIdentities`' `isRegisteredContainer` check stays false for it. Registering it makes `invalidateProjections(of:)` and the emit middleware's own-identity nudge work for it, so a consuming project's after-commit nudge needs no hook at all. Per OQ19 this call is how every `DataModel` enters the registry: it wires the lifecycle middleware and the nudge together, and it replaces a bare `app.migrations.add` for contained types too.

### 1.10 The write route

Ruled: validate, apply, save inside `liveTransaction`. `commitUpdate` and `commitCreate` wrap steps 2 through 6 of their existing sequence in `liveTransaction`, so model validation's reads and the save see one state and the emit flushes on commit. `invalidateWrittenContainers` stays outside, as now.

The request body's `validate()` at the top of each write method stays. It calls `validate(fields: nil, validations:)`, the same `Fields` rules the middleware runs again at field validation with `fields: nil`. Running them twice is cheap, and the body check answers before any candidate load, which the middleware cannot. The open question in the ticket is closed that way: run both, all fields.

### 1.11 Archive and destroy write methods

Ruled. `commitDelete` becomes two methods:

- `commitArchive` serves `ArchiveRequest` with a plain `delete(on:)`, which the delete-timestamp check at route registration has guaranteed is a soft delete.
- `commitDestroy` serves `DestroyRequest` with `delete(force: true, on:)`.

Both inside `liveTransaction` like the other two. `DestroyRequest` is rejected at boot today (`ViewModelRequest.swift`, `rejectWriteProtocolAtReadDoor` throws `unsupportedWriteProtocol`), and one controller may not hold both delete-family actions (`ServerRequestController.swift:73`). So destroy is new work: a `register<SR: DestroyRequest>` overload with its own action table, `serveDestroy`, and `commitDestroy`; the boot rejection is removed.

**The delete-timestamp check.** When a route for a work itemhive action registers (`register(request:app:)`, where the target model type is reachable through the body's `WriteTargetProviding` constraint), the framework builds one fresh instance of the target model and walks its Fluent properties for a delete-triggered timestamp. FluentKit's own `deletedTimestamp` helper is internal, and `AnyTimestamp` with it, but `TimestampProperty` and its `trigger` are public, so an internal FOS protocol with a retroactive conformance on `TimestampProperty` reaches the same fact. No timestamp: a typed `ServerRequestControllerError` case naming the request and model types, with both fixes in its message. Same moment as the existing archive-plus-destroy-on-one-URL rejection, and reported through the same `ServerRequestControllerError`.

### 1.12 The request-side rename

Ruled: `ServerRequestAction.delete` → `.archive`; `DeleteRequest` → `ArchiveRequest`; `DeleteResponseBody` → `ArchiveResponseBody`; the `"/delete"` suffix in `ControllerRouting.swift:61` → `"/archive"` (this affects only the `ControllerRouting` path; `register(request:app:)` derives its path from the type name); `ContainerOperation.deleteRecords` and `authorizesDeleteRecords` per OQ20; the six HTTP-method statics removed. It touches the wire (Codable case name, that URL suffix), 49 files across Sources, Tests, skills, docs and templates, including the private `httpMethod` duplicate at `TestingServerRequestResponse.swift:155`. Sequenced as its own task group with a CHANGELOG migration note.

### 1.13 What goes away

- The existing `validateModel(on:)` at `Model+Vapor.swift:48`. No callers, the database parameter was never used, and its name is taken over by the model-validation hook on `DataModelLifecycle`. The two catalog entries that sell it follow.
- The six HTTP-method statics on `ServerRequestAction`.
- The `ValidatableModel` DocC example, replaced by one that compiles and appends.

### 1.14 Field identity for a storage-only property

Ruled: one identity system per model, minted from the type, adjusting what exists if it must.

The system is `FormFieldIdentifier`. The mint becomes a freestanding expression macro over a key path:

```swift
#fieldId(\Card.score)    // expands to FormFieldIdentifier(id: "score")
```

The macro reads the key path's last component at expansion time, the way `@FieldValidationModel` already reads identifier text for `propertyNames()`. The key path must name its root (`\Card.title`, or `\Self.title` inside the type); an inferred root does not type-check against the macro's signature. The compiler checks the key path, so renaming the property breaks every site at compile time. The string still rides the wire, so `FormFieldIdentifier`, `Codable`, and every stored message are unchanged.

A form field and a storage-only property mint the same way, so a model has one identity system whether or not the property is on a form. The fields generator switches to the macro; `FormFieldIdentifier(id:)` stays for decoding and is no longer the documented mint.

### 1.15 Rejected alternatives

- **An opt-in lifecycle protocol** a DataModel adopts in addition to `DataModel`. Rejected: a model that forgot the second conformance would be a `DataModel` and silently unvalidated. What shipped is a protocol `DataModel` itself inherits, so there is nothing to forget.
- **One middleware doing emit and lifecycle.** Rejected on SRP; the emit middleware stays as it is, the lifecycle one composes beside it.
- **Field validation for archive, destroy and restore.** Rejected: nothing in the model's own columns is being written.
- **A compile-time marker protocol for archivable models.** Rejected in the ticket: a second declaration of a fact the timestamp wrapper already declares.
- **A driver-specific constraint classifier.** Rejected: FOSMVVMVapor depends on FluentKit only; `DatabaseError.isConstraintFailure` is the portable fact and the model knows its own schema.
- **Carrying advisory warnings on a successful response.** Not rejected, deferred; it is a wire change to every write's response.

---

## Part 2 — Naming table, in code context

David arbitrates every name. First the declarations as they would ship, then the alternatives per name. Every name below is a candidate.

### 2.1 The declarations (revised to the ratified rulings, 2026-09-29)

```swift
// FOSMVVMVapor — Lifecycle/DataModelAction.swift
public enum DataModelAction: Sendable, Hashable {
    case create
    case update
    case archive
    case destroy
    case restore
}

// FOSMVVMVapor — Lifecycle/DataModelWriteContext.swift
public struct DataModelWriteContext: Sendable {
    public let action: DataModelAction
    public let database: any Database
    public let application: Vapor.Application
}

// FOSMVVMVapor — Lifecycle/DataModelCommitContext.swift
public struct DataModelCommitContext: Sendable {
    public let action: DataModelAction
    public let application: Vapor.Application
}

// FOSMVVMVapor — Lifecycle/ValidationWarningPolicy.swift
public enum ValidationWarningPolicy: Sendable {
    case advisory
    case blocking
}

// FOSMVVMVapor — Lifecycle/ConstraintViolation.swift
public struct ConstraintViolation: Sendable {
    public let action: DataModelAction
    public let underlyingError: any Error & Sendable
}

// FOSMVVMVapor — Lifecycle/DataModelLifecycle.swift
public protocol DataModelLifecycle {
    func willWrite(in context: DataModelWriteContext) async throws
    func validateModel(in context: DataModelWriteContext) async throws -> [ValidationResult]
    func validationResult(for violation: ConstraintViolation) -> ValidationResult?
    func didWrite(in context: DataModelWriteContext) async throws
    func didCommit(in context: DataModelCommitContext) async
    static var warningPolicy: ValidationWarningPolicy { get }
}

public extension DataModelLifecycle {
    func willWrite(in context: DataModelWriteContext) async throws {}
    func validateModel(in context: DataModelWriteContext) async throws -> [ValidationResult] { [] }
    func validationResult(for violation: ConstraintViolation) -> ValidationResult? { nil }
    func didWrite(in context: DataModelWriteContext) async throws {}
    func didCommit(in context: DataModelCommitContext) async {}
    static var warningPolicy: ValidationWarningPolicy { .advisory }
}

// FOSMVVMVapor — Protocols/DataModel.swift
public protocol DataModel: FOSMVVM.Model, ValidatableModel, DataModelLifecycle, FluentKit.Model {}

// FOSMVVMVapor — Extensions/Application+Containment.swift, second overload (OQ10, OQ19)
public extension Application {
    func register<M: DataModel>(_ type: M.Type, migration: any Migration) throws
        where M.IDValue == ModelIdType
}

// FOSMVVM — Protocols/CreateRequest.swift, UpdateRequest.swift (OQ21b)
public protocol CreateRequest: ServerRequest, Stubbable
    where RequestBody: ValidatableModel,
    ResponseBody: CreateResponseBody,
    ResponseError: ValidatableViewModelRequestError {}
public protocol UpdateRequest: ServerRequest, Stubbable
    where RequestBody: ValidatableModel,
    ResponseBody: UpdateResponseBody,
    ResponseError: ValidatableViewModelRequestError {}

// FOSMVVM — Validation/Validations.swift (OQ21a)
@Observable public final class Validations {
    public private(set) var validations: [ValidationResult]
    public func append(_ result: ValidationResult)
    public func append(contentsOf results: some Sequence<ValidationResult>)
    public func replace(with newValidations: [ValidationResult])      // existing; now also replaces model-level messages when the incoming set has any
    public func removeAll(fieldIds: [FormFieldIdentifier]? = nil)     // existing
    public var modelMessages: [ValidationResult.Message] { get }      // OQ5
}

// FOSMVVM — Validation/ValidationResult.swift (OQ5)
public extension ValidationResult {
    init(status: Status, message: LocalizableString)
}
public extension ValidationResult.Message {
    var addressesModel: Bool { get }
}

// FOSMVVM — SwiftUI Support/View.swift (OQ6, OQ27): a modifier, like the field one
public extension View {
    func withFormValidations() -> some View
}

// FOSMacros — freestanding expression macro (OQ12, OQ24)
@freestanding(expression)
public macro fieldId<Root, Value>(_ keyPath: KeyPath<Root, Value>) -> FormFieldIdentifier
// FormFieldIdentifier.init(id:) becomes internal.

// FOSMacros — the same macro with an index (OQ29), mirroring LocalizableRef(for:propertyName:index:)
@freestanding(expression)
public macro fieldId<Root, Value>(_ keyPath: KeyPath<Root, Value>, index: Int) -> FormFieldIdentifier

// FOSMVVMVapor — Vapor Support/ServerRequestController.swift
public enum ServerRequestControllerError: Error, Equatable {
    case invalidAction(ServerRequestAction)
    case archiveUnsupported(request: String, model: String)
}

// FOSMVVM — Protocols/ServerRequest.swift, ContainerOperation.swift (rename, OQ20)
public enum ServerRequestAction { case show, create, archive, destroy, update, replace }
public enum ContainerOperation { ... case archiveRecords, destroyRecords ... }
public protocol ArchiveRequest: ServerRequest, Stubbable where ResponseBody: ArchiveResponseBody {}
```

### 2.2 Alternatives per name

Legibility is the reading-ergonomics axis: distinct leading shapes, no near-anagrams, no pairs differing only in middle letters.

- **`DataModelAction`** — your name, aligned with `Model` / `DataModel` / `ContainerDataModel`. `RowAction` was the earlier candidate.
- **`.archive`** — alternatives `retire` (dropped: shares the leading shape of `restore`), `softDelete` (Fluent's mechanism, not the row's fate). **`.destroy`** — alternative `delete`, the retired word. `create`, `update`, `destroy` deliberately equal the `ServerRequestAction` cases.
- **`DataModelLifecycle`** — alternatives `DataModelHooks`, `PersistenceLifecycle`. Same stem as the type that conforms to it.
- **`willWrite(in:)`** (ratified OQ27; was `prepare(for:in:)`) — alternatives `beforeAction`. Collision: Fluent's `Migration.prepare(on:)` is a different receiver.
- **`validateModel(in:)`** (returns results, OQ21a) — alternatives `validate(against:for:validations:)` (an overload of field validation distinguished by labels only), `validateInContext`. Shares the `validate` stem with field validation on purpose; the object word says what is validated.
- **`validationResult(for:)`** (ratified OQ27; was `validation(for:)`) — alternatives `claim(_:)`, `translate(_:)`. Reads as "the validation this violation is".
- **`didWrite(in:)`** (action dropped, OQ27) — alternatives `didSave` (wrong for destroy), `didApply`, `afterWrite`. Cocoa's did-prefix. Distinct from `didCommit` at the second word.
- **`didCommit(in:)`** (action dropped, OQ27; non-throwing, OQ23) — alternatives `afterCommit`, `didFinish`. `liveTransaction`'s DocC already says commit.
- **`DataModelWriteContext`** (ratified OQ27; was `LifecycleContext`) — alternatives `RowContext`, `WriteContext`, `SaveContext`. **`DataModelCommitContext`** — the alternative was one context with an optional database, rejected: a nil check would encode which hook is running.
- **`ValidationWarningPolicy`**, `.advisory` / `.blocking` — the alternative was a Bool static `warningsBlockWrites`, rejected on base-type discipline: an enum names the meanings. **`warningPolicy`** — alternative `validationWarningPolicy`.
- **`ConstraintViolation`** — alternatives `DatabaseConstraintFailure`, `ConstraintFailure`. Your ruling's word; Fluent's Bool says "failure".
- **`register(_:migration:)` overload** — alternative `registerRecord(_:migration:)`. Compose onto the general: one registration API, the more specific overload wins for a container.
- **`ValidationResult(status:message:)`**, **`addressesModel`**, **`modelMessages`** — alternatives `isRecordLevel`, `recordLevelMessages`. Distinct shapes from `hasError`, `isValid` on the same types.
- **`withFormValidations()`** modifier (ratified OQ27; was `ModelValidationsView`) — alternatives `ValidationSummaryView`. Sibling shape to the existing `FieldValidationsView`, distinct at the first word.
- **`#fieldId`** — alternatives `#formField`, `#field`. Matches the `fieldId:` labels already on `ValidationResult` and `FormField`.
- **`archiveUnsupported(request:model:)`** — alternatives `archiveRequiresDeleteTimestamp`, `notArchivable`.
- **Request-side rename** (ruled): `ServerRequestAction.archive`, `ArchiveRequest`, `ArchiveResponseBody`, `"/archive"`.

---

## Part 3 — Rulings ledger (design, 2026-09-29)

All ratified by David. Stable OQ labels; a later round never renumbers.

- **OQ1** Hooks grouped in `DataModelLifecycle`; `DataModel` inherits it (redlined from "on `DataModel` itself").
- **OQ2** Field validation on create and update only; `validateModel` on every action.
- **OQ3** `didCommit` routed like the emit: on commit inside `liveTransaction`, suppressed with a warning inside a bare transaction, immediate on an auto-commit save.
- **OQ4** `validateModel` receives the write context (action, database, Application); named `DataModelWriteContext` under OQ27.
- **OQ5** A message with no field is about the model; `ValidationResult(status:message:)` and helpers.
- **OQ6** A form-level validations view ships in this work (name under OQ27).
- **OQ7** SQL constraint violations: recognised via `DatabaseError.isConstraintFailure`, claimed by the model, nil rethrows.
- **OQ8** Advisory warnings on a successful write are logged and dropped; carrying them is deferred.
- **OQ9** The lifecycle middleware does not require `useLiveInvalidation`.
- **OQ10** `register(_:migration:)` overload for a `DataModel` no container declares.
- **OQ11** The request body's `validate()` stays; `Fields` rules run twice on a routed write.
- **OQ12** `#fieldId(\Model.property)` macro mints every `FormFieldIdentifier`; fields generator switches.
- **OQ13** Every name in 2.1 (superseded in part by OQ27).
- **OQ14** `liveTransaction` always installs the after-commit collector.
- **OQ15** The issuing app's identity is a `Fields` field sent in the `RequestBody`; no framework change.
- **OQ16** A projected `DataModel` must be a contained type of a registered `ContainerDataModel`.
- **OQ17** Multi-instance propagation stays DEF-L2-4 (`docs/superpowers/specs/2026-07-09-live-invalidation-l2-design.md:362`).
- **OQ18** `DataModelLifecycle`.

Terms retired during the rulings: "record" (say model), "tier" (field validation / model validation), "door", "shape", "page", "standalone", "hub". The server-side `AppState` misnomer is `planning/stream/chore-rename-projection-appstate.md`.

## Part 3b — Review round 1 (2026-09-29)

Five independent read-only reviews of Parts 1–4: cold read, completeness, testability, SOLID/encapsulation, feasibility against FluentKit and FOS source. Consolidated here. Three groups: rulings David must make (OQ19+), corrections applied to the text, and items folded into Parts 5 and 6.

### Rulings needed

**OQ19. Discovery. RULED (2026-09-29): registration through the migration call.** Every Fluent model needs its migration added, so a per-type call exists regardless. FOS already makes that call the registration for containers ("declaring the migration is registering the type"). Ruling: every `DataModel`, container or not, is registered with `register(_:migration:)`; the lifecycle middleware is wired there, one instance per type, same coverage set as the emit. Raw `app.migrations.add` on a `DataModel` is a review finding and the DocC says `register` is the way. The template's `app.migrations.add(Card.Initial())` becomes `register(Card.self, migration: Card.Initial())`. The erased-middleware alternative (one `AnyModelMiddleware` seeing every model) was verified feasible and set aside: it adds a second mechanism beside the registry to close a bypass the review check closes.

**OQ20. RULED yes.** `ContainerOperation` is a fourth vocabulary. `Sources/FOSMVVM/Protocols/ContainerOperation.swift:37` has `.deleteRecords` and `.destroyRecords`; `ContainerAuthorization.authorizesDeleteRecords` is public; the delete route passes `expectedOperation: .deleteRecords`. Rename `.deleteRecords` → `.archiveRecords` and `authorizesDeleteRecords` → `authorizesArchiveRecords` in the same sweep. Recommended: yes.

**OQ21. RULED (2026-09-29): a, b and c all ratified after the end-to-end trace in 3c; breaking change on `Validations.validations` accepted (plain compiler error; DocC, CHANGELOG line and a doctor rule carry the fix).** `Validations` cannot cross the hook boundary. `Validations` is an `@Observable final class`, not `Sendable`; `validateModel(in:validations:) async throws` hands it from a `Sendable` middleware under Swift 6 and will not compile (testability A6, feasibility C1). Separately, `Validations.validations` is a `public var`, so "append, never assign" is unenforceable (SOLID 1). Candidate that fixes both: the hook returns its results and the framework appends.

```swift
func validateModel(in context: DataModelWriteContext) async throws -> [ValidationResult]
```

No level can overwrite another because no level holds the accumulator. On the client side `Validations.validations` becomes `public private(set)` with `append(_:)` / `append(contentsOf:)`, and `replace(with:)` stays as the sanctioned reset. The `ValidatableModel.validate(fields:validations:)` signature is existing API and is not changed by this work. Recommended: yes.

**OQ22. RULED: `any Error & Sendable`.** The struct as declared will not compile (SOLID 2, cold read 6). Minimum: `any Error & Sendable`. FluentKit driver errors conform. The reviewer also flags publishing a driver's error as the API; the honest state is that FluentKit exposes no portable constraint identity, so the raw error is the only discriminator a model with two constraints has. Recommended: `any Error & Sendable`, documented as "inspect only when your model has more than one constraint".

**OQ23. RULED: `didCommit` is `async`, not `throws`.** Declared `async throws` with a promise to swallow the throw violates "never fail silently" (SOLID 5). Candidate: `didCommit` is `async`, not `throws`; the author handles their own failure and decides what to log or report. Recommended: yes.

**OQ24. RULED: the init becomes internal.** With it public, `#fieldId` is a convention, not a wall (SOLID 3). Demote the init to internal; `Codable` synthesis does not need it. Consequence: the fields generator, templates, and every client that mints by string switch to the macro in the same release. Recommended: yes.

**OQ25. RULED: the model-level opt-out stands.** David's earlier remark about middleware was a statement of fact about what middleware can do, not guidance. The ruling said "a middleware option can re-raise a violation as a `Swift.Error`"; the plan puts the opt-out on the model (`validation(for:)` returning nil). Confirm the model-level opt-out is what you meant, or name the middleware option you want.

**OQ26. RULED ok.** Batch writes. FluentKit's `Collection.create` / `Collection.delete` call the middleware per model with a `next` that writes nothing; the bulk statement runs after every middleware returns (`Model+Concurrency.swift:143-180`). So on a batch write `didWrite` runs before any row exists, constraint failures never reach the model's claim, and batch delete always dispatches hard delete, so `.archive` is unreachable. FOS cannot intercept this from a middleware. Candidate: state the contract ("hooks run per model on batch writes; the row does not yet exist in `didWrite`; constraint failures on batch writes are not translated; batch delete is always destroy") in the `DataModelLifecycle` DocC, and add a review rule warning on `Collection.create/delete` of a `DataModel`. Recommended: that, in this work.

**OQ27. RULED: all five ratified.** Naming, second pass:
- Drop the duplicated action parameter: `prepare(in context:)`, `didWrite(in context:)`, `didCommit(in context:)`; the context carries `action`.
- `validation(for:)` → `validationResult(for:)`: four near-shapes (`validation`, `validate`, `validations`, `Validations`) in one protocol.
- `prepare` → `willWrite`, pairing with `didWrite` / `didCommit`; `prepare` collides in reader space with `Migration.prepare(on:)`.
- `LifecycleContext` / `CommitContext` → `DataModelWriteContext` / `DataModelCommitContext` (family stem, NAMES §3).
- `ModelValidationsView` → `FormValidationsView`: `Model` is a FOSMVVM protocol, and NAMES §3b reads `XView` as the view of `XViewModel`. Also `FieldValidationsView` is internal and reached through a `View` modifier; the new one should ship the same way (a modifier on the form), not as a public struct.

**OQ28. RULED yes.** Advisory warnings alongside errors. When a write fails on errors, do the advisory warnings collected in the same pass ride in the `ValidationError`? Recommended: yes, the `ValidationError` carries every result collected; "dropped" applies only when the write succeeds.

**OQ29. RULED (2026-09-29): `#fieldId` takes an optional `index:`, mirroring `LocalizableRef`.** A consuming client mints field identities in a loop over a parameterised id in three places; a key-path alone cannot express "the same property, repeated". FOS already has the shape for a repeated element at `Sources/FOSMVVM/Localization/LocalizableRef.swift:4`: `.arrayValue(key:index:)`, minted through `init(for:parentKeys:propertyName:index:)` with an optional `Int` index. The field identity follows it exactly:

```swift
#fieldId(\LeadLimits.channels)             // the collection as a whole
#fieldId(\LeadLimits.channels, index: i)   // element i
```

One spelling, no method derivation, no keyed variant (an enum-driven repetition uses the case's index, as its localized strings do). Two mints with the same key path and index are equal. The element's encoded form is internal.

**OQ30. RULED yes (2026-09-30), revised form:** identity = enclosing type name + property; `\Self` is resolved from the macro's lexical context (swift-syntax 604, `MacroExpansionContext.lexicalContext`), so the same line in `extension CardFields` mints `CardFields.title` for every adopter and pasted into `extension BoardFields` mints `BoardFields.title`; explicit roots (`\CardFields.title`) allowed anywhere; `\Self` with no enclosing type is diagnosed. The template and generators keep `\Self`. Original text follows. Found by the behavioral channel: `#fieldId(\Card.title) == #fieldId(\Board.title)` today, because the identity is the property name alone, as `FormFieldIdentifier(id:)` always was. Proposed: the identity is the root name plus the property (`Card.score`, `CardFields.title`). Inside a `Fields` protocol extension the mint is `#fieldId(\CardFields.title)` (a protocol-rooted key path compiles; verified), never `\Self.title`, so the request body, the form ViewModel and the `DataModel` mint one identity. The macro REJECTS `\Self.` with a diagnostic: `Self` differs per adopter and would split the shared contract. Mirrors `LocalizableRef`, which keys by type name. Wire change to the encoded identity, pre-1.0. One more task converts the `\Self.` sites the OQ24 sweep introduced (template, generator docs, tests) and adds the diagnostic. 

**OQ31. RULED: 0.18.0.** Stamped in the release ritual after merge (CHANGELOG + Release.version together), never in the feature PR. The branch carries source breaks (`Validations.validations` read-only, `FormFieldIdentifier(id:)` sealed, write requests' `ResponseError` constraint, `DeleteRequest` gone) and wire changes (`.archive`, the `ControllerRouting` suffix, the field identity under OQ30). Floor 0.17.3. David names the number; the stamp is a separate release commit, never in the feature PR.

**OQ32. RULED (2026-09-30): squash.** PR creation still waits for David's explicit go after the squash. David reviews `feat/datamodel-validation-lifecycle` (48 commits, 110 files, `git log main..HEAD`, `git diff main --stat`). On his go: squash to one commit per task group (G1, G2+OQ24, G3, G4+G7, G5, G6, G8, behavioral), then `gh pr create`. Nothing is pushed before that.

### Corrections applied to the text (no ruling needed)

- 1.9 contradicted OQ14 (after-commit "suppressed inside any transaction"); now: suppressed only inside a bare `database.transaction`.
- 1.4 said the Application is captured weakly while 2.1 declared a strong stored property; now: captured weakly at install, the context holds it for the duration of one hook call, and no hook runs after shutdown.
- 1.8 placed `warningPolicy` on `DataModel`; now `DataModelLifecycle`.
- 1.15's rejected "separate lifecycle protocol" now says what was rejected: an opt-in protocol; the inherited one is what shipped.
- 1.1's "a test can conform a plain type without Fluent" was false (the context needs a database and an Application); removed.
- 1.11 said the boot probe sits in `ServerRequestController.boot`; the model type is only reachable in `register(request:app:)`; corrected. Also: `ServerRequest.path` derives from the type name, so the `"/archive"` suffix affects only `ControllerRouting`; 4.12 corrected.
- 1.11 said "the dispatch table gains the destroy entry"; `DestroyRequest` is rejected at boot today (`ViewModelRequest.swift`, `rejectWriteProtocolAtReadDoor`), so a `register<SR: DestroyRequest>` overload, `serveDestroy` and `commitDestroy` are new work; stated.
- 1.9's `RegisteredModel` for a plain `DataModel`: needs `where IDValue == ModelIdType` (FluentKit `find` takes `IDValue`), `containment: []`, `authorityFlow: .inherits`, and a descriptor flag so `isRegisteredContainer` stays false for it (feasibility A1).
- 1.10 "same Fields rules": the body gate calls `body.validate()` (fields: nil); the middleware calls the same with `fields: nil`; stated.
- 1.14 / 4.10 / 4.14: `#fieldId` requires a rooted key path (`\Card.title`, `\Self.title`); the inferred-root form does not type-check; stated. 4.14 uses the catalogued `fields?.contains(Self.titleField) ?? true` helper.
- 1.12 "nineteen files" → 49 files carry delete-family text (feasibility A6); the rename task group lists them.
- Part 3 rewritten as a clean ledger: every OQ with its ruling, no "reopened below" pointers.
- Coinages retired: "boot sweep" → the containment registration sweep in `registerInvalidationEmitMiddleware`; "boot probe" → the delete-timestamp check at route registration; "body gate" → the request body's `validate()`; "in the fold" → covered by the middleware; "row action" → action; "wire-shape" → wire; "hub" → live-invalidation broadcaster (`InvalidationHub`, internal).
- DocC audience: 4.1 no longer names Fluent's dispatch; 4.4 `didCommit` states the rule not the limitation; 4.6 and 4.9 lose their rationale sentences.
- fosline is glossed once in 1.7 as "a consuming project" with no further detail; DEF-L2-4 is cited with its spec path.

### Folded into Part 5 (tests)

- Both ruled test shapes assert the localized text by encoding the thrown `ValidationError` through `LocalizableTestCase.encoder(locale:)`; a thrown `LocalizableString` is unresolved until encoded (`LocalizableString.swift:163`). Fixture messages need TestYAML entries; none exist today.
- Contracts restated so they are observable: "an advisory warning never stops the write" (not "is logged"); "`didCommit` does not run when the transaction rolls back" (counter in `app.storage` + throwing closure); "hooks run once for a type reached through two containers"; the nil opt-out asserted as "not a `ValidationError`".
- `ServerRequestControllerError` gains `Equatable` so `archiveUnsupported` is distinguishable in a test.
- The named test list from the testability review (28 pairs) is the seed for Part 5.
- Fixtures missing: a `@Timestamp(on: .delete)` model (none exist in Tests/), a hooks probe writing an ordering box into `app.storage`, a container-scoped unique index, a pivot with hooks, an uncontained model, `.blocking` and `.advisory` types, claiming and declining types.

### Folded into Part 6 (decomposition)

Task groups: (a) lifecycle types + erased middleware + install; (b) `liveTransaction` collector generalized to hold `didCommit` closures, installed with or without a broadcaster; (c) FOSMVVM validation additions, `Validations` encapsulation, form validations modifier, `#fieldId` macro (first freestanding macro in FOSMacros: `ExpressionMacro` conformance, `public macro` declaration, plugin registration, Linux build under the existing guard); (d) write route transaction wrap, `commitArchive` / `commitDestroy`, `DestroyRequest` register overload and `serveDestroy`, the delete-timestamp check; (e) rename sweep over 49 files incl. `ContainerOperation`, `TestingServerRequestResponse.swift:155`'s private `httpMethod` duplicate, CHANGELOG migration note; (f) `FOSMVVMArchitecture.md` "The Shared Validation Contract", datamodel generator + reference, `checks/datamodel.md`, new review rule "validators never mutate", batch-write warning rule, API catalog (retire `validateModel(on:)` entries at `FOSMVVMVapor.md:149`, `:502`), bootstrap template DocC at `Card.swift.tmpl:15`; (g) CHANGELOG + release stamp (release ritual, never inside the feature PR).

Also noted for the implementer: `Validations.replace(with:)` semantics for model-level messages are ruled in OQ21c (3c-3). The `withFormValidations()` modifier needs `#if canImport(SwiftUI)`.

### 3c — The validation process end to end (for OQ21)

Traced 2026-09-29 from source, both sides, with the OQ21 change applied. Every site that mutates a `Validations` is listed at the end.

**App side, editing.** A `FormFieldView` binding stores the typed value, then removes that field's messages from the environment `Validations` (`FormFieldView.swift:188`, `removeAll(fieldIds:)`). On submit or after the debounce it runs the field's validator, the `Fields` rule for that one field, and merges the results per field with `replace(with:)` (`:164`). `FieldValidationsView` shows the first message naming its field. Model-level messages are untouched by editing; they are about the model and only a new server answer replaces them.

**App side, submitting.** The operation sends the request; on the server the request body's `validate()` runs every `Fields` rule and throws `ValidationError`. The client decodes `WireError<SR.ResponseError>` (`ServerRequest+Fetch.swift:131`) and the view puts `error.validations` into the environment with `replace(with:)`.

**Server side, the route.** `commitCreate` / `commitUpdate`: body `validate()`, load candidates, resolve target, `apply(to:)`, save. All inside `liveTransaction` (OQ1).

**Server side, the middleware, per Fluent event.** `willWrite`; then `validate(fields: nil, validations:)` on a `Validations` the middleware created, synchronous, same task; then `await validateModel(in:)`, whose returned results the middleware appends; gate; `next`; constraint claim; `didWrite`; `didCommit` on commit. The `Validations` instance never leaves the middleware's task, so its non-`Sendable`ness is never a problem. `validate(fields:validations:)` keeps its existing signature on both sides.

**Server side, the answer.** `ValidationError` propagates out of `save`, out of the route, into `ErrorMiddleware`, which envelopes it and localizes with the request's encoder.

**Findings from the trace.** Four, none of them caused by OQ21; the trace exposed them.

- **3c-1. The typed error path is not guaranteed.** `CreateRequest` and `UpdateRequest` constrain `RequestBody: ValidatableModel` and nothing on `ResponseError` (`CreateRequest.swift:4`, `UpdateRequest.swift:24`). The server throws the concrete `ValidationError`; the client decodes `WireError<SR.ResponseError>`. A write request whose `ResponseError` is `EmptyError` or its own type cannot decode the server's envelope and the user gets a decode failure instead of messages. `ValidatableViewModelRequestError` already carries `init(validations:)` for exactly this bridge and nothing uses it. Fix: constrain write requests' `ResponseError: ValidatableViewModelRequestError`, and have the route catch `ValidationError` from body `validate()` and from `save` and rethrow `SR.ResponseError(validations:)`. Then the middleware stays request-agnostic and the client always decodes its own typed error.

- **3c-2. `FormFieldView`'s submit guard is inverted.** `validateIt` (`FormFieldView.swift:152-166`) returns `validations.status == .error` when the validator produced results, and `onSubmit` proceeds only when that is `true` (`:138`). So a field with an error submits, and a field with only warnings does not. Pre-existing, undocumented, inside the validation process this work owns. Fix in this work: return `validations.status != .error`, with a test.

- **3c-3. `replace(with:)` never trims a model-level message.** It trims by field id (`Validations.swift:59-76`). After OQ5 a server answer with new model-level messages would stack on the old ones. Define: `replace(with:)` replaces every model-level message when the incoming set contains any model-level message, and leaves them when it does not (a per-field client validation must not clear a server-side model refusal).

- **3c-4. Skill drift.** The view generator's validation pattern reads `responseError.validationResults` (`fosmvvm-swiftui-view-generator/SKILL.md:629`, `reference.md:425`); the property is `validations`. Fixed in the docs task group.

**Every site that mutates a `Validations`, and what OQ21 does to it.**

- `FormFieldView.swift:161,164,188,216` — `removeAll(fieldIds:)`, `replace(with:)`: public methods, unchanged.
- `ValidatableModel.swift:148` — creates one for the `validate()` convenience: unchanged.
- `ValidationError.swift:45` — reads `.validations`: unchanged (the getter stays public).
- `FieldValidationsView.swift:55` — reads: unchanged.
- `Tests/FOSMVVMVaporTests/Containment/WriteFixtures.swift:109` — `validations.validations.append(...)` → `validations.append(...)`.
- `fosmvvm-fields-generator/reference.md:118,291` and the bootstrap `CardFields.swift.tmpl:80` — `validations.validations = result` → `validations.append(contentsOf: result)`. These are the overwrite sites the append-only ruling (OQ6 of the design) already required changing.
- `fosmvvm-serverrequest-generator` SKILL/reference — `validations.validations.append` → `validations.append`.
- Nothing else in Sources assigns or appends to the array.

**OQ21, three parts, all RATIFIED 2026-09-29:**

- **OQ21a.** `validateModel(in:) async throws -> [ValidationResult]`; the middleware appends. `Validations.validations` becomes `public private(set)` with `append(_:)` and `append(contentsOf:)`; `replace(with:)` and `removeAll(fieldIds:)` stay. `validate(fields:validations:)` unchanged.
- **OQ21b.** Write requests constrain `ResponseError: ValidatableViewModelRequestError`; the route rethrows `SR.ResponseError(validations:)` (3c-1). Wire-visible for any client whose write request declared another error type; pre-1.0.
- **OQ21c.** Fix the inverted submit guard (3c-2) and define `replace(with:)` for model-level messages (3c-3), both in this work.


---

## Part 3d — Review round 2 (2026-09-30): shipped code and docs against the plan

Two read-only reviews of the squashed branch: alignment (signatures, rulings, DocC, terminology, CHANGELOG) and correctness (bugs and hazards). Consolidated. Group A is being fixed as fixups into the owning commits; group B needs David.

### A. Fixes in flight (no ruling needed)

- A1 Archive and destroy routes wrap in `answeringWithRequestError`; `ArchiveRequest`/`DestroyRequest` constrain `ResponseError: ValidatableViewModelRequestError` (a refused delete surfaced as a 500).
- A2 `deferUntilCommit` also requires `db.inTransaction` before deferring (an auto-commit write on another handle inside a `liveTransaction` was deferred to an unrelated commit).
- A3 `didWrite` DocC: rollback is promised only inside a transaction; auto-commit leaves the row.
- A4 `drainHooks` DocC: no ordering promise for batch writes.
- A5 `ServerRequestAction(httpMethod:uri:)` matches `/destroy` as a path component, not a suffix.
- A6 Macro: `\Self` scope built from the full lexical chain (`Outer.Inner`, generic extensions stripped of `<…>`), backticks stripped before the case test.
- A7 `LeadLimits`/`channels` (a client's vocabulary) replaced by `Card.tags` in DocC, CHANGELOG, catalog, tests, commit body.
- A8 Every message-minting DocC example mints on the `Fields` protocol (`\CardFields.title`), incl. the CHANGELOG migration line.
- A9 Review ledger ids renumbered past the existing G22–G26; plugin version cited correctly.
- A10 CHANGELOG: `#fieldId` wire break with "deploy client and server together"; swift-syntax 604 pin; JavaScriptKit 0.26.2 with its reason; the six removed statics; `\Self` outside a type diagnosed; `LoadRequirement.destroy`.
- A11 Archive route DocC summary renamed from "delete".
- A12 The three context/violation memberwise inits become internal.
- A13 Retired words in added lines: door, gate (as a noun), probe, page, shape → ruled wording; `DeleteTimestampProbe` renamed `DeleteTimestampCheck`.
- A14 DocC examples in Sources use Card/Board, noun-first request names; test fixtures keep the directory's existing vocabulary.
- A15 Warn-once set keyed by `ObjectIdentifier`, not `String(describing:)`.
- A16 Theatre comments and `///` lines citing OQ numbers/spec sections demoted or deleted; duplicated `#fieldId` DocC trimmed on the `index:` overload.
- A17 Catalog cites `archiveUnsupported`, not a non-existent case; serverrequest check teaches Create/Update/Archive/Destroy/Replace.
- A18 Dead `registerLifecycleMiddleware` call in the `useLiveInvalidation` sweep removed if verified dead.
- A19 `behavioralClaims` module-global box moved to per-app storage.
- A20 Plan 5.2's `CaseIterable` line dropped (2.1 rules).

### B. Rulings needed

**OQ33.** Weak `Application` gone mid-write: the middleware passes through and writes an unvalidated row. Recommended: throw a framework error naming the shut-down application; never silent.

**OQ34.** Nested `liveTransaction`. `req.db`/`app.db` hand back a fresh handle with `inTransaction == false`, so an inner `liveTransaction` opens a second real transaction, not a savepoint; the inner commit can outlive an outer rollback while its hooks are discarded, and with a small pool it can starve. Recommended: a nested call joins the outer only when its handle is already in a transaction (same connection); otherwise it is its own transaction and drains on its own commit. The nested test is rewritten to exercise both.

**OQ35.** Batch writes. FluentKit's `Collection.create/delete` run the middleware per model and issue the statement afterwards, so `didWrite` and an auto-commit `didCommit` run before any row exists. Detectable: after `next`, a batch-created model still has `_$idExists == false`. Recommended: on a batch write run `willWrite` and both validations only; skip `didWrite` and `didCommit`; DocC says so (replacing the softer OQ26 text).

**OQ36.** Candidate load outside the write transaction (the load engine reads `request.db`). The target row that authorized the write is read on one connection and mutated on another. Recommended: its own work item to thread the transaction's database through the load engine; this work corrects the CHANGELOG sentence to what ships.

**OQ37.** `LoadRequirement.delete(_:in:via:)` still carries the old verb while building `.archiveRecords`. Recommended: rename to `archive`, no alias (pre-1.0), CHANGELOG line.

**OQ38.** `FormFieldIdentifier.id` is still `public let id: String`, so the sealed value is readable. Every reader is in-module. Recommended: internal.

**OQ39.** A `Fields` protocol's `validate(fields:validations:)` called twice on one `Validations` now duplicates its messages, because the template switched from assignment to `append(contentsOf:)`. `replace(with:)` is field-scoped and idempotent, which is what a `Fields` rule set wants for its own fields, while `validateModel` appends. Recommended: the template and generators use `replace(with:)` in `Fields` validate; the append-only ruling stands for cross-level accumulation.

**OQ40.** `FormFieldView.validateIt` was widened from private to internal so the submit-guard fix could be tested (`@testable`, block coverage). Keep, or restore private and leave the guard untested.


---

## Part 4 — Customer DocC, written before the code (revised 2026-09-29)

Every public symbol from 2.1, documented from the call site. Examples use the bootstrap template's `Card` and `Board`. Contract only; the rationale stays in Part 1 and 3b. These blocks are the text that ships in `///`.

### 4.1 `DataModelAction`

```swift
/// What is about to happen to your model's row, handed to every ``DataModelLifecycle`` hook
///
/// Read it from the context to make a hook act for some actions and not others:
///
/// ```swift
/// public func willWrite(in context: DataModelWriteContext) async throws {
///     if context.action == .create { createdAt = Date() }
/// }
/// ```
///
/// Your hook is told what will happen to the row, never which method was called: a model with a
/// `@Timestamp(on: .delete)` archives on a plain `delete(on:)` and destroys on
/// `delete(force: true, on:)`; a model without one destroys on either.
public enum DataModelAction: Sendable, Hashable {
    /// The row is being inserted
    case create
    /// The row is being changed in place; `save`, `update` and a replace request all arrive here
    case update
    /// The row stays, marked deleted through its delete timestamp
    case archive
    /// The row is being removed
    case destroy
    /// An archived row is coming back
    case restore
}
```

### 4.2 `DataModelWriteContext`

```swift
/// What ``DataModelLifecycle/willWrite(in:)``, ``DataModelLifecycle/validateModel(in:)`` and
/// ``DataModelLifecycle/didWrite(in:)`` receive
///
/// Read `action` to decide what applies, query through `database` so you see the same
/// transaction as the write, and reach configuration through `application`:
///
/// ```swift
/// public func validateModel(in context: DataModelWriteContext) async throws -> [ValidationResult] {
///     guard context.action == .create else { return [] }
///     let limit = context.application.cardLimits.perBoard
///     let count = try await Card.query(on: context.database).filter(\.$board.$id == $board.id).count()
///     return count >= limit ? [.init(status: .error, message: validationMessages.boardFull)] : []
/// }
/// ```
///
/// When the write came through a FOSMVVM write request, `database` is that request's
/// transaction, so what you read and what is about to be written are one state.
public struct DataModelWriteContext: Sendable {
    public let action: DataModelAction
    public let database: any Database
    public let application: Vapor.Application
}
```

### 4.3 `DataModelCommitContext`

```swift
/// What ``DataModelLifecycle/didCommit(in:)`` receives after the transaction has committed
///
/// There is no database here: the transaction is over. Use `application` for the side effect the
/// commit unlocks:
///
/// ```swift
/// public func didCommit(in context: DataModelCommitContext) async {
///     guard context.action == .create else { return }
///     await context.application.mailer.sendWelcome(to: email)
/// }
/// ```
public struct DataModelCommitContext: Sendable {
    public let action: DataModelAction
    public let application: Vapor.Application
}
```

### 4.4 `DataModelLifecycle`

```swift
/// The hooks FOSMVVM runs around every write of a `DataModel`
///
/// Every `DataModel` already conforms. Every hook has a default that does nothing, so declare
/// only the ones your model needs:
///
/// ```swift
/// public final class Card: DataModel, CardFields, @unchecked Sendable {
///     // fields …
///
///     public func willWrite(in context: DataModelWriteContext) async throws {
///         title = title.trimmingCharacters(in: .whitespaces)
///     }
///
///     public func validateModel(in context: DataModelWriteContext) async throws -> [ValidationResult] {
///         let taken = try await Card.query(on: context.database)
///             .filter(\.$board.$id == $board.id).filter(\.$title == title).filter(\.$id != id)
///             .first() != nil
///         return taken
///             ? [.init(status: .error, fieldId: #fieldId(\Card.title), message: validationMessages.titleTaken)]
///             : []
///     }
/// }
/// ```
///
/// The order for one write: `willWrite`; the field validation your `Fields` protocol defines
/// (`validate(fields:validations:)`, on create and update); `validateModel`; the write;
/// `didWrite` in the same transaction; `didCommit` once it commits. A failed validation stops
/// the write and reaches the client as the request's `ResponseError`; a throw from a hook is an
/// error, not a validation.
///
/// Register the model with its migration, `app.register(Card.self, migration: Card.Initial())`,
/// and the hooks run. On a batch write (`[Card].create(on:)`, `[Card].delete(on:)`) the hooks
/// run per model before the batch statement, so the row does not yet exist in `didWrite`,
/// a constraint failure is not offered to `validationResult(for:)`, and a batch delete is
/// always `.destroy`.
public protocol DataModelLifecycle {
    /// Change the model before it is validated and written
    ///
    /// Derive, trim, and stamp here; validation runs after this:
    ///
    /// ```swift
    /// public func willWrite(in context: DataModelWriteContext) async throws {
    ///     slug = title.slugified()
    /// }
    /// ```
    ///
    /// Throw only for an error the user cannot fix; a value the user must correct belongs in
    /// ``validateModel(in:)``.
    func willWrite(in context: DataModelWriteContext) async throws

    /// Judge this model against other rows and return every problem found
    ///
    /// Runs for every action after field validation passed. Query through `context.database`
    /// and return one `ValidationResult` per rule that fails; FOSMVVM stops the write when any
    /// is an error:
    ///
    /// ```swift
    /// public func validateModel(in context: DataModelWriteContext) async throws -> [ValidationResult] {
    ///     guard context.action == .destroy else { return [] }
    ///     let hasCards = try await Card.query(on: context.database).filter(\.$board.$id == id).count() > 0
    ///     return hasCards ? [.init(status: .error, message: validationMessages.boardHasCards)] : []
    /// }
    /// ```
    ///
    /// Return every failure, not the first. A result with no field is about the model as a
    /// whole. Throw only for a failure of the query itself.
    func validateModel(in context: DataModelWriteContext) async throws -> [ValidationResult]

    /// Turn a database constraint failure into a validation result the user can act on
    ///
    /// When the database rejects the write on a constraint your migration declared, FOSMVVM asks
    /// your model what it means. Return a result and the client receives it as a validation
    /// failure; return `nil` and the original error is thrown unchanged:
    ///
    /// ```swift
    /// public func validationResult(for violation: ConstraintViolation) -> ValidationResult? {
    ///     guard violation.action == .create else { return nil }
    ///     return .init(status: .error, message: validationMessages.alreadyClaimed)
    /// }
    /// ```
    ///
    /// Reach for this when two writers race on a unique index and the loser should see a
    /// message, not a database error.
    func validationResult(for violation: ConstraintViolation) -> ValidationResult?

    /// Do more work in the same transaction after the row was written
    ///
    /// Write related rows here; a throw rolls the whole transaction back, including the row
    /// that triggered this hook:
    ///
    /// ```swift
    /// public func didWrite(in context: DataModelWriteContext) async throws {
    ///     guard context.action == .create else { return }
    ///     try await CardHistory(cardId: try requireID(), event: .created).save(on: context.database)
    /// }
    /// ```
    func didWrite(in context: DataModelWriteContext) async throws

    /// Run a side effect once the write is durable
    ///
    /// Send the email, call the exchange, notify the other system. This runs after the
    /// transaction commits, so nothing here can be rolled back and nothing here can fail the
    /// request. Handle your own failures:
    ///
    /// ```swift
    /// public func didCommit(in context: DataModelCommitContext) async {
    ///     guard context.action == .create else { return }
    ///     await context.application.notifier.cardCreated(id: id)
    /// }
    /// ```
    ///
    /// Inside `liveTransaction { }` this runs when the transaction commits. Inside a bare
    /// `database.transaction { }` it does not run; use `liveTransaction` for any write whose
    /// commit a hook must see.
    func didCommit(in context: DataModelCommitContext) async

    /// Whether a validation warning stops the write
    ///
    /// The default, `.advisory`, lets the write proceed. Declare `.blocking` on a model whose
    /// warnings the user must see before the row is saved:
    ///
    /// ```swift
    /// public static var warningPolicy: ValidationWarningPolicy { .blocking }
    /// ```
    static var warningPolicy: ValidationWarningPolicy { get }
}
```

### 4.5 `ValidationWarningPolicy`

```swift
/// What a `DataModel` does with a validation warning at save time
///
/// Set it once per model through ``DataModelLifecycle/warningPolicy``:
///
/// ```swift
/// public static var warningPolicy: ValidationWarningPolicy { .blocking }
/// ```
public enum ValidationWarningPolicy: Sendable {
    /// The write proceeds. The default. Warnings collected alongside an error still reach the client with it.
    case advisory
    /// A warning stops the write and reaches the client like an error.
    case blocking
}
```

### 4.6 `ConstraintViolation`

```swift
/// A database constraint the write ran into, offered to ``DataModelLifecycle/validationResult(for:)``
///
/// Look at `action` to know which write failed. Inspect `underlyingError` only when your model
/// has more than one constraint and needs to tell them apart:
///
/// ```swift
/// public func validationResult(for violation: ConstraintViolation) -> ValidationResult? {
///     guard violation.action == .create else { return nil }
///     return .init(status: .error, message: validationMessages.alreadyClaimed)
/// }
/// ```
public struct ConstraintViolation: Sendable {
    public let action: DataModelAction
    public let underlyingError: any Error & Sendable
}
```

### 4.7 `Application.register(_:migration:)` for a `DataModel`

```swift
/// Register a `DataModel` with its migration, so its lifecycle hooks and live invalidation run
///
/// Same call as for a container; every `DataModel` goes through it, contained or not:
///
/// ```swift
/// // in configure(_:)
/// try app.register(Board.self, migration: Board.Initial())   // a container
/// try app.register(Card.self, migration: Card.Initial())     // a contained type
/// try app.register(ServiceStatus.self, migration: ServiceStatus.Create())  // no container
/// ```
///
/// Adding the migration directly with `app.migrations.add` skips the hooks; the review reports it.
/// Registering a model does not make it loadable by a factory: a `DataModel` a `ViewModel`
/// projects must be declared by a container.
///
/// - Throws: if the model's namespace is already registered.
func register<M: DataModel>(_ type: M.Type, migration: any Migration) throws where M.IDValue == ModelIdType
```

### 4.8 `Validations`, `ValidationResult`, model-level additions

```swift
/// The validation results a form shows, kept in the SwiftUI environment
///
/// Add results with `append`, swap a field's results with `replace(with:)`, clear with
/// `removeAll`; read `validations` to inspect them:
///
/// ```swift
/// validations.append(.init(status: .error, fieldId: #fieldId(\Card.title), message: messages.titleRequired))
/// validations.replace(with: responseError.validations)
/// validations.removeAll()
/// ```
@Observable public final class Validations {
    /// Every result, in the order added. Change it through `append`, `replace(with:)` and `removeAll`.
    public private(set) var validations: [ValidationResult]

    /// Adds one result
    public func append(_ result: ValidationResult)

    /// Adds results
    public func append(contentsOf results: some Sequence<ValidationResult>)

    /// The messages that are about the model as a whole, across every result
    ///
    /// ```swift
    /// ForEach(validations.modelMessages, id: \.self) { Text($0.message) }
    /// ```
    ///
    /// Empty when every message names a field.
    public var modelMessages: [ValidationResult.Message] { get }
}

public extension ValidationResult {
    /// A result about the model as a whole, not about any one field
    ///
    /// ```swift
    /// return [.init(status: .error, message: validationMessages.boardFull)]
    /// ```
    ///
    /// Shown by the form's validations view; field views ignore it.
    init(status: Status, message: LocalizableString)
}

public extension ValidationResult.Message {
    /// Whether this message is about the model as a whole
    ///
    /// True when the message names no field.
    var addressesModel: Bool { get }
}
```

`replace(with:)` DocC gains: "Field messages are replaced per field. Model-level messages are replaced whenever the incoming results carry any; a field-only replacement leaves them."

### 4.9 `withFormValidations()`

```swift
/// Shows the form's model-level validation messages above this view
///
/// Apply it to the form or to the view where the summary belongs; it adds nothing when there
/// are none:
///
/// ```swift
/// Form {
///     FormFieldView(fieldModel: title, focusField: $focus)
/// }
/// .withFormValidations()
/// .environment(validations)
/// ```
///
/// Requires `Validations` in the environment, like the field views.
func withFormValidations() -> some View
```

### 4.10 `#fieldId`

```swift
/// The identifier of a form field, from the property it validates
///
/// ```swift
/// static var titleField: FormField<String> { .init(
///     fieldId: #fieldId(\Card.title),
///     …
/// )}
///
/// return [.init(status: .error, fieldId: #fieldId(\Card.title), message: validationMessages.titleTaken)]
/// ```
///
/// Name the key path's root (`\Card.title`, or `\Self.title` inside the type). The compiler
/// checks the key path, so renaming the property breaks every site that names it. Use it for a
/// property the form shows and for one it does not; a model has one set of field identities.
/// For a field repeated over a collection, pass the element's index, the way a localized
/// string for one element does:
///
/// ```swift
/// for index in channels.indices {
///     fields.append(FormField(fieldId: #fieldId(\LeadLimits.channels, index: index), title: …))
/// }
/// ```
///
/// Two mints with the same key path and index are equal, so a message about an element finds
/// its field.
@freestanding(expression)
public macro fieldId<Root, Value>(_ keyPath: KeyPath<Root, Value>) -> FormFieldIdentifier
@freestanding(expression)
public macro fieldId<Root, Value>(_ keyPath: KeyPath<Root, Value>, index: Int) -> FormFieldIdentifier
```

### 4.12 `ServerRequestControllerError.archiveUnsupported`

```swift
/// An `ArchiveRequest` was registered for a model that cannot be archived
///
/// Archiving marks a row deleted through its delete timestamp. Give the model one:
///
/// ```swift
/// @Timestamp(key: "deleted_at", on: .delete) public var deletedAt: Date?
/// ```
///
/// or serve a `DestroyRequest` instead, which removes the row. Raised at boot, from
/// `register(request:app:)`.
case archiveUnsupported(request: String, model: String)
```

### 4.13 The request-side rename

```swift
/// The server should archive an existing model: the row stays, marked deleted
///
/// - Note: Creates a **DELETE** HTTP Request. The model must declare a delete timestamp;
///   registering the route for one that does not fails at boot.
case archive

/// The server should destroy an existing model: the row is removed
///
/// - Note: Creates a **DELETE** HTTP Request
case destroy
```

```swift
/// A request that archives one model: the row stays, marked deleted
///
/// ```swift
/// public final class CardArchiveRequest: ArchiveRequest, @unchecked Sendable { … }
/// ```
///
/// The target model must declare a delete timestamp; use ``DestroyRequest`` to remove a row.
public protocol ArchiveRequest: ServerRequest, Stubbable where ResponseBody: ArchiveResponseBody {}
```

`ContainerOperation.archiveRecords` and `ContainerAuthorization.authorizesArchiveRecords` carry the same one-line DocC change: "archive" for "soft delete".

### 4.14 `CreateRequest` / `UpdateRequest`, the `ResponseError` constraint

One paragraph added to each protocol's DocC:

```swift
/// Its `ResponseError` is a ``ValidatableViewModelRequestError``: a validation failure on the
/// server, from the body's rules or from the model's own, reaches the client as that error
/// with the results inside. `ValidationError` is the ready-made choice:
///
/// ```swift
/// public typealias ResponseError = ValidationError
/// ```
```

### 4.15 `liveTransaction`, amended

The existing DocC on both overloads gains one paragraph after the example:

```swift
/// ``DataModelLifecycle/didCommit(in:)`` of every model written inside the closure runs once the
/// transaction commits, whether or not live invalidation is enabled, so use `liveTransaction`
/// wherever a hook must see a durable row.
```

### 4.16 `ValidatableModel`, replaced example

```swift
/// Defines the validation rules for a set of fields, shared by every type that adopts them
///
/// Put the rules on a `Fields` protocol so the request body, the form ViewModel and the
/// `DataModel` run the same checks:
///
/// ```swift
/// public protocol CardFields: ValidatableModel {
///     var title: String { get set }
///     var validationMessages: CardFieldsMessages { get }
/// }
///
/// public extension CardFields {
///     static var titleField: FormField<String> { .init(fieldId: #fieldId(\Self.title), …) }
///
///     func validate(fields: [any FormFieldBase]?, validations: Validations) -> ValidationResult.Status? {
///         if fields?.contains(Self.titleField) ?? true, title.isEmpty {
///             validations.append(.init(status: .error, fieldId: #fieldId(\Self.title), message: validationMessages.titleRequired))
///         }
///         return validations.status
///     }
/// }
/// ```
///
/// Append to `validations`; a `DataModel` may add rules of its own after yours. Pass `fields`
/// to check only the fields a form is editing; `nil` checks every field.
public protocol ValidatableModel {
    /// Checks the fields and appends any ``ValidationResult`` to `validations`
    ///
    /// - Parameters:
    ///   - fields: The fields to check; `nil` checks all of them
    ///   - validations: Where results are appended
    /// - Returns: `validations.status` after appending
    func validate(fields: [any FormFieldBase]?, validations: Validations) -> ValidationResult.Status?
}
```

### Part 4 checklist

- Every block leads with how the customer calls it and carries an example.
- No block names Fluent's dispatch, the middleware's internals, or a rejected alternative.
- Implementer notes live in Part 1 and 3b: the retroactive `TimestampProperty` conformance behind the delete-timestamp check (1.11), the after-commit collector `liveTransaction` installs (1.9, OQ14), the batch-write limitation's cause (OQ26), the typed error bridge (3c-1).

---

## Part 5 — Contract tests

Two channels, per `shared/execution-model.md`. The invariant tests below are written by the implementing session. The behavioral tests are projected by `fosmvvm-behavioral-test-generator` in an isolated context that receives Parts 1, 3, 3c and 4 of this plan and nothing of the code; the list here is the seed it is checked against for coverage, not a script it copies. Every test goes through public API; `@testable` is for block coverage only.

### 5.1 How a test observes each contract

- **The localized text of a refusal.** A thrown `ValidationError` carries `LocalizableString`s that resolve only at encoding (`LocalizableString.swift:163`). Both shapes encode the error through `LocalizableTestCase.encoder(locale:)` and assert the decoded message text. Fixture messages need TestYAML entries; `Tests/FOSMVVMVaporTests/TestYAML/` has none for validation today.
- **Hook order and counts.** A probe `DataModel` writes an ordered event box into `app.storage` under a public `StorageKey`; tests read it back. This is the only public signal for "which hooks ran, in what order, how many times".
- **`didCommit` after commit.** Assert "does not run when the transaction throws" with a counter and a throwing `liveTransaction` closure, and "runs once after `liveTransaction` returns" with the same counter. The auto-commit case asserts the counter after a bare `save`.
- **Suppression inside a bare transaction.** Assert the counter stayed at zero; the once-per-type warning is not a contract and is not asserted.
- **Advisory warnings.** Assert the row was written; nothing about a log.
- **Wiring.** Every probe type carries hooks; a type reached through two containers asserts one run per event (mirror `EmitMiddlewareTests.doubleReachedModelEmitsExactlyOnce`).
- **Constraint claim.** The harness is in-memory SQLite (`FluentTestHarness.swift:25`), whose driver reports `isConstraintFailure`; unique-index fixtures exist (`WriteRouteTests.swift:569`). The nil opt-out asserts "not a `ValidationError`", never a driver type.
- **`#fieldId`.** Expansion is a macro test (XCTest, macOS/Linux). Public tests assert determinism, inequality across properties and indices, and `Codable` round-trip; never the string.
- **Boot rejections.** `ServerRequestControllerError` is `Equatable`; tests match the case.

### 5.2 Invariant tests (isolation-exempt)

- `ValidationResult` / `Message` round-trip with an empty `fieldIds`; `addressesModel` true.
- `ValidationError` envelope round-trip carrying a model-level message.
- `DataModelAction` `Hashable`: the five cases are distinct and each equals itself.
- `#fieldId` determinism, inequality, round-trip; `index:` variants distinct from the base and from each other.
- `ServerRequestAction` round-trip after the rename; `.archive` and `.destroy` both `httpMethod == "DELETE"`.
- Version-stability of the two shapes above per the repo's versioning tests.

### 5.3 Behavioral tests, seed list (hook direct / save path)

- `willWriteRunsBeforeFieldValidation` / `savePersistsWillWriteValue`
- `willWriteThrowIsNotValidation` / `saveThrowFromWillWriteIsNotValidationError`
- `fieldValidationRunsOnCreateAndUpdateOnly` / `archiveSkipsFieldValidation`
- `fieldValidationFailureStopsModelValidation` / `saveReportsOnlyFieldMessages`
- `modelValidationReturnsModelLevelMessage` / `saveThrowsValidationErrorCarryingModelMessage`
- `modelValidationCollectsEveryFailure` / `saveCarriesAllModelMessages`
- `modelValidationRunsOnEveryAction` (five cases) / `destroyRefusedByModelValidation`
- `modelValidationSeesTransactionState` / `saveInLiveTransactionSeesSiblingWrite`
- `updateOfSelfReturnsNothing` / `saveOfUnchangedRowSucceeds`
- `sameValueInTwoContainersReturnsNothing` / `saveInSecondContainerSucceeds`
- `violationClaimedBecomesValidationError` / `saveOnUniqueIndexThrowsValidationError`
- `violationDeclinedRethrowsOriginal` / `saveOnUniqueIndexRethrowsDriverError`
- `didWriteWritesRelatedRow` / `didWriteThrowRollsBackTheRow`
- `didCommitRunsOnceAfterCommit` / `didCommitSkippedWhenTransactionThrows` / `didCommitRunsOnAutoCommitSave` / `didCommitSkippedInBareTransaction` / `didCommitRunsWithoutLiveInvalidation`
- `blockingPolicyStopsWriteOnWarning` / `advisoryWarningLeavesRowWritten` / `advisoryWarningRidesWithError`
- `registeredContainedTypeRunsHooks` / `registeredPivotRunsHooks` / `doubleReachedTypeRunsHooksOnce` / `unregisteredModelRunsNoHooks` / `registeredUncontainedModelRunsHooks` / `modelWithNoHooksSavesUnchanged`
- `archiveRouteWithoutDeleteTimestampFailsAtBoot` / `archiveRouteWithTimestampBoots` / `destroyRouteRegisters`
- `writeRouteRethrowsRequestResponseError` (3c-1) / `bodyValidationRethrowsRequestResponseError`
- `formFieldSubmitBlockedOnError` / `formFieldSubmitProceedsOnWarning` (3c-2)
- `replaceWithReplacesModelLevelMessages` / `replaceWithFieldOnlyLeavesModelLevel` (3c-3)
- `validationsAppendAccumulates` / `validationsRemoveAllClears`

### 5.4 Fixtures the suite needs

- A `DataModel` with `@Timestamp(on: .delete)`; none exists in `Tests/` today. Serves archive, restore, and the passing route check. `Card` serves the failing check.
- A lifecycle probe `DataModel` with all five hooks and a static policy, writing to the event box.
- Separate `.blocking` and `.advisory` probe types; separate claiming and declining types.
- A `Fields` protocol with a `@FieldValidationModel` messages type and TestYAML entries so messages localize.
- A container-scoped unique index (`.unique(on: "board_id", "number")`) for the two-containers case.
- A pivot with hooks; a child declared by two containers; an uncontained model with a migration.
- A throwing-hook error type.
- Suites that rebind `app.logger` follow `LiveTransactionTests`' per-app pattern; any suite touching a shared singleton is `.serialized`.

---

## Part 6 — Decomposition

Task groups in dependency order. Each carries its DocC from Part 4 and its tests from Part 5. A group is a PR-sized unit; the rename is its own so its diff reviews apart from the lifecycle. Release stamp is never inside a feature PR.

**G1. Validation types (FOSMVVM).** `Validations` encapsulation (`private(set)`, `append`, `append(contentsOf:)`, `modelMessages`, `replace(with:)` model-level rule); `ValidationResult(status:message:)`, `Message.addressesModel`; `FormFieldView.validateIt` guard fix; `withFormValidations()` modifier (`#if canImport(SwiftUI)`); `ValidatableModel` DocC example; the five in-repo mutation sites. Tests: 5.2 round-trips, 3c-2, 3c-3, append/removeAll.

**G2. `#fieldId` macro (FOSMacros + FOSMVVM).** First freestanding macro: `ExpressionMacro` conformance reading `KeyPathExprSyntax.components.last`, diagnostics for subscript and `$` components and for a rootless key path; `public macro` declarations (base and `index:`) in `Sources/FOSMVVM/Macros/Macros.swift`; plugin registration in `FOSMacros.swift`; `FormFieldIdentifier(id:)` to internal; fields generator + template + skills switch to the macro. Tests: macro expansion (XCTest), 5.2 identity invariants.

**G3. Request-side rename.** `.delete` → `.archive`, `DeleteRequest` → `ArchiveRequest`, `DeleteResponseBody` → `ArchiveResponseBody`, `ControllerRouting` suffix, `ContainerOperation.archiveRecords`, `authorizesArchiveRecords`, HTTP-method statics removed, `httpMethod` switches (`ServerRequest+Fetch.swift:292`, `TestingServerRequestResponse.swift:155`), 49 files; CHANGELOG migration lines. Tests: 5.2 action round-trip.

**G4. Write requests' error constraint (FOSMVVM + FOSMVVMVapor).** `CreateRequest` / `UpdateRequest` `where ResponseError: ValidatableViewModelRequestError`; the write route catches `ValidationError` from body `validate()` and `save` and rethrows `SR.ResponseError(validations:)`; test requests updated. Tests: `writeRouteRethrowsRequestResponseError`, `bodyValidationRethrowsRequestResponseError`.

**G5. Lifecycle types and middleware (FOSMVVMVapor).** `DataModelAction`, `DataModelWriteContext`, `DataModelCommitContext`, `ValidationWarningPolicy`, `ConstraintViolation`, `DataModelLifecycle` with defaults, `DataModel` inherits; the lifecycle middleware (per type, weak Application, sequence of 1.3, constraint translation via `DatabaseError.isConstraintFailure`); a lifecycle coverage `StorageKey`; wiring in `register(_:migration:)` (both overloads) and `useLiveInvalidation(on:)`, lifecycle installed before emit; the `DataModel` overload (`where IDValue == ModelIdType`, `containment: []`, `.inherits`, non-container flag; `isRegisteredContainer` unaffected); retire `validateModel(on:)`. Tests: 5.3 hook, validation, policy, wiring, constraint groups.

**G6. After-commit collector (FOSMVVMVapor).** `liveTransaction` always installs the collector; the collector holds `didCommit` closures beside identities; drain on commit runs hooks then emits; bare-transaction suppression with the once-per-type warning keyed in `app.storage` (no broadcaster needed). Tests: the five `didCommit*` cases.

**G7. Write route (FOSMVVMVapor).** `commitCreate` / `commitUpdate` inside `liveTransaction`; `commitDelete` → `commitArchive` and `commitDestroy`; `register<SR: DestroyRequest>` overload with its own action table, `serveDestroy`, boot rejection removed; delete-timestamp check at archive route registration (retroactive `TimestampProperty` conformance); `ServerRequestControllerError.archiveUnsupported`, `Equatable`. Tests: route checks, `destroyRouteRegisters`, transaction-state test.

**G8. Docs, skills, catalog, template.** `FOSMVVMArchitecture.md` "The Shared Validation Contract"; datamodel generator + reference; fields generator; serverrequest generator examples; view generator (`validationResults` drift); `checks/datamodel.md` + new rules "validators never mutate", "batch write of a DataModel", "raw migrations.add of a DataModel", "validations.validations mutation"; API catalog (retire `validateModel(on:)` at `FOSMVVMVapor.md:149`, `:502`; new entries for every 2.1 symbol; reach-for lines); bootstrap template (`Card.swift.tmpl:15` DocC, `configure.swift.tmpl` registers `Card`, `CardFields.swift.tmpl` appends); plugin version bump.

**G9. Release.** CHANGELOG entry with the migration notes from G1–G4; `Release.version` stamp in the release ritual, not in any feature PR. Version is David's call; the wire and source breaks make it larger than a patch.

Behavioral projection runs after G5–G7 compile, in isolation, against Parts 1, 3, 3c, 4; its coverage gaps are classified per the execution model, never patched from the code.
