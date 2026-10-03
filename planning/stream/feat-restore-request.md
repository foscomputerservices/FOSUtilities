---
status: open
last_updated: 2026-09-29
origin: session
---

FOS has no `ServerRequest` protocol for restoring a work itemhived model. Fluent has the middleware event, and the DataModel lifecycle work gives the row action a name, but no `ServerRequest` protocol maps to it. An app that soft-deletes a model today has no framework way to bring it back.

Split 2026-09-29 from `feat-datamodel-validation-lifecycle.md` at David's ruling: the row action keeps `restore`; the request protocol waits for a client that needs it.

## Goal

A `RestoreRequest` protocol paired with the restore row action, served by FOS's write route, so a work itemhived model returns through the same request discipline that archived it.

Done means: a request type adopting the protocol routes to a restore on its target; the lifecycle middleware runs its phases with the restore row action; a restore against a model with no delete-triggered timestamp is a boot rejection, the twin of the workhive-route probe; docs, catalog, generator and review check carry it.

## Input

- **Row action exists.** The lifecycle work's phase enum names `restore` (row returns), mapped from Fluent's restore middleware event. See `feat-datamodel-validation-lifecycle.md`, Rulings.
- **Request action does not.** `Sources/FOSMVVM/Protocols/ServerRequest.swift:231` lists show, create, archive, destroy, update, replace after the rename. Restore has no natural HTTP verb; archive and destroy already share DELETE and are told apart by a path suffix, so the same mechanism is available.
- **Boot probe exists.** The workhive route's timestamp probe is the shape a restore route would reuse.
- **No consumer yet.** fosline's cases (recorded in the lifecycle ticket) do not include a restore. Per "defer API until a client exists", this item is parked until one does.

## Suggested actions

1. Wait for a client case. Model it here when it arrives.
2. Choose the HTTP carriage: PATCH with a `/restore` suffix is the leading candidate; naming table entry for David.
3. `RestoreRequest` / `RestoreResponseBody`, `ServerRequestAction.restore`, `ControllerRouting` suffix, a `commitRestore` method in `WriteRoute`, the boot probe.
4. Tests in the two shapes the lifecycle work uses; catalog, generator, review check.

## History

- 2026-09-29 split from the lifecycle work; parked pending a consumer
