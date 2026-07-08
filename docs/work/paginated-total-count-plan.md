# Paginated total-count — implementation plan

> **STATUS: DESIGN GATED, not yet decomposed into tasks.** Gated per `fosmvvm-planning`
> (design → customer DocC → contract tests → rationale). Names arbitrated with David
> 2026-07-07: accessor `totalCount(for:)`, returns bare `Int`, COUNT run always for
> paginated loads.

Surfaces the **full-set size a `PaginatedQuery` window is a view into**, so a client
can render window *position* — a scroll bar over a large table, or "showing 40–65 of
1,204,882". Adds **one** public symbol, a sibling of the existing `records(_:)`.

---

## Motivating client

An iOS **search control against a very large table** — a scrubbable, random-access
sliding window (not forward-only infinite scroll). The window itself already ships:
`Pagination(startIndex:maxResults:)` + `PaginatedQuery` (`PaginatedQuery.swift`) — the
offset window model. The one datum such a UI needs that plain paging does not is the
**total**, to size the scrollbar and place the window.

Offset (not keyset) is correct here *because* the UX is random-access: keyset cannot
jump to an arbitrary index.

---

## Confirmed model (closed with David)

**The only underivable datum is the total.** The client owns the window bounds (it
built the `Pagination`) and holds `records(_:).count`. So the framework must supply
exactly one number: the size of the **authorized** set before the window is applied.

> **Scope boundary (surfaced 2026-07-07).** The containment engine's refinement axes
> today are **sort + window only** (`ContainmentQueryRefinement.swift:57`; filter is
> marked a "future field" at `:56`). There is **no search/filter axis**. So this count
> is the authorized *container* size, window removed — paging, not searching. A real
> search control also needs a **filter axis** (apply a typed query's criteria as a
> `WHERE`), which is a separate, larger piece. When that axis lands, this same count
> path naturally reflects it — no change here.

**Pull, not envelope.** The projection is pull-based — a factory reads its children via
`context.records(handle)` (`ProjectionContext+Records.swift:39`). The total is a
**sibling pull** on the same handle. An envelope of `{children + count}` was rejected:
it would reshape the wire for every paginated collection and force non-search consumers
to destructure. The sibling pull is additive and opt-in.

**Computed in the load phase, not lazily on pull.** `ProjectionContext` holds a
snapshot (`recordsByTuple`); DB work cannot move into projection. The count is produced
during load for each paginated tuple and snapshotted alongside the records. A
non-paginated load pays nothing — its total equals `records.count`, already in hand.

**Always for paginated loads (chosen over an opt-in marker).** Any `PaginatedQuery`
load runs one extra `COUNT`. A pure infinite-scroll consumer that never renders a total
pays for one COUNT it ignores — accepted: search (the real client) always wants it, and
the opt-in marker is deferred until a real no-count consumer appears (defer-until-client).

**Authorization is the one thing that must not be gotten wrong.** The `COUNT` runs
**inside** `authorizedRecords` (`Request+ContainerLoad.swift:96`), against the same
grant-scoped query (`:133-138`), post-grant-filter / pre-window. Beside it,
you leak a total that counts rows the user cannot see.

**Count/window may drift by a row** under concurrent writes (two queries, not one
transaction). Cosmetic for a scrollbar; an accepted trade of the two-query approach.

---

## Public surface (one symbol)

A sibling of `records(_:)` in the same FOSMVVMVapor extension — same target, same
boundary properties, no new boundary question:

```swift
public extension ProjectionContext {
    func totalCount<Record: FOSMVVM.Model>(for handle: LoadRequirement<Record>) throws -> Int
}
```

### Customer DocC (drafted before implementation)

```swift
/// The total number of records the window pages through — read by the SAME handle
/// the factory declared, alongside ``records(_:)``.
///
/// A ``PaginatedQuery`` returns only a window; the View needs the full set's size to
/// render position — a scroll bar over 1.2M rows, or "showing 40–65 of 1,204,882".
/// Pre-compute it in the factory and store it (a computed property would not survive
/// the JSON round trip):
///
/// ```swift
/// static func model(context: Context) throws -> BerthSearchViewModel {
///     .init(
///         berths: try context.records(Self.berths).map(BerthRowViewModel.init),
///         totalMatches: try context.totalCount(for: Self.berths)
///     )
/// }
/// ```
///
/// The count is the **authorized** set the window is a view into — the same records
/// ``records(_:)`` would return without the window. For a non-paginated load it equals
/// `records(_:).count`.
///
/// Throws exactly as ``records(_:)`` does: an unplanned handle throws (never returns
/// 0 — a misconfiguration is not a genuine "no matches"); a handle matching more than
/// one declared load throws.
func totalCount<Record: FOSMVVM.Model>(for handle: LoadRequirement<Record>) throws -> Int
```

### Gate verdict (fosmvvm-planning step 1)

- **Minimal surface** ✓ — one accessor; the total is the only underivable datum.
- **Encapsulation** ✓ — bare `Int`; no sealed representation exposed or published.
- **No stringly-typing** ✓ — keyed by the typed `LoadRequirement<Record>`.
- **One serialization** ✓ — lands as a plain `Int` on the ViewModel; no new format.
- **Boundaries** ✓ — sibling of `records(_:)`; introduces no new boundary question.

No gate hits.

---

## Internal plumbing (no public surface)

1. **Compute** — a `count` closure on `ContainmentRelation` (twin of `load`) runs
   `keyPath.query(on: db).count()` — the base relation query, no `.range()` fetch.
   `authorizedRecords` (`Request+ContainerLoad.swift`) calls it **after the grant check**,
   only when a window is present, and caches the total. (Sort/window don't change a count;
   when a filter axis lands, apply it in both `load` and `count`, in lockstep.)
2. **Carry — no new rails.** The count is keyed by the **same** `ContainerRecordCacheKey`
   as the records (a parallel `containerRecordCountCache`), so it rides the executor's
   already-deposited `tupleCacheKeys` (`PlanExecutor.swift:57`). **`PlanExecutor` /
   `ResolvedRecordLoadPlan` are untouched.** `serve` flattens it via a `countsByTuple()`
   sibling of `recordsByTuple()` into a `ProjectionContext.countsByTuple` snapshot.
3. **Expose** — `totalCount(for:)` resolves the handle to its tuple exactly as
   `records(_:)` does (`plan.tuples(matching:)`), then reads `countsByTuple[tuple]`.
   Same unplanned/ambiguous throws.
4. **Fallback for free** — `countsByTuple()` uses the count-cache entry when present
   (windowed) and falls back to the deposited records' count otherwise (unpaginated) — so
   a non-windowed load's total is its record count, at no extra query.

---

## Contract tests (behavior, never representation)

- **Window + total** — fixture of 100, window `start 40 / max 25` →
  `records(h).count == 25` **and** `totalCount(for: h) == 100`.
- **Authorization respected** — a user authorized for a subset → the count is the
  **authorization-scoped** count, not the raw table size (the leak gotcha, as a test).
- **Unplanned handle throws** (mirrors `records(_:)`).
- **Non-paginated load** → `totalCount == records.count`.
- **Round-trip** — the ViewModel's `totalMatches` survives `try vm.toJSON().fromJSON()`.

All via public paths (`context` accessors, `.stub()`, harness request execution). No
`@testable` for contract, no JSON-shape assertions.

---

## Decomposition handoff

Decomposed into a TDD task plan: **`docs/work/paginated-total-count-tasks.md`**. Six
production touch points (dependency order):

1. `ContainmentRelation.swift` — `count` closure + `memberCount(of:on:)`.
2. `ContainerRecordCache.swift` — `containerRecordCountCache` + invalidation.
3. `Request+ContainerLoad.swift` — compute+cache the total in `authorizedRecords`
   (post-grant-check, when windowed).
4. `ProjectionContext.swift` (FOSMVVM) — `countsByTuple` field + init (`= [:]` default
   keeps existing call sites compiling).
5. `ServeRequest.swift` — `countsByTuple()` snapshot; pass into `serve`'s context.
6. `ProjectionContext+Records.swift` — `totalCount(for:)` accessor + DocC.

Tests: `MemberCountTests` (unit seam) + `TotalCountTests` (end-to-end contract).
