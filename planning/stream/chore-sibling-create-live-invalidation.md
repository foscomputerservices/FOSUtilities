---
status: open
last_updated: 2026-09-29
origin: session
---

The `.siblings` containment create path runs its two writes inside a **bare** `db.transaction { }`, which by FOSMVVM's own routing rule suppresses live invalidation for both writes and logs the warn-once "use `liveTransaction { }`" message. The `.children` create path, which takes no transaction, emits normally. Same user-visible operation, two different live-client outcomes.

Found while reviewing Vapor's Fluent transaction documentation (2026-09-29). No code was changed.

## Goal

A containment create nudges live clients the same way regardless of which relation kind backs it — or, if the asymmetry is intended, the intent is stated where a reader of `ContainmentRelation` will see it and the middleware stops warning about a call site the framework itself owns.

Done means: no FOSMVVM-owned write path trips FOSMVVM's own suppressed-emit warning, and the choice between the two readings below is ratified rather than inferred.

## Input

**The call site** — `Sources/FOSMVVMVapor/Containment/ContainmentRelation.swift:135-144`, verbatim:

```swift
            create: { container, child, db in
                // A new sibling must be persisted before the pivot can reference it; then attach.
                // One transaction: a failed attach must not leave a committed orphan row.
                let to = try child.cast(to: To.self)
                let from = try container.cast(to: From.self)
                try await db.transaction { tx in
                    try await to.create(on: tx)
                    try await from[keyPath: keyPath].attach(to, on: tx)
                }
            },
```

The transaction is correct and load-bearing — a failed attach must not leave a committed orphan row. Nothing here argues for removing it.

**The rule it trips** — `Sources/FOSMVVMVapor/LiveInvalidation/InvalidationEmitMiddleware.swift:68-85`. `route(_:on:)` checks, in order: a `LiveTransactionState.collector` task-local (collect, flush on commit) → `db.inTransaction` (suppress, warn once per model type) → otherwise emit. A bare transaction with no collector installed lands on the middle branch.

**Nothing compensates.** No call site in `Sources/` calls `liveTransaction`, and no containment path calls `invalidateProjections(of:)` afterward. The only `liveTransaction` mentions in `Sources/` are inside its own file and in DocC prose.

**The contrasting path** — `ContainmentRelation.swift:111`, the `.children` create, is a single `create(_:on:)` with no transaction, so its write reaches the third branch and emits.

**A fact that makes the wrap safe** — FluentKit transactions flatten rather than nest. `.build/checkouts/fluent-sqlite-driver/Sources/FluentSQLiteDriver/FluentSQLiteDatabase.swift:92`:

```swift
    func transaction<T: Sendable>(_ closure: @escaping @Sendable (any Database) async throws -> T) async throws -> T {
        guard !self.inTransaction else {
            return try await closure(self)
        }
```

An inner `transaction` on an already-transacting handle runs its closure inline on the same task, so an outer `liveTransaction` keeps its task-local collector visible to the inner bare transaction's writes. Verified for SQLite only — the Postgres and MySQL drivers are not vendored in this checkout, and Vapor's documentation states no nesting contract at all, so this is a driver observation, not a promise.

**Related pinned knowledge** — `Sources/FOSMVVMVapor/LiveInvalidation/LiveTransaction.swift:80-84` records why the collector binds *inside* the closure: FluentKit's async transaction bridges through an unstructured Task (`Database+Concurrency.swift:26`, `eventLoop.makeFutureWithTask`), so a binding around the call never reaches the middleware. Any fix that tries to bind higher up must re-verify against that.

**Two readings, neither ratified:**

1. The containment layer should use `liveTransaction` when a hub is present — the write path is FOSMVVM's own, so it should not require the consumer to know about the wrapper.
2. Write routes are expected to wrap at a higher level, and that wrapping is simply missing — in which case the fix belongs above `ContainmentRelation`, and the relation's bare transaction is correct as written.

## Suggested actions

1. **Rule between the two readings** (David). Everything below assumes reading 1; under reading 2 the site moves but the steps are the same shape.
2. **Reproduce first** — a test in `Tests/FOSMVVMVaporTests/LiveInvalidation/` that performs a `.siblings` create through the containment path with a hub installed and asserts the hub received nothing. It should fail only after the fix. (`LiveTransactionTests.swift:33` is the existing suite for this class of assertion; its bare-transaction suppression test at `:35-55` is the closest prior art.)
3. **Wrap at the ruled site** — swap the bare `db.transaction` for `liveTransaction` where the hub is reachable, keeping the atomicity the comment names. Note that `liveTransaction` already degrades to a plain `db.transaction` when no hub exists (`LiveTransaction.swift:75-77`), so the no-live-invalidation configuration is unaffected.
4. **Re-check the emitted set** — a sibling create mutates the child and the pivot; confirm the flushed union carries both identities and not just the child's.
5. **Sweep for peers** — any other FOSMVVM-owned path that opens a bare transaction around a model write has the same defect. Today `ContainmentRelation.swift:140` is the only one in `Sources/`; this step is to keep that true.
6. **Consider a guard** so it does not regrow — a `fosmvvm-doctor` rule, or a test, that fails when a FOSMVVM-owned source file calls `db.transaction` around a `DataModel` write. Without it, this is a one-time cleanup that decays.

## Open questions

- Does the containment `create` closure have access to the hub at its call site, or does reaching it require threading `Application`/`Request` through `ContainmentRelation`? If the latter, reading 2 gets cheaper and the ruling changes.
- Is the flatten behavior relied upon anywhere else? If a supported driver savepoint-nests instead, an outer-wrap fix silently loses the collector on that driver.

## History
- 2026-09-29 minted from a Fluent transaction-documentation review; finding recorded, no code changed, ruling pending
