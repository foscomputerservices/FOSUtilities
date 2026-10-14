---
status: open
last_updated: 2026-10-14
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

- `URLSession.bytes(for:)` is Darwin-only; swift-corelibs FoundationNetworking lacks it. The channel is Darwin-only for that reason.
- The mocking support in `URLSession+MockingSupport.swift` should cover the new call too.
- Whether the new call is `public` or `package` is a design question; access minimalism applies.

## Suggested actions

1. Design the streaming call on `DataFetch`: its signature, what it returns (status plus a byte sequence), and its access level. Write its DocC first.
2. Share the request-building in `send` with the new call instead of copying it.
3. Move `SSEInvalidationChannel` onto it and delete `makeRequest`; keep the `ClientChannelRoundTripTests` passing.
4. CHANGELOG entry if the call is public.

## History

- 2026-10-14 — Opened at David's ruling; option A (compose `versioningHeaders` with the credential headers) shipped on `fix/sse-channel-system-version` in the meantime.
