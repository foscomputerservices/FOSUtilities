---
status: open
last_updated: 2026-10-05
origin: fosline (layer A builder's ledger, reading 18, relayed 2026-10-05)
---

A test that fetches through FOSTesting's `MockURLSession` also sends the real request to the network: the mock answers its completion handler, then returns a real `URLSession.shared` task, and `DataFetch` calls `resume()` on it.

Found by fosline's layer A build (2026-10-04), which works around it with its own inert `URLSessionProtocol` conformer. Confirmed in this repo 2026-10-05.

## Goal

A test through `MockURLSession` never touches the network.

Done means: the returned task does nothing when resumed, on every platform FOSTesting builds for, with a test that fails if a mocked fetch reaches the network.

## Input

**The mock** — `Sources/FOSTesting/MockURLSession.swift:34-48`, verbatim:

```swift
    public func dataTask(
        with url: URL,
        completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {
        completionHandler(data, response, error)
        return URLSession.shared.dataTask(with: url)
    }

    public func dataTask(
        with request: URLRequest,
        completionHandler: @escaping (Data?, URLResponse?, (any Error)?) -> Void
    ) -> URLSessionDataTask {
        completionHandler(data, response, error)
        return URLSession.shared.dataTask(with: request)
    }
```

**The resume** — `Sources/FOSFoundation/Networking/DataFetch.swift:417-436`: `urlSession.dataTask(with: urlRequest) { … }.resume()`.

## Suggested actions

- Rulings this item waits on are numbered in `planning/notes/fosline-request-rulings-2026-10-05.md`.
- Ruled (OQ6): fixed as a chore.
- Return a task that does nothing when resumed; `URLSessionDataTask()`'s initializer is deprecated on Apple platforms, so pick a construction that builds without warnings on Darwin and on Linux (FoundationNetworking).
- A regression test that proves no request leaves the process.

## History

- 2026-10-04 — found by fosline's layer A build (its ledger, reading 18).
- 2026-10-05 — confirmed in this repo and minted.
- 2026-10-05 — OQ6 ruled: fixed as a chore.
- 2026-10-05 — OQ9 ruled: ships in 0.20.0 with the rest of fosline's request.
- 2026-10-05 — build order ruled by need: 4 of 5 (rulings file, OQ2).
