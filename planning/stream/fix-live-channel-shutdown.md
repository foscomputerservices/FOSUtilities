---
status: closed
last_updated: 2026-10-18
origin: fosline, relaying David ("close this issue"), 2026-10-18, after the 0.1.926 release stop
---

A served app with open live-invalidation channels cannot stop promptly: Vapor logs "Server stop took too long" and the stop waits on each channel's 15 s heartbeat.

## Goal

Stopping an app ends every open live-invalidation stream at once, so a stop takes what the request drain takes.

Done means: a served app with one open channel shuts down within about a second and logs no "Server stop took too long", in production order and under `withServedFluentTestApp`.

## Input

**Seen twice on FOSMVVMVapor 0.21.0 (fosline 0.1.926):** in production, the release stop logged `Could not stop HTTP server: Abort.500: Server stop took too long.` and the stop step took 12.2 s (about 2 s before the apps' channels opened). In fosline's test `Tests/FOSTradeDataModelsTests/LayerDModelsTests.swift` ("WI-5, AR29: ..."), about 10 s of the test's 16.6 s is Vapor waiting to stop the server.

**Cause:** nothing ends the hub's subscriptions at shutdown. `InvalidationHub` (`Sources/FOSMVVMVapor/LiveInvalidation/InvalidationHub.swift`) never finishes them, and the pump (`InvalidationRoute.swift`) learns a client is gone only when a write fails, at the next heartbeat. Vapor's server stop waits at most 10 s (`HTTPServer.swift`, `shutdownTimeout`).

**Vapor's order:** `app.asyncShutdown()` runs lifecycle handlers before storage teardown, which stops a served app's server (`ServeCommand`). `withServedFluentTestApp` stops the server first, then the app, so a lifecycle handler alone does not reach it.

**Vapor limit:** an async response body runs in an unstructured `Task` that Vapor never cancels when the client disconnects, and the writer has no close signal. A gone client is noticed only by a failed write.

**Ruled (David, 2026-10-18):** the heartbeat interval stays internal until a customer has a specific requirement to view or set it (OQ6).

## Suggested actions

1. Tests watched failing first: a served app with one open channel (client connected, and client gone) shuts down within about a second and logs no "Server stop took too long"; a subscription made after shutdown ends at once.
2. The hub ends every subscription and refuses new ones at shutdown, through a lifecycle handler installed by `useLiveInvalidation(on:)`.
3. `withServedFluentTestApp` shuts down in production's order: the application, then the server it started.
4. Drop the shortened heartbeats that existing tests set only to speed up teardown.
5. CHANGELOG under `[Unreleased]`; tell fosline the tag once released.

## History

- 2026-10-18 — Opened from fosline's report; David ruled OQ6 (heartbeat internal), OQ7 (before the macOS CI leg), OQ8 (this branch).
- 2026-10-18 — Fixed on `fix/live-channel-shutdown`: the three new tests failed first (stop ~10 s, "Server stop took too long" logged; a post-shutdown subscription never ended) and pass after (stop ~37 ms). Nine teardown-only heartbeat overrides dropped; `FOSMVVMVaporTests` 449/449 green.
- 2026-10-18 — PR #171 merged (CI fix `219577a`: the shutdown tests time only the stop, not the boot before it); released in 0.21.1; closed.
