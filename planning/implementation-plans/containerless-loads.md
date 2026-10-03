# Containerless loads — implementation plan

Work item: `planning/stream/feat-containerless-loads.md`. Rulings OQ41–OQ52 live there. This plan is the fosmvvm-planning gate's output: design first, then customer DocC, then contract tests, then decomposition. Sections after the naming table are written only once the names are ratified.

Status: **Recut 2026-09-30 on David's ruling: record authority is the first axis of authorization, container extension the second; candidates B and D together with the union rule and the subject-identity registration; D first, then B. Names ruled so far: the `ModelAuthorization` family (OQ48/OQ58); `ContainmentScope` with `.parent`/`.request`/`.application`/`.subject` and `within:` (replaces `RootScope` + `RootSource`); `useApplicationScope(_:)`; `Model.loadingPlan(_ operation: ModelOperation, within:via:)` and `Model.creationPlan(within:)` returning `LoadingPlan<Self>`, declared in a `loadingPlans` block (replaces `LoadRequirement`/`DataRequirement`; `ModelAccess`/`ModelAuthority` withdrawn). Naming for this thread is closed except the six B/D names still riding as candidates. OQ44–OQ60 ruled; the last six names (OQ48) are candidates; Part 6 written. Nothing built.**

---

## Part 1 — Design

Concepts first. Names are candidates from the table in Part 2 and are David's to arbitrate. Every code fact below is quoted from `main` at 0.18.0.

### 1.1 The model

A record is the unit of authorization. A grant names a record and says what its holder may do to that record: read, write, archive, destroy.

A container is a record, so it is authorized the same way, and it extends its authorization to the records it contains, by contained type: what the holder may do to each type inside it. `.inherits` carries that extension down the containment path.

Either authority suffices. A subject may archive a Board because a grant names the Board, or because a grant on its Workspace extends `archiveRecords` of type Board. Neither grant has to know about the other.

FOS today has the second axis only. `ContainerAuthorization` asks one question, `Sources/FOSMVVM/Protocols/ContainerAuthorization.swift:43-52`:

```swift
public protocol ContainerAuthorization: Sendable {
    /// The container this authorization grants access within (persist it as a stored ``ModelIdentity``).
    var authorizedContainer: ModelIdentity { get }
    /// Whether `operation` on records of `recordType` inside `container` is granted.
    func authorizes(
        _ operation: ContainerOperation,
        ofType recordType: any Model.Type,
        in container: ModelIdentity
    ) -> Bool
}
```

Every case of `ContainerOperation` is about a container's records (`ContainerOperation.swift:19`). Nothing is authorized as itself. So a container's own row is reachable only as a member of its parent, the top container has no parent to reach it, and a record no container extends to has no grant at all. Those are findings 2 and 1.

Under the recut the grant protocol names a model, not a container, and carries both questions. It is renamed `ModelAuthorization`, with `authorizedModel`, `ModelOperation`, and `ModelAuthorizationProvider` alongside; `ContainerOperation` keeps its name because it is still about a container's members. Deprecated typealiases and a forwarder keep every existing app compiling (1.5).

### 1.2 What a container identity does today

Four jobs, four sites. The recut keeps all four and gives each a second input.

- **Scoping.** The record set is the join off the container row: `Request+ContainerLoad.swift:128-146`, `relation.members(of: containerRecord, on: db, applying: refinement)`.
- **Authorization.** The grant filter and the operation-by-type check run against the anchor, the same lines.
- **Live refresh.** A response registers its roots and touched containers, `PlanExecutor.swift:66-74`; a write marks the row's own identity and its containers' stale, `InvalidationEmitMiddleware.swift:96-121`.
- **Create.** The root container is the create scope, `WriteRoute.swift:109-125`.

A root binds to exactly one identity: `ResolvedRecordLoadPlan.rootIdentities: [RootSource: ModelIdentity]` at `PlanExecutor.swift:109`, seeded into the load's branches at line 133.

### 1.3 Finding 2 — the subject scope (candidate D)

Every requirement is declared **within a containment scope**, the bounded region of data one party owns. `RootScope` and `RootSource` collapse into one flat enum, `ContainmentScope`, with four cases named by their owner: `.parent` (a child factory inside its parent's scope), `.request` (the container the client named in its query), `.application` (the container the application resolves for this caller), and `.subject` (what the subject's grants reach). "Root" stays the executor's internal word for the identities a scope binds to. The old spellings survive one release as deprecated overloads. A requirement within the subject scope binds to **the models of its first type that the subject's grants authorize for the requirement's operation**:

```swift
static let workspaces = Workspace.loadingPlan(.read, within: .subject)
static let boards = Board.loadingPlan(.read, within: .subject, via: Workspace.self)
```

The bound set is the union of two authorities, taken one hop deep:

- **Named records.** Every grant whose `authorizedModel` is a model of the first type and whose model-level operations cover the requirement's operation. A read of Workspaces includes every Workspace a grant names with `read`.
- **Extended members.** Every grant whose `authorizedModel` is a registered container declaring containment of the first type and whose member operations cover the operation for that type. A read of Workspaces includes every Workspace inside a granted container that declares `.all(Workspace.self)`, which is how B's system container feeds D's list.

Deeper reach stays declared. `via:` descends from the bound set through ordinary containment with the existing hop loop and the existing anchor rule. The plan never infers a path.

**Scoping.** One query per plan type, not one per grant. The binding filters the memoized grants in memory into two id lists — the models named with the operation, and the granted containers that directly contain the type with the matching member operation — and the engine runs a single query with a disjunctive predicate: id in the named list, or owner key in the granted-container list (siblings through their pivot join), or every row when a static container's `.all` is granted. The request's filter, sort, and window apply inside that query, so paging across the union is exact and the total is one count. The rows' identities are what the response registers; per-model cache keys are not needed for the read. `via:` descent from the bound set uses the existing per-container member path.

**Authorization.** The model-level question is new and is 1.5. The member question is unchanged.

**Live refresh.** Each bound root is registered as today, so a change to any listed record refreshes the list. Creates and grant changes are 1.7.

**Create.** Not within the subject scope. A create declares the container it creates into; the subject scope is a read and a write-candidate scope, never a create scope.

**Binding.** The subject scope binds one-to-many: `rootIdentities` binds a set, the load seeds one branch per bound identity, `verifyRootContainment` checks each, `touchedContainers` registers each, and the write route's candidate resolution takes the union. `.request` and `.application` keep binding one.

### 1.4 Finding 1 — the container with no table (candidate B)

An ownerless record has no grant that names it and no container that extends to it. It needs an identity to hang a grant on. The app declares a container with one instance and no storage, listing the types it owns as every row of that type:

```swift
enum Suite: SystemContainer {
    static var containment: [ContainmentRelation] { [.all(Workspace.self), .all(SystemStatus.self)] }
}

try app.register(Suite.self)
```

`Suite.identity` is minted from the type, opaque, stable. A grant row stores it as it stores any identity. `useApplicationScope` may answer with it, and a lone system container binds the application scope by itself when nothing is registered there (OQ45).

Every job runs on its existing mechanism: `.all` is one more `ContainmentRelation` whose load closure runs `Type.query(on:)` with the refinement, whose count closure runs `.count()`, whose create closure saves with no join, and whose invert closure attributes every row of the type to the system identity. The registry holds one more kind of entry, with no row to find and no middleware to install.

This is also where **create at the top** lives. Creating a Workspace is an operation on no record; the system container is the only container that can hold a `createRecords` grant for it. `Workspace.creationPlan(within: .application)` with the application scope bound to `Suite.identity`.

B is otherwise unchanged from the first draft; the implementer notes in 1.10 carry its details.

### 1.5 The model-level axis

A second operation vocabulary, for a model itself:

```swift
public enum ModelOperation: Hashable, CaseIterable, Sendable {
    case read
    case write
    case archive
    case destroy
    case anyOperation
}
```

Create is absent by design. A model is created into a container, never on itself; `ContainerOperation.createRecords` has no model-level twin, and a create declares `creationPlan(within:)` rather than a loading plan. The other four map one to one, and the wildcard excludes destroy exactly as `ContainerOperation.anyOperation` does. Intent helpers mirror the existing ones: `authorizesRead`, `authorizesWrite`, `authorizesArchive`, `authorizesDestroy`, and `authorizes(_:)` on a sequence.

The grant protocol is renamed for what it now names, and gains one requirement with a default:

```swift
public protocol ModelAuthorization: Sendable {
    /// The model this grant names (persist it as a stored ``ModelIdentity``).
    var authorizedModel: ModelIdentity { get }
    /// Whether `operation` on `model` itself is granted. Default: never.
    func authorizes(_ operation: ModelOperation, on model: ModelIdentity) -> Bool
    /// Whether `operation` on records of `recordType` inside `container` is granted.
    func authorizes(_ operation: ContainerOperation, ofType recordType: any Model.Type, in container: ModelIdentity) -> Bool
}
```

The default denies, so no app changes until it adopts the axis. `ContainerAuthorization` stays as a deprecated typealias of `ModelAuthorization`, `authorizedContainer` as a deprecated forwarder to `authorizedModel`, and `ContainerAuthorizationProvider` as a deprecated typealias of `ModelAuthorizationProvider`, so every shipped conformance compiles unchanged. `ContainerOperation` keeps its name: it is about a container's members.

The engine maps between the vocabularies internally: a read within the subject scope asks named models for `.read` and containers for `.readRecords`. The mapping stays internal until an app needs it.

### 1.6 The union rule

Either authority suffices, and the two never have to agree.

- The subject scope binds the union in 1.3.
- A write's candidate set is whatever its declared scope binds. A request that declares `Board.loadingPlan(.write, within: .subject)` accepts a target the subject may write by either authority. A request that declares `Board.loadingPlan(.write, within: .request)` accepts only the named container's extension, as today.
- Nothing an existing grant authorizes stops being authorized. The model-level axis only adds.

### 1.7 Live refresh under both scopes

- **Named and extended models** register as today, one identity per bound identity plus touched containers. A change to a listed row refreshes precisely the lists holding it.
- **Creates** are seen through B. A new Workspace inverts to the system identity, which every overview within the application scope registered. A list within the subject scope alone does not grow on create, because nothing registered an identity that did not exist.
- **Grant changes** are seen through the subject. `ModelAuthorizationProvider` gains a requirement with a default, the subject's own identity for the request, `nil` by default. When present, every requirement within the subject scope registers it. An app that declares its grant model as contained by its subject, `.children(\User.$grants)`, then refreshes a subject's lists when a grant is written, through the existing invert.
- **Cost.** Registrations grow with the bound set. The executor warns past a threshold, as the engine already does for record counts.

### 1.8 The write route under both scopes

- **Create** keeps its rule: the candidate scope is one container, bound to one identity. `.subject` is rejected at boot as a create scope.
- **Update, archive, destroy** resolve the submitted target against the candidate set. Within the subject scope the set is the union of 1.3; membership is the same check as today.

### 1.9 Boot checks

- The subject scope requires no query conformance and no `useApplicationScope`; it requires the authorization provider, which every load already requires.
- `resolveHops` accepts `.subject` when the first type is registered. A named model of type T is its own first hop; a granted container must declare containment of T.
- `creationPlan(within: .subject)` is `invalidLoadPlan` at registration, and so is a `loadingPlan` whose operation is `.anyOperation`.
- A system container's relations must all be `.all`; its owned types must be registered by the time routes register; drift between `containment` and `containedRecordTypes` is the existing check.

### 1.10 Implementer notes (rationale, not DocC)

**One query for the subject scope.** A find per named model would cost N round trips for N Workspaces and could not page across the union. The engine gains one entry for a subject-scoped plan type: build the disjunctive predicate from the two id lists and the static-container flag, apply the refinement, run once, and cache under a key made of the scope, the type, the operation, and the refinement. The registration set is derived from the returned rows' identities plus the subject. The `via:` hops below it reuse the existing per-container call and its per-container keys.

**Union at one hop, not a path walk.** Binding every path from every granted container to the requested type would be the general load, unbounded by the declaration. One hop keeps the plan's discipline: paths are declared with `via:` and validated at boot. The one-hop union already lets B's system container and D's model grants meet.

**Set-valued binding — corrected in D5 (2026-09-30).** Neither form above was right: the subject scope binds **per tuple**, not per scope. Two subject-scoped tuples with different first types (`Workspace.loadingPlan(.read, within: .subject)` and `SystemStatus.loadingPlan(.read, within: .subject)`) bind different sets, so `rootIdentities[.subject]` names no set at all. Shipped form: `ResolvedRecordLoadPlan.subjectBindings: [RecordLoadPlan.Tuple: [ModelIdentity]]` beside the unchanged `rootIdentities`, plus `subjectIdentity: ModelIdentity?`. `.request` and `.application` are untouched; the create rule holds by construction (boot refuses `.subject` as a create scope). The binding runs the tuple's first-type query at resolve time (refined when the tuple has no `via:` and carries the mark); `load` re-reads the same cache entry. No per-row `verifyRootContainment`: every bound row is of the first type by construction and boot validated the chain below it — a per-row check would be theatre. Each bound row is its own root AND anchor for its `via:` subtree (the existing anchor rule with the row as root): an extended member reached through a grant on its container does not carry that container's grant down; to descend under a container's grant, declare the path from that container within `.request`/`.application`. `tupleCacheKeys` carries `RecordCacheKey` (`.container` | `.subject`); readers go through `Request.cachedRecords(for:)` / `cachedCount(for:)`.

**D6 note (found in D5).** `invalidateContainerRecords(of:)` drops container-keyed entries only; a write route whose response plan has a subject-scoped tuple must also drop the subject-scope caches before the refresh re-run, or the archived/updated row re-serves stale. Cheapest correct form: `invalidateWrittenContainers` clears `subjectScopeCache` and `subjectScopeCountCache` whole (per-request, so the cost is nil).

**The subject identity is the provider's to vend**, not a second resolver, because the provider already answers for the subject once per request and its memo is the natural place.

**The system container's identity id part** is a framework constant pinned internally; `SystemContainer` is a sibling of `Container`, not a refinement, because it has no instances; `RegisteredModel.modelType`'s two sweeps skip a tableless entry; `.all` widens `ContainmentRelation.containerType`; more than one system container is allowed. Unchanged from the first draft.

**Contained types can gain model grants too.** A grant may name a Card. That is per-leaf authorization, possible now and paid for in grant rows by the app's choice. The bulk path stays the extension.

### 1.11 Rejected

**A. A scope that names no container.** Every job gains a second path and the authorization question gains a default nobody asked for; D answers the same declaration need with authority the app stores.

**C. The synthetic row.** Rejected in OQ41.

**A sentinel identity for "every row of a type".** A second meaning for one field. B mints a constant id as the identity of a declared type, one meaning.

### 1.12 Sequencing

Two work items. D first: it changes the authorization model, and B's grant on a system container is one more grant under that model. Then B, smaller, on whichever model has shipped. fosline's overview lands after both: its status models under B, its Workspace list under D.

---

## Part 2 — Naming table, in code context

David arbitrates every name. First the declarations as they would ship, then the alternatives per name. Every name below is a candidate.

### 2.1 The declarations

```swift
// FOSMVVM — Protocols/ModelOperation.swift
public enum ModelOperation: Hashable, CaseIterable, Sendable {
    case read
    case write
    case archive
    case destroy
    case anyOperation
}

// FOSMVVM — Protocols/ModelAuthorization.swift (renamed from ContainerAuthorization; one more requirement, with a default)
public protocol ModelAuthorization: Sendable {
    var authorizedModel: ModelIdentity { get }
    func authorizes(_ operation: ModelOperation, on model: ModelIdentity) -> Bool
    func authorizes(_ operation: ContainerOperation, ofType recordType: any Model.Type, in container: ModelIdentity) -> Bool
}
@available(*, deprecated, renamed: "ModelAuthorization")
public typealias ContainerAuthorization = ModelAuthorization
public extension ModelAuthorization {
    @available(*, deprecated, renamed: "authorizedModel")
    var authorizedContainer: ModelIdentity { authorizedModel }
}

// FOSMVVM — Protocols/LoadingPlan.swift (replaces LoadRequirement + DataRequirement on the public surface)
public struct LoadingPlan<Model: FOSMVVM.Model>: Sendable { /* the declaration's data; read back by handle */ }
public extension FOSMVVM.Model {
    /// One clause of a factory's plan: the models of this type, within a scope, the subject may `operation`.
    static func loadingPlan(
        _ operation: ModelOperation,            // .read, .write, .archive, .destroy; .anyOperation is rejected at boot
        within scope: ContainmentScope,
        via intermediates: any FOSMVVM.Model.Type...
    ) -> LoadingPlan<Self>
    /// A create request's clause: the one container this type is created into. Never the subject scope.
    static func creationPlan(within scope: ContainmentScope) -> LoadingPlan<Self>
}
@resultBuilder public enum LoadingPlans { /* collects the factory's clauses; the boot walk reads the erased list behind the wall */ }
// ComposableFactory: `static var loadingPlans: LoadingPlans { get }` replaces `dataRequirements: [any DataRequirement]`.
// LoadRequirement / DataRequirement stay one release as deprecated spellings.

// FOSMVVM — Protocols/ContainmentScope.swift (replaces RootScope + RootSource)
public enum ContainmentScope: Hashable, Sendable {
    case parent
    case request
    case application
    case subject
}
// Model.loadingPlan(_:within:via:) takes a ContainmentScope; the deprecated LoadRequirement
// `in: RootScope` overloads stay one release, mapping .parentRoot → .parent,
// .newRoot(.query) → .request, .newRoot(.apex) → .application.
// ComposedChild.child(_:within:) likewise; `rootedAt:` deprecated.
// RootedQuery becomes ScopedQuery { var scopeIdentity: ModelIdentity }, typealias deprecated.
// useApexContainerResolver(_:) becomes useApplicationScope(_:), forwarder deprecated;
// ContainmentError.duplicateApexContainerResolver becomes duplicateApplicationScope.

// FOSMVVMVapor — Protocols/ModelAuthorizationProvider.swift (renamed; one more requirement, with a default)
public protocol ModelAuthorizationProvider: Sendable {
    associatedtype Authorization: ModelAuthorization
    func modelAuthorizations(for request: Request) async throws -> [Authorization]
    func subjectIdentity(for request: Request) async throws -> ModelIdentity?
}
@available(*, deprecated, renamed: "ModelAuthorizationProvider")
public typealias ContainerAuthorizationProvider = ModelAuthorizationProvider

// FOSMVVMVapor — Extensions/Application+Containment.swift
public extension Application {
    func useModelAuthorizationProvider(_ provider: some ModelAuthorizationProvider) throws
}

// FOSMVVMVapor — Containment/SystemContainer.swift
public protocol SystemContainer {
    static var containment: [ContainmentRelation] { get }
    static var authorityFlow: AuthorityFlow { get }
}
public extension SystemContainer {
    static var identity: ModelIdentity { get }
}

// FOSMVVMVapor — Containment/ContainmentRelation.swift
public extension ContainmentRelation {
    static func all<To: DataModel>(_ type: To.Type) -> ContainmentRelation
}

// FOSMVVMVapor — Extensions/Application+Containment.swift
public extension Application {
    func register(_ type: (some SystemContainer).Type) throws
}
```

Consumer side, for the DocC examples:

```swift
struct Grant: ModelAuthorization {
    let authorizedModel: ModelIdentity
    let modelOperations: [ModelOperation]
    let memberOperations: [ContainerOperation]
    let memberTypes: [ModelNamespace]

    func authorizes(_ operation: ModelOperation, on model: ModelIdentity) -> Bool {
        model == authorizedModel && modelOperations.authorizes(operation)
    }
    func authorizes(_ operation: ContainerOperation, ofType recordType: any FOSMVVM.Model.Type, in container: ModelIdentity) -> Bool {
        container == authorizedModel && memberOperations.authorizes(operation) && memberTypes.contains(recordType.modelIdentityNamespace)
    }
}

static let workspaces = Workspace.loadingPlan(.read, within: .subject)
static let boards = Board.loadingPlan(.read, within: .subject, via: Workspace.self)

enum Suite: SystemContainer {
    static var containment: [ContainmentRelation] { [.all(Workspace.self), .all(SystemStatus.self)] }
}
```

### 2.2 Alternatives per name

Legibility is the reading-ergonomics axis: distinct leading shapes, no near-anagrams, no pairs differing only in middle letters.

- **`loadingPlan(_:within:via:)` and `creationPlan(within:)` on `Model`, returning `LoadingPlan<Self>`** (ruled) — replace `LoadRequirement.read(_:in:via:)` and its verb siblings. Ruled after `AuthorizedModels` and `ModelSelection`: the free-floating type was undiscoverable, and "load" was unrooted until it hung on the model type (Fluent's `Model.query(on:)` precedent). The filter argument is `ModelOperation` (`ModelAccess` with adjective cases was minted and withdrawn: a third enum for the same meaning). Create is its own entry point because a create names the container created into, never a set of models; `.anyOperation` is rejected in a plan at boot. The declaration block is `loadingPlans: LoadingPlans`, a result builder, so no `any` at the site; `DataRequirement`'s only job was that `any`.
- **`ContainmentScope`** (ruled) — the flat enum that replaces `RootScope` + `RootSource`. Rejected on the way: `RootAuthority` (a scope is where authority is anchored, not the authority; the subject decides nothing), `Scope` (single noun, scope of what), `LoadScope` ("load" is noun or verb and not a data word). Two nouns: the second says what it is, the first what bounds it, and containment is FOS's own term.
- **`.parent`, `.request`, `.application`, `.subject`** (ruled) — the four owners of a scope; the case is the object of `within:`. `.apex` and `.granted`/`.grants` were the earlier spellings.
- **`within:`** (ruled) — the preposition containment uses; "read Cards within the request" is the sentence.
- **`ScopedQuery` / `scopeIdentity`** — candidates for `RootedQuery` / `rootIdentity`; alternatives `RequestScopeQuery`, `ContainedQuery`.
- **`useApplicationScope(_:)`** (ruled) — replaces `useApexContainerResolver(_:)`, whose words predate the scope vocabulary and name only the mechanism. Follows the boot idiom (`useLiveInvalidation`, `useAppState`, `useModelAuthorizationProvider`). `useApplicationScopeResolver` was the interim candidate.

- **`ModelOperation`** (ruled, OQ48) — `RecordOperation` was the first candidate; "record" is retired from new names in favor of the framework's `Model` stem. The cases carry no `Records` suffix because the object is the model itself.
- **`ModelAuthorization`**, **`authorizedModel`**, **`ModelAuthorizationProvider`**, **`modelAuthorizations(for:)`**, **`useModelAuthorizationProvider(_:)`** (ruled, OQ48/OQ58) — the grant names a model and carries both questions; the container-stemmed names stay as deprecated typealiases and forwarders for one release. `ContainerOperation` keeps its name.
- **`authorizes(_:on:)`** — alternatives `authorizesModel(_:_:)`, `authorizes(_:onModel:)`. Same verb as the member question, distinguished by the `on` preposition against `in`.
- **`subjectIdentity(for:)`** — alternatives `subject(for:)`, `authorizedSubject(for:)`, `principalIdentity(for:)`. "Subject" is the word the provider's DocC already uses.
- **`SystemContainer`** — alternatives `RootContainer` (joins the `Root…` cluster), `ApexContainer` (the apex is a role, not a kind), `SingletonContainer`, `TablelessContainer`, `VirtualContainer` (mechanism words).
- **`.all(_:)`** — alternatives `.every(_:)`, `.rows(of:)`, `.allRecords(_:)`.
- **`identity`** — alternatives `containerIdentity`, `systemIdentity`.
- **`register(_:)`** overload — alternative `registerSystemContainer(_:)`.
- **`Suite`** in the examples — the consumer's own name; `Workspace` is already the top data container in the vocabulary.

---

## Part 3 — Rulings

### 3.1 Ruled 2026-09-30 (David)

OQ44 B for finding 1, not A. A recorded as rejected.

OQ45 A lone system container binds the application scope when `useApplicationScope` is not registered; a registered one wins.

OQ46 `SystemContainer` is a sibling of `Container`, not a refinement.

OQ47 The system container's identity is minted by the framework from the type, with a constant id part pinned internally.

OQ49 More than one system container per application is allowed.

OQ50 The model-level axis is restored: model authority is the first axis, container extension the second.

OQ51 D is the answer to finding 2, with the union at one hop.

OQ52 Two work items, D first, then B.

OQ53 The union rule: either authority suffices; a write's candidate set is whatever its declared root binds. Part 1.6.

OQ54 The subject scope binds the union one hop deep, named models plus direct extended members; deeper reach is declared through `via:`. Part 1.3, 1.10.

OQ55 The subject's identity is vended by `ModelAuthorizationProvider` with a `nil` default, and every requirement within the subject scope registers it when present. Part 1.7.

OQ56 `ModelOperation` has read, write, archive, destroy, and the wildcard; create is deliberately absent; the wildcard excludes destroy. Part 1.5.

OQ57 The model-level requirement defaults to deny. Part 1.5.

OQ58 `authorizedContainer` becomes `authorizedModel`, with a deprecated forwarder. Part 1.5.

OQ59 `.subject` is rejected at boot as a create scope; create at the top goes through B. Part 1.8.

OQ60 A registration-count threshold warning within the subject scope. Part 1.7.

OQ48 Names ruled so far: the `Model` grant family — `ModelAuthorization`, `authorizedModel`, `ModelOperation`, `ModelAuthorizationProvider`, `modelAuthorizations(for:)`, `useModelAuthorizationProvider(_:)` — with `ContainerOperation` unchanged; `ContainmentScope` with `.parent`, `.request`, `.application`, `.subject` and the `within:` label (replaces `RootScope` + `RootSource`; `RootAuthority` and `.grants` were interim candidates, rejected); old spellings as deprecated overloads and forwarders.

### 3.1a Review round, 2026-09-30 (five reviewers against this specification; David's rulings)

Fixed on David's word: the mutual-default recursion (the former spelling traps by name); the whole-type reach for a granted system container; the owned-types check at boot; the constant-id pin by literal; `DataRequirement`/`dataRequirements` deprecated with the defaults in a deprecated context; the `Grant(...)` example arity; the Part 4 `ContainerOperation` and `AuthorityFlow` DocC applied; caller-only DocC on the mutual defaults.

OQ61 RULED 2026-09-30 (David, "go with your recommendation"): the general `ModelIdentity.init(namespace:id:)` stays internal; a single-purpose `package static func ModelIdentity.systemContainer(for:)` in FOSMVVM mints a system container's identity, the constant id part beside it. Name is a candidate.

OQ62 RULED 2026-09-30 (David: "I don't see a big deal there"): `.parent` at a top-level factory resolves to the request's own scope, as shipped and as it always has; the Part 4 draft sentence saying it fails at boot is struck.

OQ63 Two system containers listing the same type: permitted by the shipped checks, unruled. DEFERRED by David 2026-09-30 (docs/deferrals.md).

OQ64 RULED 2026-09-30 (David: "Add it"): one sentence on the `.subject` case DocC says a create registers no identity there and points at the application scope or a system container for lists that must grow live.

Nits from the round (fourteen, mechanical) are parked for a later pass; the list is in the session transcript of 2026-09-30 and the handoff memory.

### 3.2 Awaiting your ruling

OQ48 The last names, each with its candidate from Part 2.2: `authorizes(_:on:)`, `subjectIdentity(for:)`, `SystemContainer`, `.all(_:)`, `identity`, `register(_:)`.

---

## Part 4 — Customer DocC, written before the code

Filled against the ruled names; the six B/D candidates are marked where they appear.

The enums first, every case documented with an example and when to reach for it — the option set is where a reader decides, so each option carries its own DocC.

**`ContainmentScope`**, with every case

```swift
/// The region of data a loading plan is confined to, named by the party that owns it.
///
/// Every clause of a factory's plan says where it starts with `within:`. The scope decides
/// which container the plan begins from; the subject's grants then decide what loads inside
/// it — a scope never widens authority. Choose by who owns the region:
///
/// ```swift
/// static let cards      = Card.loadingPlan(.read, within: .request)             // the container the client named
/// static let status     = SystemStatus.loadingPlan(.read, within: .application) // the container the app resolves
/// static let workspaces = Workspace.loadingPlan(.read, within: .subject)        // what the subject's grants reach
/// static var children: [ComposedChild] { [.child(CardCellViewModel.self, within: .parent)] }
/// ```
///
/// `via:` descends from any scope through declared containment:
/// `Board.loadingPlan(.read, within: .subject, via: Workspace.self)`.
public enum ContainmentScope: Hashable, Sendable {
    /// The scope the enclosing factory bound. A child composed inside a parent shares it.
    ///
    /// ```swift
    /// // BoardPageViewModel is within .request (one Board). Its child:
    /// @ViewModel struct CardCellViewModel: ComposableFactory {
    ///     static let cards = Card.loadingPlan(.read, within: .parent)   // the cards of THAT Board
    ///     static var loadingPlans: LoadingPlans { cards }
    /// }
    /// ```
    ///
    /// Use it for every child unless the child deliberately opens a region of its own. A
    /// top-level factory has no parent; its `.parent` resolves to the request's own scope.
    case parent

    /// The container the client named. The request's query conforms to ``ScopedQuery`` and
    /// vends its identity.
    ///
    /// ```swift
    /// struct BoardPageQuery: ScopedQuery {
    ///     let scopeIdentity: ModelIdentity            // the Board this page is about
    /// }
    /// static let cards = Card.loadingPlan(.read, within: .request)
    /// ```
    ///
    /// Use it for a page about one container the client chose. One request names one
    /// container. A container the subject holds no grant reaching loads empty — never an
    /// error, so a guessed identity learns nothing.
    case request

    /// The container the application resolves for this caller, through
    /// ``useApplicationScope(_:)`` — a constant for a single-tenant app, the caller's tenant
    /// for a multi-tenant one — or, with nothing registered, the one ``SystemContainer``.
    ///
    /// ```swift
    /// // configure(_:)
    /// try app.useApplicationScope { req in try await req.auth.require(SessionUser.self).tenantIdentity }
    ///
    /// static let status     = SystemStatus.loadingPlan(.read, within: .application)
    /// static let newWorkspace = Workspace.creationPlan(within: .application)   // create at the top
    /// ```
    ///
    /// Use it for anything scoped to the whole application or the caller's tenant: overviews,
    /// system-wide models, and creating a top-level container. The client cannot pick another.
    case application

    /// What the subject's grants reach: every model of the plan's type a grant names with
    /// the plan's operation, plus every such model inside a granted container that directly
    /// contains the type. Bound from the grants alone — nothing to name, nothing to resolve.
    ///
    /// ```swift
    /// static let workspaces = Workspace.loadingPlan(.read, within: .subject)                       // the Workspaces this user may see
    /// static let boards     = Board.loadingPlan(.read, within: .subject, via: Workspace.self)     // and their Boards
    /// static let archivable = Board.loadingPlan(.archive, within: .subject)                       // an archive request's candidates
    /// ```
    ///
    /// Use it for a list with no parent that differs per subject, and for a write whose
    /// target may be reachable by either a grant on the model or a grant on its container.
    /// Never a create scope: `creationPlan(within: .subject)` fails at boot. Every bound
    /// model is registered for live refresh, and the subject too when the provider vends it.
    case subject
}
```

**`ModelOperation`**, with every case

```swift
/// What a grant lets its holder do to a model itself — the model-level axis of authorization.
///
/// It has two homes. A grant answers it for the model it names:
///
/// ```swift
/// func authorizes(_ operation: ModelOperation, on model: ModelIdentity) -> Bool {
///     model == authorizedModel && modelOperations.authorizes(operation)
/// }
/// ```
///
/// and a loading plan names the operation the subject must hold over every model it returns:
///
/// ```swift
/// static let boards  = Board.loadingPlan(.read, within: .subject)
/// static let targets = Board.loadingPlan(.archive, within: .subject)   // an archive request's candidates
/// ```
///
/// Check a granted set by intent, never by comparing cases — `granted.authorizes(.archive)` —
/// so the wildcard is honored. There is no `create`: a model is created into a container,
/// which is ``creationPlan(within:)`` on the model and ``ContainerOperation/createRecords``
/// on the container's grant.
public enum ModelOperation: Hashable, CaseIterable, Sendable {
    /// Read the model's own row. In a plan: the models the subject may read.
    ///
    /// ```swift
    /// static let workspaces = Workspace.loadingPlan(.read, within: .subject)
    /// ```
    case read

    /// Modify the model's own fields. In a plan: an update request's candidates — the submitted
    /// target must be one of them.
    ///
    /// ```swift
    /// static let candidates = Workspace.loadingPlan(.write, within: .subject)
    /// ```
    case write

    /// Archive the model: it stays, marked deleted and recoverable. In a plan: an archive
    /// request's candidates.
    ///
    /// ```swift
    /// static let candidates = Board.loadingPlan(.archive, within: .subject)
    /// ```
    case archive

    /// Destroy the model permanently. Never implied by ``anyOperation``; a grant must say it.
    /// In a plan: a destroy request's candidates.
    ///
    /// ```swift
    /// static let candidates = Board.loadingPlan(.destroy, within: .subject)
    /// ```
    case destroy

    /// Wildcard: every operation except ``destroy``. A grant may hold it; a loading plan may not
    /// name it — `loadingPlan(.anyOperation, ...)` fails at boot, because "models the subject
    /// holds every authority over" is not a set anyone declares.
    ///
    /// ```swift
    /// let modelOperations: [ModelOperation] = [.anyOperation]   // read, write, archive — not destroy
    /// ```
    case anyOperation
}
```

**`ContainerOperation`**, revised for the two axes, with every case

```swift
/// What a grant lets its holder do to the models a container contains — the container-extension
/// axis of authorization, beside ``ModelOperation`` for the container itself.
///
/// A grant on a Workspace can say both: `.write` on the Workspace's own row (``ModelOperation``)
/// and `readRecords` of type `Board` inside it (this enum). A grant answers this axis per
/// contained type:
///
/// ```swift
/// func authorizes(_ operation: ContainerOperation, ofType recordType: any FOSMVVM.Model.Type, in container: ModelIdentity) -> Bool {
///     container == authorizedModel && memberOperations.authorizes(operation) && memberTypes.contains(recordType.modelIdentityNamespace)
/// }
/// ```
///
/// A loading plan never names this enum directly: `Board.loadingPlan(.read, within: .request)`
/// asks the request's container for `readRecords` of `Board`, and `Board.creationPlan(within:
/// .request)` asks it for `createRecords`. With ``AuthorityFlow/inherits`` a grant's extension
/// reaches every level beneath the container along a declared path.
///
/// Check by intent, never by comparing cases: `grantedOperations.authorizes(.readRecords)`.
public enum ContainerOperation: Hashable, CaseIterable, Sendable {
    /// Read the models the container owns. Asked by every `loadingPlan(.read, ...)` whose scope
    /// is a container, per contained type.
    case readRecords

    /// Modify the models the container owns. Asked by `loadingPlan(.write, ...)` within a
    /// container: an update request's candidates.
    case writeRecords

    /// Create new models in the container. Asked by ``creationPlan(within:)`` — the only way
    /// a create is authorized, since a model that does not exist has no grant of its own.
    ///
    /// ```swift
    /// static let newBoard = Board.creationPlan(within: .request)   // into the Workspace the client named
    /// ```
    case createRecords

    /// Archive the container's models: they stay, marked deleted and recoverable. Asked by
    /// `loadingPlan(.archive, ...)` within a container.
    case archiveRecords

    /// Permanently destroy the container's models. Never implied by ``anyOperation``. Asked by
    /// `loadingPlan(.destroy, ...)` within a container.
    case destroyRecords

    /// Wildcard: every operation except ``destroyRecords``, which must be granted explicitly.
    ///
    /// ```swift
    /// let memberOperations: [ContainerOperation] = [.anyOperation]   // read, write, create, archive — not destroy
    /// ```
    case anyOperation
}
```

**`AuthorityFlow`**, as it reads beside the two axes, with every case

```swift
/// Whether a grant on a container reaches the models beneath the models it contains, or stops
/// at its direct members.
///
/// ```swift
/// final class Workspace: ContainerDataModel { static var authorityFlow: AuthorityFlow { .inherits } }  // the default
/// final class Board: ContainerDataModel     { static var authorityFlow: AuthorityFlow { .guards } }
/// ```
///
/// With `Board.loadingPlan(.read, within: .request, via: Workspace.self)` the plan descends
/// Workspace → Board → Card; each hop's grant check runs against the nearest guarding
/// container above it, else the scope's own container.
public enum AuthorityFlow: Sendable {
    /// A grant on this container extends through it: `readRecords` of `Card` granted on a
    /// Workspace reaches the Cards of every Board inside it. The default. One grant high up
    /// serves a whole subtree.
    case inherits

    /// A grant on this container stops here: to read the Cards of a Board the subject needs a
    /// grant on that Board, whatever the Workspace grants. Use it where a container is its own
    /// unit of authority — a private Board inside a shared Workspace.
    case guards
}
```

**`ModelAuthorization`**

```swift
/// Declares that your grant value can answer "may this subject touch this model, and what it
/// contains?" — conform a value type your persisted grant row projects, so the framework can
/// scope every load with it.
///
/// ```swift
/// struct Grant: ModelAuthorization {
///     let authorizedModel: ModelIdentity        // the model this grant names — a Workspace, a Board, a Card
///     let modelOperations: [ModelOperation]     // what the holder may do to it
///     let memberOperations: [ContainerOperation] // what it extends to the models it contains
///     let memberTypes: [ModelNamespace]
///
///     func authorizes(_ operation: ModelOperation, on model: ModelIdentity) -> Bool {
///         model == authorizedModel && modelOperations.authorizes(operation)
///     }
///     func authorizes(_ operation: ContainerOperation, ofType recordType: any FOSMVVM.Model.Type, in container: ModelIdentity) -> Bool {
///         container == authorizedModel && memberOperations.authorizes(operation) && memberTypes.contains(recordType.modelIdentityNamespace)
///     }
/// }
/// ```
///
/// A grant on a container answers both questions; a grant on a leaf answers the first. The
/// framework never sees your role or user types.
```

**`ModelAuthorization.authorizes(_:on:)`**

```swift
/// Whether `operation` on `model` itself is granted.
///
/// Answer it for the model your grant names — a container's own row included — so the
/// framework can load that model on its own authority, without a parent:
///
/// ```swift
/// func authorizes(_ operation: ModelOperation, on model: ModelIdentity) -> Bool {
///     model == authorizedModel && modelOperations.authorizes(operation)
/// }
/// ```
///
/// The default answers `false`: a grant that does not implement this authorizes only the
/// models its container extends to, as before.
```

**`ModelAuthorizationProvider.subjectIdentity(for:)`**

```swift
/// The identity of the subject whose grants this request carries, so a load within the
/// subject scope refreshes live when that subject's grants change:
///
/// ```swift
/// func subjectIdentity(for request: Request) async throws -> ModelIdentity? {
///     try request.auth.require(SessionUser.self).modelIdentity
/// }
/// ```
///
/// Declare your grant model as contained by the subject — `.children(\User.$grants)` — and a
/// written grant nudges every live list within the subject scope for that subject. The default
/// answers `nil`: grant changes then reach a client on its next fetch.
```

**`SystemContainer`**, **`ContainmentRelation.all(_:)`**, **`SystemContainer.identity`**, **`Application.register(_:)`** — as drafted for B, with the example renamed to `Suite` owning `Workspace` and `SystemStatus`.

---

## Part 5 — Contract tests

Against the public contract only, through the Vapor test application.

**D**

- A read of Workspaces within the subject scope returns the Workspaces a grant names with `read`, the Workspaces inside a granted container that declares them, and nothing else; a subject with no grants loads empty.
- A grant with the default model-level answer contributes no named models and still contributes its extended members.
- Filter, sort, and pagination refine the union; the paginated total is the refined count.
- `via:` descends from the bound set: Boards inside the granted Workspaces, anchored per Workspace.
- The response's registrations include every bound identity; with a subject identity vended, they include it too; a grant write on a subject-contained grant model emits the subject's identity.
- A write request whose candidate set is within the subject scope accepts a target reachable by either authority and rejects one reachable by neither.
- `creationPlan(within: .subject)` and `loadingPlan(.anyOperation, ...)` each fail at registration with `invalidLoadPlan`.
- `ModelOperation.anyOperation` authorizes read, write, and archive and not destroy.
- A conformer written against `ContainerAuthorization` and `authorizedContainer` compiles with deprecation warnings and behaves as before.

**B** — as drafted in the first version: boot checks, load, paths, live on create and destroy, create at the top, identity stability, and the application-scope default.

---

## Part 6 — Decomposition

Two work items, in the order of 1.12, each its own branch and PR. Names are the candidates of Part 2 until OQ48 rules the last six; a later rename is a mechanical pass. Every task carries its DocC from Part 4 and its contract tests from Part 5; a task is done when both are in and the full suite is green. Every push to an open PR is gated on David.

### 6.1 Work item D — model authority (`feat/model-authority`)

**D1. `ModelOperation`.** New file `Sources/FOSMVVM/Protocols/ModelOperation.swift`: the five cases, the intent helpers (`authorizesRead`, `authorizesWrite`, `authorizesArchive`, `authorizesDestroy`) and the `Sequence` helpers mirroring `ContainerOperation.swift:44-110`. Internal mapping `ContainerOperation.modelOperation` (create → nil). Tests in `Tests/FOSMVVMTests/Protocols/`: the wildcard covers read, write, archive and not destroy; a sequence answers by intent.

**D2. The grant family rename.** `Sources/FOSMVVM/Protocols/ContainerAuthorization.swift` becomes `ModelAuthorization.swift`: `ModelAuthorization` with `authorizedModel`, the new `authorizes(_:on:)` requirement with a deny default in an extension, the member question unchanged; `ContainerAuthorization` as a deprecated typealias and `authorizedContainer` as a deprecated forwarder. `Sources/FOSMVVMVapor/Protocols/ContainerAuthorizationProvider.swift` becomes `ModelAuthorizationProvider.swift`: `modelAuthorizations(for:)`, `subjectIdentity(for:)` with a `nil` default, deprecated typealias. `Application+Containment.swift:113-` gains `useModelAuthorizationProvider(_:)` with the old name forwarding. Engine call sites move to the new names: `Request+ContainerLoad.swift` (`memoizedAuthorizations`, the anchor filter at 134-138, `holdsAuthorization`). Test fixtures (`Tests/FOSMVVMVaporTests/Containment/ContainmentFixtures.swift` and the grant fixtures beside it) adopt the new names; one fixture keeps the old names to prove the deprecated path behaves as before.

**D3. `ContainmentScope` and `LoadingPlan`.** `Sources/FOSMVVM/Protocols/RootScope.swift` becomes `ContainmentScope.swift`: the flat enum. `DataRequirement.swift` becomes `LoadingPlan.swift`: `LoadingPlan<Model>`, `Model.loadingPlan(_:within:via:)` taking a `ModelOperation`, `Model.creationPlan(within:)`, the `LoadingPlans` result builder, and `ComposableFactory.loadingPlans` replacing `dataRequirements`; `LoadRequirement`, `DataRequirement`, and the `in:`/`rootedAt:` forms stay one release, deprecated and mapped; `ComposedChild.child` gains `within:`; `RootedQuery` becomes `ScopedQuery` with a deprecated typealias; `useApexContainerResolver` becomes `useApplicationScope` with a deprecated forwarder, and `duplicateApexContainerResolver` becomes `duplicateApplicationScope`. `Sources/FOSMVVM/RecordLoadPlan.swift`: the tuple's scope type follows. `Sources/FOSMVVMVapor/Containment/PlanRegistration.swift`: `resolveHops` accepts `.subject` when the first type is registered (self or containment); `requireRootBindings` needs no binding for it; `creationPlan(within: .subject)` and a `.anyOperation` loading plan each throw `invalidLoadPlan` at registration. Tests in `Tests/FOSMVVMVaporTests/Composition/PlanRegistrationTests.swift`.

**D4. The subject-scope query in the engine.** DONE `edb3201` (shipped form: one member-id query per relation reaching the type, then ONE refined load and ONE count — not the single disjunctive statement drafted below; sibling pivot joins do not disjunct cleanly. Review round 2026-09-30: a granted system container now makes the reach the whole type (`SubjectReach.everyModel`, `ContainmentRelation.reachesWholeType`), so no id list is built for `.all`.) `Request+ContainerLoad.swift` gains `authorizedModels(ofType:for:sortedBy:pagination:filter:)`, the subject-scope twin of `authorizedRecords(of:containing:...)`: filter the memoized grants into the named-id list (grants whose `authorizedModel` is of the type and whose model operations cover the mapped `ModelOperation`) and the granted-container list (grants whose `authorizedModel` is a registered container declaring the type and whose member operations cover the `ContainerOperation`), note whether any granted static container lists the type, build one query with the disjunctive predicate over id, owner keys per `.children` relation, pivot join per `.siblings` relation, or all rows, apply `ContainmentQueryRefinement`, run once, cache under a subject-scope key, and answer the count twin the same way. Tests beside the engine's existing ones in `Tests/FOSMVVMVaporTests/Containment/`: named-only, extended-only, both, the deny default yielding only the extended set, refinement and total across the union, and one query observed per call.

**D5. Binding the subject scope.** DONE `37d0588` (2026-09-30; binding form corrected in 1.10: per tuple). `Sources/FOSMVVMVapor/Containment/PlanExecutor.swift`: for a `.subject` tuple the first level runs D4's one query and its rows become the bound set; `rootIdentities` becomes set-valued for `.subject` (decide the one-type-change form or the second field here); `load` seeds one `via:` branch per returned row, deduplicating by identity; `verifyRootContainment` is satisfied by construction for the first level and checks each row as the container of the next hop; `touchedContainers` registers each returned identity and the subject identity when vended; the registration-count warning past a threshold beside `maxRecordsWarningThreshold`. Tests in `Tests/FOSMVVMVaporTests/Composition/PlanExecutorTests.swift` and `ProjectionContextTests.swift`: the union, the empty-grant subject, refinement of the union, `via:` from the bound set anchored per root, registrations including every root and the subject.

**D6. The write route.** DONE (2026-09-30; plus the subject-cache drop from the 1.10 D6 note). `Sources/FOSMVVMVapor/Containment/WriteRoute.swift`: `loadCandidates` and `resolveWriteTarget` accept a set-valued candidate root; `commitCreate` keeps its one-container rule and is unreachable within the subject scope by D3. Tests in `Tests/FOSMVVMVaporTests/Containment/` beside the write fixtures: an update, an archive, and a destroy whose candidate set is within the subject scope accept a target reachable by either authority and reject one reachable by neither.

**D7. Live.** DONE (2026-09-30; tests only, as planned). `Sources/FOSMVVMVapor/LiveInvalidation/`: nothing new to emit; the registration side is D5. Tests in `Tests/FOSMVVMVaporTests/LiveInvalidation/RegistrationHeaderTests.swift`: a response within the subject scope registers its bound identities and the subject; with the grant model declared `.children(\User.$grants)` on the subject fixture, a grant write emits the subject's identity.

**D8. Documents.** DONE (2026-09-30; plugin 2.76.0; audit 0 stale / 0 branch gaps; three pre-existing gaps on main — `testHostRequest`, `CredentialChallenge`, `ProductionParents` — reported, not touched). DocC per Part 4 on every new and renamed symbol. `.claude/docs/FOSMVVMArchitecture.md` gains the two-axis model (1.1) and the union rule (1.6). `.claude/skills/shared/api-catalog/FOSMVVM.md` and `FOSMVVMVapor.md` through the catalog-update skill: the grant family, `ContainmentScope`, the subject identity. `fosmvvm-review` checks and any skill naming `ContainerAuthorization` move to the new names; plugin version bump. CHANGELOG under Unreleased: Added for the axis and the root, Changed for the renames with their deprecations. The bootstrap client-server template's grant provider, if it conforms, adopts the new names (skeletons prove it against the checkout).

### 6.2 Work item B — the system container (`feat/system-container`)

**B1. `SystemContainer`.** DONE (2026-09-30, `feat/system-container`). New file `Sources/FOSMVVMVapor/Containment/SystemContainer.swift`: the protocol (`containment`, `authorityFlow` with the `.inherits` default) and `identity`, minted from `ModelNamespace(for:)` and a constant id part pinned by an internal comment and test. Tests in `Tests/FOSMVVMVaporTests/Containment/`: equal across calls, unequal across types, round-trips through `toJSON().fromJSON()`.

**B2. `ContainmentRelation.all(_:)`.** DONE (2026-09-30, `feat/system-container`). `Sources/FOSMVVMVapor/Containment/ContainmentRelation.swift`: the factory beside `children`, `siblings`, `parent`; load runs `To.query(on:)` with the refinement, count runs `.count()`, create saves with no join, invert attributes every mutated `To` to the owning system container's identity; `containerType` widens to carry a non-`DataModel` owner. Tests: each closure against a registered system container.

**B3. Registration.** DONE (2026-09-30, `feat/system-container`). `Sources/FOSMVVMVapor/Containment/ModelTypeRegistry.swift`: a third `RegisteredModel` init for a tableless container (`isContainer` true, no `find`, a flag the engine and `ContainmentRelation.swift:325` guard on). `Application+Containment.swift`: `register(_:)` overload with the drift check, the all-relations-are-`.all` check, and the duplicate-namespace check; the lifecycle sweep (`Lifecycle/Application+DataModelLifecycle.swift:31`) and the emit sweep (`Extensions/Application+LiveInvalidation.swift:66`) skip a tableless entry. `Request+ContainerLoad.swift:128` skips the find for it. Tests: boot refusals, a load through the system container, doctor-clean walking skeleton unaffected.

**B4. The application-scope default.** DONE (2026-09-30, `feat/system-container`). `PlanRegistration.requireRootBindings` and `PlanExecutor.resolveRecordLoadPlan`: with no `useApplicationScope` and exactly one system container registered, the application scope binds to its identity; a registered `useApplicationScope` wins; two system containers and nothing registered is the existing error. Tests in `PlanRegistrationTests.swift` and `PlanExecutorTests.swift`.

**B5. Together.** DONE (2026-09-30, `feat/system-container`). Tests that pair the two work items: a read of Workspaces within the subject scope includes the members of the system container's `.all(Workspace.self)` through a grant on `Suite.identity`; a create of a Workspace at `within: .application` persists with no join; creating, archiving, and destroying a Workspace each emit `Suite.identity` as stale.

**B6. Documents.** DONE (2026-09-30, `feat/system-container`). DocC per Part 4 for the four B symbols. Architecture doc: the container with no table and create at the top. Catalog entries. The `fosmvvm-fluent-datamodel-generator` skill learns to declare an ownerless model under a system container instead of a synthetic parent; plugin version bump. CHANGELOG Added.

### 6.3 After both

Implementer notes from the build (2026-09-30): the relation closures take an optional container (`nil` = a system container; row relations throw on it); `containerType` is `Any.Type?`, `nil` for an `.all` relation until `register(_:)` binds it to its owner through `bound(to:owner:)`, which is also where `invert` learns the owner's identity; `RegisteredModel` gained `isTableless` + `identity`, and `modelType` became optional (the two sweeps skip `nil`); `ModelIdentity.init(namespace:id:)` is `package` — the server's second minting seam; the owned-types check runs at request registration (`requireSystemContainerMembersRegistered`), not at `register(_:)`, because registration order is the app's; `SystemContainer` has no `containedRecordTypes`, so there is no drift check for it (one declaration). Two new `ContainmentError` cases refuse `.all` on a container with rows and a row relation on a system container; a third names an unregistered owned type.

The consuming project's overview factory declares its top-level containers at `within: .subject` and its status models under its system container at `within: .application`; its `SupplementalRecordLoading` conformances and its synthetic root table are deleted. That acceptance is the work item's done condition (Goal, work item).
