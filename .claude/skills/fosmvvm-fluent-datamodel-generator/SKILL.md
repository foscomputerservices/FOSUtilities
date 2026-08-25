---
name: fosmvvm-fluent-datamodel-generator
description: Generate Fluent DataModels for FOSMVVM server-side persistence. Scaffolds models, migrations, and tests for database-backed entities.
homepage: https://github.com/foscomputerservices/FOSUtilities
metadata: {"clawdbot": {"emoji": "🗄️", "os": ["darwin", "linux"]}}
---

# FOSMVVM Fluent DataModel Generator

> **Read [`shared/functional-discipline.md`](../shared/functional-discipline.md) before proceeding.** Every rule below derives from it.

Generate Fluent DataModels for server-side persistence following FOSMVVM architecture.

> **Dependency:** This skill uses [fosmvvm-fields-generator](../fosmvvm-fields-generator/SKILL.md) for the Fields layer (protocol, messages, YAML). Run that skill first for form-backed models.

> **API catalog:** check [`../shared/api-catalog/FOSMVVMVapor.md`](../shared/api-catalog/FOSMVVMVapor.md) § Protocols, § Extensions and [`../shared/api-catalog/FOSFoundation.md`](../shared/api-catalog/FOSFoundation.md) § Data before hand-writing helpers.

## Scope Guard

This skill is specifically for **Fluent** persistence layer (typically in Vapor server apps).

**STOP and ask the user if:**
- The project doesn't use Fluent
- The target is iOS-only with CoreData, SwiftData, or Realm
- The user mentions a non-Fluent ORM or persistence layer
- You're unsure whether Fluent is the persistence layer

**Check for Fluent indicators:**
- `Package.swift` imports `fluent`, `fluent-postgres-driver`, `fluent-sqlite-driver`, etc.
- Existing models use `@ID`, `@Field`, `@Parent`, `@Children`, `@Siblings` property wrappers
- A `Migrations/` directory exists with Fluent migration patterns
- Imports include `FluentKit` or `Fluent`

If Fluent isn't present, inform the user: *"This skill generates Fluent DataModels for server-side persistence. Your project doesn't appear to use Fluent. How would you like to proceed?"*

---

## When to Use This Skill

- User asks to create a new model/entity/table
- User wants to add a database-backed type (Users, Ideas, Documents, etc.)
- User mentions needing CRUD operations for a new concept
- Creating the persistence layer for a new entity

## Architecture Context

In FOSMVVM, the **Model** is the center - the source of truth that reads and writes flow through.

See [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md) | [OpenClaw reference]({baseDir}/references/FOSMVVMArchitecture.md) for full context.

### DataModel in the Architecture

```
                    ┌─────────────────────────────────────┐
                    │         Fluent DataModel            │
                    │    (implements Model + Fields)      │
                    │                                     │
                    │  • All fields (system + user)       │
                    │  • Relationships (@Parent, etc.)    │
                    │  • Timestamps, audit fields         │
                    │  • Persistence logic                │
                    └──────────────┬──────────────────────┘
                                   │
              ┌────────────────────┼────────────────────────┐
              │                    │                        │
              ▼                    ▼                        ▼
    ┌─────────────────┐  ┌─────────────────┐    ┌─────────────────┐
    │ ViewModelFactory│  │  CreateRequest  │    │  UpdateRequest  │
    │   (projector)   │  │   RequestBody   │    │   RequestBody   │
    │                 │  │                 │    │                 │
    │ → ViewModel     │  │ → persists to   │    │ → updates       │
    │   (projection)  │  │   DataModel     │    │   DataModel     │
    └─────────────────┘  └─────────────────┘    └─────────────────┘
```

### Fields vs DataModels

**Fields protocol** = Form input (user-editable subset)
- What users type into forms
- Validation, labels, placeholders
- NO relationships, NO system-assigned fields

**DataModel** = Complete entity (Fluent implementation)
- All fields including system-assigned (createdBy, timestamps)
- All relationships (@Parent, @Siblings, @Children)
- Fluent property wrappers, migrations, seeds

**Not all entities need Fields:**
- Session: system auth, no user form → DataModel-only
- Audit records: system-generated → DataModel-only
- Junction tables: pure storage → DataModel-only

---

## File Structure

Each form-backed model requires files across multiple targets:

```
── fosmvvm-fields-generator ──────────────────────────────────
{ViewModelsTarget}/                  (shared protocol layer)
  FieldModels/
    {Model}Fields.swift              ← Protocol + Enum + Validation
    {Model}FieldsMessages.swift      ← Localization message struct

{ResourcesPath}/                     (localization resources)
  FieldModels/
    {Model}FieldsMessages.yml        ← YAML localization strings

── fosmvvm-fluent-datamodel-generator (this skill) ───────────
{WebServerTarget}/                   (server implementation)
  DataModels/
    {Model}.swift                    ← Fluent model (implements protocol)
  Migrations/
    {Model}+Schema.swift             ← Table creation migration
    {Model}+Seed.swift               ← Seed data migration

Tests/
  {ViewModelsTarget}Tests/
    FieldModels/
      {Model}FieldsTests.swift       ← Unit tests

database.swift                       ← Register migrations
```

---

## How to Use This Skill

**Invocation:**
/fosmvvm-fluent-datamodel-generator

**Prerequisites:**
- Model structure understood from conversation context
- Fields protocol exists (if form-backed model) via fosmvvm-fields-generator
- Relationships and system-assigned fields identified
- Fluent confirmed as the persistence layer

**Workflow integration:**
This skill is used for server-side persistence with Fluent. For form-backed models, run fosmvvm-fields-generator first to create the Fields protocol. The skill references conversation context automatically—no file paths or Q&A needed.

## Pattern Implementation

This skill references conversation context to determine DataModel structure:

### Model Type Detection

From conversation context, the skill identifies:
- **Entity purpose** (user data, system records, audit logs, junction table)
- **User input involvement** (form-backed vs system-generated)
- **Fields protocol requirement** (if user edits this data)

### Relationship Analysis

From requirements already in context:
- **One-to-many relationships** (@Parent in DataModel, not in Fields)
- **Many-to-many relationships** (Junction table + @Siblings, NOT UUID arrays)
- **Relationship naming** (self-documenting names, not vague references)

### Field Classification

Based on data source:
- **User-editable fields** (from Fields protocol)
- **System-assigned fields** (createdBy, timestamps, status - DataModel only)
- **Computed relationships** (@Parent, @Children, @Siblings)

### File Generation Order

**If form-backed model (Fields protocol exists):**
1. Fields layer already created via fosmvvm-fields-generator
2. DataModel implementation referencing Fields
3. Schema migration
4. Seed data migration
5. Tests
6. Migration registration

**If system-only model (no Fields):**
1. DataModel struct
2. Schema migration
3. Seed data migration (if needed)
4. Tests
5. Migration registration

### Design Validation

Before generating, the skill validates:
1. **Form requirement** - System-generated entities skip Fields
2. **Relationship patterns** - Junction tables for many-to-many, @Parent for foreign keys
3. **Naming clarity** - Relationships have self-documenting names
4. **Field separation** - User fields in protocol, system fields in DataModel only

### Context Sources

Skill references information from:
- **Prior conversation**: Model requirements, relationships discussed
- **Fields protocol**: If Claude has read Fields protocol into context or just created it
- **Database schema**: From codebase analysis of existing models
- **Migration patterns**: From existing migrations in project

---

## File Templates

See [reference.md](reference.md) for complete file templates with all patterns.

---

## Key Patterns

### Fluent DataModel

```swift
import FluentKit
import FOSFoundation
import FOSMVVM
import FOSMVVMVapor
import Foundation

final class {Model}: DataModel, {Model}Fields, Hashable, @unchecked Sendable {
    static let schema = "{models}"  // snake_case plural

    @ID(key: .id) var id: ModelIdType?

    // Fields from protocol
    @Field(key: "field_name") var fieldName: FieldType

    // Validation messages
    let {model}ValidationMessages: {Model}FieldsMessages

    // Timestamps
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    // CRITICAL: Initialize validationMessages FIRST
    init() {
        self.{model}ValidationMessages = .init()
    }

    init(id: ModelIdType? = nil, fieldName: FieldType) {
        self.{model}ValidationMessages = .init()  // FIRST!
        self.id = id
        self.fieldName = fieldName
    }
}
```

### Relationships (Associated Types Pattern)

**PRINCIPLE: Existential types (`any Protocol`) are a code smell.** Always ask "Is there any other way?" before using them.

For required relationships, use **associated types** in the protocol:

```swift
public protocol IdeaFields: ValidatableModel, Codable, Sendable {
    associatedtype User: UserFields

    var createdBy: User { get set }
}
```

In the Fluent model, `@Parent` directly satisfies the protocol:

```swift
final class Idea: DataModel, IdeaFields, Hashable, @unchecked Sendable {
    @Parent(key: "created_by") var createdBy: User
    // No computed property needed - @Parent satisfies the associated type directly
}
```

In schema: `.field("created_by", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))`

**When to use each pattern:**
- **Associated type** (`associatedtype User: UserFields`): required relationships — `@Parent` satisfies it directly.
- **Optional FK to a table in this database**: `@OptionalParent(key:)` on the model, over a nullable `.references(...)` column. (Optional associated types are not supported on the protocol side; the optional relationship lives on the DataModel only.)
- **Plain `ModelIdType`/`UUID` field**: ONLY for references *outside* this database — an external system's id, a token minted elsewhere — and only with express approval documented at the declaration site, per the firm `ModelIdType Requires Junction Tables Except for @ID` principle. The documentation names its authority (a decision, an issue, an approver) or the condition under which the exception ends — a note that merely describes the reference is not approval. A same-database reference as a raw UUID has no wall: nothing constrains what is written, Fluent cannot load the relation, and the reference dangles silently when the target row goes.

### Migrations

- Schema migration named: `"{Model.schema}-initial"`
- Seed migration named: `"{Model.schema}-seed"`
- Seed is environment-aware (debug, test, release)
- Seed is idempotent: `guard count() == 0`

### Raw SQL in Migrations (PostgreSQL Features)

For PostgreSQL-specific features (tsvector, LTREE, etc.), use SQLKit:

```swift
import Fluent
import SQLKit  // Required for raw SQL

// In prepare():
guard let sql = database as? any SQLDatabase else { return }

let schema = Model.schema
try await sql.raw(SQLQueryString("ALTER TABLE \(unsafeRaw: schema) ADD COLUMN search_vector tsvector")).run()
```

Key points:
- Import `SQLKit` (not just `Fluent`)
- Cast database: `database as? any SQLDatabase`
- Use `SQLQueryString` with `\(unsafeRaw:)` for identifiers
- These columns are database-only (not in protocol or Fluent model)

### Tests

- Use `@Suite` annotation with descriptive name
- Conform to `LocalizableTestCase`
- Test all form fields
- Test validation with `@Test(arguments:)`
- Create private test struct implementing the Fields protocol

**Database-backed tests bind an ephemeral database — never an inherited one.** A migration or
schema test uses `app.databases.use(.sqlite(.memory), as: .sqlite)` (or an equally ephemeral,
test-constructed binding). Never bind a DSN read from the ambient environment (`DATABASE_URL`) —
the test's target then becomes whatever the shell says, and *Tests Must Never Modify Production
Data* is a firm principle (repo `CLAUDE.md`): tests SHALL NOT modify, delete, or corrupt
production data; isolation is constructed, not inherited.

**Test structs with associated types:**

```swift
private struct TestIdea: IdeaFields {
    typealias User = TestUser  // Satisfy the associated type

    var id: ModelIdType?
    var createdBy: TestUser    // Concrete type, not existential
}

private struct TestUser: UserFields {
    var id: ModelIdType? = .init()
    var firstName: String = "Test"
    // ... other required fields with defaults
}
```

---

## Naming Conventions

| Concept | Convention | Example |
|---------|------------|---------|
| Model class | PascalCase singular | `User`, `Idea` |
| Table name | snake_case plural | `users`, `ideas` |
| Field keys | snake_case | `created_at`, `user_id` |
| Enum cases | camelCase | `searchLanguage`, `inProgress` |
| Enum raw values | snake_case | `"search_language"`, `"in_progress"` |
| Protocol | `{Model}Fields` | `UserFields`, `IdeaFields` |
| Messages struct | `{Model}FieldsMessages` | `UserFieldsMessages` |

## Common Field Types

| Swift Type | Fluent Type | Database |
|------------|-------------|----------|
| `String` | `.string` | `VARCHAR/TEXT` |
| `Int` | `.int` | `INTEGER` |
| `Bool` | `.bool` | `BOOLEAN` |
| `Date` | `.datetime` | `TIMESTAMPTZ` |
| `UUID` | `.uuid` | `UUID` |
| Custom Enum | `.string` | `VARCHAR` (stored as raw value) |
| `JSONB` | `.json` | `JSONB` |

> **Decode stored enums honestly.** A raw value read back with a coalescing fallback — `SomeEnum(rawValue: stored) ?? .someCase` — silently rewrites every historical row the current enum no longer names. Decode throwing or into an explicit `.unknown` case; never coalesce into a meaning-bearing category.

> **No identity arrays.** `[UUID]` (`.array(of: .uuid)`) flattens a relation into a column nothing can constrain — element-level foreign keys do not exist on array columns. A many-to-many is a junction table + `@Siblings`; a design that genuinely wants the array (a subset pointer into an already-related aggregate, say) must clear the same express-approval bar as any raw identity field, naming the integrity cost it accepts.

> **Identities hide in JSON too.** A `Codable` struct stored as `.json` whose members reference this database's tables by `UUID` carries the same integrity risk as a raw identity column, one struct-level down. Keep same-database references out of JSONB payloads; relate with wrappers and join.

---

## Framework Surface Since v2.1

This skill's patterns predate several FOSMVVMVapor releases. Before hand-writing container loading, sorting, filtering, guarded writes, or live-refresh plumbing, check the catalog — these already exist:

- **`ContainerDataModel` + `ContainmentRelation`** — declare a container's authorization-bearing relations from its own Fluent `@Children`/`@Siblings`/`@Parent` KeyPaths; cardinality and joins come from Fluent, never restated.
- **`SortableDataModel` + `SortMapping`**, **`FilterableDataModel`** — published sort meanings mapped to database ordering, and query-driven narrowing of container loads.
- **`DataModelWriter` + `WriteTargetProviding`** — the guarded write path the CRUD request doors (`CreateRequest`/`UpdateRequest`/`DeleteRequest` registration) require.
- **Live invalidation** — a Fluent-persisted model's committed saves already nudge `.live` clients with no model-side code; non-Fluent sources pair `registerDependency(on:)` / `invalidateProjections(of:)`.

See [`../shared/api-catalog/FOSMVVMVapor.md`](../shared/api-catalog/FOSMVVMVapor.md) for each one's reach-for entry.

---

## See Also

- [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md) - Full FOSMVVM architecture
- [Architecture Patterns → Encapsulation Is the Precondition](../shared/architecture-patterns.md) — **encapsulation is the precondition SOLID assumes, not a SOLID checkbox** (SOLID degrades silently without it; review it separately). Especially load-bearing for persistence: `ModelIdType` (UUID) belongs only in `@ID()` (raw UUID fields in other columns bypass type safety — the stringly-typing break); use junction tables and typed relations, never a raw string/UUID reference. And a persisted type's encoded/column shape is a *library-internal* invariant — pin it with an internal comment + a forward-compat test, never by publishing it. Repo `CLAUDE.md` → *Encapsulation Is the Precondition SOLID Assumes*.
- [fosmvvm-fields-generator](../fosmvvm-fields-generator/SKILL.md) - For form validation (Fields protocols)
- [fosmvvm-viewmodel-generator](../fosmvvm-viewmodel-generator/SKILL.md) - For ViewModels that project from DataModels
- [reference.md](reference.md) - Complete file templates

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-12-23 | Initial skill based on SystemConfig pattern |
| 1.1 | 2025-12-23 | Added relationship patterns (@Parent), initialization order, imports list |
| 1.2 | 2025-12-23 | Associated types for relationships (not existentials), raw SQL patterns, test struct patterns |
| 1.3 | 2025-12-24 | Factored out Fields layer to fields-generator skill |
| 2.0 | 2025-12-26 | Renamed to fosmvvm-fluent-datamodel-generator, added Scope Guard, generalized from Kairos-specific to FOSMVVM patterns, added architecture context |
| 2.1 | 2026-01-24 | Update to context-aware approach (remove file-parsing/Q&A). Skill references conversation context instead of asking questions or accepting file paths. |
| 2.2 | 2026-08-25 | Raw-identity rules aligned with the junction-table principle: `@OptionalParent` for same-database optional FKs, no `[UUID]` arrays, no same-database ids in JSONB, express-approval documentation for external references, honest enum decodes. Post-2.1 framework surface pointer (Container/Sortable/Filterable DataModel, DataModelWriter, live invalidation). |
