---
status: closed
last_updated: 2026-10-18
origin: David's review of the SSE version-header fix (2026-10-14): the channel's hand-built request is "manual url manipulation"; ruled "A now with B as its own work item"
---

The live-invalidation channel builds its own `URLRequest`: it appends the path, sets `Accept`, and applies the headers itself. Every other client request hands a URL and a header list to `DataFetch`, which builds the request. The channel can't do that because `DataFetch` only decodes one complete response, and the channel reads an open stream (`URLSession.bytes(for:)`).

## Goal

`DataFetch` can open a streaming request, built the same way `send` builds its requests, so the channel no longer builds a `URLRequest` itself.

Done means: `SSEInvalidationChannel` passes a URL and its headers to `DataFetch` and reads the stream it gets back; no `URLRequest` is built in FOSMVVM's live-invalidation code.

## Input

**The hand-built request:** `Sources/FOSMVVM/SwiftUI Support/SSEInvalidationChannel.swift`, `makeRequest(baseURL:systemVersion:credentialHeaders:)`, called from `openAndStream`.

**How other requests are built:** `Sources/FOSFoundation/Networking/DataFetch.swift`, the `package` `send(…capturingResponseHeader:)` (around line 431). It applies the headers, `Accept-Language`, and the default `Accept`, `Content-Type`, and `Accept-Encoding`. `ServerRequest+Fetch.swift` (around line 101) composes `SystemVersion.current.versioningHeaders` with the caller's headers before calling it.

**What the channel needs from a streaming call:** the response status before any bytes (a non-2xx answer is a drop, and a 401 consults the credential provider), then the bytes as they arrive, with cancellation ending the read.

**Constraints:**

- ~~`URLSession.bytes(for:)` is Darwin-only; swift-corelibs FoundationNetworking lacks it. The channel is Darwin-only for that reason.~~ Replaced by OQ2 and OQ6: `openStream` streams on Linux too, and the channel runs everywhere but WASI.
- ~~The mocking support in `URLSession+MockingSupport.swift` should cover the new call too.~~ Replaced by OQ2: contract tests in FOSFoundationTests through a `URLProtocol` stub.
- Whether the new call is `public` or `package` is a design question; access minimalism applies.

## Suggested actions

1. Design the streaming call on `DataFetch`: its signature, what it returns (status plus a byte sequence), and its access level. Write its DocC first.
2. Share the request-building in `send` with the new call instead of copying it.
3. Move `SSEInvalidationChannel` onto it and delete `makeRequest`; keep the `ClientChannelRoundTripTests` passing.
4. CHANGELOG entry if the call is public.

## History

- 2026-10-14 — Opened at David's ruling; option A (compose `versioningHeaders` with the credential headers) shipped on `fix/sse-channel-system-version` in the meantime.
- 2026-10-16 — Design ruled (David, OQ1-OQ8):
  - OQ1: `package`.
  - OQ2: one cross-platform path. A streaming session FOSFoundation owns, built from the caller session's configuration; its data delegate feeds each call's stream and forwards TLS challenges to the caller session's delegate, so `URLSession.session(config:mutualTLS:)` pinning holds. Contract tests in FOSFoundationTests through a `URLProtocol` stub.
  - OQ3: `openStream(from:headers:locale:)`.
  - OQ4: shares `send`'s request building and response check; a wrong-type 200 is a drop.
  - OQ5: CHANGELOG Changed line on the stream's behavior; the `package` call is not named.
  - OQ6: Linux live invalidation in this work item: the channel and `MVVMEnvironment`'s default channel lose their Darwin guards; CHANGELOG Added line.
  - OQ7: returns `AsyncThrowingStream<Data, any Error>`.
  - OQ8: DocC as drafted.
  - Linux tests run in CI (the Linux job already runs `swift test`; the new tests and the channel's tests are not Darwin-guarded).
  - Verified on Linux (swift:6.4.0-resolute): a session-level data delegate receives the response first, then each chunk as sent, keeping nothing; per-task delegates receive no body for plain data tasks.
- 2026-10-17 — Built on `feat/datafetch-streaming`; macOS and Linux full suites green. Further rulings (David):
  - OQ9: the invalidation route tests read through `openStream` and run on Linux. OQ10: the L2 spec bullet amended. OQ12: `retryAfter` in the Throws list.
  - OQ14 A: server-trust forwarding tested on Apple platforms, plus direct `MutualTLSSessionDelegate` tests; FoundationNetworking has no server-trust challenge.
  - Review findings F1-F35: every recommendation applied; a streaming session refuses challenges once its caller session has lost its delegate.
  - OQ15/OQ16: a failed check cancels through its own `task.cancel()`; `onTermination` is set only after the check passes, so `failedCheckEndsTheRequest` tests it.
  - OQ17: invalidating the session does not end an open stream; stated in DocC. OQ25 A: the buffer stays unbounded; DocC says read promptly.
  - OQ18: the served-test example streams from a route it registers itself, no longer the frozen path.
  - OQ21/OQ22: `Continuations`, `shared(forwardingTo:)`.
  - OQ23: freeing a `URLSession` after an HTTPS request still aborts on Linux under Swift 6.4, even after invalidation; the process-wide registry stays, evidence in the `StreamingSession` comment.
  - OQ24: the channel waits at least as long as a Retry-After answer asks.
  - OQ20: CI runs no package tests on macOS, and `ServerBindHostedTests` fails about 1 in 20 full runs on main too; both moved to `chore-macos-ci-test-leg.md`.
- 2026-10-18 — PR #170 merged (CI fix `f8c9da2`: the reconnect-loop test harnesses yield their thread, so a 4-vCPU runner cannot livelock); released in 0.21.0; closed.
