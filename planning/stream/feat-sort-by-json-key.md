---
status: open
last_updated: 2026-09-30
origin: fosline (cross-session message, at David's word)
---

A request that sorts a list by a value stored inside a JSON column cannot declare that ordering: `SortMapping` has one factory, by Fluent field, and the ordering Fluent renders for a nested path is numeric on SQLite but textual on Postgres, so the same declaration orders "9" after "10" there.

Minted 2026-09-30 from a consuming project's report. Its case: every money, price, and unit is one `.json` column holding a quantity plus its currency, and every ratio the same way; a list sorted by money (a table by gain, a ledger by amount) needs `SortableDataModel` to order by the quantity inside the column. Nothing on the consuming side is built yet; no urgency.

## Goal

A `SortableDataModel` can declare an ordering by a key inside a JSON column, and that ordering is numeric on every dialect FOSMVVMVapor runs on.

Done means: a `SortMapping` factory beside `.keyPath(_:)` that names a Fluent field and a key inside it, with a test on SQLite and a test on Postgres that each order a three-row fixture holding 9, 10, and 100 as 9, 10, 100 ascending.

## Input

**The one factory** — `Sources/FOSMVVMVapor/Containment/SortableDataModel.swift:46-58`, verbatim:

```swift
/// One database ordering for a ``SortableDataModel`` — build it from a Fluent field KeyPath.
public struct SortMapping<M: SortableDataModel>: Sendable {
    /// Erased at the factory (same discipline as ContainmentRelation): the factory is the only
    /// construction path, so no column strings exist anywhere.
    private let sort: @Sendable (QueryBuilder<M>, SortDirection) -> QueryBuilder<M>

    /// Order by this Fluent field (direction comes from the request's ``SortTerm``).
    public static func keyPath<Field: QueryableProperty>(_ keyPath: KeyPath<M, Field> & Sendable) -> SortMapping<M>
        where Field.Model == M {
        .init { query, direction in
            query.sort(keyPath, direction.fluentDirection)
        }
    }
}
```

The init is private by design (no column strings anywhere), so a consuming project cannot add the factory itself.

**How Fluent renders a nested path** — fluent-kit 1.55.0, `Sources/FluentSQL/SQLQueryConverter.swift:224-225`: a `DatabaseQuery.Field.path` with two or more keys goes through the dialect's `nestedFieldExpression`. SQLite renders `json_extract(column, '$.key')`, which is a number; Postgres renders `(column->'…'->>'key')`, which is text. A `query.sort(.path(...), direction)` is therefore numeric on SQLite and lexicographic on Postgres. The reporter names `DatabaseQuery.Sort.sql(embed:)` (fluent-kit `DatabaseQuery+SQL.swift`) as the entry for a dialect-specific cast.

**Filtering by a JSON key already works portably** through `.path`, and sums over a JSON key are out of scope: the consuming project does its sums in Swift.

## Suggested actions

- Design first, through the planning gate: the factory's name and shape (candidate from the reporter: `.jsonPath(\Model.$field, "key")`), whether the key is a string or a typed key path into the stored `Codable` value, and where the dialect switch lives.
- The key must not be a stringly-typed hole: prefer a key path into the JSON-stored value's type, so the key is minted from a type, or state why a string is the only option here.
- Render per dialect: the nested path where the dialect already yields a number (SQLite, MySQL), a numeric cast on Postgres. Decide the cast's numeric type (the reporter's quantities are `Int128`).
- Tests on both dialects, since the defect is dialect-specific; the Postgres leg needs the CI service the lifecycle work already uses.
- DocC and a catalog entry beside `SortableDataModel` / `SortMapping` (`FOSMVVMVapor.md § Containment`), then the plugin bump.

## History

- 2026-09-30 — minted from the consuming project's message; its data-model document names this ticket beside its money rule (§ 6.14). Awaiting David's scheduling.
