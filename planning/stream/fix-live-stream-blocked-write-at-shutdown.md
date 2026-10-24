---
status: open
last_updated: 2026-10-24
origin: code review of PR #171's diff, 2026-10-24; David: create the work items
---

Shutting down the application ends a live-invalidation stream only once its pump comes back around its loop. A pump suspended inside a write to a client that has stopped reading never does, so the server stop still waits Vapor's 10 s timeout and logs "Server stop took too long".

## Goal

Stopping an app ends every open live-invalidation stream, including one whose pump is blocked in a write.

Done means: a served app with one connected client that has stopped reading, after enough emissions to fill its socket send buffer, shuts down within about a second and logs no "Server stop took too long".

## Input

**Trigger:** a peer that dropped off the network without closing its socket, after a burst of emissions filled the server's send buffer for it. An idle client waiting on a heartbeat is already handled by 0.21.1.

**Cause:** `InvalidationHub.shutDown()` (`Sources/FOSMVVMVapor/LiveInvalidation/InvalidationHub.swift`) only finishes each subscription. The pump (`InvalidationRoute.pump`, `Sources/FOSMVVMVapor/LiveInvalidation/InvalidationRoute.swift`) learns of `.hubEnded` only when it next reads from `merged`. While it is suspended in `writer.write`, nothing cancels the pump's task, closes the channel, or unblocks the write.

**Vapor limit (from the 0.21.1 work item):** an async response body runs in an unstructured `Task` that Vapor never cancels, and the writer has no close signal. A blocked write ends only when the socket does.

**Existing test to build on:** `overflowClosesObservedByClient` in `FOSMVVMVaporTests` already sets up a client that stops reading.

**Pre-existing:** the base of PR #171 behaves the same. The 0.21.1 CHANGELOG line "ends every open stream at once" overstates for this corner.

**Also found in the same review (harness, no behavior change):** in `Sources/FOSTestingVapor/ServedFluentTestHarness.swift`, the happy path's inner `do/catch` around `app.asyncShutdown()` duplicates what the outer `catch` already does, because `appShutDown` is set before the call and `startedServer` is still held. The inner catch, the `appShutdownError` local and the rethrow can go.

## Suggested actions

1. Test watched failing first: a served app with one open channel whose client has stopped reading after a burst shuts down within about a second and logs no "Server stop took too long".
2. Give the hub, or the route, a way to end a blocked pump at shutdown: cancel the pump's task from the hub's shutdown, or race each write against a shutdown signal and close the channel on that signal.
3. Fold in the harness teardown simplification above while the harness is open.
4. CHANGELOG under `[Unreleased]`; correct the 0.21.1 wording if it still reads as covering this corner.

## History

- 2026-10-24 — Opened from the code review of PR #171's diff; David judged it not significant; not scheduled.
