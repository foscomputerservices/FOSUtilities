---
status: closed
last_updated: 2026-10-03
origin: session
---

FOS declares that a `DataModel` is validatable, documents that storage validates with the same rules as the form, and then never runs that validation on the server. The only enforcement is the write route's body gate. A model has no framework hook for pre-save work, contextual (cross-model) validation, or post-save work, so an app that needs any of those must hand-write a Fluent model middleware per type, which is the pattern FOS is meant to replace.

Minted 2026-09-29 from a review of FOS's existing validation surface against a prior implementation of the full lifecycle. Rulings so far are recorded under Input. No code was changed.

## Goal

A `DataModel` gets, by adopting protocols and nothing else, a boot-registered lifecycle around every Fluent save: prepare, validate the type in isolation, validate the model in context, save, after-save, after-commit. Each step is a defaulted protocol hook. The implementer never writes a middleware, never registers a type by hand, and never forks the framework's middleware to get at a phase it lacks.

Done means: every registered `DataModel` is validated on the server before commit through both validations; a model can do phase-aware pre-save and post-save work through framework hooks with the full middleware context; validation results reach the client in the same shape they have today; the docs that already promise storage-side validation become true; and the open rulings below are ratified rather than inferred.

## Input

### What exists in FOS today

**The contract is one protocol.** `Sources/FOSMVVM/Protocols/ValidatableModel.swift:103`:

```swift
public protocol ValidatableModel {
    func validate(fields: [any FormFieldBase]?, validations: Validations) -> ValidationResult.Status?
}
```

**DataModel composes it in.** `Sources/FOSMVVMVapor/Protocols/DataModel.swift:22`:

```swift
public protocol DataModel: FOSMVVM.Model, ValidatableModel, FluentKit.Model {}
```

**The only Fluent-side helper has no callers and no tests.** `Sources/FOSMVVMVapor/Extensions/Model+Vapor.swift:48`. The `database` parameter is unused and the function awaits nothing. It is a synchronous `validate()` with an inherited signature.

```swift
public extension FOSMVVM.Model where Self: ValidatableModel {
    func validateModel(on database: Database) async throws -> Self {
        if let error = validate() {
            throw error
        }

        return self
    }
}
```

**The write route validates the body, applies, and saves. The target model's own validation is never invoked.** `Sources/FOSMVVMVapor/Containment/WriteRoute.swift:69-83` (update; create at `:90` has the same shape):

```swift
        // 2. Structural gate: a failing validation never reaches apply.
        if let error = body.validate() {
            throw error
        }
        // 3. Load the writer's candidate set (write-verb grants), candidates only.
        let context = try await loadCandidates(for: boundRequest)
        ...
        // 5. Authored apply. 6. Save (the caller invalidates).
        try body.apply(to: target)
        try await target.save(on: db)
```

The save is bare. Only the `.siblings` attach path opens a transaction (see `chore-sibling-create-live-invalidation.md`).

**FOS already occupies the Fluent middleware seam, once, for live invalidation.** `Sources/FOSMVVMVapor/LiveInvalidation/InvalidationEmitMiddleware.swift:35` is an `AsyncModelMiddleware<M: DataModel>`. It is registered automatically at boot by sweeping the model type registry: the container, every contained type, every pivot, one middleware per type. `Sources/FOSMVVMVapor/Extensions/Application+LiveInvalidation.swift:62`. That sweep is the discovery mechanism this work item builds on. A `DataModel` that is neither registered nor contained is invisible to it.

**The result shape is field-addressed.** `Sources/FOSMVVM/Validation/ValidationResult.swift:33`: a `Message` carries `fieldIds: [FormFieldIdentifier]` and a `LocalizableString`. Multi-field messages are supported. Model-level messages (no field) are not. `Validations.replace(with:)` exists at `Sources/FOSMVVM/Validation/Validations.swift:43` and nothing in the templates or DocC uses it; both overwrite `validations.validations` instead.

**The sharing mechanism is the Fields protocol.** The RequestBody and the DataModel both adopt it. The bootstrap template says so (`Sources/FOSMVVMBootstrap/Templates/client-server/Sources/{{PROJECT_NAME}}Server/DataModels/Card.swift.tmpl:15`) and the review skill enforces it as a blocker (`.claude/skills/fosmvvm-review/checks/datamodel.md:52`). The promise those two make is only true for the fields the body sets, and only through the body gate.

**Docs already claim the missing behaviour.** `.claude/skills/shared/api-catalog/FOSMVVMVapor.md:149` sells `validateModel(on:)` as save-time validation. `:502` says the datamodel generator scaffolds it; the generator does not mention it.

**The ValidatableModel DocC example does not compile.** `ValidatableModel.swift:26-101` uses a property that does not exist (`validations.elements`), appends an optional array with `+=`, names a macro that does not exist (`@ValidationModel`), mints a field identity from a string literal, and its summary line says it validates the ViewModel.

**Test coverage.** One write-gate test (`Tests/FOSMVVMVaporTests/Containment/WriteRouteTests.swift:337`) proving the body gate only. Every Vapor fixture's `validate` returns nil. `ValidationsTests` covers `hasError(for:)` only.

### Lessons from the prior implementation

A full lifecycle was built once before on a hand-written Fluent model middleware per type, with a second protocol for cross-model validation. These are the failure modes it exhibited, each of which the design must close.

- **Manual per-type registration forked three times.** Models that needed a delete phase or post-save work abandoned the generic middleware and wrote their own. The phase enum listed five cases; only create and update were ever wired.
- **The Application was threaded through validators so they could do side effects.** Email verification, receipt sending, flag flips, and launch-argument checks lived inside validation hooks because no other hook existed.
- **Cross-model errors had no field to hang on.** Four adopters minted a field name from a string; one borrowed another model's field. Model-level results are the norm at model validation, not the exception.
- **Two field-identity systems drifted on one model.** A model declared a form field for a property and its validator named the same property by the Fluent column key.
- **Accumulation reset at every protocol level.** Each Fields level overwrote the accumulator, so every extender saved, re-appended, and deduped by hand.
- **Field and model validation ran concurrently.** Cross-model queries executed even when the type had already failed in isolation.
- **Model validation short-circuited.** Each rule failed its own future and the join failed on the first, so the user saw one contextual error per round trip while field validation reported everything at once.
- **Warnings aborted saves.** A `.warning` result was thrown through the failure path.
- **Three outcomes were conflated in one channel.** A user-fixable rule with a localized message, a dangling foreign key dressed as a validation with an unlocalized string, and a broken invariant thrown as an internal error all came out of the same hook.
- **Derivation lived inside validators.** Filling derived dates, trimming input, and setting a verified flag happened in validation or in the bespoke middleware because the type had no other hook.
- **Futures plus weak self in every adopter.** If self was gone the validation silently passed.
- **Wrong-hook detection ran at runtime** through an existential cast on first save, not at boot.
- **Error domains were the right idea inside the wrong type.** Validation failures were user-facing: encoded through the localizing encoder so messages arrived localized, logged at info, never sent to crash reporting. Internal failures were the opposite. That policy was carried by a single catch-all error type with a category enum, which is retired by design in FOS; the policy survives as a property of `ValidationError` being its own type.
- **Tests that proved something took two shapes.** Model validation called directly with a phase, asserting on the exact localized message it produced; and save-path tests that assert the throw from `save` carries a specific localized message, covering create, update-of-self (no false positive against its own row), and the same value in two different containers being allowed.

### Consuming client: fosline (unratified)

fosline replied on 2026-09-29 with four cases and a note, sent at David's word. Every one rests on an unratified statement of fosline's own work itemhitecture document, so they are the shape fosline needs, not approved requirements. Its services communicate only through shared DataModels and the typed Fluent operations on them; what an app asks becomes a model that another service acts on and answers with a model of its own.

- **Refusals at the write (cross-model).** A command to the trader must be refused, typed, before it persists, when the trader's own models show the act cannot stand: a coin that is not flat, or a sub-account another stream already holds. Today hand-written in a controller action. Model validation, every failure collected, model-level typed messages.
- **Settings change guarded by state (cross-model).** Some settings of a stream may change only while every coin of the stream is flat; others at any time. Model validation on an `UpdateRequest` of the settings DataModel, the refusal naming the coin.
- **Queue create guarded by prerequisites (cross-model).** A task may be created only when its parent model, with its own dependent model, is already persisted. Model validation at create, typed.
- **Live nudge after commit.** A `DataModel` fosline persists that no registered container declares needs `invalidateProjections(of:)` called after the commit so a live `ViewModel` refreshes. Served by registering that `DataModel` (the `register(_:migration:)` overload) and the after-commit hook, both ruled.
- **Note, not a case: claim by uniqueness.** One service claims a task through a create that wins or loses on a schema uniqueness constraint. fosline wants the violation caught typed at the save as a model-level failure, not as a raw Fluent error. Served by the constraint-violation ruling.

### Rulings (David, 2026-09-29)

All ruled. Nothing in this section is open.

**Validation and lifecycle**

- **Field validation and model validation, intentional.** Field validation validates the type in isolation, possibly through its Fields protocol; the same rules run client-side on the form and again on the DataModel server-side before commit, and the DataModel may add rules for storage-only properties. Model validation validates the model against database state. The boundary: field validation reads only the model's own columns; model validation needs another row.
- **Model-level validation messages** are a first-class shape.
- **Automatic boot registration.** Adopting the protocol brings the type into the fold. No per-type registration call.
- **Delete is a validated phase, and destroy alongside it.**
- **Model validation collects every failure** before reporting; no short-circuit within model validation.
- **Throw is for errors, never validation.** Validation reaches the user only through appended results with localized messages. The two channels are orthogonal.
- **A pre-save hook** exists as a protocol requirement, sequenced before field validation, with all the facilities of Fluent's model middleware: the row action, the database, and the `Vapor.Application`.
- **A post-save hook** exists with the same constraints.
- **Transaction.** The write route runs validate, apply and save inside `liveTransaction`, so model validation's reads and the save see one state.
- **Constraint violations** surface as typed model-level validation results. A middleware option can re-raise a violation as a plain `Swift.Error` where a situation needs it.
- **Warning policy** lives on the type as a defaulted static. Warnings are maybe-blocking through that option.
- **A `DataModel` no registered container declares** gets a registration API (an overload of `register(_:migration:)`), so the boot sweep sees it.
- **Phase is the proposed row action.** Fluent decides the proposed action before any middleware runs, from the call plus whether the model declares a delete timestamp; the hook receives that decision; validation decides whether it becomes the outcome and never chooses among outcomes. Candidate enum, names liked but not yet arbitrated in a naming table: `create` (row appears), `update` (row changes), `archive` (row stays, marked deleted; Fluent's softDelete event), `destroy` (row gone; Fluent's delete event, forced or not), `restore` (row returns).
- **Accumulation is append-only** into the passed `Validations`. No level ever overwrites another.
- **Field identity for non-form properties:** one identity system per model, minted from the type. Adjust what exists if it must.
- **After-save and after-commit are two hooks.** After-save runs in the transaction, may write rows, a throw rolls back. After-commit is side effects only, a throw can only be reported. Live invalidation already sits at after-commit.

**Request-side alignment** (same day, from the row-action naming)

- **Both deletion semantics supported, each named once.** Archive is soft delete only. Destroy is a forced delete on any model. Fluent's fallthrough (plain delete becomes hard on a model with no delete timestamp) is retired from every FOS write route; app code calling Fluent's plain `delete()` directly is outside FOS vocabulary, and the lifecycle middleware reports whichever row action Fluent actually took.
- **Archive on a model with no delete-triggered timestamp is a boot rejection.** Registering a work itemhive route probes the target type with a fresh instance the way Fluent's own `excludeDeleted` does; no timestamp found throws a typed controller error naming the request and model types and the two fixes (add the timestamp, or adopt the destroy request). Same shape and moment as the existing archive-plus-destroy-on-one-URL rejection at `ServerRequestController.swift:73`. A compile-time marker protocol was set aside: it would be a second declaration of a fact the property wrapper already declares, and the two can drift.
- **Rename the request side to match.** `ServerRequestAction.delete` becomes `.archive`; `DeleteRequest` becomes `ArchiveRequest`; `DeleteResponseBody` becomes `ArchiveResponseBody`; the route suffix `"/delete"` at `ControllerRouting.swift:61` becomes `"/archive"`. The DELETE-method disambiguation keeps working. Wire changes twice (Codable case name, URL suffix); pre-1.0, accepted.
- **Remove the six HTTP-method statics** on `ServerRequestAction` (`GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `DESTROY`). Zero callers; `DESTROY` is not an HTTP method; after the rename `DELETE` would return `.archive`.
- **No `RestoreRequest` in this work.** The row action keeps `.restore` because Fluent has the middleware event. The request protocol waits for a client; open work item `feat-restore-request.md`.

## Suggested actions

1. **Rulings: done 2026-09-29.** See Input.
2. **Run the fosmvvm-planning gate.** Design block first, concepts before names, with the naming table as a first-class deliverable and David arbitrating every name. Then the customer DocC for each hook, written before the code. Then tests.
3. **One middleware per `DataModel`, registered by the existing registry sweep.** Extend `registerInvalidationEmitMiddleware`'s discovery, or a sibling of it, so the validation lifecycle middleware is wired for the same set of types with the same one-per-type guard. The Application is captured at boot as the emit middleware captures its registry reader.
4. **Sequence the steps**: prepare, field validation, model validation, `next`, after-save, after-commit. Model validation runs only when field validation passes. Every hook defaulted so a model declares only what it has.
5. **Phase-aware hooks** for create, update, archive, destroy, and restore, mapped from Fluent's five middleware entry points; the row-action enum is the first entry in the naming table.
6. **Extend `ValidationResult.Message`** for model-level messages per the ruling, and settle field identity for non-form properties per the ruling (one identity system per model).
7. **Define accumulation** as append-only per the ruling and make the Fields-protocol composition contract explicit, so a DataModel that adopts Fields and adds its own rules has one documented way to do it.
8. **Retire or rewrite `validateModel(on:)`.** Either it becomes the async body the middleware calls, or it goes, and the catalog entries at `FOSMVVMVapor.md:149` and `:502` follow.
9. **Fix the ValidatableModel DocC example** so it compiles and speaks to the customer, and switch the template and DocC from overwriting `validations.validations` to the ruled accumulation.
10. **Tests.** Middleware runs both validations on every registered type; model validation skipped when field validation fails; every phase reached; model-level messages round-trip to the client as `ValidationError`; a throw from a hook is not a `ValidationError`; boot rejects misconfiguration; a bare `DataModel` with no hooks saves unchanged. Two shapes per rule: the hook called directly with a phase, asserting the exact localized message; and a save-path test asserting `save` throws a `ValidationError` carrying that message, including update-of-self and same-value-different-container as the no-false-positive cases.
11. **Docs and skills.** `FOSMVVMArchitecture.md` "The Shared Validation Contract", the datamodel generator and its reference, the datamodel review check, the API catalog. Add a review rule: validators never mutate.
12. **Request-side rename.** `.delete` → `.archive`, `DeleteRequest`/`DeleteResponseBody` → `ArchiveRequest`/`ArchiveResponseBody`, `"/delete"` → `"/archive"`, the six HTTP-method statics removed, the workhive-route boot probe added beside the existing one-URL rejection, `WriteRoute.commitDelete` split into `commitArchive` (soft delete) and `commitDestroy` (forced). Skills, catalog, review check, templates, tests follow.
13. **Bootstrap template.** The scaffolded DataModel gains nothing by default (hooks are defaulted), but the template's DocC comment at `Card.swift.tmpl:15` becomes true and should say how.

## Open questions

- Does field validation on the server run the Fields rules with `fields: nil` (all fields), or does the write route pass the fields the body touched? All-fields is the safe default; the question is whether a partial update should be allowed to skip rules on columns it did not write.
- Should the middleware run field validation at all when the write came through the route, given the body gate already ran the same Fields rules? Running twice is cheap and closes every non-route save path; skipping requires the middleware to know the write's origin.
- ~~Restore at the request layer~~ → moved to `feat-restore-request.md` (2026-09-29).

## History
- 2026-09-29 minted from a review of FOS's validation surface and a prior full-lifecycle implementation; rulings 1 through 11 of the session recorded, eight items open, no code changed
- 2026-09-29 fosline session answered the offer with four cases and a note (unratified on its side); recorded under Input; open items 2, 4 and 8 now have a live consumer
- 2026-09-29 final pass over the prior implementation's wire mapping, logging policy and tests; two lessons and the test shapes added; nothing further to glean from it
- 2026-09-29 IMPLEMENTED on feat/datamodel-validation-lifecycle: G1–G8 + OQ24 sweep merged, isolated behavioral projection (76 tests) green, full suite green ×7 (501/373/100/63). Open at the review gate: version number (G9), #fieldId identity is property-name-only (as FormFieldIdentifier always was) → document or scope by type; one G8 line added to .claude/CLAUDE.md catalog index; hazard: nested app.liveTransaction test needs two pool connections and timed out twice under parallel agent test runs
- 2026-09-29 OQ20–OQ28 ruled (see plan 3b); OQ21 ratified a/b/c after the end-to-end validation trace (plan 3c: typed error path constraint on write requests, inverted FormFieldView submit guard fixed, replace(with:) model-level semantics); breaking change on Validations.validations accepted; a consuming client's impact assessed (17 + 27 mechanical sites, three dynamic field ids → OQ29 open)
- 2026-09-29 review round 1 (five lenses) → plan Part 3b, OQ19–OQ28; OQ19 ruled: every DataModel registers through register(_:migration:) (the migration call is the registration), raw migrations.add on a DataModel is a review finding; erased middleware set aside
- 2026-09-29 DESIGN CLOSED: all OQs ratified (plan Part 3); OQ15 = issuing identity is a Fields field, no framework change; OQ16 = a projected DataModel must be contained; server-side AppState misnomer split to `chore-rename-projection-appstate.md`
- 2026-09-29 third redline: `validateModel` (not validateRecord), "record" retired everywhere for "model" (FOS has no records), model-level messages ratified, `didCommit` routing ratified; open: which actions model validation covers, whether `validateModel` takes the `LifecycleContext`
- 2026-09-29 plan redlined twice: `DataModelAction` (David's name), hooks grouped in `DataModelLifecycle` with `DataModel` conforming, "tier" retired for field validation / model validation, `#fieldId` macro ratified, model-level messages ride the existing `ValidationError` plus `ModelValidationsView`, credential-to-write is its own work item (ruled b)
- 2026-09-29 the eight open items ruled; item 5 corrected from "outcome" to "proposed row action" (validation gates, never chooses); request-side alignment ruled: archive/destroy each named once, fallthrough retired, archive-route boot probe, `DeleteRequest` → `ArchiveRequest`, HTTP-method statics removed, `RestoreRequest` split to its own work item
- 2026-10-03 CLOSED: merged via PR #157, released in 0.18.0
