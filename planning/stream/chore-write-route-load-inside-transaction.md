---
status: open
last_updated: 2026-09-30
origin: session
---

A write route loads its candidate set on the request's database and then mutates the resolved target inside a different transaction. The row that authorized the write is read on one connection; the write happens on another. Between the two, another writer can change or remove that row, and nothing notices.

Found in review round 2 of the DataModel validation lifecycle work (OQ36, 2026-09-30). No code was changed; the CHANGELOG sentence that overstated what ships was corrected in that work.

## Goal

The candidate load, the target resolution and the write are one state: the load engine reads through the same transaction that mutates the row, so a concurrent change between load and save is either seen by the load or blocked by the transaction.

Done means: a test that mutates the target row between the candidate load and the save observes the write refusing or seeing the change, rather than committing over it.

## Input

**The load engine reads `request.db`** — `Sources/FOSMVVMVapor/Extensions/Request+ContainerLoad.swift:128`, `:146`, `:163`, verbatim:

```swift
        guard let containerRecord = try await descriptor.find(container.id, on: db) else {
```

```swift
            try await records += relation.members(of: containerRecord, on: db, applying: refinement)
```

```swift
                total += try await relation.memberCount(of: containerRecord, on: db, applying: refinement)
```

`db` there is `Vapor.Request.db` — an auto-commit handle. The engine takes no database parameter; every load in the plan resolves it the same way.

**The write's target is resolved outside the transaction that mutates it** — `Sources/FOSMVVMVapor/Containment/WriteRoute.swift:83-97`, verbatim:

```swift
        // 3. Load the writer's candidate set (write-verb grants), candidates only.
        let context = try await loadCandidates(for: boundRequest)
        // 4. Resolve the submitted target against the candidate set (not-yours == not-found).
        guard let selector = boundRequest.query?.target else {
            throw Abort(.badRequest, reason: "\(String(describing: SR.self)) requires a target identity")
        }
        let target: SR.RequestBody.Target = try resolveWriteTarget(selector: selector, context: context)
        // 5. Authored apply. 6. Save (the caller invalidates).
        try await answeringWithRequestError(SR.self) {
            try await liveTransaction { db in
                try body.apply(to: target)
                try await target.save(on: db)
            }
        }
```

`commitCreate` (`WriteRoute.swift:107-131`), `commitArchive` (`:135-151`) and `commitDestroy` (`:154-167`) have the same shape: `loadCandidates` first, `liveTransaction` after.

**What the lifecycle promises on top of it** — `DataModelWriteContext.database` is documented as the request's transaction, and a `validateModel(in:)` hook that queries through it does see the write's transaction. The gap is one step earlier: the candidate set that decided the caller *may* write this row was read before that transaction opened.

## Suggested actions

- Thread the write transaction's database through the load engine: give the container-load entry points a database parameter (defaulting to `request.db` for reads) and pass the `liveTransaction` handle when the load is a write's candidate load.
- Move `loadCandidates` and `resolveWriteTarget` inside the `liveTransaction` closure in all four commit paths, so the load, the resolution, the apply and the save share one connection.
- Decide what the request's container-record cache means once a load can happen on two different handles — a cached candidate set read outside the transaction must not satisfy a load made inside it.
- Add a test that proves a concurrent change between load and save is seen: hold the write open after the candidate load, change (or delete) the target row on another handle, then let the write proceed and assert it refuses or acts on the changed row rather than committing over it.

## History

- 2026-09-30 — Raised as OQ36 in the DataModel validation lifecycle review round 2. Ruled: its own work item; the work corrects only the CHANGELOG sentence that claimed load was inside the transaction.
