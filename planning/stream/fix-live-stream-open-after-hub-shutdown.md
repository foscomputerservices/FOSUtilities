---
status: open
last_updated: 2026-10-24
origin: code review of PR #171's diff, 2026-10-24; David: create the work items
---

A client that opens a live-invalidation stream after the hub has shut down, but before the listener closes, gets a 200 `text/event-stream` answer that ends at once. The client reads that as a successful open, so it resets its back-off and runs a full dispatcher sweep, then reconnects about once a second for as long as the stopping server accepts connections.

## Goal

A stream open that lands after the hub has shut down is refused, so the client backs off instead of treating it as connected.

Done means: during the window between the hub's shutdown and the listener closing, a client that reconnects gets a non-2xx answer, does not yield `.connected`, does not sweep, and its back-off grows.

## Input

**Window:** `app.asyncShutdown()` runs lifecycle handlers in reverse before the storage teardown that stops a served app's listener. `InvalidationHubShutdown` runs early in that order. The handlers after it include `PushServiceShutdown`, Fluent's, and any app handlers. The server accepts connections throughout.

**Server side:** `InvalidationHub.subscribe()` (`Sources/FOSMVVMVapor/LiveInvalidation/InvalidationHub.swift`) returns an already-finished stream once `isShutDown` is set. The route (`Sources/FOSMVVMVapor/LiveInvalidation/InvalidationRoute.swift`) still answers 200, writes `: open`, then `.end`.

**Client side:** `SSEInvalidationChannel.openAndStream` (`Sources/FOSMVVM/SwiftUI Support/SSEInvalidationChannel.swift`) calls `onOpen()` on any 2xx event-stream answer. `runReconnectLoop` then resets back-off to `initialBackoff` and yields `.connected`, which the dispatcher answers with a refetch of every registered ViewModel. Those refetches run against a server whose databases are shutting down.

**Already handled by the client:** a non-2xx answer is a drop, so back-off grows. A 503 with `Retry-After` is honored as a minimum wait (`DataFetchError.retryAfter`). The client's own comment at the open names the 1 Hz false-connected spin as the thing to avoid.

**Pre-existing in spirit:** before 0.21.1 the same window existed, but subscriptions were never ended, so no stream ended at once and no spin followed.

## Suggested actions

1. Test watched failing first, server side: after `hub.shutDown()`, `GET /invalidations` answers non-2xx. Client side, with the existing reconnect-loop test harness: a server that answers 503 with `Retry-After` during the window produces no `.connected` and a growing back-off.
2. Once the hub has shut down, the route answers 503 with a `Retry-After` instead of opening an empty stream. Decide the `Retry-After` value; the client's `maxBackoff` is the ceiling it will honor.
3. Keep `subscribe()`'s finished-stream behavior for the race where the hub shuts down between subscribe and the first write.
4. CHANGELOG under `[Unreleased]`.

## History

- 2026-10-24 — Opened from the code review of PR #171's diff; David judged it not significant; not scheduled.
