---
status: open
last_updated: 2026-10-08
origin: feat-bind-error review (OQ17, David 2026-10-08)
---

On Linux, every test target runs in one process, and suites in several targets write the process-wide `SystemVersion.current` (directly, or by constructing an `MVVMEnvironment`). The `.systemVersionAccess` test trait added on `feat/bind-error` serializes only the `FOSMVVMTests` suites, so a Vapor suite can still overwrite the version while `SystemVersionTests` asserts. On macOS each target runs in its own process, so the race does not occur there.

## Goal

No test suite in any target can change `SystemVersion.current` while another suite depends on it, on every platform CI runs.

## Input

- The trait: `Tests/FOSMVVMTests/SystemVersionAccess.swift` (a `TestScoping` trait over an `AsyncSemaphore(maxConcurrentTasks: 1)`).
- Suites that write the version outside `FOSMVVMTests` (found 2026-10-08): `Tests/FOSMVVMVaporTests/Middleware/ClientCredentialMiddlewareTests.swift`, `Tests/FOSMVVMVaporTests/Protocols/ClientCredentialRoundTripTests.swift`, `Tests/FOSMVVMVaporTests/Extensions/Request+FOSTests.swift`, `Tests/FOSFoundationTests/Versioning/SystemVersionTests.swift`.
- Sharing the trait across targets means placing it in a library both test targets depend on, which may add API (FOSTesting is a public product).

## Suggested actions

1. Decide where a cross-target test lock lives without growing a public product's surface (a package-internal test-support target, or `package` access).
2. Apply it to every suite above.
3. Confirm on the Linux CI leg.

## History

- 2026-10-08 — Opened at David's ruling on feat-bind-error OQ17.
