---
name: fosmvvm-fields-generator
description: Generate FOSMVVM Fields protocols with validation rules, FormField definitions, and localized messages. Define form contracts once, validate everywhere.
homepage: https://github.com/foscomputerservices/FOSUtilities
metadata: {"clawdbot": {"emoji": "📋", "os": ["darwin", "linux"]}}
---

# FOSMVVM Fields Generator

> **Read [`shared/functional-discipline.md`](../shared/functional-discipline.md) before proceeding.** Every rule below derives from it.

Generate Form Specifications following FOSMVVM patterns.

## Conceptual Foundation

> For full architecture context, see [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md) | [OpenClaw reference]({baseDir}/references/FOSMVVMArchitecture.md)

> **API catalog:** check [`../shared/api-catalog/FOSMVVM.md`](../shared/api-catalog/FOSMVVM.md) § Forms, § Validation before hand-writing helpers.

A **Form Specification** (implemented as a `{Name}Fields` protocol) is the **single source of truth** for user input. It answers:

1. **What data** can the user provide? (properties)
2. **How should it be presented?** (FormField with type, keyboard, autofill semantics)
3. **What constraints apply?** (validation rules)
4. **What messages should be shown?** (localized titles, placeholders, errors)

### Why This Matters

The Form Specification is **defined once, used everywhere**:

```swift
// Same protocol adopted by different consumers:
struct CreateIdeaRequestBody: ServerRequestBody, IdeaFields { ... }  // HTTP transmission
@ViewModel struct IdeaFormViewModel: IdeaFields { ... }              // Form rendering
final class Idea: Model, IdeaFields { ... }                          // Persistence validation
```

This ensures:
- **Consistent validation** - Same rules on client and server
- **Shared localization** - One YAML file, used everywhere
- **Single source of truth** - Change once, applies everywhere

> ← **Functional discipline:** one input, three projections; duplicating the definition forks the input layer.

### Connection to FOSMVVM

Form Specifications integrate with:
- **Localization System** - FormField titles/placeholders and validation messages use `LocalizableString`
- **Validation System** - Implements `ValidatableModel` protocol
- **Request System** - RequestBody types adopt Fields for validated transmission
- **ViewModel System** - ViewModels adopt Fields for form rendering, hosting each field as `@FormFieldModel(…Field) public var …`

> **A Fields protocol never carries an identity** (no `id: ModelIdType?`). An update names its target with a `TargetedQuery` whose `target: ModelIdentity` is the identity the form ViewModel carried, echoed back; the body (Fields) carries only the editable values. **SOLID protected: DIP and encapsulation** — a raw id in the form contract can be minted and forged, and drags a persistence type into the shared module.

## When to Use This Skill

- Defining a new form (create, edit, filter, search)
- Adding validation to a request body
- Any type that needs to conform to `ValidatableModel`
- When `fosmvvm-fluent-datamodel-generator` needs form fields for a DataModel

## What This Skill Generates

A complete Form Specification consists of **3 files**:

| File | Purpose |
|------|---------|
| `{Name}Fields.swift` | Protocol + FormField definitions + validation methods |
| `{Name}FieldsMessages.swift` | `@FieldValidationModel` struct with `@LocalizedString` properties |
| `{Name}FieldsMessages.yml` | YAML localization (titles, placeholders, error messages) |

## Project Structure Configuration

Replace placeholders with your project's actual paths:

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{ViewModelsTarget}` | Shared ViewModels SPM target | `ViewModels`, `SharedViewModels` |
| `{ResourcesPath}` | Localization resources path | `Sources/Resources` |

**Expected Structure:**
```
Sources/
  {ViewModelsTarget}/
    FieldModels/
      {Name}Fields.swift
      {Name}FieldsMessages.swift
  {ResourcesPath}/
    FieldModels/
      {Name}FieldsMessages.yml
```

## How to Use This Skill

**Invocation:**
/fosmvvm-fields-generator

**Prerequisites:**
- Form purpose understood from conversation context
- Field requirements discussed (names, types, constraints)
- Entity relationship identified (what is this form creating/editing)

**Workflow integration:**
This skill is used when defining form validation and user input contracts. The skill references conversation context automatically—no file paths or Q&A needed. Often precedes fosmvvm-fluent-datamodel-generator for form-backed models.

## Pattern Implementation

This skill references conversation context to determine Fields protocol structure:

### Form Analysis

From conversation context, the skill identifies:
- **Form purpose** (create, edit, filter, login, settings)
- **Entity relation** (User, Idea, Document - what's being created/edited)
- **Protocol naming** (CreateIdeaFields, UpdateProfile, LoginCredentials)

### Field Design

For each field from requirements:
- **Property specification** (name, type, optional vs required)
- **Presentation type** (FormFieldType: text, textArea, select, checkbox)
- **Input semantics** (FormInputType: email, password, tel, date)
- **Constraints** (required, length range, value range, date range)
- **Localization** (title, placeholder, validation error messages)

### File Generation Order

1. Fields protocol with FormField definitions and validation
2. FieldsMessages struct with @LocalizedString properties
3. FieldsMessages YAML with localized strings

### Context Sources

Skill references information from:
- **Prior conversation**: Form requirements, field specifications discussed
- **Specification files**: If Claude has read form specs into context
- **Existing patterns**: From codebase analysis of similar Fields protocols

## Key Patterns

### Protocol Structure

```swift
public protocol {Name}Fields: ValidatableModel, Codable, Sendable {
    var fieldName: FieldType { get set }
}
```

> **The protocol carries no messages instance.** The validation messages are minted statically on the extension (see *Validation Messages Are Minted, Not Read* below), so a `var {name}ValidationMessages: {Name}FieldsMessages { get }` requirement has no reader — and keeping one leaves the broken read a keystroke away.

> **Overridable-with-a-default member? Declare it as a *requirement* AND provide the default.** If you want a Fields member to have a zero-config default that a conformer can still override (a validation policy, a message source), it must be a protocol **requirement** with a default in an extension. A member defined *only* in an extension is statically dispatched — a conformer's "override" merely **shadows** it and calls through the protocol/a generic `some {Name}Fields` still hit the default. That's a silent OCP failure. See [Architecture Patterns → Requirement + Default = a Real Override](../shared/architecture-patterns.md).

> **The `{name}FieldsValidateModel(validations:fields:)` composition helper lives in the extension deliberately — it is not an override point** (ratified 2026-08-25). Its protocol-derived prefix is the point: a type adopting two Fields protocols writes one `validate(fields:validations:)` that calls `documentFieldsValidateModel(…)` *and* `otherFieldsValidateModel(…)` — a composition seam, so the requirement-plus-default rule above does not apply to it. (`ValidatableModel.validate(fields:validations:)` itself *is* a real requirement, so a `validate` default in a Fields extension is dynamically dispatched and correctly overridable.)

### FormField Definition

> **`#fieldId` is the only way to mint a `FormFieldIdentifier`** — its initializer is internal.
> This is **encapsulation**, the precondition SOLID assumes: a hand-written `"content"` is a
> stringly-typed identity anyone can mint, parse, or mistype, and a renamed property leaves it
> silently pointing at nothing. The macro reads the property from a **rooted** key path
> (`\Self.content` inside the protocol's extension, `\IdeaFields.content` elsewhere), so the compiler
> checks it and a rename breaks every site at build time. For one element of a repeated field,
> pass the position: `#fieldId(\Self.tags, index: index)`. Never compose, parse, or
> hand-construct the identity's string.

> **The identity is scoped to the type the key path names**, so `\Card.title` and `\Board.title`
> are different fields. `\Self` inside the Fields protocol's own extension resolves to the
> **protocol**, which is what makes the contract shared: the one line mints the one identity for
> the request body, the form ViewModel and the `DataModel` alike. Anywhere outside that extension —
> a `validateModel` on the Fluent model, a controller building results by hand — name the Fields
> protocol (`\IdeaFields.content`), never the adopting type, or the message lands on a field the
> form does not show.

> **SwiftFormat users:** disable `redundantStaticSelf` in the project's `.swiftformat`. Inside a static member it strips the root from `\Self.content`, leaving `\.content`, which the macro cannot resolve to a property name.

```swift
static var contentField: FormField<String?> { .init(
    fieldId: #fieldId(\Self.content),
    title: .localized(for: {Name}FieldsMessages.self, propertyName: "content", messageKey: "title"),
    placeholder: .localized(for: {Name}FieldsMessages.self, propertyName: "content", messageKey: "placeholder"),
    type: .textArea(inputType: .text),
    options: [
        .required(value: true)
    ] + FormInputOption.rangeLength(contentRange)
) }
```

### FormField Types Reference

| FormFieldType | Use Case |
|---------------|----------|
| `.text(inputType:)` | Single-line input |
| `.textArea(inputType:)` | Multi-line input |
| `.checkbox` | Boolean toggle |
| `.select` | Dropdown selection |
| `.colorPicker` | Color selection |

### FormInputType Reference (common ones)

| FormInputType | Keyboard/Autofill |
|---------------|-------------------|
| `.text` | Default keyboard |
| `.emailAddress` | Email keyboard, email autofill |
| `.password` | Secure entry |
| `.tel` | Phone keyboard |
| `.url` | URL keyboard |
| `.date`, `.datetimeLocal` | Date picker |
| `.givenName`, `.familyName` | Name autofill |

### Validation Messages Are Minted, Not Read

A `ValidationResult` carries its message to the client, so the message must be a `LocalizableString` minted from the messages model's key path — exactly the way a `FormField`'s `title:` and `placeholder:` above are minted. Put one static mint on the extension per message:

```swift
static var contentRequiredMessage: LocalizableString {
    .localized(for: {Name}FieldsMessages.self, propertyName: "content", messageGroup: "validationMessages", messageKey: "required")
}

static var contentOutOfRangeMessage: LocalizableString {
    .localized(for: {Name}FieldsMessages.self, propertyName: "content", messageGroup: "validationMessages", messageKey: "outOfRange")
}
```

The key path is identical to the `@LocalizedString` wrapper's, so the YAML below does not change. The `@FieldValidationModel` struct stays exactly as it is: its `@LocalizedString` declarations are what say which keys the YAML must carry.

> **Never read the message off an instance of the messages struct.** A `@LocalizedString` property binds its key only while its own model is being encoded, so a message pulled out of one and carried in a `ValidationResult` encodes empty — the user gets a blank message, in the form and on the wire, with nothing failing loudly enough to notice.

### Validation Method Pattern

A per-field method answers only for its own field. The guard is the shipped idiom — `fields?.contains(Self.contentField) ?? true` — so a `nil` `fields` (check everything) and a list naming this field both proceed, and a list naming other fields returns `nil`:

```swift
internal func validateContent(_ fields: [FormFieldBase]?) -> [ValidationResult]? {
    guard fields?.contains(Self.contentField) ?? true else {
        return nil
    }

    var result = [ValidationResult]()

    if content.isEmpty {
        result.append(.init(
            status: .error,
            field: Self.contentField,
            message: Self.contentRequiredMessage
        ))
    } else if !Self.contentRange.contains(NSString(string: content).length) {
        result.append(.init(
            status: .error,
            field: Self.contentField,
            message: Self.contentOutOfRangeMessage
        ))
    }

    return result.isEmpty ? nil : result
}
```

### Validation Accumulates; A Fields Validate Replaces Its Own Fields

`validate(fields:validations:)` composes the per-field methods and hands the results to `replace(with:)` on the `Validations` it was handed — the Fields rules own exactly the fields they name, so they re-answer for those fields and leave every other level's results standing. `Validations.validations` is `private(set)`; `append(_:)`, `append(contentsOf:)`, `replace(with:)` and `removeAll(fieldIds:)` are the whole of the API, and an assignment no longer compiles:

```swift
func validate(fields: [FormFieldBase]?, validations: Validations) -> ValidationResult.Status? {
    let result = {name}FieldsValidateModel(validations: validations, fields: fields) ?? []
    validations.replace(with: result)
    return validations.status
}
```

> **OCP.** One `Validations` is the single accumulator every level adds to — the Fields rules, then the `DataModel`'s own `validateModel(in:)` rules, then the server's answer on the way back. Each level extends the judgement without modifying what the level before it found. Assign the array instead and the extension point is gone: a `DataModel` that adds a rule after the Fields rules erases them, and the user is told about the second problem with their form only after fixing the first.

> **Why `replace(with:)` and not `append(contentsOf:)` here.** A form calls its Fields validate on every edit and again at submit. Appending would stack a second copy of the same message each time; `replace(with:)` is field-scoped, so running it twice on one `Validations` leaves one answer per field. `validateModel(in:)` still returns its results for the framework to append — it judges the model as a whole and owns no field to replace.

Read the accumulator through `validations.status`, `hasError`, `isValid`, `hasError(for:)` and `validationError` rather than its contents; `.init(for:)` over a local array answers only for the slice you just computed and misses what another level appended.

### Model-Level Results

A rule about the model as a whole — not about any one field — makes a result that names no field, with `ValidationResult(status:message:)`:

```swift
if activeCards.count >= Self.cardLimit {
    validations.append(.init(status: .error, message: Self.boardFullMessage))
}
```

`ValidationResult.Message.addressesModel` is how such a message says it names none. The field views ignore it; the form shows it by applying `.withFormValidations()`, so a Fields protocol that emits model-level results must say so in its documentation — a form that omits the modifier shows nothing at all for them. Cross-field conflicts are the other case: name **both** fields (`.init(status:fieldIds:message:)`) when the conflict is between them, and use the model-level form only when no field is at fault.

### Messages Struct Pattern

```swift
@FieldValidationModel public struct {Name}FieldsMessages {
    @LocalizedString("content", messageGroup: "validationMessages", messageKey: "required")
    public var contentRequiredMessage

    @LocalizedString("content", messageGroup: "validationMessages", messageKey: "outOfRange")
    public var contentOutOfRangeMessage
}
```

### YAML Structure

```yaml
en:
  {Name}FieldsMessages:
    content:
      title: "Content"
      placeholder: "Enter your content..."
      validationMessages:
        required: "Content is required"
        outOfRange: "Content must be between 1 and 10,000 characters"
```

## Naming Conventions

| Concept | Convention | Example |
|---------|------------|---------|
| Protocol | `{Name}Fields` | `IdeaFields`, `CreateIdeaFields` |
| Messages struct | `{Name}FieldsMessages` | `IdeaFieldsMessages` |
| Field definition | `{fieldName}Field` | `contentField` |
| Range constant | `{fieldName}Range` | `contentRange` |
| Validate method | `validate{FieldName}` | `validateContent` |
| Required message (static mint) | `{fieldName}RequiredMessage` | `contentRequiredMessage` |
| OutOfRange message (static mint) | `{fieldName}OutOfRangeMessage` | `contentOutOfRangeMessage` |

## See Also

- [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md) - Full FOSMVVM architecture reference
- [Architecture Patterns → Encapsulation Is the Precondition](../shared/architecture-patterns.md) — **encapsulation is the precondition SOLID assumes, not a SOLID checkbox.** A Fields contract must express field identity/validation as *typed* values, never raw `String` keys/identities (stringly-typing is the encapsulation break — the small hole in the dam). Repo `CLAUDE.md` → *Encapsulation Is the Precondition SOLID Assumes*.
- [fosmvvm-viewmodel-generator](../fosmvvm-viewmodel-generator/SKILL.md) - For ViewModels that adopt Fields
- [fosmvvm-fluent-datamodel-generator](../fosmvvm-fluent-datamodel-generator/SKILL.md) - For Fluent DataModels that implement Fields
- [reference.md](reference.md) - Complete file templates

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2024-12-24 | Initial skill |
| 2.0 | 2024-12-26 | Rewritten with conceptual foundation; generalized from Kairos-specific |
| 2.1 | 2026-01-24 | Update to context-aware approach (remove file-parsing/Q&A). Skill references conversation context instead of asking questions or accepting file paths. |
| 2.2 | 2026-09-29 | Validation corrected to the shipped API: `Validations` is append-only (`validations` is `private(set)`; the assignment the templates taught no longer compiles), with the OCP reason. Validation messages are minted statically from the messages model's key path — reading one off a `{Name}FieldsMessages` instance encodes empty — so the `{name}ValidationMessages` requirement and its adopter storage are gone. Model-level results via `ValidationResult(status:message:)`, shown by `withFormValidations()`. Guard idiom aligned to `fields?.contains(Self.someField) ?? true`; SwiftFormat `redundantStaticSelf` note for `#fieldId(\Self.property)`. |
| 2.3 | 2026-09-30 | A field identity is scoped by the type the key path names: `\Self` inside the Fields protocol's own extension resolves to the protocol, so every adopter shares the one identity; outside that extension name the Fields protocol (`\IdeaFields.content`), never the adopting model. |
