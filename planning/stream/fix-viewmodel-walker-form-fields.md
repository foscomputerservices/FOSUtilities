---
status: open
last_updated: 2026-10-09
origin: PopTalk session relaying David, 2026-10-09; fix (1) ruled by David (OQ28)
---

`expectFullViewModelTests` never checks the localized text inside a `@FormFieldModel` property: the field's title, its placeholder, or its save button title. A view-model test passes while every field title is untranslated, and nothing says the fields were skipped.

David: the walker is expected to do what `expectFullFormFieldTests` does; having to call that separately is an oversight.

## Goal

A view-model test checks every field the view model holds, with no per-field call. A missing title, placeholder, or save title translation fails the test with the field's path.

Done means: `expectFullViewModelTests` reaches the localized text of every `@FormFieldModel` property; `expectFullFormFieldTests` stays for a `FormField` checked on its own.

## Input

**Ruling (OQ28, 2026-10-09):** fix (1): the walker recognizes a field through a small `package` protocol and runs its localized values through the existing `expectTranslated`. Not fix (2), making `FormFieldModel` `RetrievablePropertyNames`, because that conformance also feeds the localizing encoder and could change how fields encode in shipped apps.

**Where the walk stops** — `Sources/FOSTesting/LocalizableTestCase.swift:160`, verbatim:

```swift
        case .struct, .class:
            // Only ViewModels (and their kin) are walked — a Date, a URL, or a value type
            // from Foundation has children too, but none of them localize.
            guard value is any RetrievablePropertyNames else { return }
            for child in mirror.children {
```

**What it skips** — `Sources/FOSMVVM/Forms/FormFieldModel.swift:49`:

```swift
@propertyWrapper @Observable
public final class FormFieldModel<Value: Codable & Hashable>: Codable, ResettableModel, @unchecked Sendable {
    public private(set) var vmId: ViewModelId = .init()

    public var formField: FormField<Value>
```

`FormField.title` and `placeholder` are `LocalizableString`; `FormFieldModel` also holds the save button title (`LocalizableString/defaultSaveTitle`, YAML key `FOSForms.save`).

**The per-field call it replaces:** `expectFullFormFieldTests(_:locales:)`, `LocalizableTestCase.swift:252`.

**Field evidence (PopTalk, FOSUtilities 0.20.2):** 18 view models hold fields such as `@FormFieldModel(Self.preChargeField) public var batteryIncreasePreCharge: String`; 84 view-model tests pass without resolving a field title. Validation messages are reached, because the `FieldValidationModel` values on the view models are `RetrievablePropertyNames`.

## Suggested actions

1. Customer DocC first (fosmvvm-planning): what `expectFullViewModelTests` now promises about fields.
2. A test, watched failing first: a view model with a `@FormFieldModel` whose title has no translation fails `expectFullViewModelTests`.
3. The `package` protocol on `FormFieldModel` exposing its localized values; the walker's `.struct, .class` case checks it before the `RetrievablePropertyNames` guard.
4. Check that existing in-repo view-model tests still pass; any newly failing one is a real untranslated field.
5. Update the `fosmvvm-viewmodel-test-generator` skill where it tells users to call `expectFullFormFieldTests` per field. CHANGELOG (Fixed, with a note that tests may now fail on untranslated fields).
6. Tell PopTalk once, after release.

## History

- 2026-10-09 — Opened at David's ruling (OQ28), from PopTalk's relay.
