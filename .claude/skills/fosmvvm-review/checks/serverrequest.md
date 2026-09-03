---
area: serverrequest
generator-skill: fosmvvm-serverrequest-generator
where:
  - "Sources/**/ServerRequests/**/*.swift"
  - "Sources/**/*Request.swift"
  - "Sources/**/routes.swift"
  - "Sources/**/*Controller.swift"
  - "Sources/**/*+Factory.swift"
  - "Sources/**/Factories/**/*.swift"
  - "Sources/**/*+Live.swift"
  - "Sources/**/LiveInvalidation/**/*.swift"
  - "Sources/**/configure.swift"
---

# ServerRequest Checks

The positive pattern lives in the `fosmvvm-serverrequest-generator` skill.

## Reviewer Guidance

- **Anchor an area-wide finding at the instance where the loss is largest**, and list the rest in the body. Some defects here are one belief replicated across a dozen files; reporting them per file buries the diagnosis, and a finding still needs one `path:line` a reader can open.
- **The transport is not the contract.** A `ResponseError` declared on the request and an `Abort(.badRequest, reason:)` thrown in the controller are two different vocabularies; when they disagree, the declared type is decoration and the status is the real API. Check both ends before concluding an area is clean.
- **`CredentialRejectedError` is already handled and is not the request's business.** `WireError` decodes the FOS-owned surface errors strictly before the request's own `ResponseError`, so a rejection always reaches the client typed, whatever the `ResponseError` is. Do NOT recommend defensive shapes to "avoid swallowing a 401" — and treat a comment claiming that risk as a finding, not as a rationale.
- Do NOT recommend collapsing a typed error to a `String` to reduce boilerplate. The vocabulary *is* the value; a free-text field is an error a client cannot branch on.
- A `ResponseError` is the operation's *semantic* error — the well-defined Swift error the operation would `throw` if it were a local function call. `ServerRequestError` exists so that throw can happen across the wire (server throws → rides the response as `Codable` → the client's `processRequest` rethrows the same typed error). It is **not** an HTTP-status mapping; HTTP statuses are transport dressing and carry no result semantics. See [Architecture Patterns → Typed Errors Are the Operation's Throw](../../shared/architecture-patterns.md).

## Check: responseerror-models-the-throw
**Severity:** blocker
**What:** A `ResponseError` must declare the operation's failure vocabulary as typed data — what the operation would `throw` locally — not mirror the transport. Two smells: (a) error cases named after HTTP statuses or transport categories rather than operation outcomes; (b) a `ResponseError` whose only content is a free-text `reason`/`message` `String`. A reason-only shape mirrors a middleware abort body, so *any* rejection decodes into it and the client cannot distinguish cases by type.
**Anti-pattern:**
```swift
struct MyError: ServerRequestError {
    let reason: String                       // free-text only — string-puns with any abort body
}

enum ErrorCode: Codable, Sendable {
    case unauthorized401                     // status-named — transport leaked into semantics
    case badRequest
}
```
**Detection:** For each type conforming to `ServerRequestError` (excluding `EmptyError` and `ValidationError`): flag if (a) its only stored data is one or more free-text `String` fields (no `ErrorCode`-style enum, no typed associated data); or (b) its enum cases are named for HTTP statuses/transport categories (`unauthorized`, `forbidden`, `badRequest`, `notFound` with no operation noun, numeric-status suffixes) rather than operation outcomes (`duplicateContent`, `quotaExceeded`, `sessionExpired`).


## Check: controller-throws-the-declared-error
**Severity:** blocker
**What:** The controller throws the `ResponseError` its request declares, rather than lowering the failure into an HTTP status and prose.
**Anti-pattern:**
```swift
} catch let error as DAGValidationError {
    throw Abort(.badRequest, reason: error.reason)   // typed error → status + String
}
```
**Detection:** For each request declaring a `ResponseError`, find its controller or factory and read the failure paths. Flag a handler that throws `Abort(_:reason:)` for an outcome the declared error covers, or should.

**A reason-only `ResponseError` that is never thrown is this check's maximal instance, not an exemption from it.** Read literally, "where the declared error has a case for that outcome" lets the worst shape escape — a `{reason: String}` type has no cases at all, so nothing ever matches. That is the defect, not a reason to pass: the type was declared, the operation has real outcomes, and none of them survive the wire.

**Infrastructure failures are correctly `Abort`s and are not hits.** `Abort(.internalServerError, reason: "SomeService unavailable")` means *this server is broken*, which is not an outcome of the operation and has no place in its vocabulary. Carve those out explicitly when you report, so the finding is not diluted — and do not let the carve-out stretch to cover a genuine operation outcome that merely arrives as a 500 — the distinction the type exists to carry (wrong role, no live connection, malformed input) then survives only as prose in a status body, and no client can branch on it.

This is the check that catches an area-wide inversion: a codebase can declare typed errors on every request and throw none of them, in which case the declared types are decoration and HTTP is the actual contract. Say so once, at the level it is true, rather than filing the same finding per request.

## Check: no-defensive-error-for-credential-rejection
**Severity:** warning
**What:** A `ResponseError` is not shaped, and its permissive fields are not justified, by a fear of swallowing credential rejections.
**Anti-pattern:**
```swift
/// A REQUIRED field by design: an error type whose decode accepts anything
/// (e.g. `EmptyError`) would swallow a credential-middleware 401 on the
/// FOSMVVM client, hiding the re-pull trigger.
public struct ResponseError: ServerRequestError {
    public let reason: String
}
```
**Detection:** Grep the `ResponseError` declarations and their documentation for reasoning about 401s, credential rejection, or `EmptyError` swallowing errors. Flag it: every error body crosses inside one typed envelope that names whether it carries the surface rejection or the request's own error (0.16.0; before that, the rejection was decoded strictly first), so the rejection is never reachable by the `ResponseError` and the defensive shape buys nothing. It also costs something — a permissive error decodes any abort body, so unrelated failures arrive wearing this operation's type.

**Report this once for the whole area when the rationale has propagated**, listing every site in the body. A copied justification is one belief, not N defects, and filing it per request buries the fact that it spread.

**Widen the grep past `ResponseError`.** The reasoning migrates: look for any member — including `ResponseBody` fields — whose documentation cites `EmptyError` swallowing, 401s, or credential rejection as a design reason. Once the belief is in a codebase it justifies shapes well outside the error type.

**Say what to do instead.** Where the operation has no well-defined throw, the fix is `typealias ResponseError = EmptyError`, not an invented enum. Point at an in-repo example if one exists — most codebases with this problem have at least one request that got it right.

Report the comment and the field together, and check whether the same block has been copied across requests: this is a rationale that propagates, and finding it once usually means finding it everywhere. Where the shape is otherwise a bare `reason: String`, `responseerror-models-the-throw` is the primary finding and this one explains why it was written that way — report both, but say which is the defect and which is the cause.

## Check: requestbody-adopts-its-fields
**Severity:** blocker
**What:** A write request's RequestBody carrying user-entered field values adopts the entity's Fields protocol — the one contract the form, the body, and the model all validate with. The compiler forces `ValidatableModel` onto `CreateRequest`/`UpdateRequest` bodies, but it cannot force the conformance to *mean* anything: a hand-written `validate` returning `nil` satisfies the constraint and validates nothing, so invalid data rides the wire behind a green build.
**Anti-pattern:**
```swift
public struct RequestBody: ServerRequestBody, ValidatableModel {
    public let name: String            // user-typed value
    public func validate(fields: [any FormFieldBase]?, validations: Validations) -> ValidationResult.Status? {
        nil                             // constraint satisfied, nothing validated
    }
}
```
**Detection:** Enumerate the **whole write family**: `CreateRequest`, `UpdateRequest`, **and `ReplaceRequest`** — a peer protocol with the same `RequestBody: ValidatableModel` constraint that refines neither of the others, and the most form-like write shape there is (a PUT-upsert); a conformance scan keyed on Create/Update alone misses exactly the bodies most likely to carry user values. Add any plain `ServerRequest` whose declared `action` override is a write (`.create`, `.update`, `.replace`) — the conformance-free spelling escapes a protocol scan, and a deliberate control-channel command (the legitimate use, usually saying so in its DocC) is distinguished by the discriminator, not by skipping the file. A `RequestBody = EmptyBody` short-circuits to not-a-hit — the framework conforms `EmptyBody` to `ValidatableModel` for precisely the body-less write. Then, per body:

- **Apply the discriminator first** (ruled 2026-08-25, shared with `datamodel-adopts-its-fields`): does the body carry *user-entered field values* — things a person typed into the requesting client's UI — or *operation parameters* — ids being acted on, verbs, flags, machine-minted or machine-assembled payloads? Operation-parameter bodies owe no Fields protocol and are not hits; `DeleteRequest`/`DestroyRequest` land there by construction. Free text is not automatically user text: a subprocess log tail in a `String?` is machine-produced; content authored upstream in a config file and submitted by an agent is not a form entry. An admin's CLI argument naming a catalog key is an id acted on, not a typed field value.
- **A user-values body adopting its Fields protocol:** confirm the wiring is real — its `validate` reaches the Fields validation helpers (the `{name}FieldsValidateModel(validations:fields:)` composition, or the per-field validators), not a parallel hand-rolled rule set. Adoption whose `validate` ignores the helpers has dropped the contract while wearing it — the same hit.
- **A user-values body with no Fields protocol anywhere:** the contract is missing wholesale. Name the minimal remedy — a one-field Fields protocol is a small contract, same principle — and note that `datamodel-adopts-its-fields` sees the same absence from the model side: anchor the finding in whichever area holds the richer evidence and cross-reference the other; do not file it twice.
- **A body that copies Fields members without adopting** is `validation-not-duplicated-downstream`'s finding (the `fields` area) — note the pairing, do not re-grade it here.
- **A DocC claiming the contract the code lacks** — "the same Fields validation applies at every layer" over a `validate` returning `nil` and no Fields protocol in the repo — is `comment-asserts-an-invariant-the-code-lacks` (`cross-cutting`) wearing request clothes; report it there and say what it will cost the next reader.

The full composed shape is `ServerRequestBody` + Fields + `ValidatableModel` + `Stubbable`; a body missing `Stubbable` degrades request testing — say so as a note in the finding, not as this check's blocker.

## Check: registration-uses-the-request-door
**Severity:** blocker
**What:** Requests are registered with `register(request:app:)`, mounted on middleware-only groups.
**Anti-pattern:** `try app.grouped("admin").register(request: DockPageRequest.self, app: app)` — a path-prefixing group; or a `ServerRequestController` route collection standing in for requests the request door already covers.
**Detection:** Establish first what the door can actually reach, because a controller is legitimate whenever the constraints cannot be met — and in some codebases they never can:

- **Read door** — `register(request:app:)` requires `SR.ResponseBody: VaporResponseBodyFactory`.
- **Write doors** — `CreateRequest`/`UpdateRequest`/`DeleteRequest` additionally require `SR.RequestBody: DataModelWriter`. These are Fluent-container doors: a project with no Fluent layer cannot use them for *any* write, and every write controller is correct.

Check the conformances before flagging. Skipping this turns every write controller in a non-Fluent project into a false blocker.

Then flag two shapes. First, a `register(request:app:)` mounted on a group built with a path prefix — `grouped("string")` — rather than middleware only: the client derives the served URL from the request type, so a server-side prefix moves the route out from under that derivation. FOSMVVM rejects this at boot, so it is a startup failure rather than a silent one, but it is worth catching before the boot.

Second, a `ServerRequestController` collection registered for operations `register(request:app:)` covers. Controllers are for what the request door does not reach — a `ReplaceRequest`, a multi-record operation. A collection standing in for ordinary CRUD is a parallel door, and the reason it usually exists is that someone needed to throw a status the typed error could not express, which is `controller-throws-the-declared-error` wearing a different hat.


## Check: controller-derives-its-own-route
**Severity:** blocker
**What:** A `ServerRequestController` mounts at the request's own path and binds the query through `VaporServerRequestMiddleware<TRequest>` — it does not invent either.
**Anti-pattern:**
```swift
private func path(forDestroy base: String) -> [PathComponent] {
    [.constant(base), "destroy"]        // client fetches /<path>, server serves /<path>/destroy
}

let query = try req.query.decode(RequestQuery.self)   // form decoder; client sends JSON
```
**Detection:** For each `ServerRequestController` that overrides `boot(routes:)`, check two things against the client's derivation, which is not negotiable and not visible from the server file:

- **Path.** The client sets `urlComps.path = "/" + Self.path` with **no action suffix** (`Sources/FOSMVVM/Protocols/ServerRequest+Fetch.swift`). A hand-built `[PathComponent]` array that appends a verb — `"destroy"`, `"update"` — serves a URL no client asks for. Flag it.
- **Query.** The client sends the query as a **JSON string** (`try query?.toJSON()`), which `VaporServerRequestMiddleware<TRequest>` decodes. Vapor's `req.query.decode` is a URL-encoded-**form** decoder and cannot read it. Flag a bespoke `boot` that hand-decodes instead of binding through the middleware.

This is the same guarantee `registration-uses-the-request-door` protects — client and server never independently invent a URL — but it fails far worse. A path-prefixing group is **rejected at boot**, loudly, before anything ships. A hand-built path compiles, boots, passes its own tests, and 404s in production.

**Check the tests too, and say so.** This defect hides behind tests that hand-build the server's invented URL (`"\(Controller.baseURL)/destroy?…"`, or a query built with `URLEncodedFormEncoder`) rather than going through `processRequest`. A green suite over a bespoke `boot` is evidence of nothing; a test that calls `processRequest` would have caught it on the first run.

## Check: request-names-follow-the-dictionary
**Severity:** warning
**What:** Request type names follow the naming dictionary (NAMES.md §1a–1c) — the entity noun leads, always: writes and semantic actions are `<Noun><Verb>Request` (`UserCreateRequest`, `IdeaMoveRequest` — never `CreateUserRequest`, `MoveIdeaRequest`); a screen ViewModel's read is `<Noun>Request` with **no verb** (`DocksRequest` — the read is the one canonical fetch); a raw-data read keeps an explicit noun-first `Show` (`UserShowRequest`). Noun-first keeps an entity's whole request family together — verb-first scatters it across the alphabet and buries the entity.
**Anti-pattern:** `CreateClientRequest`, `MoveIdeaRequest`, `GetDashboardRequest`, `MintAgentTokenRequest` — the dictionary's own wrong-column entries, in the wild.
**Detection:** **Enumerate `ServerRequest` conformers — never `*Request`-named types.** The suffix sweep hits domain types that merely end in the word (`PullRequest`, a GitHub wire type, is not a request and not a finding); conformance is the membership test, per this file's standing discipline. Then classify each conformer by its contract, not its name, and check the form the dictionary assigns:

1. **Write / semantic action** (CRUD conformances — Create/Update/Delete/Replace — and write-actioned plain `ServerRequest`s, per `requestbody-adopts-its-fields`' enumeration): the leading token must be the entity, the action verb second-to-last. A leading `Create`/`Update`/`Delete`/`Get`/`Start`/`Stop`/`Mint`/`Move`/`Report`/`Accept`-style token that names the request's **own action** is the hit.
2. **Screen read** (a `ViewModelRequest` whose response is a `RequestableViewModel`): the name is the ViewModel's stem + `Request`, verbless. Resolve against the paired VM (the `viewmodel-request-pairing` walk already computes this): `DashboardViewModel` → `DashboardRequest`; `GetSidebarRequest` and `ShowXxxRequest` forms are hits.
3. **Raw read** (a read-shaped plain `ServerRequest`): `<Entity>ShowRequest`, noun-first — `GetLicenseKeyRequest` is the hit form; `LicenseKeyShowRequest` is its correction.

**The leading-token test is about the request's own action, not any verb-derived word.** A screen noun may legitimately contain one: a confirmation modal's read named after `DeleteConfirmationViewModel` correctly carries `Delete` inside the noun phrase — the request's action is a read, and the paired VM stem settles it. This is why classification precedes the token test.

**A wholesale verb-first codebase gets one finding, not seventy — and the right framing.** Verb-first is the REST idiom's default and the default AI-authored code arrives with; a codebase written before this dictionary existed follows it uniformly, and that *dates* the code, it does not indict it. Report a single area-wide finding anchored at the largest-loss instance (per this file's guidance), listing the family and framing per the dictionary's own callout: existing verb-first names are **rename items — do not add more**. A *new* verb-first name arriving in the reviewed diff is the sharper per-instance finding, because the dictionary now exists to be followed.

**Where the dictionary is silent, do not improvise.** A semantic the dictionary has no row for (a distinct `List` form, say) is a candidate for the owner — the finding derives the nearest dictionary-consistent spelling (a raw list read is still a read: plural noun + `Show`) and says the dictionary should rule.

**The collision-contortion clause (NAMES.md §2), same stage, any projection type:** a display type renamed only to dodge sharing a name with its domain counterpart (`CatalogTier` display type beside `CatalogChannel.Tier`, renamed out of collision fear) is a warning — the module *is* the namespace, the collision is harmless, and a display name is chosen for **meaning**. A more-descriptive name chosen for meaning is fine; the tell is a name whose only explanation is the dodge.

## Check: live-invalidation-is-a-pair
**Severity:** blocker
**What:** For a `@ViewModel(options: [.live])` screen, register a dependency on what the projection reads; invalidate projections of what changed — **both naming the same entity. That pairing is the live contract** (FOSMVVMArchitecture → Live Invalidation; the api-catalog states it verbatim). Plan-loaded records register automatically and Fluent-registered container commits notify automatically — the manual pair covers exactly what Fluent doesn't own: `Application`-hosted actors, computed aggregates, external feeds.
**Anti-pattern:** An `invalidateProjections(of: X)` no factory ever registers on — the emit nudges nobody, and the mutation lands invisibly; a `registerDependency(on: Y)` nothing ever invalidates — the screen renders that state once and never refreshes on its change; a hand-driven Fluent write to a live model inside a bare `database.transaction { }` — the framework cannot see the commit, stays silent (one warning), and no client refreshes, where `liveTransaction` is the wrapper.
**Detection:** Three sets, then pair them — and **enumerate every file before pairing**: registrations routinely live in `+Live.swift` factory extensions and `LiveInvalidation/` sentinel files, and a truncated sweep manufactures a dead-emit finding against a codebase that holds the contract (the verification run's own first sweep did exactly this).

1. **The live set:** every `@ViewModel(options: [.live])` type (by attribute) and its server factory, wherever its extensions live.
2. **The registration set:** every `context.registerDependency(on: <expr>)`. **The emit set:** every `invalidateProjections(of: <expr>)`, `app`- and `req`-flavored, including those wired through composition-root closures (`onChange:` hooks in `configure`).
3. **Pair by entity expression.** An emit with no matching registration is a blocker — name the mutating source and which factory must register. A registration with no matching emit is a blocker — name the state and which mutator must emit. A live factory reading outside its plan (an `appState` snapshot, a computed aggregate) with no registration at all is the same blocker from the read side.
4. **The conformant idiom to recognize:** a sentinel `FOSMVVM.Model` projection type whose shared `static let observed` is referenced by *both* halves — one identifier holds the pairing together, and drift between the halves becomes impossible to spell.
5. **The bare-transaction clause:** a `.transaction { }` writing a registered live container model, outside `liveTransaction` and outside the framework's own write door (`DataModelWriter`), is a blocker — the refresh silently never happens (the catalog's own Don't).

**Not hits:** `context.records(...)` reads (plan-loaded — auto-registered); writes through `DataModelWriter` or `liveTransaction` (framework-notified); non-live ViewModels, which carry no refresh contract to break; and `invalidateProjections` calls present but inert because `useLiveInvalidation` was never enabled — that is a boot-wiring observation, not a pairing defect (the call is documented as a safe no-op).

## Check: server-installs-the-error-middleware
**Severity:** blocker
**Scope:** project
**What:** The server's boot path installs FOSMVVMVapor's `ErrorMiddleware` (ruled 2026-08-25; the api-catalog's entry is the statement — "Don't keep Vapor's stock ErrorMiddleware"). Without it, Vapor's stock middleware flattens every typed rejection — a validation failure, a thrown `ResponseError` — into a bare 500 with prose, and no client can branch on what happened. The field case: a Fields-contract validation ran correctly on the server and the client saw only `500 Internal Server Error`.
**Anti-pattern:** A `configure(_:)`/`registerServices(_:)` that registers requests and enables localization but never touches `app.middleware` — the stock middleware is silently in charge of every error.
**Detection:** In the server target's boot path, find `app.middleware.use(FOSMVVMVapor.ErrorMiddleware.default(environment:))`. **The module qualification matters**: Vapor declares its own `ErrorMiddleware`, the bare name is ambiguous beside it, and `Vapor.ErrorMiddleware.default` type-checks while installing the wrong one — verify which module's middleware is named, not merely that the line exists. Absence in any server target that declares `ServerRequest`s is the blocker; the remedy is the catalog's one-liner. A project-authored middleware demonstrably serving encodable errors typed-and-localized is a judgment call, not an automatic hit — say what it covers and what the FOS middleware would add.
