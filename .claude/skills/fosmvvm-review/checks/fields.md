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

**Two shapes are not hits.** A Fluent migration's `.required` column is a storage-integrity constraint that exists whether or not a form does, and carries no length — reporting it pushes toward nullable columns, which is worse. And a bare HTML `required` attribute with no `minlength`/`maxlength` is close to native form semantics and is *the correct case*: it is the absence of the range restatement. Flag the hand-typed bounds, not the requiredness.

Fields exists so one definition projects into three artifacts. A rule restated downstream is a second definition that will drift from the first, and the drift is invisible until the two disagree about a specific value. Note which one is authoritative in the finding: the Fields declaration is, and the downstream copy is what gets deleted.
