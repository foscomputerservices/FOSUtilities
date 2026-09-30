# FOSMVVM Fluent DataModel Generator - Reference Templates

This document contains the complete file templates for generating Fluent DataModels.
Replace `{Model}` with the actual model name (e.g., `User`, `Idea`).

> **Fields Layer:** For form-backed models, first run [fosmvvm-fields-generator](../fosmvvm-fields-generator/SKILL.md) to generate the Fields protocol, Messages struct, and YAML localization.

---

## File 1: {Model}.swift (Fluent Model)

**Location:** `Sources/{WebServerTarget}/DataModels/{Model}.swift`

```swift
import FluentKit
import FOSFoundation
import FOSMVVM
import FOSMVVMVapor
import Foundation
import {ViewModelsTarget}

final class {Model}: DataModel, {Model}Fields, Hashable, @unchecked Sendable {
    static let schema = "{models}"  // snake_case plural

    // MARK: Public Properties

    @ID(key: .id) var id: ModelIdType?

    // MARK: {Model}Fields Protocol

    // Add fields matching the protocol:
    // @Field(key: "field_name") var fieldName: FieldType

    let {model}ValidationMessages: {Model}FieldsMessages

    // MARK: Timestamps

    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    init() {
        self.{model}ValidationMessages = .init()
    }

    init(id: ModelIdType? = nil, /* add field parameters */) {
        self.{model}ValidationMessages = .init()
        self.id = id
        // Assign fields
    }
}
```

---

## File 2: {Model}+Schema.swift

**Location:** `Sources/{WebServerTarget}/Migrations/{Model}+Schema.swift`

```swift
import Fluent

extension {Model} {
    struct Initial: AsyncMigration {
        let name = "\({Model}.schema)-initial"

        func prepare(on database: any Database) async throws {
            try await database.schema({Model}.schema)

                // MARK: Properties

                .id()
                // Add fields:
                // .field("field_name", .string, .required)
                // .field("optional_field", .string)
                // .field("foreign_key", .uuid, .references("other_table", "id"))

                // MARK: Timestamps

                .field("created_at", .datetime)
                .field("updated_at", .datetime)

                // MARK: Constraints

                // Add constraints:
                // .unique(on: "field_name")

                .create()
        }

        func revert(on database: any Database) async throws {
            try await database.schema({Model}.schema).delete()
        }
    }
}
```

---

## File 3: {Model}+Seed.swift

**Location:** `Sources/{WebServerTarget}/Migrations/{Model}+Seed.swift`

```swift
import Fluent
import Vapor

extension {Model} {
    struct Seed: AsyncMigration {
        let name = "\({Model}.schema)-seed"

        func prepare(on database: any Database) async throws {
            guard try await {Model}.query(on: database).count() == 0 else { return }

            let items: [{Model}]
            switch Vapor.Environment.deployment {
            case .debug:
                items = try {Model}.defaultDebugItems
            case .test:
                items = try {Model}.defaultTestItems
            default:
                fatalError("Unknown Deployment: \(Vapor.Environment.deployment)")
            }

            for item in items {
                try await item.save(on: database)
            }
        }

        func revert(on database: any Database) async throws {}
    }
}

private extension {Model} {
    static var defaultDebugItems: [{Model}] {
        get throws { [
            // Add debug seed data:
            // .init(fieldName: "value")
        ] }
    }

    static var defaultTestItems: [{Model}] {
        get throws { [
            // Add test seed data:
            // .init(fieldName: "test_value")
        ] }
    }
}
```

---

## File 4: {Model}FieldsTests.swift

**Location:** `Tests/{ViewModelsTarget}Tests/FieldModels/{Model}FieldsTests.swift`

```swift
import FOSFoundation
import FOSMVVM
import FOSTesting
import Foundation
import Testing
import {ViewModelsTarget}

@Suite("{Model} Fields")
struct {Model}FieldsTests: LocalizableTestCase {
    @Test func {model}FormFields() throws {
        // Test all form fields:
        // try expectFullFormFieldTests({Model}.fieldNameField)
    }

    // Add validation tests with arguments:
    // @Test(arguments: [
    //     Test{Model}(fieldName: ""),
    //     Test{Model}(fieldName: String.random(length: {Model}.fieldNameRange.lowerBound - 1)),
    //     Test{Model}(fieldName: String.random(length: {Model}.fieldNameRange.upperBound + 1))
    // ]) fileprivate func `{Model} FieldName Validation`(
    //     item: Test{Model}
    // ) throws {
    //     for locale in locales {
    //         var item = item
    //         try item.localizeMessages(encoder: encoder(locale: locale))
    //
    //         let validations = Validations()
    //         let status = try #require(item.validate(validations: validations))
    //         #expect(status.hasError)
    //         let error = try #require(validations.validationError)
    //         let messages = error.validations
    //             .compactMap { $0.messages(for: {Model}.fieldNameField.fieldId) }
    //             .flatMap(\.self)
    //         #expect(messages.count == 1)
    //         guard let message = messages.first else { return }
    //
    //         #expect(message.message != .empty, "\(locale)")
    //     }
    // }

    let locStore: LocalizationStore

    init() async throws {
        self.locStore = try Self.loadLocalizationStore(
            bundle: Bundle.module,
            resourceDirectoryName: ""
        )
    }
}

private struct Test{Model}: {Model}Fields {
    var id: ModelIdType?
    // Add fields matching protocol

    private(set) var {model}ValidationMessages: {Model}FieldsMessages

    mutating func localizeMessages(encoder: JSONEncoder) throws {
        {model}ValidationMessages = try {Model}FieldsMessages().toJSON(encoder: encoder).fromJSON()
    }

    init(
        id: ModelIdType? = .init()
        // Add default parameters for all fields
    ) {
        self.id = id
        // Assign fields
        self.{model}ValidationMessages = .init()
    }
}
```

`Validations` is append-only: results go in through `append(_:)` / `append(contentsOf:)` (or `replace(with:)`), and `validations` is read-only from outside. Read a run's outcome through `status`, `hasError(for:)`, `modelMessages` or `validationError`.

---

## File 5: Update database.swift

**Location:** `Sources/{WebServerTarget}/database.swift`

Add to the existing file:

```swift
// Under MARK: Migrations
try app.register({Model}.self, migration: {Model}.Initial())

// Under MARK: Seed (inside the if !app.environment.isRelease block)
// A Seed is a plain Migration, not a DataModel — it still goes through migrations.add
app.migrations.add({Model}.Seed(), to: dbId)
```

`register(_:migration:)` adds the migration **and** installs the model's lifecycle middleware. `app.migrations.add({Model}.Initial())` on a `DataModel` creates the table and nothing else — `willWrite`, `validateModel(in:)`, `validationResult(for:)`, `didWrite` and `didCommit` never run, so the model's own rules are quietly absent from every write.

---

## DataModel Lifecycle

`DataModel` conforms to `DataModelLifecycle`. Every requirement has a do-nothing default, so a model declares only the hooks it actually needs — and the hooks run for **every** write of that model, whatever called `save`/`delete`/`restore`, because `try app.register({Model}.self, migration:)` installed the middleware.

### The order, per Fluent event

1. **`willWrite(in:)`** — may change the model: derive, trim, stamp. A throw here is an error, never a validation.
2. **Field validation** — your `Fields` protocol's `validate(fields: nil, validations:)`. **Create and update only**; archive, destroy and restore write none of the model's own columns.
3. **Refusal** — an error (or a warning under `.blocking`) stops here with a `ValidationError`. Model validation does not run when field validation failed.
4. **`validateModel(in:)`** — the model judged against other rows. **Every action.** Returns its results; the framework appends them. Every rule runs; nothing short-circuits.
5. **Refusal again**, same rule.
6. **Fluent applies the action.** A driver constraint failure is offered to `validationResult(for:)`.
7. **`didWrite(in:)`** — same database, so the same transaction. May write rows. A throw rolls the transaction back, the triggering row included.
8. **`didCommit(in:)`** — `async`, non-throwing, side effects only.

### What each hook may and may not do

**`willWrite(in: DataModelWriteContext) async throws`** — the one place that changes the model. Throw only for a failure the user cannot fix; a value the user must correct belongs in `validateModel(in:)`.

**`validateModel(in: DataModelWriteContext) async throws -> [ValidationResult]`** — judges, never mutates. Query through `context.database` so you read the same transaction the write is in. Return one result per rule that fails, all of them, not the first; a result built with `.init(status:message:)` (no field) is about the model as a whole, and one built with `.init(status:fieldId:message:)` addresses a form field — mint the id with `#fieldId(\{Model}Fields.property)` — the Fields protocol the form field was minted from, so the message reaches that field — never a string. Throw only when the query itself fails.

**`validationResult(for: ConstraintViolation) -> ValidationResult?`** — turns a database constraint failure into a message the user can act on. Read `violation.action` to know which write hit it, and `violation.underlyingError` only when the model has more than one constraint to tell apart. Returning a result makes the failure a `ValidationError` carrying it; **returning `nil` — the default — rethrows the original error unchanged**, which is what you want for a constraint the user has no way to satisfy. This is the hook for the loser of a race on a unique index.

**`didWrite(in: DataModelWriteContext) async throws`** — more work in the same transaction. This is where a history/audit row belongs. A throw rolls everything back.

**`didCommit(in: DataModelCommitContext) async`** — the side effect the durable write unlocks: send the mail, call the other system, notify. There is no database on this context; the transaction is over. It cannot fail the request and nothing it does can be rolled back, so handle your own failures.

**`static var warningPolicy: ValidationWarningPolicy`** — `.advisory` (the default) lets a write proceed with warnings, which are logged and go no further. `.blocking` makes a warning stop the write and reach the client exactly like an error. Warnings collected alongside an error always travel with it, under either policy.

### The after-commit rule

`didCommit(in:)` sees the commit only inside `liveTransaction { }`.

Inside a bare `database.transaction { }` it does **not** run — the framework cannot see whether that transaction commits, so the after-commit work is suppressed (and logged once per model type). On an auto-commit write — a plain `save(on: db)` outside any transaction — it runs immediately after `didWrite`.

**Use `liveTransaction` for any write whose commit a hook must see.**

### Batch-write limits

FluentKit's `[{Model}].create(on:)` and `[{Model}].delete(on:)` call each model's middleware with a `next` that writes nothing, then run one bulk statement. The hooks therefore run per model *before* any row exists:

- `didWrite(in:)` sees no row — `requireID()` may hold, but nothing is queryable yet.
- A constraint failure is **not** offered to `validationResult(for:)`; it surfaces as the driver's error.
- A batch delete always dispatches **`.destroy`**, never `.archive`, even for a model that declares a delete timestamp.

Write one model at a time when a hook's correctness depends on the row being there.

### SOLID

**SRP** — `willWrite` mutates, `validateModel` judges, `didWrite` writes companions, `didCommit` reaches outside. Collapsing two of those into one hook is how a model ends up writing a value no rule ever saw, or rolling back an email that was already sent.

**OCP** — every hook is a protocol requirement with a default, so the framework extends through the protocol and you never patch the write path. A near-miss signature (`validateModel(on:)`, `willSave(in:)`) witnesses no requirement: it compiles, and it silently never runs.

**DIP / ISP** — `try app.register({Model}.self, migration:)` is the single registration call; the model declares rules and knows nothing about middleware. A bare `app.migrations.add` on a `DataModel` leaves the type outside that wiring, and the rules are simply absent.

---

## Relationship Patterns

### Pattern 0: Many-to-Many (Junction Tables)

Use junction tables, NEVER UUID arrays.

**Anti-pattern (don't do this):**
```swift
// BAD - loses referential integrity, bypasses type safety
@Field(key: "source_nodes") var sourceNodes: [ModelIdType]
```

**Correct pattern:**

1. Create junction table (DataModel-only, no Fields needed):
```swift
import FluentKit
import Foundation

final class {Parent}{Relationship}: Model, @unchecked Sendable {
    static let schema = "{parent}_{relationships}"  // snake_case plural

    @ID(key: .id) var id: UUID?
    @Parent(key: "{parent}_id") var {parent}: {Parent}
    @Parent(key: "{related}_id") var {related}: {Related}
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init({parent}ID: {Parent}.IDValue, {related}ID: {Related}.IDValue) {
        self.${parent}.id = {parent}ID
        self.${related}.id = {related}ID
    }
}
```

2. Wire `@Siblings` in parent model:
```swift
final class {Parent}: DataModel, {Parent}Fields, ... {
    @Siblings(through: {Parent}{Relationship}.self,
              from: \.${parent},
              to: \.${related}) var {relationships}: [{Related}]
}
```

3. Create migration for junction table:
```swift
extension {Parent}{Relationship} {
    struct Initial: AsyncMigration {
        let name = "\({Parent}{Relationship}.schema)-initial"

        func prepare(on database: any Database) async throws {
            try await database.schema({Parent}{Relationship}.schema)
                .id()
                .field("{parent}_id", .uuid, .required,
                       .references({Parent}.schema, "id", onDelete: .cascade))
                .field("{related}_id", .uuid, .required,
                       .references({Related}.schema, "id", onDelete: .cascade))
                .field("created_at", .datetime)
                .unique(on: "{parent}_id", "{related}_id")
                .create()
        }

        func revert(on database: any Database) async throws {
            try await database.schema({Parent}{Relationship}.schema).delete()
        }
    }
}
```

**Naming convention:**
- Junction table: `{Parent}{Relationship}` (e.g., `DocumentOriginatingConversation`)
- Relationship property: descriptive verb (e.g., `originatingConversations`)
- Avoid generic names like `sourceNodes` - be specific about the relationship meaning

### Pattern 1: Associated Type (Preferred for Required Relationships)

**PRINCIPLE: Existential types (`any Protocol`) are a code smell.** Use associated types for required relationships.

**In the protocol** (`{Model}Fields.swift`):
```swift
public protocol {Model}Fields: ValidatableModel, Codable, Sendable {
    associatedtype {Related}: {Related}Fields

    var id: ModelIdType? { get set }
    var {related}: {Related} { get set }  // Associated type, not existential
}
```

**In the Fluent model** (`{Model}.swift`):
```swift
final class {Model}: DataModel, {Model}Fields, Hashable, @unchecked Sendable {
    static let schema = "{models}"

    @ID(key: .id) var id: ModelIdType?
    @Parent(key: "{related}_id") var {related}: {Related}  // Directly satisfies protocol!

    // CRITICAL: Initialize validationMessages FIRST
    init(id: ModelIdType? = nil, {related}ID: {Related}.IDValue) {
        self.{model}ValidationMessages = .init()  // FIRST!
        self.id = id
        self.${related}.id = {related}ID
    }
}
```

**In the schema** (`{Model}+Schema.swift`):
```swift
.field("{related}_id", .uuid, .required, .references({Related}.schema, "id", onDelete: .cascade))
```

**In tests** (`{Model}FieldsTests.swift`):
```swift
private struct Test{Model}: {Model}Fields {
    typealias {Related} = Test{Related}  // Satisfy the associated type

    var id: ModelIdType?
    var {related}: Test{Related}  // Concrete type
}

private struct Test{Related}: {Related}Fields {
    var id: ModelIdType? = .init()
    // ... all required fields with defaults
}
```

### Pattern 2: Plain ID (For Optional FKs or External References)

Use when the relationship is optional or references an external system:

**In the protocol:**
```swift
var {related}Id: ModelIdType { get set }           // Required FK as ID
var externalSystemId: ModelIdType? { get set }     // Optional/external FK
```

**In the Fluent model:**
```swift
@Parent(key: "{related}_id") var {related}: {Related}

// Computed property to satisfy protocol
var {related}Id: ModelIdType {
    get { ${related}.id }
    set { ${related}.id = newValue }
}

// Optional external reference - plain field, not @Parent
@OptionalField(key: "external_system_id") var externalSystemId: ModelIdType?
```

---

## Raw SQL in Migrations (PostgreSQL Features)

For PostgreSQL-specific features not supported by Fluent's schema builder:

```swift
// {Model}+Schema.swift

import Fluent
import SQLKit  // Required for raw SQL

extension {Model} {
    struct Initial: AsyncMigration {
        let name = "\({Model}.schema)-initial"

        func prepare(on database: any Database) async throws {
            // Standard Fluent schema builder
            try await database.schema({Model}.schema)
                .id()
                .field("content", .string, .required)
                .field("created_at", .datetime)
                .field("updated_at", .datetime)
                .create()

            // PostgreSQL-specific features via raw SQL
            guard let sql = database as? any SQLDatabase else { return }

            let schema = {Model}.schema

            // Full-text search with tsvector (GENERATED column)
            try await sql.raw(SQLQueryString("""
                ALTER TABLE \(unsafeRaw: schema) ADD COLUMN search_vector tsvector
                GENERATED ALWAYS AS (to_tsvector('english', content)) STORED
                """)).run()

            // GIN index for full-text search
            try await sql.raw(SQLQueryString("""
                CREATE INDEX \(unsafeRaw: schema)_search_idx
                ON \(unsafeRaw: schema) USING GIN (search_vector)
                """)).run()

            // LTREE column for hierarchical data
            // try await sql.raw(SQLQueryString("""
            //     ALTER TABLE \(unsafeRaw: schema) ADD COLUMN path ltree
            //     """)).run()
        }

        func revert(on database: any Database) async throws {
            try await database.schema({Model}.schema).delete()
        }
    }
}
```

**Key points:**
- Import `SQLKit` (not just `Fluent`)
- Cast database: `database as? any SQLDatabase`
- Use `SQLQueryString` with `\(unsafeRaw:)` for table/column names
- These columns exist only in the database - not in the protocol or Fluent model
- The Fluent model can still query/filter on them using raw queries
