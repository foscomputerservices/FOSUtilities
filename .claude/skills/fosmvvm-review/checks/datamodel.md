---
area: datamodel
generator-skill: fosmvvm-fluent-datamodel-generator
where:
  - "Sources/**/DataModels/**/*.swift"
  - "Sources/**/Models/**/*.swift"
  - "Sources/**/Migrations/**/*.swift"
  - "Sources/**/*Migration*.swift"
  - "Sources/**/database.swift"
  - "Sources/**/databases.swift"
---

# DataModel Checks

The positive pattern lives in the `fosmvvm-fluent-datamodel-generator` skill. The Model is the center of the architecture — the source of truth reads and writes flow through — and these checks are about identity leaking out of `@ID`, the form contract diverging from storage, and the schema drifting from the model that writes to it.

## Reviewer Guidance

- **Resolve types by conformance, not by name — or by prose.** A DataModel is a type conforming to `DataModel` (FOSMVVMVapor) or Fluent's `Model`, wherever it lives and whatever it is called. Trust the conformance over the DocC: a stale comment claiming "this model uses `Model` (not `DataModel`)" beside a `DataModel` conformance has been seen in the field. `ModelIdType` is a typealias for `UUID` — resolve the alias; the two spellings are one type.
- **Not every entity has Fields, and that is correct.** Session records, audit logs, and junction tables are system-only — no user form, no Fields protocol. Do NOT recommend inventing a Fields protocol for an entity no form edits. The discriminator when an entity is written by requests: does the request body carry *user-entered field values* (Fields required) or *operation parameters* (bare DataModel is correct)? A session-close request is operational; a rename request carrying a user-typed `name` is a form edit.
- **A junction table is the prescribed shape for many-to-many, not a workaround.** Do NOT recommend "simplifying" `@Siblings` + junction into a `[UUID]` array column — that is the exact defect `modelid-outside-id` exists to catch.
- **The contract-side twin lives in `fields`.** An identity requirement (`var id: ModelIdType? { get set }`) on a Fields *protocol* is `fields-carry-no-identity`'s finding, not this area's — do not re-report it here, but when you see it, say the pairing out loud: the protocol requirement is what forces adopters to carry the identity.
- **This area is macOS/Linux server code.** The pinned FOSUtilities version governs which protocols exist (`ContainerDataModel`, `SortableDataModel`, `FilterableDataModel`, `DataModelWriter` arrived across 0.4.0–0.10.0); check the pin before flagging their absence, per the dispatch prompt's version-floor rule.

## Check: modelid-outside-id

**Severity:** blocker
**What:** Identity appears in exactly one place on a DataModel: the `@ID(key: .id)` property. Every other identity-bearing stored field — `ModelIdType`/`UUID` (one type; resolve the alias), optionals and collections of them, and identities smuggled in other clothes (see Detection) — requires express approval and documentation at the declaration site (the repo's firm `ModelIdType Requires Junction Tables Except for @ID` principle). Relationships ride the typed wrappers — `@Parent`, `@OptionalParent`, `@Children`, `@Siblings` with a junction table — which give Fluent the join and the database the foreign-key constraint. A raw identity column has no wall: any value can be written into it, the database enforces nothing, and the reference silently dangles when the target row goes.
**Anti-pattern:**
```swift
final class ToolCallRecord: DataModel, @unchecked Sendable {
    @ID(key: .id) var id: UUID?
    // NOTE: relationship disabled during migration; restore later.
    @OptionalField(key: "session_id") var sessionId: UUID?   // same-database FK as raw UUID
    @Field(key: "tag_ids") var tagIds: [UUID]                // many-to-many flattened into an array
}
```
**Detection:** For each DataModel (by conformance), list stored properties whose type is `ModelIdType`/`UUID` or an optional/collection of either. Exempt the `@ID(key: .id)` property — under either spelling. Then widen past the obvious type list, because the smuggled forms carry the same risk and escape a type-keyed scan:

- A `Codable` struct stored as a `.json` column whose members include identities referencing tables in this database.
- A `String`-typed field or dictionary key that holds an identity (a UUID-string key set, a `conversationId: String`).

For every hit, decide which side of the principle it is on:

- **The express-documentation bar.** The principle allows approved, documented exceptions. Documentation that clears the bar names its authority — a decision, an issue, an approver — or states a condition under which the exception ends. A comment that merely *describes* the reference ("the session this belongs to") is not approval, and **a documented deferral whose stated milestone has passed is drift, not an exception** — a "will be restored in R2.2" note outliving R2.2's ship date is precisely the finding.
- **Legitimate shapes** are references *outside* this database: an external system's id, an opaque token minted elsewhere. Those still deserve the documentation, but the finding, if any, is the missing note — say so at warning tone inside the report text.
- **The array form** (`[UUID]`, an id-keyed dictionary) is a flattened relation. The junction table with `@Siblings` (or a child table) is the remedy; the only path past it is the same express-approval bar, and a design note claiming the exception must name the integrity cost it accepts — element-level foreign keys do not exist on array columns, so nothing constrains the members. An array with a documented design decision but no named integrity tradeoff has not cleared the bar.

**Say what the raw column costs, from the migration — and name the right remedy site.** No `.references(...)` on the column means no integrity at all; with `.references(...)` the database constrains it, but relation loading is still unavailable because loading comes from the *wrapper* (`@Parent`/`@OptionalParent`), not from the constraint. And when the original migration runs before the referenced table exists in the migration order, the constraint cannot be added there — the remedy is a follow-up migration, so point the finding at that, not at the original file.

## Check: datamodel-adopts-its-fields

**Severity:** blocker
**What:** A form-backed entity's DataModel adopts its Fields protocol. The Model implements Fields and contains more — system fields, timestamps, relationships — but the user-editable subset comes from the one shared contract, so storage validates with exactly the rules the form and the RequestBody validate with. A model that restates the properties without the conformance has forked the contract; an entity edited by users with no Fields protocol anywhere has no contract at all — every `validate` on the path returns nil, and nothing anywhere bounds what a user can store.
**Anti-pattern:** A model whose DocC says its `name` is user-edited, written by an `UpdateRequest` whose RequestBody carries the user-typed string — and no `{Entity}Fields` protocol exists; both the RequestBody's and the model's `validate` return `nil`.
**Detection:** Two directions, and they need each other:

1. **From Fields:** for each Fields protocol in the shared module, find the DataModel persisting that entity (match by the entity, not the name — the model whose schema the entity's factory and write requests use). Flag a model that stores the protocol's properties without declaring the conformance.
2. **From the model:** a DataModel with no Fields protocol is a hit only when some request body elsewhere carries *user-entered field values* for it — apply the guidance discriminator: user-entered values mean a form contract is owed; operation parameters (close, advance, retry) do not. With no user-editing surface anywhere, the entity is system-only and correct as a bare DataModel.

When the conformance exists, spot-check that it is real: the model's stored properties satisfy the protocol requirements directly (Fluent's wrappers witness them — `@Field var content: String` satisfies `var content: String`), not through shadow computed properties copying values around.

**Scale the remedy to the surface.** One user-editable field means a one-field Fields protocol — small contract, same principle. State the minimal shape in the finding so a single inline-rename entity is not read as demanding a full form apparatus.

## Check: schema-matches-the-model

**Severity:** blocker
**What:** The model and the *net* result of its migration sequence agree, and every migration is registered. Every wrapper key on the model has a column in the net schema and vice versa; a drifted key string compiles clean and fails at runtime with an opaque SQL error, and an unregistered migration means the table never exists at all.
**Anti-pattern:** `@Field(key: "user_name")` beside a migration creating `"username"`; a `{Model}+Schema.swift` never added in `database.swift`; a column created by the initial schema whose wrapper was removed, with no migration dropping it.
**Detection:** For each DataModel, collect the key strings from its property wrappers (`@ID`, `@Field`, `@OptionalField`, `@Parent(key:)`, `@OptionalParent`, `@Timestamp`, `@Enum`, `@Siblings` through its junction model). Compute the schema as the **net of the full registered migration sequence** — creates, alters, and drops, applied in registration order — not any single file. Two subtleties the field has already produced:

- **Dialect-forked migrations fork the net schema.** A migration that guards on the SQL dialect (`postgresql`-only drops, say) leaves a different net schema on the test dialect than in production. When a column is dropped on one dialect and survives on another, that divergence is itself the finding — name both nets.
- **Data-preservation columns are exemptible at the same bar as `modelid-outside-id`** (ratified 2026-08-25). A Fluent-created column no wrapper reads, documented at its migration site as deliberately retained for existing data, is exempt *while its stated plan is live*; a retention note whose restore-or-remove milestone has passed is the drift finding, not an exemption. Raw-SQL (SQLKit) database-only columns — search vectors and the like — are deliberately invisible to the model and are not mismatches; the generator's own pattern says so.

Then confirm each migration type is registered (`app.migrations.add(...)`, conventionally `database.swift`); flag one that never is. **Conditional registration is acceptable when it is deliberate** — seeds gated on non-release environments are the generator's own pattern; registration gated on something that looks accidental is the finding.

## Check: migration-honors-the-fields-contract

**Severity:** warning
**What:** Where the schema and the Fields contract describe the same property, they agree on what must exist: a field the Fields protocol requires (`.required(value: true)` on its FormField, non-optional in the protocol) is `.required` in its column, and an optional protocol property's column does not demand what the contract lets a user omit. This is agreement, not duplication — the fields area's `validation-not-duplicated-downstream` already establishes that `.required` on a column is storage integrity (correct here), while restating a *length or range* in the schema is the duplication to flag there.
**Anti-pattern:** A Fields protocol with `var value: String { get set }` (non-optional) and a `.required(value: true)` FormField — while the migration declares the `value` column without `.required`. A row can now exist that no form could have produced, and its decode into the non-optional `@Field` fails at read time.
**Detection:** For each DataModel adopting a Fields protocol, walk the protocol's non-optional properties and required FormFields against the net schema's columns: flag a required field whose column lacks `.required`, and an optional protocol property whose column is `.required` with no default (the write path fails on legitimate nil). For enum-typed Fields properties, confirm the column stores what the enum writes (raw-value type agreement). The Fields protocol is authoritative for user-editable semantics, the migration for storage shape.

## Check: stored-enum-decodes-honestly

**Severity:** blocker when the fallback is a meaning-bearing case; warning when it is an explicit unknown/none case
**What:** A raw value stored in a column and decoded with a coalescing fallback — `SomeEnum(rawValue: stored) ?? .someCase` — silently rewrites every historical row whose value the current enum no longer names. No decode error, no log line: the row simply *means something else now*. This is how a renamed or removed case strands data invisibly, and it is statically visible at the decode site even though the stranded rows are not.
**Anti-pattern:**
```swift
var signalType: GovernanceSignalType {
    GovernanceSignalType(rawValue: signalTypeRaw) ?? .actionBias   // history coerced to a real category
}
```
**Detection:** For each DataModel storing an enum as a raw value — through `@Enum`, or a `String`/`Int` field paired with a computed decode — find the decode path and its failure posture. Flag `?? .meaningBearingCase` at blocker: unknown historical values become a live business category. An explicit `?? .unknown` (a case that exists to mean "not recognized") is the tolerant-reader pattern done honestly — warning at most, and only when nothing downstream treats `.unknown` as a real category. A throwing or optional decode that surfaces the mismatch is correct and is not a hit. Applies to every DataModel, Fields-backed or bare — the field evidence for this check came from bare models.
