---
area: fields
generator-skill: fosmvvm-fields-generator
where:
  - "Sources/**/Fields/**/*.swift"
  - "Sources/**/*Fields.swift"
  - "Sources/**/*FieldsMessages.swift"
---

# Fields Checks

The positive pattern lives in the `fosmvvm-fields-generator` skill. A Fields protocol is the **form contract**, defined once and projected into a RequestBody, a Form ViewModel, and a Model. These checks are about the contract leaking, drifting from its messages, or being defined in a way a conformer cannot actually override.

## Reviewer Guidance

- **A Fields protocol defines the user-editable form contract only** — validation rules, localized messages, input handling. It carries no identity. Do NOT recommend adding one "for convenience"; that is the project's `[Architecture] Fields Protocols Define Form Contracts Only` principle, and the reason is that Fields is projected into three artifacts that must not each acquire an identity of their own.
- **Do NOT recommend moving a member out of the protocol into an extension "to simplify."** A member defined only in an extension is statically dispatched, so a conformer's override merely shadows it — calls through the protocol still hit the default. That is a silent OCP failure and the opposite of a simplification.
- Validation lives on the Fields protocol, not in the View and not in the controller. A rule enforced in two places will disagree; a rule enforced only downstream is not part of the contract at all.

## Check: fields-carry-no-identity
**Severity:** blocker
**What:** A Fields protocol declares no `ModelIdType`, `UUID`, or other identity field.
**Anti-pattern:** `var documentId: ModelIdType { get set }` on a `DocumentFields` protocol.
**Detection:** Flag requirements **typed** as identity — `ModelIdType`, `UUID`, or a typed model identifier. Do *not* flag on the name alone: a `String` holding a polymorphic reference is not identity, however it is spelled, and a name-shaped heuristic reports it while missing an identity typed under an alias. Identity belongs to the Model's `@ID()`, not to the form contract — and because Fields projects into a RequestBody, a Form ViewModel, and a Model, an identity here becomes three identities that can disagree. Per the repo's principles, a `ModelIdType` outside `@ID()` requires express approval and documentation; absent that, it is a finding.

## Check: overridable-members-are-requirements
**Severity:** blocker
**What:** A Fields member intended to be overridable is a protocol *requirement* with a default in an extension — never extension-only.
**Anti-pattern:**
```swift
public protocol DocumentFields: ValidatableModel {
    var content: String { get set }
}
extension DocumentFields {
    var validationPolicy: Policy { .strict }   // no requirement — a conformer can only shadow it
}
```
**Detection:** For each Fields protocol, compare its declared requirements against members defined in its extensions — then apply the exemptions below *first*, because they cover most of what an extension legitimately holds.

**Not hits — this is the prescribed shape.** The generator puts these in an extension by design, and flagging them would fail everything it emits:

- `static var …Range` constants
- `static var …Field: FormField<…>` definitions
- per-field `internal func validate{Field}(_:)` helpers
- `{name}FieldsValidateModel(validations:fields:)` — the protocol-prefixed composition helper. Its prefix is the point: a type adopting two Fields protocols writes one `validate` calling `documentFieldsValidateModel` *and* `otherFieldsValidateModel`. It is a composition seam, not an override point (ratified 2026-08-25; the generator states it).

**Hits** are members carrying policy a conformer would plausibly want to change and cannot: a validation strategy, a message source, an on/off switch, a default that is not one of the shapes above. Swift dispatches extension-only members statically, so the conformer's "override" applies only where the concrete type is known — every call through the protocol, or through a generic `some SomeFields`, still gets the default.

This fails silently and in the confusing direction: the override works in a unit test that names the concrete type, and does nothing in the code that goes through the protocol. Say which member, and which call sites keep getting the default.

Note that `ValidatableModel.validate(fields:validations:)` is a real protocol requirement, so a `validate` in a Fields extension is a *default for a requirement* — dynamically dispatched and correctly overridable. Confirm that upstream before grading it either way.

## Check: every-field-has-its-messages
**Severity:** warning
**What:** Every `FormField` has the localized messages it references, and every message is reachable from a field.
**Anti-pattern:** A `FormField` whose `title:` names `messageKey: "title"` while the YAML defines only `placeholder` — or a `…RequiredMessage` on the Messages struct that no validation method ever returns.
**Detection:** Three artifacts must agree, and they drift independently:

- the `FormField` definitions and the `messageKey`s they reference,
- the `@FieldValidationModel` Messages struct's properties,
- the YAML under `{Name}FieldsMessages:`.

Walk all three and flag both directions: a referenced key with no YAML entry, and a Messages property no validation method returns. The first renders an empty string in the form; the second is usually a validation rule that was removed with its message left behind.

Two further shapes worth naming when you see them, because they are the same drift wearing different clothes: a YAML file for a type that no longer exists, and two YAML files defining the *same* key with different content — where which one wins depends on load order.

**Trace reachability, not just presence, for the second direction.** A message returned by a validator that its only caller can never reach — because the caller tests the same condition first and returns something else — is as invisible as one nothing returns. Follow the call path; the syntactic test alone misses it.

**Watch for a fourth artifact competing with the three.** If a Form ViewModel declares its own label and placeholder `@LocalizedString`s, the `FormField` titles are dead — nothing on the rendering path asks for them, which is *why* gaps in the Fields YAML can sit unnoticed indefinitely. Report the competing source, not merely the gap; otherwise the fix looks like "add the missing keys" when it is "delete one of the two sources."

## Check: validation-not-duplicated-downstream
**Severity:** blocker
**What:** A rule declared in Fields is enforced there, not restated in a View, a controller, or a Model.
**Anti-pattern:** `DocumentFields.validateContent` requiring 1–10,000 characters, and a `DocumentView` separately disabling its save button on `content.count > 10_000`. Equally: a template hand-typing `maxlength="200"` where `FormInputOption.rangeLength` already ships the bound; a RequestBody declining to adopt the protocol and copying its static members into a private helper enum; and — the one that drifts first — a Form ViewModel re-declaring the field's label and placeholder as its own `@LocalizedString`s.

**Messages are part of the contract, not decoration.** Fields carries data, presentation, constraints, *and* messages. A title or placeholder re-declared outside the Fields messages struct is the same duplication as a re-declared range, and it goes wrong sooner: nobody notices two YAML files disagreeing until a user reads both spellings.
**Detection:** For each validation rule on a Fields protocol, search the downstream projections — the Form ViewModel's View, the controller handling the RequestBody, the Model's migration — for the same constraint expressed again. Flag the duplicate, naming both sites.

**Two forms are not hits.** A Fluent migration's `.required` column is a storage-integrity constraint that exists whether or not a form does, and carries no length — reporting it pushes toward nullable columns, which is worse. And a bare HTML `required` attribute with no `minlength`/`maxlength` is close to native form semantics and is *the correct case*: it is the absence of the range restatement. Flag the hand-typed bounds, not the requiredness.

Fields exists so one definition projects into three artifacts. A rule restated downstream is a second definition that will drift from the first, and the drift is invisible until the two disagree about a specific value. Note which one is authoritative in the finding: the Fields declaration is, and the downstream copy is what gets deleted.

## Check: results-accumulate-never-assigned
**Severity:** blocker
**What:** A `Validations` changes through its own methods — `append(_:)`, `append(contentsOf:)`, `replace(with:)`, `removeAll(fieldIds:)`. Nothing assigns, appends to, or clears its `validations` array directly. One accumulator carries one write's whole answer, every level writes only its own part of it, and no level can erase what another found.
**Anti-pattern:**
```swift
validations.validations = result              // erases everything an earlier level wrote
validations.validations.append(.init(…))      // reaches around the accumulator to add
validations.validations.removeAll()           // clears without saying which fields
```
**Detection:** Find expressions whose base resolves to a `Validations` and whose next component is `.validations`, followed by an assignment or a mutating call (`append`, `append(contentsOf:)`, `removeAll`, `insert`, subscript assignment, `+=`). Reading `.validations` — iterating it for display, counting it, passing it to `ValidationError(validations:)` — is not a hit.

**Why it is a blocker and not a style note.** A Fields protocol's `validate(fields:validations:)` and a `DataModel`'s own validation both write into the same instance on a server-side save, and a form's per-field check writes into the same instance again on the client. An assignment is not "setting the results", it is deleting somebody else's: the model's refusal disappears because a field-level rule ran second, and nothing reports that it happened.

**A Fields validate uses `replace(with:)`, not `append(contentsOf:)`.** Its rules own exactly the fields they name, and a form runs them again on every edit and once more at submit — appending stacks a second copy of the same message each time, `replace(with:)` re-answers for those fields and leaves every other level's results standing. Report `validations.append(contentsOf: result)` at the end of a `validate(fields:validations:)` as a **warning**: the messages duplicate on the second call, which a user sees as the same complaint listed twice. `validateModel(in:)` is the counter-case and not a hit — it returns its results for the framework to append, because a model-level judgement names no field to replace.

**Version floor first, and expect the compiler to be ahead of you.** `Validations.validations` is `private(set)`, so outside FOSMVVM the assigning spellings no longer compile — in a project pinned to that floor or above, a hit means the code has not been migrated and is not building. Below the floor they compile and are the real defect. Either way the remedy is the same: `replace(with:)` for a Fields validate's own fields and for swapping in a server answer, `append(contentsOf:)` where a level adds to what came before, `removeAll(fieldIds:)` for clearing one field.

## Check: field-identity-comes-from-the-macro
**Severity:** blocker
**What:** A `FormFieldIdentifier` is minted by `#fieldId(\Model.property)` — or `#fieldId(\Model.items, index: i)` for one element of a repeated field — and by nothing else. The identifier's string form is not composed, parsed, or hand-constructed.
**Anti-pattern:**
```swift
fieldId: FormFieldIdentifier(id: "title")                    // a string where a property was meant
fieldId: .init(id: "tags[\(index)]")                     // the representation, hand-forged
fieldId: FormFieldIdentifier._property(in: "Card", named: "title") // the macro's expansion, written out
if messageFieldIds.contains(where: { $0.id == "title" }) { } // the same break, reading
```
**Detection:** Find every construction of a `FormFieldIdentifier` outside FOSMVVM itself: `FormFieldIdentifier(id:)`, `.init(id:)` in a `fieldId:` position, and `FormFieldIdentifier._property(in:named:)`. The leading underscore on that last one is the declaration saying it is the macro's expansion and not a call site — a project writing it by hand has reached past the wall on purpose. Also flag comparisons and lookups against a literal `.id` string, which is the same break from the reading side.

**This is the repo's stringly-typed-identity principle in its named instance for form fields** — report it here, not under `cross-cutting`'s general check. The string has no wall: anyone can mint one, compose one, or route on one, and a renamed property leaves every hand-written site compiling and silently pointing at a field that no longer exists. The macro takes a key path, so the compiler checks it and the rename breaks at every site the moment it happens.

**A second, quieter hit: a mint scoped to the wrong type.** The identity is the key path's root plus the property, so a `validateModel` or controller that writes `#fieldId(\Card.title)` while the form field was declared on `CardFields` names a different field and the message never reaches the form. Outside the Fields protocol's own extension — where `\Self` resolves to the protocol — the root must be the Fields protocol (`#fieldId(\CardFields.title)`). Flag a mint whose root is a type that adopts a Fields protocol carrying that property.

**Version floor first.** `#fieldId` and the sealed initializer arrived together; below that pin the string initializer is public and the hand-written mint is the only spelling available — an adoption candidate, not a violation. Above it, the initializer is internal and a hit is code that has not migrated.

**Two shapes are not hits.** `Codable` decoding of a `FormFieldIdentifier` off the wire is the framework's own path. And a `\Self.property` key path inside a static member is correct — note for the reader that a project running SwiftFormat must disable `redundantStaticSelf`, which strips the root the macro requires.
