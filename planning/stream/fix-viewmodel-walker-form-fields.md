---
status: open
last_updated: 2026-10-09
state: paused, awaiting David's rulings OQ29-OQ32 (David on vacation)
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

**Finding, 2026-10-09 (probe against `main` 0c75a4f, test code since removed):** the gap is narrower than this item first said. `expectFullViewModelTests` encodes with the strict encoder, so a field title whose YAML key is missing ALREADY fails at encode (`LocalizerError: Missing translation for localized(ProbeMissingVM.nope.title) in locale 'en'`); so does a missing `FOSForms.save`. Two cases pass silently: a key present with a blank value (`""`), and a `.empty` title (e.g. `FormField.dummy` never replaced). PopTalk's 84 passing tests did resolve their field titles; what they cannot catch is blank or empty field text.

**Also held by `FormFieldModel`:** `cancelButtonTitle` (`LocalizableString/defaultCancelTitle`, YAML `FOSForms.cancel`). Nothing else in `Sources/FOSMVVM/Forms` is localized (title, placeholder, save, cancel are the full set).

**Proposed customer DocC for `expectFullViewModelTests` (`Sources/FOSTesting/LocalizableTestCase.swift:189`), awaiting OQ31:**

```swift
    /// Performs tests to ensure that the **ViewModel** is complete and stable
    ///
    /// This test performs all aspects of automated verification against the **ViewModel**, including:
    ///
    ///   - ``expectCodable(_:encoder:decoder:_:)``
    ///   - ``expectVersionedViewModel(_:version:encoder:decoder:_:fixedTestFilePath:file:line:)-79yr2``
    ///   - ``expectTranslations(_:locales:)``
    ///
    /// The translation check reaches every localized value the view model holds:
    /// nested view models, rows of collections, optionals, and each `@FormFieldModel`
    /// field's title, placeholder, and save and cancel button titles. A missing or blank
    /// translation fails the test and names the property, for example
    /// `MyViewModel.email.title -- Missing Translation -- es`.
    ///
    /// > A field the view model holds needs no ``expectFullFormFieldTests(_:locales:)`` call;
    /// > use that for a ``FormField`` checked on its own.
    ///
    /// ## Example
    ///
    /// ```swift
    /// try expectFullViewModelTests(MyViewModel.self)
    /// ```
```

Parameters unchanged. The draft also fixes two pre-existing errors in today's DocC: the example calls a nonexistent `expectFullyTestedViewModel`, and "ViewMode" for "ViewModel".

**Awaiting David's ruling:**

OQ29 — Proceed on the narrower premise (blank/empty field text, not missing keys), and correct this item's wording accordingly?

OQ30 — Check `cancelButtonTitle` too?

OQ31 — Approve the DocC above, including the two pre-existing doc fixes?

OQ32 — Failing-first test uses a field whose title value is blank in `es` (the case that passes today)?

## Suggested actions

1. Customer DocC first (fosmvvm-planning): what `expectFullViewModelTests` now promises about fields.
2. A test, watched failing first: a view model with a `@FormFieldModel` whose title has no translation fails `expectFullViewModelTests`.
3. The `package` protocol on `FormFieldModel` exposing its localized values; the walker's `.struct, .class` case checks it before the `RetrievablePropertyNames` guard.
4. Check that existing in-repo view-model tests still pass; any newly failing one is a real untranslated field.
5. Update the `fosmvvm-viewmodel-test-generator` skill where it tells users to call `expectFullFormFieldTests` per field. CHANGELOG (Fixed, with a note that tests may now fail on untranslated fields).
6. Tell PopTalk once, after release.

## History

- 2026-10-09 — Opened at David's ruling (OQ28), from PopTalk's relay.
- 2026-10-09 — Branch `fix/viewmodel-walker-form-fields` cut; probe narrowed the gap to blank/empty field text; DocC drafted; OQ29-OQ32 put to David. Paused: David on vacation.
