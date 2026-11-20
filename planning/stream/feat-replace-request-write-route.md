---
status: closed
last_updated: 2026-11-20
branch: feat/replace-request-write-route
origin: a consumer session asked whether FOS serves a replace request (2026-11-19); David ruled that FOS adds it first and the consumer then uses it
---

FOS declares `ReplaceRequest` but cannot serve one. `register(request:app:)` has write overloads for Create, Update, Archive and Destroy; a `ReplaceRequest` reaches the read overload and is rejected at boot. An app with a PUT write hand-writes a `ServerRequestController` today.

## Goal

A `ReplaceRequest` registers through `register(request:app:)` and is served by FOS's write route, with the same candidate loading, target resolution, lifecycle phases, invalidation and refresh the other write requests get.

Done means: a request type adopting `ReplaceRequest` registers with one line and its PUT replaces the target; the boot rejection for `ReplaceRequest` is gone; the DocC, the `fosmvvm-serverrequest-generator` skill, the API catalog and the review check stop sending a replace to a hand-written controller; the waiting consumer builds its write on it.

## Input

- **Protocol exists.** `Sources/FOSMVVM/Protocols/ReplaceRequest.swift:26` — `ReplaceRequest`, `ReplaceResponseBody`, action `.replace`.
- **Verb mapping exists.** `Sources/FOSMVVMVapor/Extensions/ServerRequestAction+Vapor.swift:33` maps PUT to `.replace`; `Sources/FOSMVVMVapor/Protocols/ControllerRouting.swift:54` routes it.
- **No write overload, no serve method.** `Sources/FOSMVVMVapor/Containment/WriteRoute.swift` has `serveUpdate`, `serveCreate`, `serveArchive`, `serveDestroy` and their `commit…` twins. Nothing for replace.
- **Boot rejection.** `rejectWriteProtocolAtReadRoute` in `Sources/FOSMVVMVapor/Vapor Support/ViewModelRequest.swift:250` throws `ContainmentError.unsupportedWriteProtocol` for any `ReplaceRequest`.
- **Stale error text.** `Sources/FOSMVVMVapor/Containment/ContainmentError.swift:100` names `DestroyRequest` as unsupported and says only Create, Update and Delete are wired. Destroy is wired.
- **Row action already named.** `Sources/FOSMVVMVapor/Lifecycle/DataModelAction.swift:35` says a replace request arrives as the in-place change action.
- **Current teaching.** The `ServerRequestController` DocC (`Sources/FOSMVVMVapor/Vapor Support/ServerRequestController.swift:27`) uses a replace as its example of a hand-written controller, and `.claude/skills/fosmvvm-serverrequest-generator/SKILL.md:548` says the same.
- **Consumer.** One waiting: a ratified PUT that replaces a whole. Its build is blocked on this. David confirmed 2026-11-19 that the replaced state is a single Fluent `DataModel` row, so `RequestBody: DataModelWriter` fits and the non-model-write deferral (`docs/deferrals.md:135`) stays out of this work item.

## Rulings

David, 2026-11-19:

- **OQ1 — what replace means that update does not.** Not much. It aligns with REST semantics: the request replaces the row as a whole. Nothing enforces that.
- **OQ2 — a PUT whose target does not exist.** Not-found, as update answers. Something that does not exist cannot be updated.
- **OQ3 — fields the body does not carry.** Left alone.

## Suggested actions

1. Design through `fosmvvm-planning`, on the rulings below.
2. DocC first for the new overload, then tests, then `serveReplace` / `commitReplace`, the `register(request:app:)` overload, and the candidate-plan operation.
3. Remove the `ReplaceRequest` branch of the boot rejection; correct the `unsupportedWriteProtocol` text or retire the case.
4. Re-teach: `ServerRequestController` DocC example, the serverrequest generator and test generator skills, the API catalog, the review check, CHANGELOG; bump the plugin version.
5. Tell the consumer session once, at the end, with the release that carries it.

## History

- 2026-11-19 — Opened at David's ruling: FOS adds replace support first; the consumer waits for it.
- 2026-11-19 — David confirmed the consumer's replaced state is one Fluent `DataModel` row.
- 2026-11-19 — David ruled OQ1–OQ8. OQ4: the protocol gains the `ResponseError` constraint. OQ5: `ContainmentError.unsupportedWriteProtocol` stays, for a future action. OQ6: candidates use `.write`. OQ8: the `ServerRequestController` example becomes a token rotation.
- 2026-11-19 — Built on `feat/replace-request-write-route`, uncommitted: overload, `serveReplace`/`commitReplace`, protocol constraint, DocC, tests, generator and test-generator skills, catalog, review check, CHANGELOG, plugin 2.82.0. Catalog audit: 0 stale. Open: the consumer has not been told.
- 2026-11-20 — David ruled no lifecycle-hook test for replace: the shared save already runs the hooks. The `DataModelAction` DocC example no longer sets `createdAt` by hand, which Fluent does itself. Two test files' header years corrected for the current SwiftFormat.
- 2026-11-20 — PR #177 merged; released in 0.22.0; the consumer was told; closed.
