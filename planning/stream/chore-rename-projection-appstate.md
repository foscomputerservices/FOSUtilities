---
status: open
last_updated: 2026-09-29
origin: session
---

`AppState` names two different things in FOS. On the client it is the application's own state, read by `.clientHosted` factories through `ClientHostedModelFactoryContext.appState`. On the server it is a per-request value a registered builder computes from the `Vapor.Request` in the load phase and hands to `body(context:)` as `ProjectionContext.appState`; its DocC example is a signed-in banner. The shared name led a design review on 2026-09-29 to treat the server value as a way a `DataModel` reaches a projection, which it is not.

Minted 2026-09-29 from the DataModel lifecycle design review (`feat-datamodel-validation-lifecycle.md`, OQ16). No code changed.

## Goal

The server-side per-request projection value has a name of its own, distinct from the client's `AppState`, so the two concepts cannot be confused in a signature, a DocC, or a design discussion.

Done means: the generic parameter, the `ProjectionContext` property, the `ResponseBodyFactory` associated type, the registration call, its errors and tests, the catalog entry and the CHANGELOG entry all carry the new name; the client-side `AppState` is untouched; the naming table is David's, decided when the work starts.

## Input

**Server-side sites** (all shipped 2026-07-05 in commit `197d485`, the L0/L1 model-identity work):

- `Sources/FOSMVVM/Protocols/ProjectionContext.swift:32` — `public struct ProjectionContext<Request: ServerRequest, AppState: Sendable>`; `:46` `public let appState: AppState`; inits at `:66`, `:82`.
- `Sources/FOSMVVM/Protocols/ResponseBodyFactory.swift:40` — `associatedtype AppState: Sendable = Void`; `:44` `body<R>(context: ProjectionContext<R, AppState>)`.
- `Sources/FOSMVVMVapor/Containment/AppStateRegistry.swift` — `useAppState(_:builder:)` at `:40`, `appStateBuilder(forTypeIdentifier:)`, `requireAppStateBuilder(appStateType:request:)`, `AppStateBuilder`, `AppStateBuilderStore`; the file name itself.
- `Sources/FOSMVVMVapor/Containment/ContainmentError.swift` — `duplicateAppStateBuilder`, `missingAppStateBuilder`.
- `Sources/FOSMVVMVapor/LiveInvalidation/ProjectionContext+Dependencies.swift`, `Sources/FOSMVVMVapor/Vapor Support/ServeRequest.swift`, `Sources/FOSMVVMVapor/Vapor Support/ViewModelRequest.swift` — resolve and thread the value.
- `Tests/FOSMVVMVaporTests/Containment/AppStateTests.swift`.
- `.claude/skills/shared/api-catalog/FOSMVVMVapor.md` — entry "Register per-request app state for projections — `useAppState`" and the `ProjectionContext` entry's `appState` mention.
- `CHANGELOG.md` ~1585–1610 (historical; the entry stays, a note points at the rename).

**Client-side sites, untouched:** `Sources/FOSMVVM/Protocols/ViewModelFactory.swift:49` `ClientHostedModelFactoryContext<Request, AppState>` and the `@ViewModel(options: [.clientHostedFactory])` macro output.

**Wire impact:** none. The value never crosses the wire; it is built and consumed inside one request.

## Suggested actions

1. Naming table for David: the concept ("a per-request value computed from the request for the projection"), candidates, collision and legibility passes. Decided when this item starts, not before.
2. Mechanical rename across the server-side sites above; the file `AppStateRegistry.swift` follows the new name.
3. Catalog entry and reach-for index line updated; plugin version bumped.
4. CHANGELOG entry for the rename with the one-line migration.

## History

- 2026-09-29 minted from the lifecycle design review; naming deferred to execution by David
