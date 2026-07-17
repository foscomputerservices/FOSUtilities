# RoutesBuilder Register Door Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the four `register(request:)` methods from `Vapor.Application` to `RoutesBuilder` (taking `app:` as a parameter) and delete the Application-sited versions, so a request can be mounted behind the caller's middleware group (the credential-guarding case) — while keeping the guarantee that registering a request always derives and validates its load plan.

**Architecture:** The receiver becomes the mount point (`try adminAuth.register(request:app:)`); the `app:` parameter supplies the Application, which remains where everything registers (plan derivation, appState checks, candidate plans all land in `Application.storage`, which serve-time reads via `req.application`). Vapor's `Application` conforms to `RoutesBuilder`, so mounting at the root still works through this same single method. A boot-time path check rejects path-prefixing groups, which would otherwise silently change the served URL while clients keep deriving it from the request type.

**Tech Stack:** Swift 6 / Swift Testing, Vapor, existing FOSMVVMVapor machinery (no new mechanisms).

---

## Design & Rationale (the fosmvvm-planning gate output)

### The ruling and the shape

David's ruling (2026-07-17): the Application-sited `register(request:)` methods are
**eliminated**, replaced by RoutesBuilder-sited doors. The house sentence:

*Where a request mounts is your decision; that its plan is derived is not.*

```swift
func routes(_ app: Application) throws {
    let authed = app.grouped(ClientCredentialMiddleware(verifier: harborVerifier))
    try authed.register(request: DocksRequest.self, app: app)      // guarded
    try app.register(request: LandingPageRequest.self, app: app)   // public (Application IS a RoutesBuilder)
}
```

### Why this design (and what the old constraint actually protected)

- **What the old restriction actually guaranteed — and why the move keeps it.** The
  existing DocC says: "Registration is Application-only by construction: there is no
  grouped/`Routes`-level door, so a composable body can never be registered without its
  plan" (`ViewModelRequest.swift:39`). The guarantee behind that sentence is simply:
  *every registered request gets its load plan derived and validated.* That guarantee
  holds because the derivation call sits inside `register(request:)` itself — the same
  function that mounts the route. It does not depend on which builder the route mounts
  on. The new method still takes the Application and still derives the plan in the same
  function body, so the guarantee is unchanged. Restricting registration to the
  Application was the original *way* of ensuring it, not the guarantee itself.
- **The middleware ordering already works — no new code.**
  `ServerRequestController.boot` wraps its routes in `VaporServerRequestMiddleware`
  (the framework middleware that decodes and binds the typed request) on top of
  whatever builder it is registered on (`ServerRequestController.swift:82`). Mount on a
  credential group and the chain is: credential middleware first, then the framework's
  request-binding middleware, then the handler — so an unauthenticated write is
  rejected before anything mutates. After a write commits, the server builds the
  response by calling `serve()` directly in-process; there is no second trip through
  routing (`ServeRequest.swift:24-29`), so a response build can never be rejected after
  the data already changed. A `.live` refresh re-fetches through the same URL and
  therefore the same middleware (`ViewModelView.refreshInPlace` →
  `processRequestCapturingRegistrations`), so guarded screens stay guarded on every
  refresh.
- **Why delete the Application methods instead of keeping both:** two public ways to
  register the same request is API duplication this repo doesn't allow, and Vapor
  already conforms `Application` to `RoutesBuilder`
  (`vapor/Routing/Routes.swift:62`) — so mounting at the root still works through the
  one remaining method. The new siting is also the Vapor-aligned one (David,
  2026-07-17): in standard Vapor practice, routing surfaces are where processing is
  mounted (`routes.get(...)`, Vapor's own `register(collection:)`), while the
  `Application` receiver is for app-wide configuration (`app.middleware.use`,
  `app.migrations.add`). `register(request:)` mounts a route; siting it on the
  Application was the deviation. The one non-standard remainder is the `app:` parameter
  itself, needed because plan derivation runs at registration time — before any request
  exists, so `req.application` (how Vapor handlers normally reach the app) isn't
  available, and `RoutesBuilder` carries no app reference. David asked whether removing
  the Application methods loses anything; verified: nothing functional. The real cost:
  every existing call site breaks (dozens in-repo — grep is the authority; the fix is
  one added argument). Pre-1.0 is the time to make this break.

### The conflation the old restriction hid, and the boot check that separates it

The old Application-only restriction conflated two different things a Vapor group can
do (David, 2026-07-17):

1. **Path prefixing** (`app.grouped("admin")`) — changes the served URL. FOS cannot
   follow this: the client derives `<Request>.path` from the type and would never learn
   the prefix — client and server silently disagree; runtime 404s. (Supporting a
   deliberate, client-visible prefix someday would be its own designed feature; today a
   prefixed deployment already requires a stripping proxy, and that stays true.)
2. **Middleware attachment** (`app.grouped(middleware)`) — changes nothing about the
   URL, and applications require it (credential guarding).

The old design banned both to avoid the first. This change permits the second and
turns the first from a silent runtime failure into a boot error: after
`register(collection:)` returns, the method verifies the routes just added carry
exactly the type-derived path; any prefix throws, naming the request type and the
actual mounted path. Middleware-only groups add no path components and pass untouched.

Mechanics (implementer note): `Routes.all` is append-only and registration is
single-threaded at boot — snapshot `app.routes.all.count` before the
`register(collection:)` call, then validate `route.path.map(\.description) ==
SR.path.pathComponents.map(\.description)` for each appended route. Both the snapshot
and the post-register validation read `app.routes.all` — **never `self`** (the receiver
may be a `MiddlewareGroup`, which has no route storage; groups forward `add(route:)` up
the chain to the root). The error is a new case on **`ContainmentError`**
(`Containment/ContainmentError.swift` — the existing internal home of the sibling boot
diagnostics `writeRequestAtReadDoor` / `missingAppStateBuilder`, already thrown from
`ViewModelRequest.swift`; apps never catch it, its value is the boot diagnostic). Do
NOT add it to `ServerRequestControllerError` — that enum is `public`, and this change
adds no public symbols beyond the doors.

### Step-1 gate results (public surface)

Four public symbols moved (none added beyond the `app:` parameter), four removed:

- `RoutesBuilder.register(request:app:)` — read door (`SR: ServerRequest`)
- `RoutesBuilder.register(request:app:)` — create door (`SR: CreateRequest`)
- `RoutesBuilder.register(request:app:)` — update door (`SR: UpdateRequest`)
- `RoutesBuilder.register(request:app:)` — delete door (`SR: DeleteRequest`)
- **Removed:** the four `Vapor.Application.register(request:)` methods.

Gate: one method per operation (the duplicate Application spelling is removed, and no
new duplicate is added) ✓; no
stringly-typing (mount point is a typed `RoutesBuilder`, path stays type-derived) ✓;
parameter label settled as **`app:`** — plain and honest; `deriving:`/`for:`/`in:`
considered and cut (jargon or vague; the parameter's role IS the Application whose
registries receive the derivation). Sits harmoniously beside Vapor's own
RoutesBuilder-sited `register(collection:)`. Boundaries unchanged ✓. Old-code migration
UX: `app.register(request: X.self)` fails with a missing-argument diagnostic pointing at
the new signature (Application is a RoutesBuilder, so overload resolution finds the new
door and names the missing `app:`).

Internal relocations (not public surface): `rejectWriteProtocolAtReadDoor` uses no
Application state — becomes a private free function (or private RoutesBuilder extension)
in `ViewModelRequest.swift`. The registry helpers stay Application extensions
(`app.registerRecordLoadPlan(...)`, `app.requireAppStateBuilder(...)`,
`app.deriveCandidatePlan(...)` — all internal, same module, verified).

### Step-2 DocC (drafted first — the read door; write doors adapt the same frame)

```swift
/// Registers a read request's route (GET) on this route group
///
/// The group you call it on decides the middleware that guards the route —
/// mount privileged requests behind your credential group, public ones on the
/// `Application` itself (an `Application` is a `RoutesBuilder`):
///
/// ```swift
/// func routes(_ app: Application) throws {
///     let authed = app.grouped(ClientCredentialMiddleware(verifier: myVerifier))
///     try authed.register(request: DockPageRequest.self, app: app)
///     try app.register(request: LandingPageRequest.self, app: app)
/// }
/// ```
///
/// One door for every request — a body that is a ViewModel and a body that is
/// not (a report, an export) register the same way.
///
/// >  *ServerRequest* provides a protocol extension that sets *ServerRequest/path* based on
/// >   the *ServerRequest/RequestBody* and *ServerRequest/ResponseBody* types. Thus, the
/// >   route's path is automatically maintained and there is never a path collision or
/// >   confusion between the client and server. Mount on **middleware-only** groups: a
/// >   path-prefixing group would change the served URL while clients derive it from the
/// >   type — registration rejects that at boot.
///
/// Register the app's containers (``Vapor/Application/register(_:migration:)``) **before**
/// calling this — a composable body's load plan is derived and validated here, against
/// `app`'s registered containers. Every door derives the plan: where a request mounts is
/// your decision; that its plan is derived is not.
///
/// A write request (Create/Update/Delete) has its own overload; register it the same way
/// (`try authed.register(request: BerthUpdateRequest.self, app: app)`), and Swift picks
/// the write door. A write request that reaches *this* read door — because its
/// Query/RequestBody miss the write overload's constraints, or because its protocol
/// (Replace/Destroy) is not yet supported — fails fast at boot rather than registering
/// GET-only (which would silently drop the write).
///
/// - Parameters:
///   - request: A *ServerRequest* whose *ResponseBody* is a ``VaporResponseBodyFactory``
///   - app: The application this route serves — the request's load plan is derived
///     into and validated against it
```

Write doors: keep each existing DocC body, reframed to the group receiver (example call
shows `try authed.register(request: ..., app: app)`), plus the shared `- Parameters:`
block. No rationale, no representation, contract only.

### Step-3 contract tests (public surface only)

1. **A group's middleware guards the route** (the harbor case, end to end): register a
   read request on `app.grouped(ClientCredentialMiddleware(verifier:
   BearerCredentialVerifier(...)))`; serve without a token → the typed credential
   rejection (assert via the shipped `TestingServerRequestResponse.credentialRejection`
   helper — never on status alone); serve with the token → the body arrives.
2. **A write is rejected BEFORE it mutates:** unauthenticated PATCH to a group-mounted
   update request → credential rejection AND the record is unchanged in the database
   (read it back).
3. **Root mounting via the Application receiver:** `try app.register(request: X.self,
   app: app)` serves normally (Application-as-RoutesBuilder — the migration's own
   spelling, asserted once explicitly; the migrated call sites cover it implicitly).
4. **Path-prefixed group fails at boot:** registering on `app.grouped("admin")` throws
   at registration, naming the request type; nothing is served.
5. **Plan derivation still runs on a group:** a composable body registered on a group
   without its containers registered → the same boot throw as today (existing
   `PlanRegistrationTests` migrate and keep covering derivation; add one group-sited
   assertion).
6. **Registrations header rides a group-mounted route:** a plan-bearing request mounted
   behind middleware still carries `X-FOS-Registrations` (whole-value `fromJSON()`
   decode, membership via public equality — pattern: `RegistrationHeaderTests`).

All identities/bodies via public API; no `@testable`-for-contract; no raw JSON
inspection.

### Rejected alternatives (do not re-propose)

- **Keeping both sitings** (Application + RoutesBuilder): two spellings of one act.
- **Realm/type-declared guards** (request type declares its plane, boot binds a
  verifier): parked, not rejected on merit — compile-forced guarding at real ceremony
  cost; defer until a client exists (e.g. client-side per-request credential selection).
- **In-pipeline verify call inside `serve()`**: wrong placement — runs after a write's
  mutation on the post-commit re-serve, and double-verifies internal re-entries.
- **DocC-only warning for path-prefix groups** (no boot check): the invisible mode —
  client 404s at runtime instead of a named boot failure.
- **Deprecation shims for the old methods**: pre-1.0 removes cleanly; a parallel
  "legacy" door is the composition failure David's standards ban.

---

## File Structure

- **Modify:** `Sources/FOSMVVMVapor/Vapor Support/ViewModelRequest.swift`
  — the four doors become `public extension RoutesBuilder` (same file, same
  responsibility: the registration doors); Application extensions removed;
  `rejectWriteProtocolAtReadDoor` becomes file-private free function; the path
  check added to the shared mounting step.
- **Modify:** `Sources/FOSMVVMVapor/Containment/ContainmentError.swift`
  — new internal boot-diagnostic case for the path-check failure.
- **Modify (mechanical migration):** every `register(request:` **invocation** gains
  `, app: app`. The grep is the authority, but it returns two populations — actual
  call sites (`try …register(request:` — migrate mechanically) and *references*
  (DocC cross-links, `.docc` guide examples, error-message strings, comments — these
  go through Task 3's documentation sweep, and must NOT get a mechanical
  `, app: app` appended).
- **Create:** `Tests/FOSMVVMVaporTests/Middleware/GroupMountedRegistrationTests.swift`
  — contracts 1, 2, 3, 4, 6 above (contract 5 lands as an added assertion in
  `Tests/FOSMVVMVaporTests/Composition/PlanRegistrationTests.swift`).
- **Modify:** `CHANGELOG.md` (Unreleased → Changed, breaking, with the one-line
  migration), `.claude/docs/FOSMVVMArchitecture.md` (registration prose), api-catalog +
  generator-skill docs that show the old spelling (sweep; plugin bump via the
  catalog-update skill).

---

### Task 0: Branch

- [ ] **Step 1:**
```bash
cd /Users/david/Repository/FOS/FOSUtilities
git checkout -b feature/routesbuilder-register-door
```

---

### Task 1: Move the read door + the path check

**Files:**
- Create: `Tests/FOSMVVMVaporTests/Middleware/GroupMountedRegistrationTests.swift`
- Modify: `Sources/FOSMVVMVapor/Vapor Support/ViewModelRequest.swift`
- Modify: `Sources/FOSMVVMVapor/Containment/ContainmentError.swift`
- Modify: read-door call sites (compiler-driven)

- [ ] **Step 1: Write the failing contract tests** — contracts 1, 3, 4 (read-door
  scope; contracts 2 lands in Task 2, 5-6 in later steps). Pattern the served-HTTP
  harness on `RegistrationHeaderTests.swift`; the credential fixture uses
  `ClientCredentialMiddleware` + `BearerCredentialVerifier` (both shipped, see
  `Middleware/ClientCredentialMiddleware.swift`) and asserts rejection via
  `TestingServerRequestResponse.credentialRejection` (FOSTestingVapor, shipped 0.7.0).
  Neutral fixture vocabulary; reuse existing SQL fixtures only as plumbing.

- [ ] **Step 2: Run to verify red** — `swift test --filter GroupMountedRegistrationTests`
  fails: no `register(request:app:)` on RoutesBuilder.

- [ ] **Step 3: Implement the read door.** In `ViewModelRequest.swift`: change
  `public extension Vapor.Application` to `public extension RoutesBuilder` for the read
  door; signature `func register<SR: ServerRequest>(request _: SR.Type, app:
  Vapor.Application) throws`; body calls become `app.`-qualified
  (`try app.registerRecordLoadPlan(for: SR.self)` etc.); mounting becomes
  `try register(collection: GuardedRequestController<SR>(...))` on `self`, bracketed by
  the path check (snapshot `app.routes.all.count`, validate appended routes'
  paths equal `SR.path.pathComponents` — reading `app.routes.all`, never `self`;
  mismatch throws the new internal `ContainmentError` case naming the request and the
  mounted path). Replace
  the DocC with the draft from this plan's Design section (verbatim).
  `rejectWriteProtocolAtReadDoor` → file-private free function, unchanged body.

- [ ] **Step 4: Migrate read-door call sites** — compiler-driven; write doors still
  compile on Application in this task. `swift build` until clean, then
  `swift test --filter GroupMountedRegistrationTests` → green.

- [ ] **Step 5: Commit** (trailers per repo convention).

---

### Task 2: Move the three write doors

**Files:**
- Modify: `Sources/FOSMVVMVapor/Vapor Support/ViewModelRequest.swift`
- Modify: `Tests/FOSMVVMVaporTests/Middleware/GroupMountedRegistrationTests.swift` (add contract 2)
- Modify: remaining call sites (compiler-driven)

- [ ] **Step 1: Add the failing write-guard test** (contract 2: unauthenticated PATCH →
  typed rejection + record unchanged; authenticated → mutates and returns the refreshed
  body). Red: write doors not on RoutesBuilder yet — the test's group-mounted write
  registration doesn't compile.
- [ ] **Step 2: Move the create/update/delete doors** — same mechanical transform as
  Task 1 (receiver `RoutesBuilder`, `app:` parameter, `app.`-qualified helpers,
  path check, DocC reframed to the group receiver with the shared
  `- Parameters:` block). All Application-sited register(request:) methods are now GONE.
- [ ] **Step 3: Migrate every remaining call site** (`grep -rn "register(request:"` is
  the authority — its hits split into invocations, which migrate, and doc/DocC
  references, which go to Task 3's sweep). Full `swift test` → green.
- [ ] **Step 4: Add contract 5's group-sited assertion** to `PlanRegistrationTests` and
  contract 6 (registrations header on a guarded route) to
  `GroupMountedRegistrationTests`. Green.
- [ ] **Step 5: Commit.**

---

### Task 3: Docs, catalog, changelog

- [ ] **Step 1: CHANGELOG** — Unreleased → `### Changed` (BREAKING, house style):
  the four doors moved to `RoutesBuilder` with the mount-point rationale and the
  one-line migration (`try app.register(request: X.self)` →
  `try app.register(request: X.self, app: app)`, or mount on a middleware group);
  note the new boot rejection of path-prefixing groups. Contract only.
- [ ] **Step 2: Architecture doc** — update registration prose (grep
  `.claude/docs/FOSMVVMArchitecture.md` for register(request:) / Application-only
  language; recut to the mount-point sentence).
- [ ] **Step 3: Sweep ALL in-`Sources` documentation** — `grep -rn "register(request:"
  Sources` and fix every *reference* (never by appending `, app: app` mechanically —
  each is prose or a link):
  - `.docc` guides teaching the old root call:
    `Sources/FOSMVVM/FOSMVVM.docc/ServerOverview.md:40-41`,
    `Sources/FOSMVVM/FOSMVVM.docc/ViewModelandViewModelRequest.md:142` — update to the
    new spelling (show the guarded and root forms).
  - Dangling DocC symbol cross-refs to the deleted methods:
    `VaporResponseBodyFactory.swift:52`, `ServerRequestController.swift:42` — repoint
    at the RoutesBuilder door (verify resolution as in prior work: extension symbols
    catalog under the extending module's path).
  - Stale error strings and maintainer comments that name the old siting:
    `PlanRegistration.swift:62` ("Registration is Application-only"),
    `PlanExecutor.swift:44`, `WriteRoute.swift:144` (error strings telling users to
    `try app.register(request:)`), `AppStateRegistry.swift:32,57`,
    `ContainmentError.swift:84`, `GuardedRequestController.swift:20`,
    `VaporServerRequestMiddleware.swift:28`, `ServeRequest.swift:80`.
  Line numbers are start-of-task hints; the grep is the authority.
- [ ] **Step 3b: Sweep skill docs** — `grep -rn "register(request:" .claude/skills` —
  generator skills teach the old spelling; update examples to the new door (guarded and
  root forms).
- [ ] **Step 4: Run the `fosutilities-api-catalog-update` skill** (catalog entries for
  the four doors, reach-for index, plugin version bump).
- [ ] **Step 5: Commit.**

---

### Task 4: Verification sweep

- [ ] **Step 1:** full `swift test`; `swiftformat .`; `swiftlint` (commit any format
  deltas separately as chore).
- [ ] **Step 2:** final whole-branch review.
- [ ] **STOP — review gate.** No PR until David reviews and says go.

---

## Out of Scope (deliberately)

- Realm/type-declared guards (parked; see Rejected alternatives).
- Any change to `useLiveInvalidation(on:)` (already RoutesBuilder-sited; unchanged).
- Container registration `register(_:migration:)` stays Application-sited — it is
  persistence registration, not routing.
- Client-side changes: none — the URL contract is unchanged by design (and now
  boot-enforced).
