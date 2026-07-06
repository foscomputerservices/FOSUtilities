# Layer 1 · C4 — Fluent Containment & the Injected Type Registry (Design Spec)

**Status:** Reviewed — spec-document + FOSMVVM-discipline reviewers (2026-07-03), no blockers; fixes
folded in (see §Review reconciliation).
**Date:** 2026-07-03
**Layer:** 1, component **C4** of `2026-07-03-authorized-container-data-loading-architecture.md`.
**Targets:** FOSMVVMVapor (primary; Fluent-coupled). **One small FOSMVVM addition** (`package` visibility on `ModelIdentity`'s stored parts).
**Depends on:** L0 (`ModelIdentity`, `ModelNamespace` — implemented) + C1 (`Container` — implemented).
**Blocks:** C6 (load engine), C8 (factory). C3 proceeds in parallel (arch §6, build-order item 4).

**Component shorthand** — the L1 architecture doc (`…authorized-container-data-loading-architecture.md`, §5)
splits the system into components; this spec is **C4**. (There's no standalone **C5** — the injected type
registry was folded into C4, so it lives right here.) The ones referenced here:

| | | |
|---|---|---|
| **C1** Container + `ContainerOperation` vocabulary *(shipped)* | **C2** Query·Sort·Pagination on the request *(shipped)* | **C3** authorization model (who may access which container) |
| **C4** *(this spec)* Fluent containment + type registry | **C6** the authorized load engine (**C6a** = sort→KeyPath mapping) | **C7** composition / data-requirements aggregation |
| **C8** unified server-hosted factory (+ post-write refresh) | **C9** live invalidation (Layer 2) | |

> **The problem C4 solves** — the *bridge from the sealed-identity world back to concrete Fluent*. The
> framework operates over `ModelIdentity`: a sealed, **non-generic** `(namespace, id)` token that carries
> no Swift type. When the server must load "the Berths of Dock #5" from a stored/authorized container
> reference, it holds `ModelIdentity(namespace: "Dock", id: …)` — **not `Dock.self` and not the
> `\.$berths` KeyPath**, so it cannot write `dock.$berths.query(on: db)`. C4 supplies the two things that
> close that gap: (1) an injected **registry** that recovers `Dock.self` (and its containment) from the
> namespace, and (2) a **containment declaration** captured where the concrete types are still in scope,
> vending a type-erased load the generic engine can invoke. This is centralized framework infrastructure
> — not ad-hoc app Fluent calls — because the resulting load is the single, non-bypassable authorization
> boundary (C3) reused identically by the read projection, the post-write refresh, and the L2 live path.

Gated through `fosmvvm-planning` (design → customer-DocC → contract tests); rationale in §"Design rationale".

## The type-erased flow (what C4 makes possible)

The framework starts with nothing but an opaque token and must reach a concrete, authorized Fluent query.
Each step, top to bottom:

1. **Start** — a stored/authorized `ModelIdentity(namespace, id)`. Type-erased: no Swift type in hand.
2. **Recover the type** — `registry.registered(for: namespace)` returns a `RegisteredModel` descriptor
   (captured at registration, where `Dock` was still concrete). *(`ModelTypeRegistry`: injected, server-only.)*
3. **Fetch the container** — `descriptor.find(id, on: db)` returns the container instance as
   `any DataModel` (e.g. `Dock #5`) — now *fetched*, so its Fluent relationship `idValue` is populated.
4. **Load members** — for each `ContainmentRelation` in `descriptor.containment`, call
   `rel.members(of: container, on: db)`, which runs Fluent's own relationship query
   (`.children` / `.siblings` / `.parent`).
5. **Result** — `[any DataModel]`: the contained records.
6. **C6 takes over** — auth-scoping, filter, sort, and pagination layer on top.

Steps **1–5 are C4**; step **6 is C6**. C4 never authorizes, filters, sorts, or paginates — it proves the
generic, type-erased path reaches concrete Fluent and hands C6 the primitives.

## Scope (what ships in this spec)

1. **`ModelIdentity` — `package` visibility on the stored parts** (FOSMVVM): the existing
   `private let namespace` / `private let id` stored properties become `package let`. No new API, no
   extension, no rename — FOSMVVMVapor reads `identity.namespace` / `identity.id` to drive the registry
   lookup + find. Client-facing opacity is unchanged (still no `public` getter).
2. **`ContainmentRelation`** (FOSMVVMVapor) — a type-erased value over one typed Fluent relationship,
   built via `.children` / `.siblings` / `.parent` factories, vending the contained type + a member load.
3. **`ContainerDataModel`** (FOSMVVMVapor) — the Vapor container protocol carrying
   `static var containment: [ContainmentRelation]` (Fluent KeyPaths stay off the shared `Container`).
4. **`ModelTypeRegistry` + `RegisteredModel`** (FOSMVVMVapor, **`package`-level**) — the injected
   `ModelNamespace → RegisteredModel` map (server-only), and the erased per-model descriptor (find-by-id +
   containment). `package`, not `public`: every named consumer (C6 engine, C8 factory, DEF-7 guard,
   contract tests) is in-package, and promoting to `public` later is additive ("Defer API Until Client
   Exists"). Apps interact with the registry only through `app.register(_:migration:)`.
5. **Migration-as-registration** — one **throwing** `Application` call that adds a model's Fluent migration
   **and** registers its descriptor, so declaring the migration *is* the registration. It fail-fasts at
   boot (throws — idiomatic in Vapor's throwing `configure(_:)`) on: a **duplicate `ModelNamespace`**
   registration; a `containment` element whose **container type isn't the registered type**; and
   **containment↔`containedRecordTypes` drift** (arch §5 C4 invariant (a): the relations' contained types
   must equal the shared `Container.containedRecordTypes` — declared in two places across the boundary,
   they must not drift).
6. Contract tests for all of the above (against an in-memory SQLite Fluent test DB). **This is the repo's
   first Fluent test infrastructure**: adds the `fluent-sqlite-driver` dependency (test support) to
   `Package.swift` and establishes a reusable Fluent test-DB harness in `FOSTestingVapor` so C6/C3/C8
   inherit it, rather than a one-off in `Tests/FOSMVVMVaporTests`.

## Non-goals (explicitly deferred)

- **Auth-scoping, filter, sort, and pagination push-down** → **C6** (the load engine). C4's `members(of:on:)`
  is the *unrefined* containment load; C6 wraps it with the authorization boundary and composes the C1+C2
  vocabulary onto the relationship's `QueryBuilder`. C4 deliberately does not expose a "load everything"
  public convenience that bypasses C6's auth.
- **The `SortKey → [KeyPath]` mapping (C6a)** — sort resolution needs the contained type's KeyPaths and
  belongs with C6.
- **A generating macro** for `containment` (auto-listing a container's relationships) — a later ergonomic;
  v1 declares `containment` by hand. (It would also need a per-relationship "is containment" marker, since
  not every relationship is authorization-bearing.)
- **Optional / composite relationship variants.** v1 factories cover Fluent's required
  `@Children` / `@Siblings` / `@Parent`. `@OptionalChild` / `@OptionalParent` / `Composite*` properties
  cannot be declared as containment yet — additional factories are purely additive when a consuming
  container needs one ("Defer API Until Client Exists").
- **DEF-7** (fail-fast guard that every persisted-identity `Model` overrode the reflection-default
  namespace) — its own build-order item (arch §6 item 7); it rides on C4's registry but does not ship here.
- **L2** emit/dispatch; **C3** authorization records.

## Types & placement

FOSMVVMVapor for everything Fluent-coupled; the one FOSMVVM change is the `package` visibility. The registry
is injected into the Vapor `Application` (and read per-`Request`) via the existing `StorageKey` +
`LifecycleHandler` idiom already used for `localizationStore` / `mvvmEnvironment`.

### C4.1 `ModelIdentity` package visibility (`FOSMVVM/Protocols/ModelIdentity.swift`)

L0 sealed `ModelIdentity` so **no `public` API exposes its contents** — that guarantee is for *clients*.
The server legitimately must read a stored identity's parts to look up the type and fetch the row. Since
FOSMVVM and FOSMVVMVapor are one Swift package, **promoting the existing stored properties to `package`**
gives server code access without reopening the client surface, adding no new API:

```swift
public struct ModelIdentity: Hashable, Codable, Sendable {
    // `package`, NOT public — server-side targets read these to drive the ModelTypeRegistry lookup +
    // Fluent find; clients still cannot read identity contents (opacity is a public-surface guarantee, L0).
    package let namespace: ModelNamespace
    package let id: ModelIdType
    // …unchanged…
}
```

*(No DocC: `package` API isn't a customer surface. The `//` note states why it exists and that it is not
`public`.)* Be precise about breadth: `package` is visible to **every target in this Swift package** —
including client-linked ones (FOSMVVM itself, FOSTesting, FOSTestingUI) — but to **no consuming app**, so
the L0 client-opacity guarantee holds. The accompanying review invariant: outside `ModelIdentity.swift`,
only server-only targets (FOSMVVMVapor, FOSTestingVapor) and server-side tests reference `.namespace` /
`.id` on an identity (grep-checked at review).

### C4.2 `ContainmentRelation` (`FOSMVVMVapor/Containment/ContainmentRelation.swift`)

**Customer DocC (drafted first):**

```swift
/// One authorization-bearing containment relationship of a container, declared from a Fluent relationship.
///
/// Build these from your `@Children` / `@Siblings` / `@Parent` relationships — the framework reads the
/// join off Fluent, so you never restate a foreign key or pivot table:
///
/// ```swift
/// extension Dock: ContainerDataModel {
///     static var containment: [ContainmentRelation] {
///         [.children(\Dock.$berths), .siblings(\Dock.$crew)]   // Dock owns Berths (FK) and Crew (pivot)
///     }
/// }
/// ```
///
/// List only the relationships that a subject can be *authorized to* — not every Fluent relationship is
/// containment.
public struct ContainmentRelation: Sendable {
    // Erased types, `package`: consumed by the register-time checks + C6, not by app code.
    // NOTE: `DataModel`, not a bare `Model` — FOSMVVMVapor sees both `FOSMVVM.Model` and
    // `FluentKit.Model`, and C6 needs the Fluent query capability. `any DataModel` throughout.
    package let containerType: any DataModel.Type   // == From.self, captured by the factory
    package let containedType: any DataModel.Type   // == To.self, captured by the factory

    /// A to-many child relationship (child table holds the foreign key back to the container).
    public static func children<From, To>(_ keyPath: KeyPath<From, ChildrenProperty<From, To>>)
        -> ContainmentRelation where From: DataModel, To: DataModel
    /// A to-many sibling relationship joined through a pivot table.
    public static func siblings<From, To, Through>(_ keyPath: KeyPath<From, SiblingsProperty<From, To, Through>>)
        -> ContainmentRelation where From: DataModel, To: DataModel, Through: DataModel
    /// A to-one parent relationship (this container's record references the parent by foreign key).
    public static func parent<From, To>(_ keyPath: KeyPath<From, ParentProperty<From, To>>)
        -> ContainmentRelation where From: DataModel, To: DataModel
}
```

Internally each factory captures the concrete `From`/`To`(/`Through`) and closes over the relationship's
own `query(on:)`; the erased member load (consumed by C6, see below) casts the passed container to `From`
and runs `container[keyPath: keyPath].query(on: db).all()`. Fluent computes the FK / pivot join — C4 never
touches a column name. The factories' free `From` generic is what register-time checking pins down: nothing
at *construction* ties `From` to the declaring container (`extension Dock { …[.children(\Ship.$berths)]… }`
compiles), so `register(_:migration:)` asserts every relation's `containerType` **is** the registered type
(boot-time fail-fast, see C4.5).

*Implementation note for the plan:* `ContainmentRelation: Sendable` holds closures over `KeyPath`s, which
are not unconditionally `Sendable` under Swift 6 strict concurrency. Resolve it at the factory, where
`From`/`To` are concrete (e.g. a `@Sendable` closure capturing the key path once) — do **not** reach for
`@unchecked Sendable` reflexively.

**The load primitive (consumed by C6, not a public "load-all" convenience):**

```swift
package extension ContainmentRelation {
    // The UNREFINED, UNAUTHORIZED containment load. C6 is the authorized entry point that wraps this and
    // composes filter/sort/pagination onto the query. `package` so only in-package engine code calls it.
    // For `.parent` (to-one) the result is a single-element array.
    package func members(of container: any DataModel, on db: any Database) async throws -> [any DataModel]
}
```

If the cast of `container` to the captured `From` fails, `members` **throws a typed error**
(`ContainmentError.containerTypeMismatch`) — it never silently returns `[]`, which downstream would be
indistinguishable from "not authorized" at the C6 authorization boundary. In a correctly registered app
this is unreachable (C4.5's boot-time check), so the throw is a framework-invariant backstop, not a path
apps handle.

### C4.3 `ContainerDataModel` (`FOSMVVMVapor/Containment/ContainerDataModel.swift`)

```swift
/// A Fluent-backed ``Container`` that declares which of its relationships are authorization-bearing
/// containment.
///
/// ```swift
/// final class Dock: ContainerDataModel {
///     static var containment: [ContainmentRelation] { [.children(\Dock.$berths), .siblings(\Dock.$crew)] }
///     // ...Fluent + Container members...
/// }
/// ```
public protocol ContainerDataModel: DataModel, Container where IDValue == ModelIdType {
    static var containment: [ContainmentRelation] { get }
}
```

Two deliberate constraints:

- **No `[]` default for `containment`.** A defaulted static requirement is a silent-witness trap (a
  misspelled `containments` compiles and yields the empty default), and unlike shared `Container` — where
  "owns nothing" is meaningful — a `ContainerDataModel` with no containment has no reason to exist.
  Name-the-requirement: conformers declare it. (C4.5's drift check would also catch the empty-vs-declared
  mismatch at boot, but the compiler catching it is better.)
- **`where IDValue == ModelIdType`.** `RegisteredModel.find` must call Fluent's `find(_:on:)`, which takes
  the model's `IDValue`; `DataModel` doesn't constrain it. Pinning it on the protocol (rather than a
  `where` clause on `register`) states the project rule — `@ID` is `ModelIdType` — once, where conformers
  see it.

### C4.4 `ModelTypeRegistry` + `RegisteredModel` (`FOSMVVMVapor/Containment/ModelTypeRegistry.swift`)

**`package`-level — not a customer surface.** The registry is configured as a side effect of
`app.register(_:migration:)` and read only by in-package engine code; no DocC, `//` notes only:

```swift
// Recovers a persisted ModelIdentity's Swift model type (and its containment) on the server.
// Populated as a side effect of Application.register(_:migration:); injected into Application/Request.
// `package`: every current consumer (C6 engine, C8 factory, DEF-7 guard, contract tests) is in-package —
// promote to `public` only when an app-side consumer appears (additive).
package struct ModelTypeRegistry: Sendable {
    // The descriptor registered for a namespace, or nil if none is registered.
    package func registered(for namespace: ModelNamespace) -> RegisteredModel?
}

// A type-erased handle to a registered model — recover an instance by id, and read its containment.
package struct RegisteredModel: Sendable {
    package let namespace: ModelNamespace
    package let containment: [ContainmentRelation]
    // Fetch the instance for this identity's id — the engine's recover step.
    package func find(_ id: ModelIdType, on db: any Database) async throws -> (any DataModel)?
}
```

- **Injected, not global** (defeats the process-global anti-pattern; preserves parallel-test isolation).
  `Application.modelTypeRegistry` and `Request.modelTypeRegistry` (both **`package`**; backed by a private
  `StorageKey`, populated at boot; the `Request` one reads the application's) — mirroring
  `localizationStore` / `mvvmEnvironment`. With `find`/`members` already `package`, a `public` registry
  read would be harmless — but it has no consumer, so it doesn't ship ("Defer API Until Client Exists").
- **Naming:** `ModelTypeRegistry` — deliberately distinct from the existing *internal* localization
  `ModelRegistry`.

### C4.5 Migration-as-registration (`FOSMVVMVapor/Extensions/Application+Containment.swift`)

```swift
public extension Application {
    /// Register a container model: adds its Fluent migration **and** its identity descriptor in one call,
    /// so declaring the migration *is* registering the type — there is no separate step to forget.
    ///
    /// ```swift
    /// // in configure(_:)
    /// try app.register(Dock.self, migration: Dock.CreateDock())
    /// ```
    ///
    /// - Throws: if the model's namespace is already registered, or its `containment` doesn't match
    ///   its `containedRecordTypes` — a misconfiguration caught at boot, not at first request.
    func register(_ type: (some ContainerDataModel).Type, migration: any Migration) throws
}
```

Internally: `self.migrations.add(migration)` **+** insert a `RegisteredModel` (capturing `type`'s `find` +
`containment`) under `type.modelIdentityNamespace` into the injected `ModelTypeRegistry`.

**Boot-time fail-fast checks (throws `ContainmentError`; throwing beats `precondition` here — it is
idiomatic in Vapor's throwing `configure(_:)` and contract-testable without exit tests):**

1. **`.duplicateNamespace`** — the namespace is already registered (double `register`, or two model types
   whose namespaces collide). Silent last-writer-wins would corrupt the identity→type mapping that
   authorization keys on.
2. **`.containerTypeMismatch`** — some `containment` element's `containerType` isn't the registered type
   (the factory's free `From` generic allows `extension Dock { …[.children(\Ship.$berths)]… }` to compile;
   this is where it dies).
3. **`.containmentDrift`** — arch §5 C4 invariant (a): the set of `containment` contained types (by type
   identity, `ObjectIdentifier`) must **equal** the set of shared `Container.containedRecordTypes`. The
   same contract declared on both sides of the SPMLibraries boundary must not drift — including the
   "declared `containedRecordTypes`, forgot `containment`" direction.

## Testing (contract tests; Fluent test DB — SQLite in-memory)

**Net-new infrastructure:** the repo has no Fluent test support today (`Package.swift` depends on
`fluent-kit` but not `fluent-sqlite-driver`; `FOSTestingVapor` has no DB setup). C4 adds the
`fluent-sqlite-driver` dependency and a reusable in-memory Fluent test-DB harness in **`FOSTestingVapor`**
(migrate-seeded fixtures, per-test isolation) that C6/C3/C8 reuse. Mind the existing async-boot gotcha:
`app.test()` runs only sync `boot()`; lifecycle handlers need explicit async boot.

Behavior only — contractual obligations are tested through the APIs that carry them, never by opening
an implementation and asserting its internals' format (`package` API is itself a real contract for
in-package consumers; access levels are chosen by who legitimately consumes a symbol, never widened for
tests). No assertions on SQL text or column names.

1. **Registry round-trip** — after `try app.register(Dock.self, migration:)`, `registry.registered(for: Dock.modelIdentityNamespace)` returns a descriptor whose `containment` matches `Dock.containment` (assertion basis: element count + per-element `containedType` identity via `ObjectIdentifier` — `ContainmentRelation` is not `Equatable`); an unregistered namespace returns `nil`.
2. **`RegisteredModel.find`** — seeds a `Dock`, then `find(dockId, on: db)` returns that `Dock` (as `any DataModel`, equal by id); a missing id returns `nil`.
3. **`ContainmentRelation.children`** — seed a `Dock` with 3 `Berth`s (+ a Berth of another Dock); `.children(\Dock.$berths).members(of: dock, on: db)` returns exactly this dock's 3 Berths.
4. **`ContainmentRelation.siblings`** — seed a pivot many-to-many; `.siblings(\Dock.$crew).members(of:on:)` returns the joined records for this container only.
5. **`ContainmentRelation.parent`** — to-one returns a **single-element array** containing the parent record.
6. **End-to-end erased bridge** — starting from a `ModelIdentity` (via the `package` stored parts for id/namespace) → `registry` → `find` → each `containment` → members; asserts the contained records load **without naming `Dock`/`Berth` at the call site** (proves the type-erased path). This is the test that demonstrates the whole picture.
7. **`package` opacity** — `ModelIdentity` still exposes **no `public`** namespace/id getter (review invariant; the stored parts are `package`).
8. **Duplicate registration fail-fast** — a second `register` of the same type (and a second type sharing the namespace) throws `.duplicateNamespace`; the first registration is unchanged.
9. **Container-type mismatch fail-fast** — registering a type whose `containment` includes a relation built from another container's KeyPath throws `.containerTypeMismatch`.
10. **Containment drift fail-fast** — registering a type whose `containment` contained types ≠ its `containedRecordTypes` (either direction: extra, missing, or empty-vs-declared) throws `.containmentDrift`; a matching declaration registers cleanly.

## Risks & mitigations

- **`ContainmentRelation.members` requires the container fetched** (relationship `idValue` populated, else Fluent `fatalError`s). Mitigation: the engine always obtains the container via `RegisteredModel.find` (a fetched instance) before calling `members`; document the precondition; tests exercise the fetched path.
- **Type-erased casts** (`container as? From`) fail if the registry/containment are mismatched. Mitigation: construction alone can't prevent it (the factory's `From` is a free generic), so `register(_:migration:)` fail-fasts at boot on any relation whose `containerType` isn't the registered type, and `members` throws `.containerTypeMismatch` as the runtime backstop — never a silent `[]`.
- **Registry population depends on the app calling `register(_:migration:)`.** Mitigation: it is the *same* call that adds the migration, so a persisted model that runs its migration is registered by construction. (The broader reflection-default-namespace guard is DEF-7 — explicitly out of scope, see Non-goals.)
- **`package` breadth on `ModelIdentity`'s stored parts.** `package` exposes them to *all* targets of this Swift package — including client-linked ones — though never to consuming apps. Mitigation: client opacity is a public-surface guarantee and holds; the review invariant (C4.1) confines actual references to server-only targets.

## Definition of done

- New API compiles across FOSMVVMVapor (+ the FOSMVVM `package` visibility change); `swift build`/`swift test` green on macOS/Linux; `swiftformat`/`swiftlint` clean.
- All 10 test groups pass against a real Fluent (SQLite) test DB — including the end-to-end erased-bridge test and the three boot-time fail-fast groups.
- `ModelIdentity` exposes no `public` namespace/id getter (opacity review invariant holds; the stored parts are `package`), and outside `ModelIdentity.swift` only server-only targets reference them (grep).
- Customer DocC with examples on every `public` symbol (`ContainmentRelation` + factories, `ContainerDataModel`, `Application.register`); `package` symbols (`ModelTypeRegistry`, `RegisteredModel`, `members`) carry `//` notes, not DocC.
- No Fluent type crosses onto shared `Container`/`Model`/`ServerRequest` (grep: FOSMVVM has no `import FluentKit`; the containment lives only in FOSMVVMVapor).
- `Package.swift` gains `fluent-sqlite-driver` for test support only (no production target depends on it); the Fluent test-DB harness lands in `FOSTestingVapor`.
- CHANGELOG entry drafted.

## Design rationale (why-this-way — kept out of the DocC)

- **Why a registry at all, when the request is statically typed.** Statically-typed read requests know
  their container type at compile time and wouldn't need it — but the *auth-driven* and *stored-reference*
  paths don't: authorization records store `authorizedContainer: ModelIdentity`, and loading what a stored
  reference points to means recovering the type from a bare namespace. The registry serves those
  type-erased paths (and L2's namespace routing). It's injected, never global — a process-global type
  service defeats parallel-test isolation and leaks shared state.
- **Why `package` visibility on `ModelIdentity`'s stored parts.** The identity is sealed so *clients*
  can't parse or forge it. The server, holding a stored identity, must read its namespace (to look up the
  type) and id (to fetch the row). `package` grants exactly the same-package access without a `public`
  crack; it mirrors the north star's deferral register (DEF-6), which anticipated that L2's Freshness
  producer would need broadened access. The client-surface opacity guarantee is untouched.
- **Why derive from Fluent's relationship query (not hand-built SQL).** Fluent already encodes the FK /
  pivot join; `ChildrenProperty.query(on:)` / `SiblingsProperty.query(on:)` are public and return a
  `QueryBuilder<To>`. Using them removes the hand-specified cardinality enum, the FK/pivot column
  extraction (which is *not* reachable through Fluent's type-erased `Relation` protocol — verified against
  FluentKit source), and the "re-sort to id order" wart. Blind runtime reflection can't read those keys for
  `@Children`/`@Siblings`, which is *why* the container hands us typed relationship KeyPaths — the factory
  captures the concrete generics so the erased load can run the concrete query.
- **Why `containment` is Vapor-side, not on shared `Container`.** The KeyPaths are Fluent types; putting
  them on `Container` (FOSMVVM) would drag Fluent across the SPMLibraries boundary (LSP/DIP violation).
  `ContainerDataModel` (a `DataModel & Container`) is the Fluent-side home.
- **Why the load primitive is `package`, not a public convenience.** Seam-invariant #1: the container load
  is the non-bypassable authorization boundary. A public "load all members" would let a caller bypass C6's
  auth. So `ContainmentRelation.members` and `RegisteredModel.find` are `package` — C6 is the public,
  authorized entry point.
- **Why cardinality is implicit.** Which factory built a relation (`.parent` vs `.children`/`.siblings`)
  *is* the cardinality; no hand-authored `.toOne`/`.toMany` enum, nothing to keep in sync with Fluent.
- **Why `register` throws instead of `precondition`ing.** The three boot checks are misconfiguration, and
  fail-fast is the requirement — but a thrown error surfaces in Vapor's already-throwing `configure(_:)`
  with a typed, testable diagnosis, where a `preconditionFailure` would need exit tests and take the whole
  process down in a way tests can't observe. Same fail-fast timing (boot), better error story.
- **Rejected:** hand-built member-id SQL (Option A — strictly more code, needs unreachable keys, keeps the
  re-sort wart); a process-global registry; a public unauthorized load; a `String`-keyed registry; a
  defaulted `containment` (silent-witness trap); a `public` registry surface with no consumer.

## Decisions (resolved with David, 2026-07-03)

- **D2 — registry name:** **`ModelTypeRegistry`** (confirmed).
- **D3 — registration call:** **`app.register(_:migration:)`** (confirmed).
- **D1 — the C6 refinement seam: DEFERRED to the C6 spec.** C4 ships only the unrefined `members(of:on:)`
  primitive. *How* C6 pushes filter/sort/pagination into the relationship query — C6 hands erased
  instructions to the contained-type-aware `ContainmentRelation` to apply — is a C6 design detail. C4 keeps
  the primitive `package` so C6 can extend/re-open it; nothing for C4 to decide.

## Review reconciliation (2026-07-03; spec-document + FOSMVVM-discipline reviewers)

Both reviewers: no blockers (Sound-with-fixes / Approve-with-fixes). Changes folded in above:

- **Boot-time fail-fast checks on `register` (both reviewers' top findings):** duplicate-namespace,
  container-type-mismatch (the factory's free `From` generic made "structurally impossible" an overclaim),
  and the arch's invariant (a) containment↔`containedRecordTypes` drift check that the draft had dropped.
  `members` throws `.containerTypeMismatch` rather than ever returning a silent `[]`. Test groups 8–10.
- **`any DataModel` throughout** the Vapor-side erased signatures (FOSMVVMVapor sees both `FOSMVVM.Model`
  and `FluentKit.Model`; the bare spelling was ambiguous and the choice is semantic).
- **Registry surface narrowed to `package`** ("Defer API Until Client Exists" — every consumer is
  in-package); `Application`/`Request.modelTypeRegistry` likewise `package`.
- **`containment` default `[]` dropped** (silent-witness trap; name-the-requirement) and
  **`where IDValue == ModelIdType`** added to `ContainerDataModel` (Fluent `find` needs it).
- **C4.1 restated as promoting the stored `private let`s to `package let`** (the draft's extension sketch
  self-recursed), with the `package`-breadth claim corrected (visible package-wide, not "server targets
  only") + a grep review invariant.
- **Test infra called out as net-new:** `fluent-sqlite-driver` dependency + reusable harness in
  `FOSTestingVapor`.
- Explicit non-goals added (optional/composite relationship factories; DEF-7 stays arch build-order
  item 7); DEF-6 pointer corrected to the north star's deferral register; `.parent` result shape and
  test-1 assertion basis pinned; "Blocks:" header aligned with the arch's build order (C3 parallel).

**Implementation finding (2026-07-04):** rootless key-path literals (`\.$berths`) do **not** compile in
`containment` declarations — the factory's free `From` generic gives the compiler no contextual root —
so the canonical spelling is explicit-root (`\Dock.$berths`). Examples above updated to match. (A
`Self`-rooted builder could restore the shorthand, but that's the rejected construction-time-constraint
alternative; the boot-time `register` check remains the misuse guard.)
