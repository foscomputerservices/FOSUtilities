---
status: open
last_updated: 2026-10-14
origin: fosline session's field report on the live-invalidation stream (2026-10-14); David: open a work item to plan it, not now
---

When the server refuses every live-invalidation stream open with the same 4xx, the client gives no sign. The channel treats each refusal as a drop and keeps reconnecting with back-off, so a misconfigured app looks healthy except that screens never refresh live.

## Goal

A repeated refusal of the stream open is visible to the app's developer without anyone reading the server's log.

Done means: the planned behavior is designed and ruled by David. Building it is a later step.

## Input

**Field report (fosline, FOSTradeInfoService):**

- The server log held 10,357 `GET /invalidations` lines, each refused with `SystemVersionError: Missing system version`. No stream ever opened.
- Nothing on the client showed it. David's overview stayed stale for a day and a half until he restarted the app.
- The cause, the missing version header, is fixed on `fix/sse-channel-system-version` (`e4fc507`). This work item covers the silence, not the cause.

**Where a refusal is handled:** `Sources/FOSMVVM/SwiftUI Support/SSEInvalidationChannel.swift`, `openAndStream`. A non-2xx answer throws `SSEStreamOpenError.badStatus` and `runReconnectLoop` swallows it.

**Constraint:** FOSMVVM has no logging today. Any logger is new surface: what it is, where it writes, and whether apps can route it.

## Suggested actions

1. Decide what "visible" means: a log line, a callback or error the app can observe, or both.
2. Decide what counts as repeated (the same status N times, or any refusal) and how often to report it (once, once per status change, or rate-limited).
3. Present the options to David with their trade-offs; David rules.
4. Then plan the build: DocC first, then tests, then code.

## History

- 2026-10-14 — Opened from fosline's field report at David's request; not scheduled.
