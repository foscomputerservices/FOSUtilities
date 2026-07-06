# L1 C3 — Authorization Provider Seam Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the reviewed C3 spec — `ContainerAuthorizationProvider`, throwing boot registration, and the opened-generic memoized provider-driven engine entry.

**Architecture:** Two public symbols (protocol + registration), everything else `internal` — zero new `package` symbols. The provider is stored as `any` behind a private StorageKey (unavoidable heterogeneous-storage erasure); one SE-0352 opening at the internal engine entry rebinds the concrete type, and `[P.Authorization]` memoizes under a generic StorageKey — no existential authorization array exists anywhere.

**Tech Stack:** Swift 6, Vapor 4 (Application/Request storage), the shipped C6 engine, Swift Testing + `withFluentTestApp`.

**Spec (normative):** `docs/superpowers/specs/2026-07-04-authorization-provider-design.md` — its DocC drafts, 5 test groups, and access-level table are the contract. WORKTREE: all work in `/Users/david/Repository/FOS/FOSUtilities-model-identity`.

---

## Plan prose — rationale & gotchas

- **Storage `Value` must be `Sendable`** (Vapor requirement): `any ContainerAuthorizationProvider` is (the protocol refines `Sendable`); `[P.Authorization]` is (`ContainerAuthorization` refines `Sendable` + Array's conditional conformance). NO `@unchecked Sendable` anywhere in this slice — the record cache's box is a different situation; do not copy it.
- **SE-0352 opening**: `authorizedRecords(via: provider, …)` with `provider: any ContainerAuthorizationProvider` passed to a `<P: ContainerAuthorizationProvider>` parameter opens implicitly (single occurrence of P). The opened call must be one expression — assign the storage read to a local `any` first, then call.
- **The memo key is generic**: `private struct AuthorizationMemoKey<P: ContainerAuthorizationProvider>: StorageKey { typealias Value = [P.Authorization] }` — one provider per app ⇒ one instantiation; a fresh `Request` has fresh storage, so per-request isolation is free.
- **Error-case payloads are diagnostic strings** (`String(describing:)` on provider types) — never identity.
- **Counting provider for the memoization test**: use `NIOLockedValueBox<Int>` (via `import NIOConcurrencyHelpers`, already a Vapor dependency) inside a `final class`/struct provider — not an actor (the protocol requirement is nonisolated).
- **Test file uses `@testable import FOSMVVMVapor`** with a header comment: test 1 is the contract test (public registration API; the typed-case assertion is a coverage rider); tests 2–5 are coverage of the internal acquisition path, per the corrected testing discipline (the public contract becomes observable at C8's factory). No access level is widened for tests.
- **Registration configure blocks** in engine-driven tests need the harbor migrations + `register(Dock…)` — copy the `configureHarbor` pattern from `AuthorizedLoadEngineTests.swift`.
- **swiftformat**: `docComments` will force `///` on some `//` notes (accepted); `redundantSendable` is disabled (leave it).
- **Do not add**: multi-provider support, memo invalidation, any public load surface, any `package` symbol.

## File structure

| File | Responsibility |
|---|---|
| `Sources/FOSMVVMVapor/Protocols/ContainerAuthorizationProvider.swift` (create) | The public protocol (spec C3.1 DocC verbatim) |
| `Sources/FOSMVVMVapor/Extensions/Application+Containment.swift` (modify) | + `useContainerAuthorizationProvider` (public, throwing), private storage key, internal read accessor |
| `Sources/FOSMVVMVapor/Containment/ContainmentError.swift` (modify) | + `.duplicateAuthorizationProvider(registered:duplicate:)`, `.noAuthorizationProvider`; refresh the stale type-level doc |
| `Sources/FOSMVVMVapor/Extensions/Request+ContainerLoad.swift` (modify) | + internal provider-driven entry + private opened-generic core + generic memo key |
| `Tests/FOSMVVMVaporTests/Containment/AuthorizationProviderTests.swift` (create) | Spec tests 1–5 |
| `docs/superpowers/specs/2026-07-03-authorized-container-data-loading-architecture.md` (modify) | §C3: sketch → full-set-per-request; DECISION-PROPOSED → resolved (provisional) |
| `Sources/FOSMVVMVapor/Containment/ContainerRecordCache.swift` (modify) | maintainer note: one-auth-set contract now structural for the provider-driven path |
| `CHANGELOG.md` (modify) | the two public symbols |

---

### Task 1: Protocol + registration + error cases

**Files:** Create `Sources/FOSMVVMVapor/Protocols/ContainerAuthorizationProvider.swift`; Modify `Sources/FOSMVVMVapor/Extensions/Application+Containment.swift`, `Sources/FOSMVVMVapor/Containment/ContainmentError.swift`; Test `Tests/FOSMVVMVaporTests/Containment/AuthorizationProviderTests.swift` (test 1 only).

- [ ] **Step 1: Failing test** (spec test 1 — contract via public API; typed-case assertion is a labeled coverage rider):

```swift
@Test func duplicateProviderRegistrationThrows() async throws {
    try await withFluentTestApp { app in
        try app.useContainerAuthorizationProvider(EmptyProvider())
        for duplicate in 0..<2 {
            do {
                // attempt 0: same type again; attempt 1: a different provider type
                if duplicate == 0 {
                    try app.useContainerAuthorizationProvider(EmptyProvider())
                } else {
                    try app.useContainerAuthorizationProvider(OtherProvider())
                }
                Issue.record("expected ContainmentError.duplicateAuthorizationProvider")
            } catch let error as ContainmentError {
                guard case .duplicateAuthorizationProvider = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
        }
    } _: { _, _ in }
}
```

with local fixtures `EmptyProvider`/`OtherProvider: ContainerAuthorizationProvider` returning `[TestGrant]()` — construct `TestGrant` only if trivially possible from the fixture file, else a minimal local `NoGrant: ContainerAuthorization` value.

- [ ] **Step 1c:** Write the test file's header comment (the discipline label, verbatim intent): test 1 is the contract test (public registration API; typed-case assertion = coverage rider reading package API); tests 2-5 are coverage of the internal acquisition path via `@testable` (sanctioned — the public contract becomes observable at C8's factory); no access level is widened for tests.
- [ ] **Step 2:** `swift test --filter AuthorizationProviderTests 2>&1 | tail -4` → compile FAIL (`cannot find 'ContainerAuthorizationProvider'`).
- [ ] **Step 3: Implement** — protocol file with spec C3.1 DocC **verbatim**; in `Application+Containment.swift` add (public DocC verbatim from spec C3.2):

```swift
public extension Application {
    func useContainerAuthorizationProvider(_ provider: some ContainerAuthorizationProvider) throws {
        guard storage[ContainerAuthorizationProviderStore.self] == nil else {
            throw ContainmentError.duplicateAuthorizationProvider(
                registered: String(describing: type(of: storage[ContainerAuthorizationProviderStore.self]!)),
                duplicate: String(describing: type(of: provider))
            )
        }
        storage[ContainerAuthorizationProviderStore.self] = provider
    }
}

internal extension Application {
    // Read side of the seam — consumed only by Request's provider-driven entry (same module).
    var containerAuthorizationProvider: (any ContainerAuthorizationProvider)? {
        storage[ContainerAuthorizationProviderStore.self]
    }
}

private struct ContainerAuthorizationProviderStore: StorageKey {
    typealias Value = any ContainerAuthorizationProvider
}
```

`ContainmentError` gains both cases now (`.noAuthorizationProvider` used in Task 2) + diagnostic descriptions; refresh the stale type-level doc line ("Boot-time registration misconfiguration + the members() cast backstop") to cover request-time cases too.

- [ ] **Step 4:** Test 1 PASS; full suite green (416 expected = 415 + 1). swiftformat/swiftlint clean on touched files.
- [ ] **Step 5:** `git commit -m "feat(FOSMVVMVapor): add ContainerAuthorizationProvider + boot registration (C3 seam)"`

### Task 2: Opened-generic memoized engine entry

**Files:** Modify `Sources/FOSMVVMVapor/Extensions/Request+ContainerLoad.swift`; extend `Tests/FOSMVVMVaporTests/Containment/AuthorizationProviderTests.swift` (tests 2–5).

- [ ] **Step 1: Failing tests** (coverage — file already `@testable`; label per plan prose):
  - **scoping**: register a provider vending a dock1-only `TestGrant` (built in `configure` is impossible — grants need the seeded dock's identity, which exists only after seeding in `body`; SOLUTION: the provider queries/derives at request time — use a provider that loads the FIRST dock by name "Dock 1" and mints a grant for it: this also partially covers test 5's async need, but keep test 5 separate per spec). Call the internal entry for dock1 → its 3 berths; for dock2's identity → empty; register-an-empty-provider variant (fresh app) → empty.
  - **memoization**: `CountingProvider` (NIOLockedValueBox counter) — two entry calls on ONE `Request` (Berth then CrewMember types) ⇒ counter == 1; a second minted `Request` + one call ⇒ counter == 2.
  - **no provider**: fresh app without registration → entry throws `.noAuthorizationProvider`.
  - **async provider**: provider awaits a real Fluent query (fetch dock1 row) before minting its grant ⇒ scoping works end-to-end.
- [ ] **Step 2:** FAIL (`no member 'authorizedRecords'` with that arity/labels).
- [ ] **Step 3: Implement** in `Request+ContainerLoad.swift`:

```swift
internal extension Request {
    // The C8 entry: acquisition + scoping in one call (spec C3.3). Opens the stored provider (cheap;
    // no fetch) and forwards to the opened-generic core — generics preserved end-to-end.
    func authorizedRecords(
        of container: ModelIdentity,
        containing containedType: any DataModel.Type,
        for operation: ContainerOperation,
        sortedBy sortTerms: [AnySortTerm] = [],
        pagination: Pagination? = nil
    ) async throws -> [any DataModel] {
        guard let provider = application.containerAuthorizationProvider else {
            throw ContainmentError.noAuthorizationProvider
        }
        return try await authorizedRecords(
            via: provider, of: container, containing: containedType,
            for: operation, sortedBy: sortTerms, pagination: pagination
        )
    }
}

private extension Request {
    // Opened-generic core: memoizes [P.Authorization] once per Request (the structural form of the
    // cache's one-authorization-set contract for this path), then calls the shipped generic engine.
    // Memo box is plainly Sendable (ContainerAuthorization refines Sendable) — no @unchecked here.
    func authorizedRecords<P: ContainerAuthorizationProvider>(
        via provider: P,
        of container: ModelIdentity,
        containing containedType: any DataModel.Type,
        for operation: ContainerOperation,
        sortedBy sortTerms: [AnySortTerm],
        pagination: Pagination?
    ) async throws -> [any DataModel] {
        let authorizations: [P.Authorization]
        if let memoized = storage[AuthorizationMemoKey<P>.self] {
            authorizations = memoized
        } else {
            authorizations = try await provider.containerAuthorizations(for: self)
            storage[AuthorizationMemoKey<P>.self] = authorizations
        }
        return try await authorizedRecords(
            of: container, containing: containedType, authorizedBy: authorizations,
            for: operation, sortedBy: sortTerms, pagination: pagination
        )
    }
}

private struct AuthorizationMemoKey<P: ContainerAuthorizationProvider>: StorageKey {
    typealias Value = [P.Authorization]
}
```

(If the shipped engine's `authorizedBy:` parameter type `some Sequence<some ContainerAuthorization> & Sendable` rejects `[P.Authorization]` for any reason, report BLOCKED — it should not: a concrete array of a Sendable-conforming element satisfies it.)

- [ ] **Step 4:** All AuthorizationProviderTests PASS (5 tests); the existing `AuthorizedLoadEngineTests` untouched-green; full suite green (~420; report actual). swiftformat/swiftlint clean.
- [ ] **Step 5:** `git commit -m "feat(FOSMVVMVapor): provider-driven authorized load — opened-generic per-request memoization"`

### Task 3: Arch/doc sweep + CHANGELOG

**Files:** Modify the arch doc, `ContainerRecordCache.swift` (one comment), `CHANGELOG.md`.

- [ ] **Step 1:** Arch doc §C3 (`docs/superpowers/specs/2026-07-03-authorized-container-data-loading-architecture.md` ~lines 222-245): update the sketched provider comment (lines ~222-234) to the full-set-per-request signature with a one-line drift/memoization rationale + pointer to the C3 spec; change the `[DECISION — PROPOSED]` thin-framework marker (~lines 244-245) to `[DECISION — RESOLVED (thin), 2026-07-04 — provisional pending David's confirmation; see C3 spec D-C3-1]`. Update OQ-L1-2 in §8 the same way.
- [ ] **Step 1b:** In the arch doc's §6 build order, under the C8 item, add a short **"C8 package audit (accumulating)"** list seeding the definitive-statement audit David mandated: every `package` symbol must carry a named cross-target consumer no other level serves, or demote to `internal` ("tests can see it" counts for nothing). Seed items: `ContainmentError`'s `package` level (legacy test-assertion justification — demotion candidate); the `package` `authorizedBy:` engine entry (demote/remove once C8 routes all framework callers); `Application.maxRecordsWarningThreshold`; the general engine-room sweep (`ModelTypeRegistry`, `RegisteredModel`, `members`, refinement, cache). The `ModelIdentity.namespace`/`id` `package` parts carry their definitive statement (cross-module consumer + `public` forbidden by L0 opacity) and survive.
- [ ] **Step 2:** `ContainerRecordCache.swift` maintainer note ("unsupported until C3's provider makes the single set structural" or similar): reword — structural for the provider-driven path (C3); the `authorizedBy:` entry retains the documented contract until the C8 audit.
- [ ] **Step 3:** DoD greps (paste outputs): `grep -rn "package " Sources/FOSMVVMVapor/Protocols/ContainerAuthorizationProvider.swift` → empty; `grep -n "package" Sources/FOSMVVMVapor/Extensions/Request+ContainerLoad.swift` → only pre-existing engine symbols (no NEW package); no Vapor/Fluent in FOSMVVM (standard grep).
- [ ] **Step 4:** CHANGELOG under Unreleased/Added: `ContainerAuthorizationProvider` + `Application.useContainerAuthorizationProvider(_:)` — contract wording only.
- [ ] **Step 5:** `swiftformat . && swiftlint --quiet && swift test 2>&1 | tail -2` all clean/green; `git add -A && git commit -m "docs: resolve arch §C3 to the provider seam; record C3 in CHANGELOG"`

## Final verification (spec DoD)

- [ ] Tests 1–5 mapped and green; full suite green.
- [ ] DocC + examples on both public symbols; internal notes only elsewhere.
- [ ] Zero new `package` symbols (grep evidence); enum-case rider acknowledged in the spec already.
- [ ] Coverage labeling present in the test file header.
- [ ] Arch §C3 + cache note + `ContainmentError` type doc updated; CHANGELOG entry present.
