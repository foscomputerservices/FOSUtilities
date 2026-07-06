# L1 C4 — Fluent Containment & Injected Type Registry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the reviewed C4 spec — the type-erased bridge from a sealed `ModelIdentity` back to concrete Fluent: `ContainmentRelation`, `ContainerDataModel`, the injected `ModelTypeRegistry`, throwing migration-as-registration, plus the repo's first Fluent test harness.

**Architecture:** Everything Fluent-coupled lands in FOSMVVMVapor; the sole FOSMVVM change promotes `ModelIdentity`'s stored properties to `package let`. Type erasure is done by closure capture in the `.children`/`.siblings`/`.parent` factories (concrete generics captured where they're in scope — never `any` passed around on a public surface). `app.register(_:migration:)` throws three boot-time fail-fast `ContainmentError`s. The registry is `package`-level and injected via the existing `StorageKey` idiom.

**Tech Stack:** Swift 6 (strict concurrency), Vapor 4, FluentKit + vapor/fluent + fluent-sqlite-driver (in-memory SQLite for tests), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-07-03-container-cardinality-registry-design.md` — read it fully first; its DocC drafts, test groups (1–10), and §Review reconciliation are normative. The architecture doc is `docs/superpowers/specs/2026-07-03-authorized-container-data-loading-architecture.md` (§5 C4).

---

## Plan prose — rationale & gotchas (implementer-facing; keep OUT of DocC)

- **Why vapor/fluent is a new production dependency.** The spec's `self.migrations.add(migration)`, `app.databases`, `app.db`, and `autoMigrate()` all live in the **vapor/fluent** package (product `Fluent` — the Vapor↔FluentKit glue), not in `fluent-kit`, which the package already has. Real apps universally drive migrations through vapor/fluent, so `register` must integrate with *its* `Application.migrations` or registration wouldn't participate in `app.autoMigrate()`. Confined to FOSMVVMVapor/FOSTestingVapor (macOS/Linux). `fluent-sqlite-driver` stays test-support-only per the spec's DoD.
- **Swift 6 Sendability.** `ContainmentRelation` is `Sendable` and stores `@Sendable` closures. Bare `KeyPath` is not unconditionally Sendable — take the factory parameters as `KeyPath<…> & Sendable` (key-path *literals* satisfy this since SE-0418), never `@unchecked Sendable` on the relation. Fluent model fixtures follow Vapor's own template idiom (`final class … Model, @unchecked Sendable`) — that's the blessed Fluent pattern, fixtures only.
- **Metatype comparison** uses `ObjectIdentifier` (hashable, works on `Any.Type`) for both the container-type check and the drift-set comparison.
- **Diagnostic strings in `ContainmentError` payloads are fine.** `String(describing: type)` in an error message is diagnostics, not identity — nothing routes or compares on it. Identity stays `ModelNamespace`/`ObjectIdentifier`.
- **`members` precondition:** Fluent `fatalError`s if the container's relationship `idValue` is unpopulated. The engine always obtains containers via `RegisteredModel.find` (fetched). Tests must also use fetched instances (seed → `find`/query back → then `members`).
- **Test group 7 (opacity) is a review invariant, not a runtime test** — access levels aren't observable at runtime. It's enforced by grep in the final task (matching how L0 handled it) plus the fact that no existing L0 test changes.
- **Harness boot:** use `asyncBoot()`/`asyncShutdown()` (never sync `shutdown()`); async lifecycle handlers only run under async boot — see `VaporServerTestCase.swift`'s doc comment and the repo's known gotcha.
- **Migration order matters** (FK dependencies): configure migrations parents-first (Pier → Dock → Berth/CrewMember → pivot).
- **Rejected here** (already settled in the spec — do not relitigate): cardinality enum, public unauthorized load, `String`-keyed registry, defaulted `containment`, public registry surface, `precondition` instead of `throws` in `register`.

## File structure

| File | Responsibility |
|---|---|
| `Package.swift` (modify) | + vapor/fluent, fluent-sqlite-driver deps; products onto targets |
| `Sources/FOSMVVM/Protocols/ModelIdentity.swift` (modify) | `private let` → `package let` on `namespace`/`id` |
| `Sources/FOSMVVMVapor/Containment/ContainmentError.swift` (create) | `package` boot-check + cast-backstop error, diagnostic descriptions |
| `Sources/FOSMVVMVapor/Containment/ContainmentRelation.swift` (create) | Erased relationship value + 3 public factories + `package members` |
| `Sources/FOSMVVMVapor/Containment/ContainerDataModel.swift` (create) | `DataModel & Container where IDValue == ModelIdType` + `containment` requirement (NO default) |
| `Sources/FOSMVVMVapor/Containment/ModelTypeRegistry.swift` (create) | `package` registry + `RegisteredModel` descriptor |
| `Sources/FOSMVVMVapor/Extensions/Application+Containment.swift` (create) | `register(_:migration:)` + 3 checks; `package` Application/Request accessors; private StorageKey |
| `Sources/FOSTestingVapor/FluentTestHarness.swift` (create) | `withFluentTestApp` — in-memory SQLite + lifecycle scoping |
| `Tests/FOSMVVMVaporTests/Containment/ContainmentFixtures.swift` (create) | Pier/Dock/Berth/CrewMember/DockCrew models + migrations |
| `Tests/FOSMVVMVaporTests/Containment/FluentTestHarnessTests.swift` (create) | Harness smoke test |
| `Tests/FOSMVVMVaporTests/Containment/ContainmentRelationTests.swift` (create) | Spec test groups 3, 4, 5 + cast-mismatch throw |
| `Tests/FOSMVVMVaporTests/Containment/ModelTypeRegistryTests.swift` (create) | Spec test groups 1, 2, 8, 9, 10 |
| `Tests/FOSMVVMVaporTests/Containment/ErasedBridgeTests.swift` (create) | Spec test group 6 (end-to-end) |
| `CHANGELOG.md` (modify) | C4 entry |

All new Vapor-side source compiles only where the target exists (macOS/Linux); FOSTestingVapor files keep the existing `#if canImport(FOSMVVMVapor)` guard idiom.

---

### Task 1: Package dependencies

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Add packages + products**

In the `#if os(macOS) || os(Linux)` dependency block (after the `fluent-kit` line, `Package.swift:79`):

```swift
result.append(.package(url: "https://github.com/vapor/fluent.git", .upToNextMajor(from: "4.12.0")))
result.append(.package(url: "https://github.com/vapor/fluent-sqlite-driver.git", .upToNextMajor(from: "4.8.0")))
```

Target changes (same file):
- `FOSMVVMVapor` deps: add `.product(name: "Fluent", package: "fluent", condition: .when(platforms: [.macOS, .linux]))`
- `FOSTestingVapor` deps: add `.product(name: "Fluent", package: "fluent")` and `.product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver")`
- `FOSMVVMVaporTests` deps: add `.product(name: "FluentKit", package: "fluent-kit")` and `.product(name: "Fluent", package: "fluent")` (fixtures declare Fluent models; tests add migrations via `app.migrations`)

- [ ] **Step 2: Verify resolution + build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!` (new checkouts `fluent`, `fluent-sqlite-driver`, `sqlite-kit`, `sqlite-nio` resolve; no version conflicts against fluent-kit 1.52.2 / vapor 4.119).

- [ ] **Step 3: Commit**

```bash
git add Package.swift Package.resolved
git commit -m "build: add vapor/fluent + fluent-sqlite-driver for C4 containment"
```

---

### Task 2: FOSTestingVapor Fluent test harness

**Files:**
- Create: `Sources/FOSTestingVapor/FluentTestHarness.swift`
- Test: `Tests/FOSMVVMVaporTests/Containment/FluentTestHarnessTests.swift`

- [ ] **Step 1: Write the failing smoke test**

`Tests/FOSMVVMVaporTests/Containment/FluentTestHarnessTests.swift` (license header via swiftformat later; Swift Testing):

```swift
import Fluent // app.migrations lives in vapor/fluent, not FluentKit
import FluentKit
import FOSTestingVapor
import Foundation
import Testing

@Suite("Fluent test harness")
struct FluentTestHarnessTests {
    @Test func migratesSeedsAndQueries() async throws {
        let count = try await withFluentTestApp { app in
            app.migrations.add(CreateSmokeRecord())
        } _: { _, db in
            try await SmokeRecord(label: "hello").save(on: db)
            return try await SmokeRecord.query(on: db).count()
        }
        #expect(count == 1)
    }

    @Test func eachCallGetsAFreshDatabase() async throws {
        // Runs the same seed twice; the second call must not see the first call's row.
        for _ in 0..<2 {
            let count = try await withFluentTestApp { app in
                app.migrations.add(CreateSmokeRecord())
            } _: { _, db in
                try await SmokeRecord(label: "solo").save(on: db)
                return try await SmokeRecord.query(on: db).count()
            }
            #expect(count == 1)
        }
    }
}

// Minimal local fixture — the containment fixtures arrive in Task 3.
final class SmokeRecord: FluentKit.Model, @unchecked Sendable {
    static let schema = "smoke_records"
    @ID(key: .id) var id: UUID?
    @Field(key: "label") var label: String
    init() {}
    init(label: String) { self.label = label }
}

struct CreateSmokeRecord: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(SmokeRecord.schema).id().field("label", .string, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(SmokeRecord.schema).delete()
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter FluentTestHarnessTests 2>&1 | tail -5`
Expected: FAIL to compile — `cannot find 'withFluentTestApp' in scope`.

- [ ] **Step 3: Implement the harness**

`Sources/FOSTestingVapor/FluentTestHarness.swift`:

```swift
#if canImport(FOSMVVMVapor)
import Fluent
import FluentKit
import FluentSQLiteDriver
import Vapor

/// Runs `body` against a booted Vapor application backed by a fresh in-memory SQLite database.
///
/// Configure the application in `configure` — register containers, add migrations — then use the
/// application and database handed to `body`. The harness runs the migrations, boots, and always
/// shuts the application down:
///
/// ```swift
/// let berths = try await withFluentTestApp { app in
///     try app.register(Dock.self, migration: CreateDock())
///     app.migrations.add(CreateBerth())
/// } _: { app, db in
///     try await Dock(name: "5").save(on: db)
///     return try await Berth.query(on: db).all()
/// }
/// ```
///
/// Each call owns a private database and a full application lifecycle, so tests stay isolated and
/// run safely in parallel.
public func withFluentTestApp<R: Sendable>(
    configure: @Sendable (Application) async throws -> Void,
    _ body: @Sendable (Application, any Database) async throws -> R
) async throws -> R {
    let app = try await Application.make(.testing)
    do {
        app.databases.use(.sqlite(.memory), as: .sqlite)
        try await configure(app)
        try await app.autoMigrate()
        // asyncBoot, not startup()/boot(): async lifecycle handlers only run under async boot,
        // and startup()'s console parser chokes on test-runner arguments (see VaporServerTestCase).
        try await app.asyncBoot()
        let result = try await body(app, app.db)
        try await app.asyncShutdown()
        return result
    } catch {
        try? await app.asyncShutdown()
        throw error
    }
}
#endif
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter FluentTestHarnessTests 2>&1 | tail -5`
Expected: 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/FOSTestingVapor/FluentTestHarness.swift Tests/FOSMVVMVaporTests/Containment/FluentTestHarnessTests.swift
git commit -m "feat(FOSTestingVapor): add withFluentTestApp in-memory SQLite test harness"
```

---

### Task 3: Containment test fixtures

**Files:**
- Create: `Tests/FOSMVVMVaporTests/Containment/ContainmentFixtures.swift`

The fixture graph exercises all three factories: `Pier ←@Parent– Dock –@Children→ Berth` and `Dock –@Siblings(DockCrew)→ CrewMember`. Plain `DataModel` conformance now; `ContainerDataModel` conformance is added in Task 5 (the protocol doesn't exist yet).

- [ ] **Step 1: Write the fixtures + a round-trip test**

`Tests/FOSMVVMVaporTests/Containment/ContainmentFixtures.swift`:

```swift
import Fluent // app.migrations (addHarborMigrations) lives in vapor/fluent
import FluentKit
import FOSFoundation
import FOSMVVM
import FOSMVVMVapor
import Foundation
import Vapor

// Fluent fixtures follow Vapor's template idiom (final class + @unchecked Sendable).
// validate(fields:validations:) returns nil — fixtures carry no form contract.

final class Pier: DataModel, @unchecked Sendable {
    static let schema = "piers"
    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    init() {}
    init(name: String) { self.name = name }
    func validate(fields: [any FormFieldBase]?, validations: Validations) -> ValidationResult.Status? { nil }
}

final class Dock: DataModel, @unchecked Sendable {
    static let schema = "docks"
    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Parent(key: "pier_id") var pier: Pier
    @Children(for: \.$dock) var berths: [Berth]
    @Siblings(through: DockCrew.self, from: \.$dock, to: \.$crewMember) var crew: [CrewMember]
    init() {}
    init(name: String, pierId: ModelIdType) {
        self.name = name
        self.$pier.id = pierId
    }

    func validate(fields: [any FormFieldBase]?, validations: Validations) -> ValidationResult.Status? { nil }
}

final class Berth: DataModel, @unchecked Sendable {
    static let schema = "berths"
    @ID(key: .id) var id: UUID?
    @Field(key: "number") var number: Int
    @Parent(key: "dock_id") var dock: Dock
    init() {}
    init(number: Int, dockId: ModelIdType) {
        self.number = number
        self.$dock.id = dockId
    }

    func validate(fields: [any FormFieldBase]?, validations: Validations) -> ValidationResult.Status? { nil }
}

final class CrewMember: DataModel, @unchecked Sendable {
    static let schema = "crew_members"
    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Siblings(through: DockCrew.self, from: \.$crewMember, to: \.$dock) var docks: [Dock]
    init() {}
    init(name: String) { self.name = name }
    func validate(fields: [any FormFieldBase]?, validations: Validations) -> ValidationResult.Status? { nil }
}

final class DockCrew: DataModel, @unchecked Sendable {
    static let schema = "dock_crew"
    @ID(key: .id) var id: UUID?
    @Parent(key: "dock_id") var dock: Dock
    @Parent(key: "crew_member_id") var crewMember: CrewMember
    init() {}
    init(dockId: ModelIdType, crewMemberId: ModelIdType) {
        self.$dock.id = dockId
        self.$crewMember.id = crewMemberId
    }

    func validate(fields: [any FormFieldBase]?, validations: Validations) -> ValidationResult.Status? { nil }
}

// MARK: - Migrations (parents first — FK order)

struct CreatePier: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Pier.schema).id().field("name", .string, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Pier.schema).delete()
    }
}

struct CreateDock: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Dock.schema).id()
            .field("name", .string, .required)
            .field("pier_id", .uuid, .required, .references(Pier.schema, "id"))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Dock.schema).delete()
    }
}

struct CreateBerth: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Berth.schema).id()
            .field("number", .int, .required)
            .field("dock_id", .uuid, .required, .references(Dock.schema, "id"))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Berth.schema).delete()
    }
}

struct CreateCrewMember: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(CrewMember.schema).id().field("name", .string, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(CrewMember.schema).delete()
    }
}

struct CreateDockCrew: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(DockCrew.schema).id()
            .field("dock_id", .uuid, .required, .references(Dock.schema, "id"))
            .field("crew_member_id", .uuid, .required, .references(CrewMember.schema, "id"))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(DockCrew.schema).delete()
    }
}

// MARK: - Shared seed

/// Seeds the standard graph and returns the two fetched docks:
/// dock1 (3 berths, 2 crew) and dock2 (1 berth, 1 shared crew member).
func seedHarbor(on db: any Database) async throws -> (dock1: Dock, dock2: Dock) {
    let pier = Pier(name: "North Pier")
    try await pier.save(on: db)
    let dock1 = try Dock(name: "Dock 1", pierId: pier.requireId())
    let dock2 = try Dock(name: "Dock 2", pierId: pier.requireId())
    try await dock1.save(on: db)
    try await dock2.save(on: db)
    for number in 1...3 {
        try await Berth(number: number, dockId: dock1.requireId()).save(on: db)
    }
    try await Berth(number: 9, dockId: dock2.requireId()).save(on: db)
    let alice = CrewMember(name: "Alice")
    let bob = CrewMember(name: "Bob")
    try await alice.save(on: db)
    try await bob.save(on: db)
    try await DockCrew(dockId: dock1.requireId(), crewMemberId: alice.requireId()).save(on: db)
    try await DockCrew(dockId: dock1.requireId(), crewMemberId: bob.requireId()).save(on: db)
    try await DockCrew(dockId: dock2.requireId(), crewMemberId: alice.requireId()).save(on: db)
    return (dock1, dock2)
}

/// Adds every fixture migration in FK order.
func addHarborMigrations(_ app: Application) {
    app.migrations.add(CreatePier())
    app.migrations.add(CreateDock())
    app.migrations.add(CreateBerth())
    app.migrations.add(CreateCrewMember())
    app.migrations.add(CreateDockCrew())
}
```

Append to `FluentTestHarnessTests.swift`:

```swift
@Test func harborFixturesSeedAndRelate() async throws {
    let names = try await withFluentTestApp { app in
        addHarborMigrations(app)
    } _: { _, db in
        let (dock1, _) = try await seedHarbor(on: db)
        let berths = try await dock1.$berths.query(on: db).all()
        return berths.map(\.number).sorted()
    }
    #expect(names == [1, 2, 3])
}
```

- [ ] **Step 2: Run to verify it passes**

Run: `swift test --filter FluentTestHarnessTests 2>&1 | tail -5`
Expected: 3 tests PASS (fixture graph compiles, saves, and relates).

- [ ] **Step 3: Commit**

```bash
git add Tests/FOSMVVMVaporTests/Containment/
git commit -m "test(FOSMVVMVaporTests): add harbor containment fixtures + seed helper"
```

---

### Task 4: `ModelIdentity` package visibility (FOSMVVM)

**Files:**
- Modify: `Sources/FOSMVVM/Protocols/ModelIdentity.swift:40-41`

- [ ] **Step 1: Promote the stored properties**

Change (spec §C4.1 — no new API, no extension):

```swift
    // `package`, NOT public — server-side targets read these to drive the ModelTypeRegistry lookup +
    // Fluent find; clients still cannot read identity contents (opacity is a public-surface guarantee, L0).
    package let namespace: ModelNamespace
    package let id: ModelIdType
```

replacing the two `private let` lines. Do not touch anything else in the file.

- [ ] **Step 2: Verify the full existing suite is untouched**

Run: `swift test 2>&1 | tail -5`
Expected: all tests pass (same count as before this task; L0 identity tests unchanged — opacity is a public-surface guarantee and no public surface changed).

- [ ] **Step 3: Commit**

```bash
git add Sources/FOSMVVM/Protocols/ModelIdentity.swift
git commit -m "feat(FOSMVVM): open ModelIdentity stored parts to package for the server seam"
```

---

### Task 5: `ContainmentError` + `ContainmentRelation` + `ContainerDataModel`

**Files:**
- Create: `Sources/FOSMVVMVapor/Containment/ContainmentError.swift`
- Create: `Sources/FOSMVVMVapor/Containment/ContainmentRelation.swift`
- Create: `Sources/FOSMVVMVapor/Containment/ContainerDataModel.swift`
- Test: `Tests/FOSMVVMVaporTests/Containment/ContainmentRelationTests.swift`

- [ ] **Step 1: Write the failing tests (spec groups 3, 4, 5 + cast backstop)**

`Tests/FOSMVVMVaporTests/Containment/ContainmentRelationTests.swift`:

```swift
import FluentKit
import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing

@Suite("ContainmentRelation member loads")
struct ContainmentRelationTests {
    // Spec test group 3: children of THIS dock only.
    @Test func childrenLoadsOnlyThisContainersMembers() async throws {
        let numbers = try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let members = try await ContainmentRelation.children(\Dock.$berths).members(of: dock1, on: db)
            return try members.map { try #require($0 as? Berth).number }.sorted()
        }
        #expect(numbers == [1, 2, 3])
    }

    // Spec test group 4: siblings through the pivot, this container only.
    @Test func siblingsLoadsThroughPivotForThisContainerOnly() async throws {
        let names = try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let (_, dock2) = try await seedHarbor(on: db)
            let members = try await ContainmentRelation.siblings(\Dock.$crew).members(of: dock2, on: db)
            return try members.map { try #require($0 as? CrewMember).name }.sorted()
        }
        #expect(names == ["Alice"])
    }

    // Spec test group 5: parent (to-one) returns a single-element array.
    @Test func parentLoadsSingleElementArray() async throws {
        let parents = try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let members = try await ContainmentRelation.parent(\Dock.$pier).members(of: dock1, on: db)
            return members.map { ($0 as? Pier)?.name }
        }
        #expect(parents == ["North Pier"])
    }

    // Cast backstop: wrong container type throws, never a silent [].
    @Test func mismatchedContainerThrowsTyped() async throws {
        try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let berth = try #require(try await dock1.$berths.query(on: db).first())
            let relation = ContainmentRelation.children(\Dock.$berths)
            do {
                _ = try await relation.members(of: berth, on: db) // a Berth is not a Dock
                Issue.record("expected ContainmentError.containerTypeMismatch")
            } catch let error as ContainmentError {
                guard case .containerTypeMismatch = error else {
                    Issue.record("wrong ContainmentError case: \(error)")
                    return
                }
            }
        }
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter ContainmentRelationTests 2>&1 | tail -5`
Expected: FAIL to compile — `cannot find 'ContainmentRelation' in scope`.

- [ ] **Step 3: Implement the three source files**

`Sources/FOSMVVMVapor/Containment/ContainmentError.swift`:

```swift
import Foundation

// Boot-time registration misconfiguration + the members() cast backstop. `package`, not public:
// apps never catch it — its value is the diagnostic message in Vapor's failed configure(_:);
// in-package tests assert the typed cases.
package enum ContainmentError: Error, CustomDebugStringConvertible {
    case duplicateNamespace(modelType: String)
    case containerTypeMismatch(expected: String, actual: String)
    case containmentDrift(modelType: String, containmentTypes: [String], containedRecordTypes: [String])

    package var debugDescription: String {
        switch self {
        case .duplicateNamespace(let modelType):
            "Duplicate ModelTypeRegistry registration: \(modelType)'s namespace is already registered. Each container is registered exactly once (register(_:migration:))."
        case .containerTypeMismatch(let expected, let actual):
            "ContainmentRelation container-type mismatch: relation was built from \(expected)'s relationship, but was applied to \(actual). Build containment only from the declaring container's own KeyPaths."
        case .containmentDrift(let modelType, let containmentTypes, let containedRecordTypes):
            "\(modelType).containment (\(containmentTypes.sorted())) must declare the same record types as its containedRecordTypes (\(containedRecordTypes.sorted())). These two declarations must not drift."
        }
    }
}
```

`Sources/FOSMVVMVapor/Containment/ContainmentRelation.swift` — DocC comes verbatim from spec §C4.2:

```swift
import FluentKit
import Foundation

/// One authorization-bearing containment relationship of a container, declared from a Fluent relationship.
///
/// Build these from your `@Children` / `@Siblings` / `@Parent` relationships — the framework reads the
/// join off Fluent, so you never restate a foreign key or pivot table:
///
/// ```swift
/// extension Dock: ContainerDataModel {
///     static var containment: [ContainmentRelation] {
///         [.children(\.$berths), .siblings(\.$crew)]   // Dock owns Berths (FK) and Crew (pivot)
///     }
/// }
/// ```
///
/// List only the relationships that a subject can be *authorized to* — not every Fluent relationship is
/// containment.
public struct ContainmentRelation: Sendable {
    // Erased types, `package`: consumed by the register-time checks + C6, not by app code.
    // `any DataModel`, not a bare `Model` — this module sees both FOSMVVM.Model and FluentKit.Model,
    // and C6 needs the Fluent query capability.
    package let containerType: any DataModel.Type // == From.self, captured by the factory
    package let containedType: any DataModel.Type // == To.self, captured by the factory

    private let load: @Sendable (any DataModel, any Database) async throws -> [any DataModel]

    /// A to-many child relationship (child table holds the foreign key back to the container).
    public static func children<From, To>(
        _ keyPath: KeyPath<From, ChildrenProperty<From, To>> & Sendable
    ) -> ContainmentRelation where From: DataModel, To: DataModel {
        .init(containerType: From.self, containedType: To.self) { container, db in
            try await container.cast(to: From.self)[keyPath: keyPath].query(on: db).all()
        }
    }

    /// A to-many sibling relationship joined through a pivot table.
    public static func siblings<From, To, Through>(
        _ keyPath: KeyPath<From, SiblingsProperty<From, To, Through>> & Sendable
    ) -> ContainmentRelation where From: DataModel, To: DataModel, Through: DataModel {
        .init(containerType: From.self, containedType: To.self) { container, db in
            try await container.cast(to: From.self)[keyPath: keyPath].query(on: db).all()
        }
    }

    /// A to-one parent relationship (this container's record references the parent by foreign key).
    public static func parent<From, To>(
        _ keyPath: KeyPath<From, ParentProperty<From, To>> & Sendable
    ) -> ContainmentRelation where From: DataModel, To: DataModel {
        .init(containerType: From.self, containedType: To.self) { container, db in
            try await container.cast(to: From.self)[keyPath: keyPath].query(on: db).all()
        }
    }

    private init(
        containerType: any DataModel.Type,
        containedType: any DataModel.Type,
        load: @escaping @Sendable (any DataModel, any Database) async throws -> [any DataModel]
    ) {
        self.containerType = containerType
        self.containedType = containedType
        self.load = load
    }
}

package extension ContainmentRelation {
    // The UNREFINED, UNAUTHORIZED containment load. C6 is the authorized entry point that wraps this
    // and composes filter/sort/pagination onto the query. `package` so only in-package engine code
    // calls it. For `.parent` (to-one) the result is a single-element array.
    // PRECONDITION: `container` must be a *fetched* instance (Fluent fatalErrors on an unpopulated
    // relationship idValue) — the engine always obtains it via RegisteredModel.find.
    func members(of container: any DataModel, on db: any Database) async throws -> [any DataModel] {
        try await load(container, db)
    }
}

private extension DataModel {
    // Backstop, not a code path: register(_:migration:) proves every relation's containerType at
    // boot, so a failing cast here means framework-invariant breakage — throw, never return [].
    func cast<To: DataModel>(to _: To.Type) throws -> To {
        guard let cast = self as? To else {
            throw ContainmentError.containerTypeMismatch(
                expected: String(describing: To.self),
                actual: String(describing: type(of: self))
            )
        }
        return cast
    }
}
```

`Sources/FOSMVVMVapor/Containment/ContainerDataModel.swift` — DocC from spec §C4.3:

```swift
import FluentKit
import FOSFoundation
import FOSMVVM
import Foundation

/// A Fluent-backed ``Container`` that declares which of its relationships are authorization-bearing
/// containment.
///
/// ```swift
/// final class Dock: ContainerDataModel {
///     static var containment: [ContainmentRelation] { [.children(\.$berths), .siblings(\.$crew)] }
///     // ...Fluent + Container members...
/// }
/// ```
public protocol ContainerDataModel: DataModel, Container where IDValue == ModelIdType {
    /// The authorization-bearing containment relationships. Must declare the same record types as
    /// ``Container/containedRecordTypes`` — ``Application/register(_:migration:)`` verifies both
    /// declarations agree at boot.
    static var containment: [ContainmentRelation] { get }
}
```

(No `[]` default and no `where` clause on `register` — the protocol carries both constraints; spec §C4.3 records why.)

- [ ] **Step 4: Run to verify tests pass**

Run: `swift test --filter ContainmentRelationTests 2>&1 | tail -5`
Expected: 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/FOSMVVMVapor/Containment/ Tests/FOSMVVMVaporTests/Containment/ContainmentRelationTests.swift
git commit -m "feat(FOSMVVMVapor): add ContainmentRelation factories + ContainerDataModel"
```

---

### Task 6: `ModelTypeRegistry` + throwing migration-as-registration

**Files:**
- Create: `Sources/FOSMVVMVapor/Containment/ModelTypeRegistry.swift`
- Create: `Sources/FOSMVVMVapor/Extensions/Application+Containment.swift`
- Test: `Tests/FOSMVVMVaporTests/Containment/ModelTypeRegistryTests.swift`

- [ ] **Step 1: Conform the fixtures**

In `ContainmentFixtures.swift`, change `Dock`'s conformance line to:

```swift
final class Dock: ContainerDataModel, @unchecked Sendable {
```

and add inside `Dock`:

```swift
    static var containedRecordTypes: [any FOSMVVM.Model.Type] { [Berth.self, CrewMember.self, Pier.self] }
    static var containment: [ContainmentRelation] {
        [.children(\.$berths), .siblings(\.$crew), .parent(\.$pier)]
    }
```

Add misconfigured fixture types at the bottom of the file (for the fail-fast tests):

```swift
// MARK: - Deliberately misconfigured containers (fail-fast tests)

/// Same namespace as Dock (anchored to Dock) — duplicate-registration fixture.
final class RogueDock: ContainerDataModel, @unchecked Sendable {
    static let schema = "rogue_docks"
    static var modelIdentityNamespace: ModelNamespace { .init(for: Dock.self) }
    static var containedRecordTypes: [any FOSMVVM.Model.Type] { [] }
    static var containment: [ContainmentRelation] { [] }
    @ID(key: .id) var id: UUID?
    init() {}
    func validate(fields: [any FormFieldBase]?, validations: Validations) -> ValidationResult.Status? { nil }
}

/// containment built from ANOTHER container's KeyPath — container-type-mismatch fixture.
final class MismatchedDock: ContainerDataModel, @unchecked Sendable {
    static let schema = "mismatched_docks"
    static var containedRecordTypes: [any FOSMVVM.Model.Type] { [Berth.self] }
    static var containment: [ContainmentRelation] { [.children(\Dock.$berths)] }
    @ID(key: .id) var id: UUID?
    init() {}
    func validate(fields: [any FormFieldBase]?, validations: Validations) -> ValidationResult.Status? { nil }
}

/// containment ≠ containedRecordTypes — drift fixture, MISSING direction (declared Berth, forgot containment).
final class DriftingDock: ContainerDataModel, @unchecked Sendable {
    static let schema = "drifting_docks"
    static var containedRecordTypes: [any FOSMVVM.Model.Type] { [Berth.self] }
    static var containment: [ContainmentRelation] { [] }
    @ID(key: .id) var id: UUID?
    init() {}
    func validate(fields: [any FormFieldBase]?, validations: Validations) -> ValidationResult.Status? { nil }
}

/// containment ≠ containedRecordTypes — drift fixture, SURPLUS direction (containment declares a type
/// containedRecordTypes omits). Needs its own child relationship so the KeyPath's From is itself.
final class SurplusDock: ContainerDataModel, @unchecked Sendable {
    static let schema = "surplus_docks"
    static var containedRecordTypes: [any FOSMVVM.Model.Type] { [] }
    static var containment: [ContainmentRelation] { [.children(\.$boats)] }
    @ID(key: .id) var id: UUID?
    @Children(for: \.$surplusDock) var boats: [Boat]
    init() {}
    func validate(fields: [any FormFieldBase]?, validations: Validations) -> ValidationResult.Status? { nil }
}

/// Child of SurplusDock (exists only so SurplusDock has a relationship of its own).
final class Boat: DataModel, @unchecked Sendable {
    static let schema = "boats"
    @ID(key: .id) var id: UUID?
    @Parent(key: "surplus_dock_id") var surplusDock: SurplusDock
    init() {}
    func validate(fields: [any FormFieldBase]?, validations: Validations) -> ValidationResult.Status? { nil }
}
```

(If `Container`'s `containedRecordTypes` spelling is `[any Model.Type]` and `Model` is unambiguous in the test file, drop the `FOSMVVM.` qualifier — match what compiles cleanly; the test target imports both FluentKit and FOSMVVM, so qualification is likely required.)

- [ ] **Step 2: Write the failing tests (spec groups 1, 2, 8, 9, 10)**

`Tests/FOSMVVMVaporTests/Containment/ModelTypeRegistryTests.swift`:

```swift
import Fluent // app.migrations lives in vapor/fluent
import FluentKit
import FOSMVVM
import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing

@Suite("ModelTypeRegistry + migration-as-registration")
struct ModelTypeRegistryTests {
    // Spec test group 1: registry round-trip; unregistered namespace → nil.
    @Test func registrationRoundTripsDescriptor() async throws {
        try await withFluentTestApp { app in
            try app.register(Dock.self, migration: CreateDock())
            app.migrations.add(CreatePier())
            app.migrations.add(CreateBerth())
            app.migrations.add(CreateCrewMember())
            app.migrations.add(CreateDockCrew())
        } _: { app, _ in
            let descriptor = try #require(app.modelTypeRegistry.registered(for: Dock.modelIdentityNamespace))
            // Assertion basis per spec: count + per-element containedType identity (not Equatable).
            #expect(descriptor.containment.count == Dock.containment.count)
            #expect(
                Set(descriptor.containment.map { ObjectIdentifier($0.containedType) })
                    == Set(Dock.containment.map { ObjectIdentifier($0.containedType) })
            )
            #expect(app.modelTypeRegistry.registered(for: Pier.modelIdentityNamespace) == nil)
        }
    }

    // Spec test group 2: find by id; missing id → nil.
    @Test func registeredModelFindsById() async throws {
        try await withFluentTestApp { app in
            try app.register(Dock.self, migration: CreateDock())
            app.migrations.add(CreatePier())
            app.migrations.add(CreateBerth())
            app.migrations.add(CreateCrewMember())
            app.migrations.add(CreateDockCrew())
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let descriptor = try #require(app.modelTypeRegistry.registered(for: Dock.modelIdentityNamespace))
            let found = try await descriptor.find(dock1.requireId(), on: db)
            #expect(try #require(found as? Dock).id == dock1.id)
            let missing = try await descriptor.find(ModelIdType(), on: db)
            #expect(missing == nil)
        }
    }

    // Spec test group 8: duplicate namespace fail-fast — both a second register of the SAME type
    // and a second TYPE sharing the namespace; first registration unchanged.
    @Test func duplicateRegistrationThrows() async throws {
        try await withFluentTestApp { app in
            try app.register(Dock.self, migration: CreateDock())
            for attempt in 0..<2 {
                do {
                    // attempt 0: same type twice; attempt 1: different type, colliding namespace.
                    if attempt == 0 {
                        try app.register(Dock.self, migration: CreateDock())
                    } else {
                        try app.register(RogueDock.self, migration: CreateDock())
                    }
                    Issue.record("expected ContainmentError.duplicateNamespace (attempt \(attempt))")
                } catch let error as ContainmentError {
                    guard case .duplicateNamespace = error else {
                        Issue.record("wrong case: \(error)")
                        return
                    }
                }
            }
            // First registration untouched:
            let descriptor = app.modelTypeRegistry.registered(for: Dock.modelIdentityNamespace)
            #expect(descriptor?.containment.count == Dock.containment.count)
            // Don't migrate the harbor graph here — this test never touches the DB body.
        } _: { _, _ in }
    }

    // Spec test group 9: containment from another container's KeyPath fail-fasts.
    @Test func containerTypeMismatchThrows() async throws {
        try await withFluentTestApp { app in
            do {
                try app.register(MismatchedDock.self, migration: CreateDock())
                Issue.record("expected ContainmentError.containerTypeMismatch")
            } catch let error as ContainmentError {
                guard case .containerTypeMismatch = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
            #expect(app.modelTypeRegistry.registered(for: MismatchedDock.modelIdentityNamespace) == nil)
        } _: { _, _ in }
    }

    // Spec test group 10: containment ≠ containedRecordTypes fail-fasts in BOTH directions
    // (missing: DriftingDock; surplus: SurplusDock); a matching declaration registers cleanly.
    @Test func containmentDriftThrows() async throws {
        try await withFluentTestApp { app in
            // Missing direction: declared Berth, containment empty.
            do {
                try app.register(DriftingDock.self, migration: CreateDock())
                Issue.record("expected .containmentDrift (missing direction)")
            } catch let error as ContainmentError {
                guard case .containmentDrift = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
            // Surplus direction: containment declares Boat, containedRecordTypes empty.
            do {
                try app.register(SurplusDock.self, migration: CreateDock())
                Issue.record("expected .containmentDrift (surplus direction)")
            } catch let error as ContainmentError {
                guard case .containmentDrift = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
            // The matching declaration (Dock) registers cleanly:
            try app.register(Dock.self, migration: CreateDock())
        } _: { _, _ in }
    }
}
```

(The `== nil` expectations compile as written — Swift's optional-to-`nil` comparison doesn't require `Equatable`.)

- [ ] **Step 3: Run to verify they fail**

Run: `swift test --filter ModelTypeRegistryTests 2>&1 | tail -5`
Expected: FAIL to compile — `cannot find 'ModelTypeRegistry'` / `no member 'register'`.

- [ ] **Step 4: Implement registry + registration**

`Sources/FOSMVVMVapor/Containment/ModelTypeRegistry.swift`:

```swift
import FluentKit
import FOSFoundation
import FOSMVVM
import Foundation

// Recovers a persisted ModelIdentity's Swift model type (and its containment) on the server.
// Populated as a side effect of Application.register(_:migration:); injected into Application/Request
// storage — never process-global (parallel-test isolation). `package`: every current consumer
// (C6 engine, C8 factory, DEF-7 guard, contract tests) is in-package — promote to `public` only when
// an app-side consumer appears (additive). Deliberately distinct from localization's ModelRegistry.
package struct ModelTypeRegistry: Sendable {
    private var models: [ModelNamespace: RegisteredModel] = [:]

    package init() {}

    // The descriptor registered for a namespace, or nil if none is registered.
    package func registered(for namespace: ModelNamespace) -> RegisteredModel? {
        models[namespace]
    }

    // Throws ContainmentError.duplicateNamespace — silent last-writer-wins would corrupt the
    // identity→type mapping that authorization keys on.
    mutating func insert(_ model: RegisteredModel, describing typeName: String) throws {
        guard models[model.namespace] == nil else {
            throw ContainmentError.duplicateNamespace(modelType: typeName)
        }
        models[model.namespace] = model
    }
}

// A type-erased handle to a registered model — recover an instance by id, and read its containment.
package struct RegisteredModel: Sendable {
    package let namespace: ModelNamespace
    package let containment: [ContainmentRelation]

    private let findById: @Sendable (ModelIdType, any Database) async throws -> (any DataModel)?

    init(for type: (some ContainerDataModel).Type) {
        self.namespace = type.modelIdentityNamespace
        self.containment = type.containment
        self.findById = { id, db in try await type.find(id, on: db) }
    }

    // Fetch the instance for this identity's id — the engine's recover step.
    package func find(_ id: ModelIdType, on db: any Database) async throws -> (any DataModel)? {
        try await findById(id, db)
    }
}
```

`Sources/FOSMVVMVapor/Extensions/Application+Containment.swift` — `register` DocC from spec §C4.5:

```swift
import Fluent
import FluentKit
import FOSMVVM
import Foundation
import Vapor

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
    func register(_ type: (some ContainerDataModel).Type, migration: any Migration) throws {
        // Boot-time fail-fast #2: every relation must be built from the registered type's own KeyPaths
        // (the factory's From generic is free — construction alone can't prove this).
        for relation in type.containment
            where ObjectIdentifier(relation.containerType) != ObjectIdentifier(type) {
            throw ContainmentError.containerTypeMismatch(
                expected: String(describing: type),
                actual: String(describing: relation.containerType)
            )
        }

        // Boot-time fail-fast #3 (arch §5 C4 invariant (a)): the two cross-boundary declarations of
        // "what this container owns" must not drift.
        let declared = Set(type.containment.map { ObjectIdentifier($0.containedType) })
        let contained = Set(type.containedRecordTypes.map { ObjectIdentifier($0) })
        guard declared == contained else {
            throw ContainmentError.containmentDrift(
                modelType: String(describing: type),
                containmentTypes: type.containment.map { String(describing: $0.containedType) },
                containedRecordTypes: type.containedRecordTypes.map { String(describing: $0) }
            )
        }

        // Boot-time fail-fast #1 (duplicate namespace) lives in insert(_:describing:).
        var registry = modelTypeRegistry
        try registry.insert(RegisteredModel(for: type), describing: String(describing: type))
        storage[ModelTypeRegistryStore.self] = registry

        migrations.add(migration)
    }
}

package extension Application {
    // Injected, not global — parallel-test isolation. Mirrors localizationStore/mvvmEnvironment.
    var modelTypeRegistry: ModelTypeRegistry {
        storage[ModelTypeRegistryStore.self] ?? ModelTypeRegistry()
    }
}

package extension Request {
    var modelTypeRegistry: ModelTypeRegistry {
        application.modelTypeRegistry
    }
}

private struct ModelTypeRegistryStore: StorageKey {
    typealias Value = ModelTypeRegistry
}
```

- [ ] **Step 5: Run to verify tests pass**

Run: `swift test --filter ModelTypeRegistryTests 2>&1 | tail -5`
Expected: 5 tests PASS. Also run `swift test --filter ContainmentRelationTests 2>&1 | tail -3` — still green after the fixture conformance change.

- [ ] **Step 6: Commit**

```bash
git add Sources/FOSMVVMVapor/ Tests/FOSMVVMVaporTests/Containment/
git commit -m "feat(FOSMVVMVapor): add injected ModelTypeRegistry + throwing migration-as-registration"
```

---

### Task 7: End-to-end erased bridge (spec test group 6)

**Files:**
- Create: `Tests/FOSMVVMVaporTests/Containment/ErasedBridgeTests.swift`

- [ ] **Step 1: Write the test**

The whole point of C4: from a bare `ModelIdentity`, reach the contained records **without naming `Dock`/`Berth` at the loading call sites**. The generic helper takes only the identity + registry + db:

```swift
import Fluent // app.migrations lives in vapor/fluent
import FluentKit
import FOSMVVM
import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing

@Suite("End-to-end erased bridge")
struct ErasedBridgeTests {
    @Test func identityReachesContainedRecordsWithoutConcreteTypes() async throws {
        let membersByRelation = try await withFluentTestApp { app in
            try app.register(Dock.self, migration: CreateDock())
            app.migrations.add(CreatePier())
            app.migrations.add(CreateBerth())
            app.migrations.add(CreateCrewMember())
            app.migrations.add(CreateDockCrew())
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let identity = try dock1.modelIdentity
            // From here down: NO concrete container/record type names — the erased path only.
            return try await loadAllMembers(of: identity, registry: app.modelTypeRegistry, on: db)
        }
        // dock1: 3 berths (children), 2 crew (siblings), 1 pier (parent).
        #expect(membersByRelation.sorted() == [1, 2, 3])
    }
}

/// The C4 flow, generically: identity → registry → find → containment → members.
/// Deliberately references no concrete model type.
private func loadAllMembers(
    of identity: ModelIdentity,
    registry: ModelTypeRegistry,
    on db: any Database
) async throws -> [Int] {
    let descriptor = try #require(registry.registered(for: identity.namespace))
    let container = try #require(try await descriptor.find(identity.id, on: db))
    var counts: [Int] = []
    for relation in descriptor.containment {
        counts.append(try await relation.members(of: container, on: db).count)
    }
    return counts
}
```

(`identity.namespace` / `identity.id` are the Task 4 `package` stored parts — this test also proves the server seam. `#require` inside a non-test helper: if Swift Testing balks, return optionals and `#require` in the test body instead.)

- [ ] **Step 2: Run to verify it passes**

Run: `swift test --filter ErasedBridgeTests 2>&1 | tail -5`
Expected: 1 test PASS — counts `[1, 2, 3]` sorted = parent(1) + crew(2) + berths(3).

- [ ] **Step 3: Commit**

```bash
git add Tests/FOSMVVMVaporTests/Containment/ErasedBridgeTests.swift
git commit -m "test(FOSMVVMVaporTests): prove the end-to-end erased identity→Fluent bridge"
```

---

### Task 8: Definition-of-done sweep + CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Boundary + opacity greps (spec DoD + test group 7)**

```bash
grep -rn "import FluentKit\|import Fluent\b" Sources/FOSMVVM/ Sources/FOSFoundation/ ; echo "---"
grep -rn "public var namespace\|public let namespace\|public var id\|public let id" Sources/FOSMVVM/Protocols/ModelIdentity.swift ; echo "---"
grep -rln "\.namespace\b\|modelIdentity\.id\b" Sources/FOSMVVM/ Sources/FOSTesting/ Sources/FOSTestingUI/
```

Expected: first two sections empty (no Fluent in shared targets; no public getters on `ModelIdentity`); third shows no client-linked target reading identity parts (hits in `ModelIdentity.swift` itself are fine).

- [ ] **Step 2: Format, lint, full suite**

```bash
swiftformat . && swiftlint --quiet
swift test 2>&1 | tail -5
```

Expected: formatter may add license headers to new files (re-stage); lint clean; full suite green (prior count + 13 new tests; the 2 pre-existing known issues unchanged).

- [ ] **Step 3: CHANGELOG entry**

Under the unreleased/0.4.0 section, add (contract-level only — never the encoded/representation details):

```markdown
### Added
- `ContainerDataModel` + `ContainmentRelation` (FOSMVVMVapor): declare a container's
  authorization-bearing relationships from its own Fluent `@Children`/`@Siblings`/`@Parent`
  KeyPaths — cardinality and joins come from Fluent, never restated.
- `Application.register(_:migration:)` (FOSMVVMVapor): registering a container's migration also
  registers its identity descriptor; misconfigurations (duplicate namespace, foreign KeyPaths,
  containment drift vs `containedRecordTypes`) throw at boot.
- `withFluentTestApp` (FOSTestingVapor): scoped in-memory SQLite + Vapor application harness for
  Fluent-backed tests.
```

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md
git add -A   # any swiftformat header additions
git commit -m "docs(CHANGELOG): record C4 Fluent containment + type registry"
```

---

## Final verification (Definition of Done from the spec)

- [ ] `swift build` + `swift test` green on macOS (Linux via CI).
- [ ] All 10 spec test groups covered: 1,2,8,9,10 (`ModelTypeRegistryTests`), 3,4,5 + backstop (`ContainmentRelationTests`), 6 (`ErasedBridgeTests`), 7 (grep review invariant, Task 8).
- [ ] `swiftformat`/`swiftlint` clean.
- [ ] DocC with examples on every `public` symbol; `package` symbols carry `//` notes only.
- [ ] No Fluent import in FOSMVVM/FOSFoundation; `fluent-sqlite-driver` linked only from FOSTestingVapor.
- [ ] CHANGELOG entry present.
