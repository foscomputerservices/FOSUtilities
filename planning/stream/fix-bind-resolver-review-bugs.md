---
status: in progress
last_updated: 2026-10-08
origin: feat/bind-error review rounds (David 2026-10-08: "You found good bugs, so those should be fixed too, but in a separate branch")
---

The review rounds on `feat/bind-error` found bugs in the server `bind()` resolver (`VMServerResolverView`, `Sources/FOSMVVM/SwiftUI Support/ViewModelView.swift`) that exist with or without `bind(error:)`. `feat/bind-error-v2` ships `bind(error:)` without them; this item fixes them on their own branch.

## Goal

The server resolver fetches once per load, cancels what it abandons, never lets a stale result overwrite a newer one, and never loses an invalidation or a credential rejection.

## Input

The bugs, each confirmed against the code during review:

- **Double fetch:** `onChange(of: query, initial: true)` re-fetches right after the first load succeeds. With `bind(error:)`, a failure of that second fetch tears down a screen that just loaded.
- **Uncancellable reloads:** query/fragment reloads and live refreshes run in unstructured `Task {}` blocks; a late failure after the screen moved on can still write.
- **Stale live refresh:** a refresh that began before a navigation or invalidation can install the old query's data afterwards (`FreshnessGate` accepts anything over `nil`).
- **Invalidation lost mid-load:** the invalidation `onChange` sits on the bound view, which is absent while loading.
- **Credential rejection dropped:** a live refresh that gets `CredentialRejectedError` prints it and nothing else; `requestErrorHandler` never takes rejections.
- **Reappearance re-fetch** (only if the fix moves fetching into one `.task(id:)`): a same-key re-fetch while data shows must not wipe the data, must go through the freshness gate, and the shared invalidation flag must not get stuck when a screen leaves mid-reload.

Reference: `feat/bind-error` (kept, not merged) tried one design — one `.task(id:)` keyed on query, fragment and attempt; a `loadGeneration` check for refreshes; resolver-level invalidation — and its last review found three new bugs in it (stuck invalidation flag, reappearance skipping the freshness gate, dropped rejection). Read its commits as evidence, not as the design.

## Suggested actions

1. Design the fetch lifecycle first (which events start a fetch, which cancel one, which result may replace which) and show David before code.
2. Hosted tests in `ServerBindHostedTests` style for each bug, watched failing first.
3. One review by David; any second-opinion findings go to him to rule, never applied on their own.

## History

- 2026-10-08 — Opened at David's direction; `bind(error:)` ships first on `feat/bind-error-v2`.
- 2026-10-08 — Built on `fix/bind-resolver` (branched off `feat/bind-error-v2`) at David's "create a branch off of that and add the other fixes". One `.task(id:)` per load key; reappearance of the shown key does not re-fetch; invalidation observed at the resolver and acknowledged at once; `loadGeneration` supersedes stale refreshes; refresh rejections go to the `error:` binding. Hosted tests for the double fetch, superseded reload and mid-load invalidation, each watched failing first. Stale refresh and refresh rejection have no hosted test (they need a live-invalidation channel in the harness).
