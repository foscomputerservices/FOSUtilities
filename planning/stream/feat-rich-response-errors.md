---
status: open
last_updated: 2026-10-05
origin: fosline (layer A builder's ledger, reading 7, relayed 2026-10-05); ruled by David 2026-10-05 (OQ7, "B")
---

When a REST service answers 429 or 503 with a `Retry-After` header, the caller of `DataFetch` cannot learn how long to wait: the wait travels only in the header, and the networking stack throws either the service's decoded error or a bare status, never the wait. More generally, a caller has no way to turn a service's quirky response into a rich error of its own.

Found by fosline's layer A build (2026-10-04): its Binance client needs the wait after a 429 and reads it through its own session wrapper. Ruled 2026-10-05 as a rich error on the existing error path, not as access to the status or headers, plus a hook through which a caller adapts a service's quirks into rich errors of its own.

## Goal

FOSFoundation's networking supports the HTTP standards itself, and lets a caller adapt a service's quirks; either way the caller receives a rich error, and the HTTP status and headers never reach an app.

Done means:

- **The standard:** a public typed error for "the service asked you to wait", carrying the wait as a `Duration`, thrown for 429 and 503 responses that carry `Retry-After`, in both its forms (seconds, and an HTTP date); tests through a mocked session for each form, for a malformed header, and for a 429 without one.
- **The hook:** a caller-supplied hook that inspects the HTTP response and returns a rich error (or nothing, leaving the existing path); tests that a hook's error is thrown, and that without a hook nothing changes.
- DocC with the caller's example for each; a catalog entry.

## Input

**David on the hook, 2026-10-05**, verbatim: "Now, if we need to allow the client of FOSFoudnation's networking stack to provide a hook to inspect the http response and turn it into rich information, we can do that; it doesn't have to be hard coded into FOSFoundation's networking stack.  FOSFoundation should support the HTTP standards, but clients should be able to adapt to quirkiness."

**David's comment on OQ7**, verbatim: "Please be very, very careful here. Maybe this is needed for internal implementation, not sure. But I don't want client applications to turn into HTTP processing apps as that's not rich enough information. That is, standard HTTP response codes are not enough infrormation to present the user with effective actions, they just say stupid things like, "A keyboard error occurred. Press any key to continue." The idea was that the server turns errors into rich errors that are defined by the ServerRequest and then tunneled through the HTTP response and surfaced through FOSFoundation's networking stack and thrown. This also works with standard REST clients, as they often return JSON for errors, which FOSFoundation's networking stack can turn back into rich Errors and thrown."

**Ruled (OQ7):** B, a rich error for the standard case; no public access to the status or headers. The rulings file: `planning/notes/fosline-request-rulings-2026-10-05.md`.

**Where the wait is lost** — `Sources/FOSFoundation/Networking/DataFetch.swift:491-496`, verbatim: a non-2xx status becomes `DataFetchError.badStatus`, and a body that decodes as the caller's error type replaces it, so neither carries the header.

```swift
        } catch let e as DataFetchError {
            if errorType != DummyError.self, let responseData, let resultError: ResultError = try? responseData.fromJSON() {
                throw resultError
            }

            throw e
        }
```

**The status check** — `Sources/FOSFoundation/Networking/DataFetch.swift:515-517`:

```swift
        guard (200...299).contains(httpResponse.statusCode) else {
            throw DataFetchError.badStatus(httpStatusCode: httpResponse.statusCode)
        }
```

**The one call that reads a header today** is `package`: `send(…errorType:capturingResponseHeader:)`, `Sources/FOSFoundation/Networking/DataFetch.swift:367`. It stays `package`.

**The standard:** `Retry-After` (RFC 9110 § 10.2.3) is either a number of seconds or an HTTP date, sent with 429 (RFC 6585) and 503.

## Suggested actions

- Design first, through the planning gate. A service that sends both a JSON error and `Retry-After` (Binance) is the hook's case: its client builds one error carrying both. Decide the order: the caller's hook first, then the built-in standard handling, then today's decode of the error type.
- Decide whether the error is a new case of `DataFetchError` or its own type; it reads as an instruction to the caller ("wait this long"), never as a status code.
- A date in the past or a malformed header yields no wait: the existing error path, unchanged.
- The hook is the caller's adapter, not a raw-response API: it is reached only inside the networking call, and its output is an `Error`. Where it is supplied (per call, or per `DataFetch`) is the planning gate's.
- Names are David's (OQ8, ruled): before building, bring him a naming table with just enough context per name; the error, its member, and the hook go in the naming table.
- DocC first, with the caller's retry loop as the example; then the catalog entry (`FOSFoundation.md § Networking`) and the plugin bump.
- Tell fosline when it ships, so its Binance client can replace the session wrapper with the hook.

## History

- 2026-10-04 — found by fosline's layer A build (its ledger, reading 7).
- 2026-10-05 — OQ7 ruled B at David's word; minted.
- 2026-10-05 — widened at David's word: a caller-supplied hook that turns a quirky response into a rich error, beside the built-in standard handling.
- 2026-10-05 — OQ9 ruled: ships in 0.20.0 with the rest of fosline's request.
- 2026-10-05 — build order ruled by need: 5 of 5 (rulings file, OQ2).
