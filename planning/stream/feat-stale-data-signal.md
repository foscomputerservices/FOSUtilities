---
status: open
last_updated: 2026-10-08
origin: David's ruling on feat-bind-error OQ6 (2026-10-08)
---

A screen bound with `bind()` that is already showing data keeps showing it when a later refresh fails. Nothing tells the app, so the user sees old data presented as current.

`feat-bind-error` deliberately leaves this alone: its error binding covers the first load and navigation only.

## Goal

An app can tell when the data on a bound screen has stopped updating, and show that to the user.

Done means: a failed refresh of a screen that is already showing data reaches the app through a public hook, the app can present it without losing the data on screen, and the app learns when updates resume.

## Input

**David, 2026-10-08:** "stale data is something we need to be able to account for. For example, the fostrading app might be showing some sort of trading information that might be changing slowly, but they certainly wouldn't want to see stale data, they'd want to know that the UI isn't updating. I could easily see this happening when roaming between wifi and cellular, or dropping in and out of cellular connections, for example."

**Where the failure is dropped today** — `Sources/FOSMVVM/SwiftUI Support/ViewModelView.swift:492-504`, verbatim:

```swift
    /// A nudge-triggered same-request refresh: re-fetch and swap through the freshness gate, then
    /// re-register the latest response's set so newly-touched containers start listening.
    ///
    /// A failed re-fetch returns `(nil, [])`, so the guard covers the swap AND the registration:
    /// the screen keeps showing its stale data and keeps listening with the prior set —
    /// reregistering to the error path's empty set would deafen it until the next `.connected`
    /// sweep or navigation. A genuinely-empty *successful* response still reregisters to empty.
    private func refreshInPlace() async {
        let (vm, registrations) = await resolveServerHostedRequest()
        guard let vm else { return }
        swapThroughFreshnessGate(vm)
        registerLive(registrations)
    }
```

**Related cases to account for:**

- A live ViewModel whose invalidation connection drops: no refresh is attempted, so no error happens, yet the data stops updating.
- A pushed refresh that fails to decode (`ViewModelView.swift:448-453`, `try?` with a TODO).

**Rulings carried from feat-bind-error:** the error binding is `Binding<Error?>`, cleared at each attempt; cancellation never writes it; retry beyond clear-to-re-fetch is the app's.

## Suggested actions

1. Decide with David whether stale data reuses the `bind(error:)` binding or gets its own signal; the two states differ (an error while waiting vs. old data on screen).
2. Decide whether a dropped live connection counts as stale.
3. Draft the customer DocC first (fosmvvm-planning), then tests, then build.

## History

- 2026-10-08 — Opened at David's ruling on feat-bind-error OQ6.
