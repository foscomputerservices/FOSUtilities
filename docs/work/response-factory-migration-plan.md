# RefreshRequest removal — implementation plan

> **STATUS: IMPLEMENTED.** All units landed on `spec/model-identity-live-invalidation`;
> suite 553 green, swiftlint 0. `ProjectionContext` additionally shed `appVersion` + its
> vestigial `ViewModelFactoryContext` conformance, and its `plan` optionality is hidden
> behind two intent-revealing inits (data-bearing vs zero-data). The typed `records(_:)`
> lives in a FOSMVVMVapor extension (`ProjectionContext+Records.swift`). `DestroyRequest`
> aligned to the family (`ResponseBody: DestroyResponseBody`).

Removes `RefreshRequest` from the write protocols by **generalizing the existing
body-side factory** so one `ResponseBody` can be produced for *any* request that
returns it — read or write. Gated per `fosmvvm-planning`
(design → customer DocC → contract tests → rationale → decomposition).

> Worktree: `FOSUtilities-model-identity` · branch `spec/model-identity-live-invalidation`.
> Supersedes the earlier request-side-relocation draft (that approach duplicated a
> shared body's construction across every request returning it — see §4).

---

## Confirmed model (closed with David)

**The leak.** `RefreshRequest` / `refreshRequest()` put a *server implementation
detail* — how the fresh value is produced — onto the *client-facing* request
contract. A client needs one fact: *execute the request, receive a
`ServerRequestBody`.* How the server builds it is the server's business.

**The real cause of `RefreshRequest`.** The factory already lives on the body and the
read path already reaches it through `SR.ResponseBody` (`ServeRequest.swift:30`). What
forced `RefreshRequest` was this associated type on the factory:

```swift
// ResponseBodyFactory.swift:10
associatedtype Request: ServerRequest where Request.ResponseBody == Self
```

Because `Request.ResponseBody == Self` holds for only one request type, it forces each
body to name **exactly one** request. `BerthListVM.Request` can be `BerthListRequest`
**or** `UpdateBerthRequest`, not both — so a write couldn't reuse the read body's factory
and had to name a `RefreshRequest`.

**The fix — delete that `Request` associated type, keep the factory on the body.** Let a
body build itself from *any* request that returns it:

```swift
static func body<R: ServerRequest>(context: ProjectionContext<R, AppState>) throws -> Self
    where R.ResponseBody == Self
```

- The shared construction stays on the shared type (`BerthListVM`), authored **once**;
  `BerthListRequest` (read) and `Update/Create/DeleteBerthRequest` (writes) all reuse
  it. This is the norm — container-perspective writes return the same view the read
  returns.
- Forward edge is `SR.ResponseBody.body(…)` — works for read **and** write.
  `RefreshRequest` is removed.
- `ComposableFactory` (`BerthListVM.berths`) **stays on the body**, shared;
  `PlanRegistration.swift:39` already reads it off `SR.ResponseBody` — unchanged.

**Two-phase write (unchanged from the model we settled).**

- **Phase 1 (always):** load the writer's authored candidate set
  (`WriteTargetProviding.candidates`) — the records its `Target` may mutate — to find +
  authorize + mutate the target. Authored on the writer, unchanged.
- **Phase 2 (data-bearing):** construct the `ResponseBody` (the container's children)
  via `SR.ResponseBody.body(…)`, reusing phase-1 records; a manual factory often
  needs no second pull. "No 2nd pull" is runtime cache reuse between the phases, not a
  merge of the two declarations.
- **`EmptyBody` response:** phase 2 skipped — nothing to construct. Rare / non-UI. The
  candidate is still authored like any other write; there is no special case.

---

## 1. Public surface — justified, then gated

### Removed (surface shrinks)

- **`ResponseBodyFactory.Request` associated type** (with `Request.ResponseBody == Self`)
  — the one-request restriction that forced `RefreshRequest`.
- **`ResponseFactory`** (the request-side sketch in `ResponseBodyFactory.swift`) —
  deleted; we are **not** going request-side.
- **`CreateRequest` / `UpdateRequest` / `DeleteRequest` `.RefreshRequest` /
  `refreshRequest()`** — deleted.
- **`registerRefreshPlan`** (`ViewModelRequest.swift:157`) — deleted; a write derives
  its own `ResponseBody`'s plan via `registerRecordLoadPlan(for: SR.self)`.

### Changed

- **`ResponseBodyFactory.body`** — from `body(context: ProjectionContext<Request,…>) -> Self`
  to the generic `body<R: ServerRequest>(context: ProjectionContext<R, AppState>) -> Self
  where R.ResponseBody == Self`. `AppState` stays on the body.

### Kept (names retained — David's call)

- **`ResponseBodyFactory`**, **`VaporResponseBodyFactory`** — names unchanged; the
  factory stays body-side. `VaporResponseBodyFactory`'s `encodeResponse → buildResponse`
  localize-on-serve default is **unchanged** (stays on the body).
- **`ComposableFactory`** — protocol and its body-side home unchanged.

### Gate (step-1 checklist)

- [x] **Minimal surface.** Net *removal*: the `Request` associated type, a whole request-side protocol,
  `RefreshRequest`×3, `registerRefreshPlan`, `candidates` (common case). The one
  change (generic `body`) *widens* reuse, adds no new public type.
- [x] **Encapsulation.** The server-only construction detail leaves the wire contract.
- [x] **No stringly-typing.** Forward edge is the typed `SR.ResponseBody`.
- [x] **One serialization.** Untouched.
- [x] **Requirement + default.** `ResponseBodyFactory` stays requirement + `AppState =
  Void` default.
- [x] **Don't publish representation.** N/A.
- [x] **Boundaries hold.** FOSMVVM stays Fluent/Vapor-free; `VaporResponseBodyFactory`
  stays in FOSMVVMVapor; ViewModel module never imports the wire module.
- [x] **Writer surface unchanged.** The candidate stays authored on the writer
  (`WriteTargetProviding.candidates`) — a shared body can't own a per-write mutation
  scope, so there is no derivation and no `EmptyBody` special case.

---

## 2. Customer-facing DocC — drafted first (contract only, with examples)

**`ResponseBodyFactory`** (body-side, now shared across requests)

> Construct this body on the server from a request that returns it.
>
> ```swift
> extension BerthListVM: VaporResponseBodyFactory {
>     static func body<R: ServerRequest>(context: ProjectionContext<R, Void>) throws -> Self
>         where R.ResponseBody == Self {
>         BerthListVM(berths: try context.records(Self.berths).map(BerthCell.init))
>     }
> }
> extension BerthListVM: ComposableFactory {
>     static let berths = LoadRequirement.read(Berth.self, in: .parentRoot)
>     static var dataRequirements: [any DataRequirement] { [berths] }
> }
> ```
>
> Author it **once** on the body; every request whose `ResponseBody` is this type —
> the read *and* the writes that return it — reuses it. Records are loaded before
> `body` runs; `body` is synchronous — construction, never I/O.

**Write request (no `RefreshRequest`)** — on `UpdateRequest`/`CreateRequest`/`DeleteRequest`:

> A write returns a `ResponseBody` like any request — normally the container's updated
> children, the same type the read returns. Point the write at that type; the
> framework loads its plan write-scoped to find and mutate your target, then read-scoped
> to build the response after the commit.
>
> ```swift
> final class UpdateBerthRequest: UpdateRequest {
>     typealias RequestBody = UpdateBerthBody
>     typealias ResponseBody = BerthListVM        // same body the read returns — no RefreshRequest
>     // …query/init…
> }
> extension UpdateBerthBody: DataModelWriter {
>     func apply(to berth: Berth) throws { berth.name = name; berth.capacity = capacity }
> }
> ```

(Rationale — why body-side, why generic, the rejected relocation and `RefreshRequest`
— lives in §4, never in these DocC blocks.)

---

## 3. Contract tests (public contract only)

- **One body, many requests.** The *same* `BerthListVM` served by `BerthListRequest`
  (GET) and by `UpdateBerthRequest` (PATCH) — both decode to an equal-shaped value;
  the write reflects the mutation. Via `app.test` / `fromJSON()`, never raw JSON.
- **Fresh-after-write.** Post-write children reflect the change (invalidation honored).
- **Zero-data write.** `Delete → EmptyBody` returns empty; phase-2 skipped.
- **Read unchanged.** GET serve byte-identical after the `Request` associated type is removed.
- **Boot fail-fasts preserved.** Write-protocol-at-read-door, missing `AppState`
  builder, unstable tokens, verb–door coherence still fire.
- **Macro output clean.** A macro-expansion test asserts `@ViewModel` /
  `@VersionedFactory` generated code references no `.Request` associated type on a
  response body — catches a re-introduction on any future edit, not just today.
- **No `@testable` for contract.** Public request types + the harness only.

---

## 4. Rationale (prose — the "why", not for DocC)

- **Why body-side, not the request.** A body is returned by *many* requests (read +
  the container-perspective writes). "Produce this body" is a shared responsibility →
  it belongs on the shared type, authored once. The rejected draft moved it to the
  request, which copied the identical `body()` + plan onto every request returning the
  type — duplication in the common case. (David's check: *"what if the same type is the
  result of a Read Request and a Write Request?"*)
- **Why the generic `body<R>`.** The `Request` associated type's one-request restriction
  — not the factory's home — is what forced `RefreshRequest`. Generalizing to any `R`
  where `R.ResponseBody == Self` lets one builder serve read and write; the forward edge
  is `SR.ResponseBody`.
- **Why one plan, two phases.** The container's children are the records both the
  candidate (write verb) and the response (read verb) want — one declaration, two
  verbs; phase 2 reuses phase 1.
- **Why `EmptyBody` doesn't drive the shape.** UI writes return children; empty is
  rare/non-UI.

---

## 5. Files touched

**Delete**

- `Sources/FOSMVVM/Protocols/ServerRequestFactory.swift` — empty scratch.
- The `ResponseFactory` (request-side sketch) inside
  `Sources/FOSMVVM/Protocols/ResponseBodyFactory.swift`.

**FOSMVVM**

- `ResponseBodyFactory.swift` — delete the `Request` associated type; generic `body<R>`.
- `UpdateRequest.swift` — strip `RefreshRequest`/`refreshRequest()` (Create/Delete
  done in WIP); scrub the "freshly-rendered screen" DocC on all three.
- `CreateRequest.swift` / `DeleteRequest.swift` — remove stale `RefreshRequest` DocC.

**FOSMVVMVapor**

- `VaporResponseBodyFactory.swift` — track the generic `body<R>` signature; the
  `encodeResponse`/localization default is otherwise unchanged.
- `ServeRequest.swift` — `serve` drops `SR.ResponseBody.Request == SR`; `SR.ResponseBody.body(context:)`.
- `WriteRoute.swift` — `serveCreate/Update/Delete` drop `RefreshRequest.*` + the
  `serve(refreshRequest())` tail; phase 2 = `SR.ResponseBody.body(context:)`.
- `ViewModelRequest.swift` — three `register(request:)` overloads drop `RefreshRequest.*`;
  delete `registerRefreshPlan`; a write derives its own plan via
  `registerRecordLoadPlan(for: SR.self)`.
- `PlanRegistration.swift` — read-plan derivation **and** candidate derivation
  (`deriveCandidatePlan` / `CandidateFactory`) unchanged.

**Deliberately unchanged** — `WriteTargetProviding.swift` / `DataModelWriter`: the
candidate stays authored on the writer.

**FOSTestingVapor**

- `VaporServerTestCase.swift` — drop `Request.ResponseBody.Request == Request`.

**DocC**

- `ViewModelandViewModelRequest.md`, `ServerOverview.md`, `Operations.md` — drop
  `RefreshRequest`; factory example takes the generic `body<R>`.

**Tests**

- `Tests/FOSMVVMVaporTests/Containment/WriteFixtures.swift` (+ neighbors) — remove
  `refreshRequest()`/`RefreshRequest`/`typealias RefreshRequest`; a write's
  `ResponseBody` is the shared VM directly; add a one-body-two-requests fixture.

**Consumer-facing**

- CHANGELOG (breaking: `RefreshRequest` removed; `body` is generic over the request).
- Migration note. Re-run `fosutilities-api-catalog-update`.

---

## 6. Decomposition handoff (each a TDD unit; suite green between)

1. **FOSMVVM factory** — delete the `Request` associated type, generic `body<R>`; delete the request-side
   `ResponseFactory` sketch + `ServerRequestFactory.swift`.
2. **FOSMVVM write protocols** — strip `RefreshRequest` from all three; scrub DocC.
3. **Serve path** — `ServeRequest` + `WriteRoute` build via `SR.ResponseBody.body`;
   two-phase write with reuse.
4. **Registration** — `ViewModelRequest` drops `RefreshRequest`/`registerRefreshPlan`;
   a write derives its own plan (`registerRecordLoadPlan(for: SR.self)`).
5. **FOSTestingVapor + fixtures + DocC.**
6. **CHANGELOG + migration + api-catalog.**

Hand to `superpowers:writing-plans` for per-file tasks + review loop.

---

## Open implementation questions (non-gating)

None. The macro check is now a contract test (§3, "Macro output clean").

---

## Future (out of scope for this change)

- **Macro-derived factory conformance.** `@ViewModel` could inspect the ViewModel's
  property wrappers and auto-generate the `ResponseBodyFactory` conformance
  (`body(context:)`), which is hand-authored today. The wrappers already describe the
  body's shape. Its own design change — recorded here so it isn't lost; not undertaken
  in this migration.
