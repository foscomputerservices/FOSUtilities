---
status: closed
last_updated: 2026-10-03
origin: session
---

A `ComposableFactory` cannot declare a load for a `DataModel` no container declares, and cannot declare a load for the list of top-level containers, because every `LoadRequirement` roots at one container identity that must declare containment of the load's first hop. Reported by fosline 2026-09-30 at David's word, verified against source on `feat/datamodel-validation-lifecycle`.

Two findings under one cause:

- **Loads of a `DataModel` no container declares.** Documented expectation: OQ16 of the lifecycle work ruled "a projected `DataModel` must be a contained type of a registered `ContainerDataModel`", and `register(_:migration:)`'s DocC says registration does not make a type loadable. The consequence in practice is a synthetic one-row container declaring every ownerless type (fosline's `SystemRoot`), which David is inclined to drop: it models nothing and adds a constant foreign key to every such table. So the ruling stands but its cost is now judged wrong; reopening it is a ruling.
- **Loads of the top-level containers themselves.** Undocumented, pre-existing. The `.apex` root resolves to ONE container identity (`PlanRegistration.swift:342`), and `verifyRootContainment` (`PlanExecutor.swift:276`) requires that container to declare the first hop. Nothing can declare "every `Stream`". This predates the lifecycle work.

## Goal

A factory declares a load whose records have no owning container, with the same declarative shape, the same refinement (filter, sort, pagination), the same authorization question, and the same automatic live registration as a contained load. No schema change for the consumer, no synthetic table.

Done means: the overview factory in the consuming project declares its list of top-level containers and its status models as plan loads; `SupplementalRecordLoading` is no longer the way to reach them; the synthetic root container is deleted; boot checks the declaration; the authorization provider is asked a question that names no container and defaults sensibly.

## Input

- `RootScope` = `.parentRoot | .newRoot(RootSource)`; `RootSource` = `.query | .apex` (`Sources/FOSMVVM/Protocols/RootScope.swift:4-11`).
- `.apex` resolves per request through `useApexContainerResolver` to a registered container's `ModelIdentity` (`PlanRegistration.swift:342`).
- `verifyRootContainment` (`PlanExecutor.swift:276-292`): the bound root's descriptor must declare containment of the tuple's first hop, else `ContainmentError.invalidLoadPlan`; an unregistered namespace throws `unregisteredNamespace`. The root→first-hop edge is deliberately unchecked at boot (`PlanRegistration.swift:108-118`) because the root binds to an identity at request time.
- Authorization is per container identity: `ContainerAuthorization.authorizes(_:ofType:in: ModelIdentity)`.
- Live invalidation: a registered `DataModel`'s own identity is emitted on every write (`InvalidationIdentitySet.staleIdentities`); plan-loaded records register dependencies automatically.
- The lifecycle work's `register(_:migration:)` overload enters an ownerless `DataModel` with `containment: []`, `isContainer: false`.

## Candidates (David arbitrates; names are placeholders)

- **A. A root that names no container.** A third `RootSource` case; `resolveHops` accepts it with zero intermediates when the record type is registered, rejects any `via:`, and can check this edge at boot; the executor runs `Record.query(on:)` with the request's refinements; `ContainerAuthorization` gains a question with no container, defaulting to the apex grant's answer. fosline's sketch. A parallel path beside the container path.
- **B. A virtual apex container.** A registered container type with an identity and no table: its containment relations mean "every row of type X" with no foreign key. `.newRoot(.apex)` keeps working; the apex resolver returns its identity; authorization asks about the apex identity as it does today; `staleIdentities` derives the apex as stale for any of its types, so live refresh of the overview follows. Composes onto the existing general mechanism (apex, per-container grants, containment-derived invalidation) instead of adding a second root kind; requires `ContainerDataModel` to admit a container that is not a `FluentKit.Model`, which is the design cost.
- **C. Keep OQ16, keep the synthetic row.** Rejected by David in spirit already; listed so the rejection is recorded.

## Rulings (David, 2026-09-30)

- **OQ41** OQ16 reopened: a factory must be able to load an ownerless `DataModel` and the list of top-level containers without a synthetic table.
- **OQ42** Its own work item, after 0.18.0 ships; not in PR #157.
- **OQ43** Design through the fosmvvm-planning gate with the authorization question at the center; both shapes (A, B) worked out in the design block.

## Rulings (David, 2026-09-30, on the recut)

- **OQ44** B for finding 1; A rejected.
- **OQ45** A lone system container stands in for the apex resolver; a registered resolver wins.
- **OQ46** `SystemContainer` is a sibling of `Container`.
- **OQ47** The system container's identity is framework-minted with a pinned constant id part.
- **OQ49** More than one system container per application is allowed.
- **OQ50** The record-level axis is restored: record authority first, container extension second.
- **OQ51** D answers finding 2 with the union at one hop.
- **OQ52** Two work items: D first, then B.
- **OQ53–OQ60** ruled as recommended (union rule; one-hop union; subject identity via the provider; `ModelOperation` cases with no create; deny default; `authorizedModel` with a deprecated forwarder; no create at `.grants`; registration threshold warning).
- **OQ48** ruled in part: the `Model` grant family (`ModelAuthorization`, `authorizedModel`, `ModelOperation`, `ModelAuthorizationProvider`; `ContainerOperation` unchanged) and `ContainmentScope` with `.parent`/`.request`/`.application`/`.subject` and the `within:` label, replacing `RootScope` + `RootSource` (David, after `RootAuthority`, `Scope`, `LoadScope` were each rejected: a scope is where authority is anchored, not the authority; single nouns say scope of what; "load" is noun-or-verb and not a data word). `LoadRequirement`'s name is next on his list. Open: `authorizes(_:on:)`, `subjectIdentity(for:)`, `SystemContainer`, `.all(_:)`, `identity`, `register(_:)`.

## Suggested actions

1. Planning gate: design block, authorization question first, both candidates, naming table, ratification list as OQ# lines.
2. Planning gate: concepts before names; the authorization question is the design's center; naming table; customer DocC first; contract tests in the two ruled shapes.
3. Consumer acceptance: the four factories fosline names move to declared loads; the synthetic root is deleted.

## History

- 2026-10-03 CLOSED: D + B merged via PR #159, released in 0.19.0
- 2026-09-30 naming: `ContainmentScope` (.parent/.request/.application/.subject, `within:`) ruled, replacing RootScope+RootSource; carried through plan Parts 1–6; `RootedQuery`→`ScopedQuery` candidate; `useApplicationScope(_:)` RULED (replaces `useApexContainerResolver`); David: `LoadRequirement` to discuss next
- 2026-09-30 Part 6 decomposition written: work item D (`feat/model-authority`, D1–D8) then B (`feat/system-container`, B1–B6), consumer acceptance after both; last six names proceed as candidates
- 2026-09-30 OQ53–OQ60 ruled as recommended; naming rulings: `ModelAuthorization` family (David: "record" retired, stem is `Model`), `RootAuthority`/`.grants` (David: authority is what authorizes); six names remain, then Part 6
- 2026-09-30 plan RECUT on the ruled model (record authority first, container extension second; B + D together; union rule; subject-identity registration; D then B); OQ44–OQ52 ruled; OQ53–OQ60 opened; Parts 4–5 redrawn; awaiting OQ48 + OQ53–OQ60
- 2026-09-30 David's redline (Part 2.1, customer-derived example names) incorporated: examples in Parts 1.3, 2, 4, 5 now use the framework's own Board/Card vocabulary (`Workspace` system container, `Board`, `Card`, `SystemStatus`); the workspace names had been copied from the framework's shipped DocC, which carries the same leak
- 2026-09-30 plan addendum 1.10–1.13: the authorization question has a second axis (record-level, on the container itself) absent from `ContainerAuthorization`; candidate D (the containers the subject's grants name) recorded for finding 2; findings 1 and 2 argued to be two problems; OQ50–OQ52 added; awaiting rulings
- 2026-09-30 design block drafted at `planning/implementation-plans/containerless-loads.md` (Parts 1–5: design, naming table, OQ44–OQ49, DocC drafts, contract tests); recommendation B; awaiting rulings
- 2026-09-30 OQ41 yes, OQ42 yes, OQ43 C (planning gate)
- 2026-09-30 minted from fosline's report; classified (one documented expectation whose cost is now rejected, one undocumented pre-existing gap); two candidates recorded; nothing built
