# Form Input Conformance — Implementation Plan

**Status:** UNRATIFIED — awaiting David's review. Section 2 carries the rulings this plan needs before a line is written; everything after it is drafted *assuming* those rulings and must be re-cut if any is answered differently.

**Scope:** make `FormFieldView` honour the input options a `FormField` already declares — `disabled`, `maxLength`, `maxValue`, `cols` — and render `.text(inputType: .number)` for `String`-valued fields as a digits-only entry. `minDate`/`maxDate` are the worked example already in the file and are not touched.

**Origin:** a consuming app declared `.text(inputType: .number)` on a `FormField<String>` and got `"The FormInputType number is NYI!"`, then asked whether `.minValue`/`.maxValue` constrain a String field today. They do not. The report is evidence and motivation only — no part of it, and nothing about its author or their product, appears in sources, fixtures, commits, or shipped docs.

---

## 0. Where this sits in the execution model

This changes FOSMVVM itself, where the framework's public API **is** the truth layer, so the traversal is the planning gate's own order — surface → DocC → contract tests → rationale → tasks — not the Fields/DataModel/ViewModel chain. Same standing as the designed-parents arc, and the same finding against `shared/execution-model.md`'s dispatch table being silent on framework-internal work.

---

## 1. What is actually true today

A consumption audit of every `FormInputOption` case, taken 2026-09-23, because the catalog and the code disagree.

**Reaches rendering:** `autocomplete` (→ `.disableAutocorrection`), `autocapitalize` (→ `.textInputAutocapitalization`), `minDate`/`maxDate` (→ `FormField.dateRange` → the `DatePicker`'s `in:` at `FormFieldView.swift:517`).

**Read into an accessor nothing uses:** `disabled` (`FormField.swift:198`), `required` (`FormField.swift:208`). `size` is written by `adjustedOptions` and never read back.

**Never read anywhere:** `cols`, `minValue`, `maxValue`, `minLength`, `maxLength`.

The catalog (`.claude/skills/shared/api-catalog/FOSMVVM.md`) documents the whole set under *"Constrain and configure input"* and tells consumers *"don't scatter keyboard types, autocapitalization, and length limits across views — declare them once here"*. So the intent is settled and documented; the readers were never written. `rangeLength(_:)` exists as a convenience for declaring a length range, which is not something anyone writes for an option meant to stay inert.

`FormInputType.number` is likewise declared and falls into `default: Text("The FormInputType \(inputType) is NYI!")` for both `String` and `String?` — `FormFieldView.swift:383` and `:496`.

---

## 2. Rulings needed before implementation

### 2.1 Not every declared option can be conformed at input — where do the rest go?

The discriminator is not preference, it is reachability: **can the user reach an illegal state while typing toward a legal one?** Where the answer is yes, refusing the keystroke makes the legal value unreachable.

**Conformable — refusing keeps a legal value reachable:**

`maxLength` — no further character helps once the limit is hit.

`maxValue` — no further digit helps once the number exceeds the maximum.

digits-only (`.number`) — a non-digit is never part of a legal value.

`disabled` — no entry at all.

`cols` — presentation of a `textArea`, nothing to refuse.

**Not conformable — every prefix of a legal value is illegal:**

`minLength` — typing toward a four-character minimum passes through one, two and three characters.

`minValue` — typing toward `4095` passes through `4`, `40` and `409`.

`required` — an empty field is a legal in-progress state on every form ever built.

**The ruling this needs:** `FormInputOption` was described as the input contract, and that holds for the first group. The second group are declared constraints that only a validator can judge. Options as I see them:

**(a)** `FormInputOption` stays one vocabulary; the framework conforms what it can at input and the rest remain declarations a consumer's `validate()` reads. Honest, but leaves a reader unable to tell from the type which is which.

**(b)** The second group is understood as *validation input*, and the framework eventually offers a default `validate()` that reads them, so the consumer's validator overrides rather than originates. Bigger arc; would change what a Fields protocol has to write by hand.

**(c)** Split the vocabulary by what it governs. Largest change, breaks existing declarations, and I do not recommend it.

This plan assumes **(a)** and touches only the first group. **(b)** is a separate arc and should not be smuggled in here.

### 2.2 Honouring a declared option is a behaviour change for existing consumers

A field that declares `.maxLength(254)` is unconstrained today. After this, the control stops accepting the 255th character. Any consumer already relying on the declaration being inert — or holding data that exceeds a limit they declared aspirationally — feels it on upgrade.

That is the fix, not a regression: the option was always documented as constraining. But it is a behaviour change and the CHANGELOG must say so in those words, not bury it under "implemented".

**The ruling this needs:** ship it as a behaviour change with a plainly-worded CHANGELOG entry, or stage it behind something a consumer opts into? I recommend the former — an opt-in for "the option now does what it says" is a permanent wart.

### 2.3 Does conformance belong in the binding or in the modifiers?

Recommendation: the **binding setters**, `FormFieldView.swift:152` (generic) and `:184` (`Value == String?`). One choke point each, covering every control and every input type. The alternative — a modifier per switch arm — repeats the rule across roughly ten arms and would drift the first time one is edited.

This is the SRP reading and I do not think it is contentious, but it is the shape of the whole change, so it is called out rather than assumed.

---

## 3. Public surface

**No new public symbols.** Every option and input type this work honours is already public and already documented. That is the whole point: the declarations exist, the readers do not.

New **internal** accessors on `FormField`, mirroring the shape of `dateRange` (`FormField.swift:216`), which is internal for the same reason:

`var lengthLimit: Int?` — the `maxLength` value, or nil.

`var valueLimit: Int?` — the `maxValue` value, or nil.

`var isDisabled: Bool` — `disabled` with a false default, replacing the unused `disabled: Bool?` accessor.

Step-1 gate: minimal surface holds (nothing added publicly). No stringly-typing — these are `Int` bounds already typed by the option. One serialization — `FormInputOption` is already `Codable` and unchanged. Nothing published about any representation. Boundaries untouched: this is all inside the SwiftUI support layer.

**The existing `required` accessor stays unused** under ruling (a) and should be left alone rather than deleted — it is the reader a future validation arc will want.

---

## 4. Customer-facing DocC, drafted before the code

No public symbol changes, so no new DocC. What changes is that existing DocC becomes true, and two documents currently overstate the present tense.

**`FormInputOption`'s own DocC** gains, per honoured case, a line saying what the control does — written from the call site:

```swift
/// The largest number the field will accept
///
/// The control refuses a keystroke that would take the entry above `value`, so a field
/// declaring `.maxValue(value: 4095)` cannot be typed up to 5000:
///
/// ```swift
/// options: [.maxValue(value: 4095), .required(value: true)]
/// ```
///
/// > Refusing entry is not validation. A value can still arrive over the wire from a client
/// > that never ran this control, so a `ValidatableModel` judges the data independently.
case maxValue(value: Int)
```

**The API catalog entry** for `FormInputOption` is amended to say which options the control conforms and which are declarations a validator reads — it currently implies all of them constrain.

---

## 5. Tests, against the contract only

These are view behaviours, so the probe is where they are pinned — `Tools/UITestingProbe`, a fixture scene per honoured option, driven through `uiTestingElement`. No `@testable`, no assertions on any encoded shape.

**Entry above `maxValue` is refused** — type `5000` into a field declaring `.maxValue(value: 4095)`; the field reads `500`. Asserted on the field's value, which is the contract, not on internal state.

**Entry beyond `maxLength` is refused** — type five characters into a `.maxLength(value: 4)` field; the field reads four.

**A non-digit is refused by `.number`** — type `1a2`; the field reads `12`.

**`.number` raises a numeric keyboard on iOS** — the keyboard exists and has no Return key, which is the same proof `KeyboardDismissalTests` already relies on.

**A `disabled` field takes no entry** — and `tap()` on it does not reach the ViewModel.

**Nothing refuses a legal prefix** — type `4` into a field declaring `.minValue(value: 1000)`; the field reads `4`. This is the regression guard for §2.1, and it is the test most likely to catch a future "improvement" that breaks entry.

**Declared-but-unconformed options change nothing** — a field declaring `.minLength` and `.required` accepts an empty value and a short one; the judgement belongs to a validator.

`setText(_:expecting:)` needs a teaching failure for the case where a filter refused characters — see §6.

---

## 6. Rationale and gotchas (implementer's chair)

**Rejecting in a setter reverts the field, and this file already learned it.** `FormFieldView.swift:161` carries the measurement: *"Store the value as typed so the TextField's display keeps whatever the user entered… Trimming here would strip a trailing space on every keystroke and revert the field, making multi-word entry (names, addresses) impossible."* A conformance filter is the same mechanism pointed at a different character class, so it must refuse only what no legal value can contain. Every rule in the conformable group above satisfies that; the non-conformable group does not, which is the whole of §2.1.

**Refusal must not fight the cursor.** Assigning a shorter string back into a bound `TextField` can move the insertion point to the end. The probe tests should type multi-keystroke sequences rather than paste, so a cursor regression surfaces as a wrong value rather than passing silently.

**`setText(_:expecting:)` verifies its postcondition**, which is what lets it return. A field that silently drops characters turns a wrong entry into a `setText` failure whose message names the value rather than the filter — legible, but it sends the reader to the wrong place. It needs a failure that says the field refused the characters, and a probe fixture for it. That cost belongs in this arc, not a later one.

**Paste is entry too.** A pasted string exceeding `maxLength` arrives through the same setter as typing, so the rule applies uniformly — but it means a paste is truncated rather than rejected, which is the right behaviour and worth a DocC line.

**Do not derive a digit cap from `maxValue`.** The consuming app asked for "max digits from the range" as a workaround for `maxValue` being inert. Deriving `4` from `4095` permits `9999`; conforming `maxValue` directly does not. The derivation exists only to substitute for the thing this arc implements, and should not be built.

---

## 7. Decomposition

Hand to the decomposition process once §2 is ruled. Task order, each ending green:

1. `FormField` internal accessors + the probe fixture scene, no behaviour yet.
2. The binding-setter conformance point, `maxLength` only, with its probe test.
3. `maxValue`, with its test and the legal-prefix regression guard.
4. `.number` for `String` and `String?` — digits-only plus the numeric keyboard, with tests.
5. `disabled` and `cols`.
6. `setText` teaching failure for refused characters, with its fixture.
7. DocC per honoured case, catalog amendment, CHANGELOG entry worded as a behaviour change.

Steps 2-5 each touch one option and can be reordered or dropped independently if a ruling moves.
