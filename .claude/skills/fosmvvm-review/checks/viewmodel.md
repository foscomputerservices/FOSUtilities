---
area: viewmodel
generator-skill: fosmvvm-viewmodel-generator
where:
  - "Sources/**/ViewModels/**/*.swift"
  - "Sources/**/*ViewModel.swift"
  - "Sources/**/*Operations.swift"
  - "Sources/**/*Ops.swift"
---

# ViewModel Checks

The positive pattern lives in the `fosmvvm-viewmodel-generator` skill. This file documents review-only concerns: anti-patterns, drift, common mistakes in ViewModels and their Operations.

## Reviewer Guidance

- Do NOT recommend collapsing the VM/data-store separation. The VM is the single source of truth for what Views read; the `@Observable` data store is what Operations write to. The `bind(appState: .init(...))` projection edge is where they meet — do not propose moving or removing it.
- Do NOT treat `@Observable` classes and structs as substitutable. They have different functional contracts: structs are values, `@Observable` classes participate in SwiftUI tracking. Recommending one in place of the other is an architectural error.
- Re-projection happens at the top of the subtree that owns `bind(appState:)`. The parent body that constructs the child's AppState is the projection edge. Do NOT propose moving projection edges to "simplify."
- **Resolve types by conformance, not by name.** A project protocol declared `LocalDockOperations: ViewModelOperations` is an Operations protocol regardless of its name; a type is a ViewModel because it carries `@ViewModel`, not because it ends in `ViewModel`. Name-keyed detection lets precisely the drifted types escape — which is the code most in need of review.
- Do NOT recommend a random `vmId` as a way to "just make it compile" or to sidestep a missing data identity. If a row has no stable identity, that is a finding about the projection, not a licence to mint one per fetch.
- **Several checks here are cross-layer and need the View layer, which is outside this area's `where:` globs.** Whether a ViewModel is rendered as a repeated row, how many views hold it, and whether a View `switch`es to select a localized value are all answered in `Sources/**/Views*/`. Read those files. Scoping yourself to the matched file list silently degrades four of the checks below to guesses.

## Check: vmid-derivation
**Severity:** blocker on a repeated row; warning elsewhere
**What:** `vmId` **uniquely and stably** identifies the ViewModel from the values it was projected from. Uniqueness alone is not enough: an id that is unique today and different after the next fetch produces exactly the churn this check exists to prevent.
**Anti-pattern:** Three shapes, in rising order of how easily they pass review. `self.vmId = .init()` — random, including as the `??` fallback of an optional id. `self.vmId = .init(id: label)` — an init parameter that identifies nothing. And `self.vmId = .init(id: id)` where the parameter is *named* `id` but holds a truncated, case-folded display derivation, with the real identifier one line below it in the same init.
**Detection:** For each `@ViewModel` type, find every assignment to `vmId` and ask the only question that matters — **does this value uniquely and stably identify this projection?** Rank against the generator's order:

1. An `id` init parameter (`userId`, `groupId`, `agentID`) when the init has one.
2. Otherwise a value composed or hashed from the init parameters that together distinguish the projection.
3. `.init(type: Self.self)` for a ViewModel singleton in identity — rule 2's degenerate case, where the values are always the same. For a singleton, 2 and 3 are both correct; prefer 3 when the composed values are literally invariant.
4. A bare `ViewModelId()` / `.init()` — random, almost never desirable.

**Do not stop at "it used an init parameter," and do not stop at the parameter's name.** Read the init's full parameter list and the DocC on each candidate. Flag a `vmId` built from a value that has been **lossily transformed for display** — truncated, case-folded, defaulted to a placeholder, or interpolated for reading — whenever an untransformed identifier is available in the same init. A `label`, `name`, or `title` is the obvious form; a parameter *named* `id` that carries a shortened display derivation is the form that slips through, and a factory writing a literal default (`label ?? "(unnamed)"`) collides every un-named instance on one string.

**Check stability, not just uniqueness.** An array ordinal is unique within a projection and passes a naive uniqueness test, but every id shifts the moment the collection's origin moves — a retention window dropping its oldest entries re-identifies every row. Accept an ordinal only when the collection is append-only from a fixed origin, and say so in the finding.

Also flag the random form wherever it appears, and `.init(type: Self.self)` on a type rendered as a repeated row — every row then shares one id and they collide.

**When no adequate parameter exists, say that.** For the `??`-random shape in particular, the answer is often that no init parameter distinguishes the instance — in which case the finding is about the projection, not the ViewModel: name what the factory must start passing. Do not push the reviewer into recommending a second-best parameter merely because it is already in scope.

**Severity, and only severity, depends on "repeated row."** Grade uniqueness and stability from the ViewModel alone — that decides whether there is a finding. Then visit the View layer to set the tier: search for a `ForEach` or `List` iterating a collection of this type, or a parent ViewModel holding it as an array. Those files sit outside this area's globs; read them anyway. A bad id on a repeated row is a **blocker** — a new or colliding id makes SwiftUI tear down and rebuild rows on every refresh, taking selection, scroll position and focus with it. Anywhere else it is a **warning**: wasteful rather than broken, but still not what anyone meant to write.

## Check: vmid-not-shadowed-by-stored-id
**Severity:** blocker
**What:** A `@ViewModel` type does not declare a stored `id` property that displaces FOSMVVM's `Identifiable` witness.
**Anti-pattern:** `public let id: String?` on a `@ViewModel` type — the concrete property wins over the protocol extension, so the type's `ID` becomes `String?` and the carefully-derived `vmId` is no longer the type's identity. Two rows with a `nil` id then collide.
**Detection:** FOSMVVM supplies `var id: ViewModelId { vmId }` (`Sources/FOSMVVM/Protocols/ViewModel.swift`). For each `@ViewModel` type, flag a stored property named `id` — most urgently when its type is `Optional`, which collides every un-identified row on `nil`. A data identity is welcome on the type; it just must not be spelled `id`. An `id` that is an init *parameter* only, never stored, is not a hit.

The stored-property test stands on its own — do not lean on `ForEach(items, id: \.vmId)` at call sites as corroboration unless that spelling is otherwise rare in the project. Many codebases write it uniformly, including over types with no stored `id` at all, in which case the signal fires everywhere and discriminates nothing.

## Check: viewmodel-not-a-mega-vm
**Severity:** warning
**What:** One top-level ViewModel per screen, composing child ViewModels — not one ViewModel serving several unrelated surfaces.
**Anti-pattern:** A single ViewModel whose localized properties are MARK-sectioned into three unrelated surfaces (a strip, a setup panel, an inspector) and which is consumed by three or more sibling views.
**Detection:** **Both** signals must fire, not either one. (a) Three or more sibling views hold the type, **and** (b) its localized properties are internally sectioned into surfaces that are unrelated to each other. Say which surfaces you can see, so the split is actionable; the remedy is composed child ViewModels, one per surface.

A view count alone is not a hit. Three mutually-exclusive presentations of one screen — a mode switcher, compact and regular variants, a board/list/graph toggle under one container — legitimately share one ViewModel, and such a type shows no sectioning because there are no unrelated surfaces to section. Pairs with `viewmodel-view-one-to-one` in `swiftui-view.md`, which sees the same defect from the View side.

## Check: enum-localization-not-flattened
**Severity:** warning
**What:** The ViewModel, not the View, selects which localized value a case gets. A View that `switch`es to pick between the ViewModel's localized properties is doing the ViewModel's job.
**Anti-pattern:** Ten `@LocalizedString` properties named for each case of a `Stage` enum, with the View writing `switch stage { case .checking: Text(viewModel.stageChecking) … }`.
**Detection:** Start from the **View**, not the ViewModel: find every `switch` in the View layer that selects among a ViewModel's localized properties, and flag the property group it selects from. That test is the whole rule, and it settles the cases that a name-based test leaves ambiguous:

- The switched enum does not have to be one the ViewModel exposes. A View-local enum picking between two of the ViewModel's localized properties is the same defect.
- Partial coverage still counts. Two properties for two of an enum's three cases is a hit; the selection is in the wrong layer either way.
- A group of case-named properties is **not** a hit when the ViewModel itself vends the selection (`rotateTitle(for:)`) and the View renders one value. That is the generator's pattern, and a detection keyed on property names alone would flag the best example in the codebase.

## Check: ops-naming-trio
**Severity:** warning
**What:** The Operations trio for `{Name}ViewModel` is `{Name}ViewModelOperations`, in `{Name}ViewModelOperations.swift`.
**Anti-pattern:** `LocalDockOperations` in `LocalDockOperations.swift` beside `LocalDockViewModel`.
**Detection:** For each protocol conforming to `ViewModelOperations`, resolve the ViewModel it serves — normally through that ViewModel's `operations` property, whose declared type names the protocol — and compare stems. Flag a mismatch. Beyond consistency this has teeth: a drifted name is what a name-keyed detection misses, so the misnamed type is the one that escapes the other checks in this file.

## Check: viewmodel-request-pairing
**Severity:** blocker for a broken round trip; warning for a stem mismatch
**What:** A `RequestableViewModel` and its `Request` point at each other.
**Anti-pattern:** `DocksViewModel` declaring `typealias Request = RunsRequest`, where `RunsRequest`'s response is `RunsViewModel`. Both types satisfy their constraints; the pairing is nonsense, and a fetch returns the wrong screen's data.
**Detection:** **The compiler does not check this.** `RequestableViewModel` requires `associatedtype Request: ViewModelRequest`; `ViewModelRequest` requires `ResponseBody: RequestableViewModel`. Each side constrains the *kind* of the other; neither constrains the round trip. A ViewModel pointing at another ViewModel's request compiles clean.

Walk it for each `RequestableViewModel`, in two mechanical steps:

1. Read its `typealias Request`.
2. Read that request's response type — **from the stored `responseBody` property**, e.g. `public var responseBody: DocksViewModel?`. Do not grep for `typealias ResponseBody`: a `ViewModelRequest` almost never writes one, because `ResponseBody` must *be* the externally-declared ViewModel. Inference through the stored property is the documented form (`Sources/FOSMVVM/Protocols/ViewModelRequest.swift` DocC) and the form the `@ViewModel` macro generates. An explicit `typealias ResponseBody` here is the unusual case, not the norm — and is not itself a finding.

Flag any pair where step 2 does not land back on the ViewModel you started from. That is the blocker.

**Stems must correspond, not match exactly.** Both `UserViewModel` ↔ `UserViewModelRequest` (the framework's DocC) and `DocksViewModel` ↔ `DocksRequest` (the common project spelling) are correct; a project should pick one and hold it. Flag a stem that corresponds to *no* reading — `DocksViewModel` ↔ `FleetRequest` — as a **warning**, and say which spelling the rest of the project uses. Do not report a whole codebase for choosing the shorter form.

**Scope: a `@ViewModel` that does not conform to `RequestableViewModel` is out of scope** — it has no `Request` to walk. That covers children composed into a parent's response, which are fetched through the parent's request.

`clientHostedFactory` types are also out of scope, but for a reason worth knowing rather than assuming: the macro **does** synthesize a `ClientHostedRequest: ViewModelRequest` into the type, so you will see one in the symbol graph. Its round trip is closed by construction and cannot drift, which is why it needs no review — not because the type "has no request."

`.live` changes nothing about the pairing; ignore the option when grading this check.

**The walk is one-directional and that is deliberate.** Starting from every `RequestableViewModel` catches VM → Request → other-VM. It does not catch an orphaned `ViewModelRequest` nothing points at. Enumerate the `ViewModelRequest` conformers too and confirm the two sets are a bijection — an unreferenced request is usually a screen that was deleted without its wire contract.

## Check: vm-holds-scalars-only
**Severity:** blocker
**What:** A `@ViewModel` type's stored properties are values — `Bool`/`Int`/`Double`/`String`, enums, `Localizable` values, value-type structs, child ViewModels — never a reference to an `@Observable` class. Not for ops dispatch, and not as a pass-through "so a child can `.bind` through me" (forward-projection rule 4, architecture-patterns.md). The reference lives on the View via `@Environment(X.self)`; ops receive storage through the View's mutation closure as `output storage:`; a child's `.bind` happens in its direct parent's body reading that parent's own environment. The VM is a `Codable` snapshot — a smuggled reference corrupts projection, breaks invalidation tracking at the edge, and carries mutable identity into the value world.
**Anti-pattern:**
```swift
@ViewModel
struct PreferencesPageViewModel {
    let userSettings: UserSettings   // @Observable class reference
    // ...rationale in review: "so the child can bind through me" / "for ops dispatch"
}
```
**Detection:** For each `@ViewModel`-declared type (by the macro attribute, not the name — and enumerate per attribute, not per file: two VMs share a file in the field), resolve every **stored** property's type and flag any that is an `@Observable` class — including optionals, collections, and references buried one level down inside a stored value type *the project owns* (the smuggle survives being wrapped in a struct; framework value types are deliberately not descended into — a consumer repo cannot police the framework's internals). The macro's compile gates (`Codable`, `Sendable` via `ServerRequestBody`) mean a smuggled reference arrives wearing fingerprints — use them as confidence tells:

- an `@Observable` class retrofitted with `Codable` so the VM compiles — the retrofit is itself part of the finding; and a `@MainActor` or `@unchecked Sendable` annotation on it is the second fingerprint, because `@MainActor @Observable` passes the `Sendable` gate silently, leaving `Codable` as the only pressure;
- hand-written `CodingKeys` omitting the reference, with the plumbing omission requires (`var`-with-default, or a hand-written `init(from:)`) — worse than the retrofit, because the property decodes absent across the wire and the VM behaves differently on its two sides.

**Existentials need one extra step.** A stored `any P` does not statically say class-or-value: resolve the conformers. When any conformer is `@Observable`, or `P` is `AnyObject`-constrained and an `@Observable` class conforms, the stored existential *is* the reference — flag it; the protocol wrapper is laundering, not insulation. A stored existential whose conformers are all value types is not this blocker, but note it against the snapshot doctrine.

**Two shapes are NOT hits — both are the framework's own patterns:**

- The **computed** `operations` property minting a fresh ops instance per access (`var operations: any XxxViewModelOperations { isStub ? StubOps() : Ops() }`) — the framework's documented idiom. This check reads stored properties; do not improvise it onto computed ones.
- `@FormFieldModel` property-wrapper backings on a Form ViewModel (ratified 2026-08-25). The wrapper is an `@Observable`, `Codable` class *by the framework's own design* — hidden infrastructure, not the cyclic pattern this check exists for: a client-stored `@Observable` couples the VM back into the store it was projected from, which the framework's own form-binding mechanism does not. Re-verify this carve-out against the consumer's pin rather than assuming it; the Forms surface evolves.

**Do NOT accept "the VM keeps it for ops dispatch" as a mitigation** (ruled 2026-08-25) — that was this rule's historical misreading, and the ops path never needs the reference on the VM. A stored property of some *other* class type (a formatter, a service handle) is not this check's blocker, but note it against the snapshot doctrine — stored properties are values — and let the finding say what value should be projected instead. Value-typed identity spellings (`String`-typed ids with a module-boundary rationale) are other checks' business — this check fires on references only. Pairs with `appstate-no-observable-args` (the projection edge's argument side) and `view-no-read-through-vm-ref` in `swiftui-view.md` (the read side); this check fires on the stored reference itself, whether or not anything reads through it yet.

## Check: computed-properties-dont-serialize
**Severity:** blocker on an encoded-JSON surface; warning where a decoded Swift instance renders
**What:** A ViewModel stores every value a rendering surface reads. Computed properties do not exist in the encoded JSON — only stored properties serialize (architecture-patterns.md → Computed Properties Don't Serialize). A derived presentation value is computed at projection time — in `init`, or in the factory that calls it — and stored; the wire carries the function's *output*, never the function.
**Anti-pattern:**
```swift
@ViewModel
struct CardViewModel {
    let cards: [Card]
    var hasCards: Bool { !cards.isEmpty }  // absent from the encoded JSON
    var cardCount: Int { cards.count }     // absent from the encoded JSON
}
```
**Detection:** For each `@ViewModel`-declared type (by attribute, not name), find every **computed instance property** — an explicit accessor block on a `var`, in the type body or an extension. Two source shapes look computed and are not hits by construction:

- **Property-wrapper declarations** (`@LocalizedString`, `@LocalizedInt`, `@FormFieldModel`, …). The source shows a wrapper-projected `var`, but the wrapper's backing storage is stored and encodes under the property's key. Never flag these.
- **The computed `operations` idiom** (`var operations: any XxxViewModelOperations { isStub ? StubOps() : Ops() }`) — the framework's documented wiring, already carved out under `vm-holds-scalars-only`. It carries no presentation data and is *meant* to be absent from the wire: each side mints its own ops.

For what remains, grade by the surface that renders this VM — cross-layer, read the Views and templates (the area globs do not include them; read them anyway):

- **Encoded-JSON surface (a Leaf template, a React component fed the serialized VM): blocker when read live, warning when not.** The property is simply absent from the JSON. LeafKit renders the read silently empty — no error, no log line — so this is precisely the drift the runtime cannot catch; in a condition (`#if(vm.hasItems)`) the misevaluation is just as silent, and the break can land either way (a section that never shows, or one that always does) — the finding does not depend on which. When resolving template reads (the `view-reads-vm-only` clause in `view.md`), follow the read's **whole path** through nested stored types: a read is resolved only when every step lands on a stored property of the type actually rendered — a computed anywhere along the path means the JSON does not carry it. A read in a **dead template** (no render site, no live `#extend` parent) does not upgrade to blocker — the template is the `view` area's dead-template finding; here the computed stays a warning. A computed nothing reads yet, on a JSON-rendered VM, is the same trap unsprung — warning, and say which template will spring it.
- **SwiftUI (a decoded Swift instance renders): warning.** The decoded instance recomputes the property from its stored siblings, so it renders — but the derivation ran on the wrong side of the wire, against the projection doctrine (functional-discipline: derived values are projected *into* the artifact at projection time). One shape is not a hit here: a computed that **selects among** the VM's stored localized properties and returns one unchanged — that is the selection-vending pattern `enum-localization-not-flattened` ratifies, and every value it can vend is already on the wire. A computed that *mints* a value (formats, concatenates, counts, compares) is the hit. On an encoded-JSON surface even the selection form is a finding — the template cannot invoke it, so the chosen value must be stored.

**Derive-on-the-owner is the correct shape, not a hit.** A computed on a stored enum or value type (`level.indent`, `availability.localizableString`) whose output the VM **freezes into a stored property at init** (`self.indent = level.indent`) is architecture-patterns' own remedy — the derivation lives on the owner, the wire carries its output. Do not flag the owner's computed; the finding exists only when the VM *fails* to store the output and a surface reads through to the computed.

**Resolve reads against the rendered type, never by property name.** One codebase holds the same property name in both forms — stored-precomputed on the page VM, computed on the card VM — and only the card's reads are findings. A name-keyed sweep flags the correct one and misses nothing-in-particular; walk each template read to the type it renders.

**The remedy names the projection site,** not just "make it stored": the value moves into `init` (or the factory) and the property becomes `let`. Where a Leaf template only needs emptiness or a count, the generator's guidance also allows the template-side built-ins (`#if(count(cards) > 0)`, `#count(cards)`) with no VM property at all — offer both, let the owner choose.

## Check: no-generic-error-architecture
**Severity:** warning
**What:** Error UI is not special — errors are data to render, through the same ViewModel → View pattern as everything else (architecture-patterns.md → Error UI Is Not Special). Each error scenario gets its own client-hosted ViewModel whose init takes the **specific** `XxxRequest.ResponseError` — tight coupling is good here — or, on SwiftUI, the typed throw routes to the framework's localizing alert surface (`.alert(error:)` over `@LocalizableError` conformers). A project-authored layer that handles "all errors" uniformly is the finding.
**Anti-pattern:** An `ErrorDisplayable`-shaped protocol; a single `ErrorViewModel`/`ToastViewModel` constructed from `any Error` or a bare message string at many catch sites; error middleware that renders one display shape for every throw; a central `switch`/downcast ladder over `any Error` re-deriving what typed catches already know.
**Detection:** Four shapes, resolved by shape rather than name:

1. **The unifying protocol.** A project-declared protocol whose requirements are display fields (message, title, severity, icon) adopted by error types or error ViewModels and consumed by one shared render path.
2. **The generic ViewModel.** One VM whose init takes `Error`, `any Error`, or a plain message `String`, constructed from catch sites of *different* request types. The per-error form takes the concrete `ResponseError`; an init parameter that has forgotten which error it holds is the tell.
3. **The central handler.** Error middleware, or one function catching broadly and producing display output on behalf of many routes — each route knows its request type, so it knows its error type; the uniform handler re-derives at runtime what the catch clause states in its pattern.
4. **The erosion signal.** A catch site erasing a typed error to `error.localizedDescription` (or interpolating it) for display, when the typed error carries localized content the framework surface would have rendered. One site is a note inside another finding; the same erasure repeated across catch sites is the generic architecture emerging without a name — flag the trend once, listing the sites.

**Three shapes are NOT hits:**

- **One shared toast/alert template rendering many per-error VMs.** The truth statement's own example renders `MoveIdeaErrorViewModel` through `Shared/ToastView` — the *surface* may be shared; the *ViewModel* must be per-error. (Each VM rendered through the shared template must still satisfy the template's reads — that agreement is `view-reads-vm-only`'s, checked per rendered VM. Whether a shared template may carry `#if`-guarded reads of fields only some of its VMs declare is an open doctrine question — candidate on file in the coverage ledger; note the shape when seen, do not grade it either way.)
- **Error-binding transport to the presentation surface.** A `Binding<Error?>` filled in a catch and presented by the framework's `.alert(error:)` is routing the throw to where it renders — transport, not architecture. A hand-rolled version of a framework transport helper is a different finding (hand-rolled framework products), not this one.
- **Typed catches per route** (`catch let error as XxxRequest.ResponseError`), each building its own VM — that is the positive pattern, however many of them a codebase accumulates. Thirteen per-error VMs through one toast template is the doctrine *held*, not violated; do not count VMs and call the number a smell.

Credential-rejection defensive shapes belong to `no-defensive-error-for-credential-rejection`, and status-keyed branching to `status-interpreted-as-result` (`cross-cutting`) — this check reads the display-architecture side only.

## Check: ops-no-output-reads
**Severity:** blocker
**What:** Operations methods must not read from the same mutable state they write to. They take inputs, transform, write outputs — never read-modify-write on the output struct.
**Anti-pattern:** A method on a `*ViewModelOperations` conformer that both reads from and writes to the same parameter (e.g., `settings.electrodeSettings[index].polarity` read, `settings.selectedPolarity = ...` write).
**Detection:** For each type conforming to FOSMVVM's `ViewModelOperations` protocol — directly or through a project protocol that refines it — read each method body. Flag methods that both READ from and WRITE to the same parameter within the same call. Resolve conformance, not the name: a project protocol declared `LocalDockOperations: ViewModelOperations` is in scope despite not matching `*ViewModelOperations`, and a name-matching detection would let exactly the drifted types escape review.

## Check: ops-not-async-unless-needed
**Severity:** warning
**What:** FOSMVVM Operations should not be `async` unless they actually await something.
**Anti-pattern:** `func toggleEnabled(...) async throws { settings.isEnabled = enabled }` — declared `async throws` with no `await` in the body.
**Detection:** For methods on `ViewModelOperations` conformers (resolved by conformance, not by name — see `ops-no-output-reads`) declared `async` (or `async throws`), grep the body for `await`. Flag methods where no `await` is present. A stub whose `async` signature is forced by a protocol whose live conformer does real I/O is not a hit.

## Check: ops-output-param-last
**Severity:** warning
**What:** For clientHostedFactory ViewModels, the output parameter must be the last parameter in the Operation signature and labeled `output:`.
**Anti-pattern:** `func myOp(output settings: Settings, otherInput: Bool)` — output before inputs. Or `func myOp(inputs..., settings: Settings)` — output not labeled `output:`.
**Detection:** Identify ViewModels using `clientHostedFactory`. For their Operations, verify each method signature ends with `output <name>: <Type>`. Flag methods where the output is not last or not labeled `output:`. Server-based VMs (no `clientHostedFactory`) are exempt.

## Check: appstate-no-observable-args
**Severity:** blocker
**What:** `bind(appState: .init(...))` arguments must be plain values projected from `@Observable` state, not `@Observable` types passed by reference.
**Anti-pattern:** `bind(appState: .init(settings: programmingSettings))` where `programmingSettings` is an `@Observable final class`. Crosses the projection boundary.
**Detection:** Find all `bind(appState: .init(...))` call sites. For each argument, determine if its type is `@Observable`. Flag any `@Observable`-typed argument. (Reading a property OFF an `@Observable` and passing the value is fine.)
