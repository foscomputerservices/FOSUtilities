---
status: open
last_updated: 2026-10-05
origin: fosline (cross-session message, at David's word of 2026-10-05); placement ruled by David 2026-10-02 ("that work should be done in FOSMVVM")
---

A ViewModel cannot carry the localized word for an enum case: an enum has no storage for its word, so a computed string on the enum never reaches the client, and the localizing encoder resolves only what a ViewModel stores.

Minted 2026-10-05 from fosline's request (its ViewModels document, VM2 and OQ-VM15). Every page of fosline that shows a case as a word, and every picker over an enum, waits on it.

## Goal

A ViewModel stores a case and its localized word in one value: the view switches on the case and shows the word. Built with an option, the value also carries the word of every case of the enum, as a list a picker can show.

Done means: `LocalizableCase<Case>` beside `LocalizableDouble`; one YAML key per case; the all-cases option; support in FOSTesting, FOSTestingUI, FOSTestingVapor, and FOSMVVMVapor's Leaf bridge; tests for each.

## Input

**David's ruling on the picker option, 2026-10-02**, verbatim as relayed: "I think that this should be part of the LocalizableCase's design/implementation. That is, to have some sort of option to have a separate property/method that allows retrieval of the localizables for all of the cases."

**David's note on the test libraries, 2026-10-02**, verbatim as relayed: "all ViewModel tests should include calling expectFullViewModelTests(), which will ensure that all values in the view model are localized properly. So, support for the new LocalizableCase would need to be added".

**Settled with fosline 2026-10-05** (answers FQ1–FQ5):

- `Case: CaseIterable` is required on every `LocalizableCase`, pickers or not; no stored enum has an associated value.
- YAML: the type's name is the parent key and the case names sit beneath it (`Timeframe: { fiveMinutes: …, oneDay: … }`). No raw values; no per-case key override; two types that share words repeat them in the YAML.
- The wire form of `LocalizableCase` is opaque; nothing of fosline's depends on how the case encodes.
- Nested types collide at the leaf (two nested `Kind`s, a `Code`, a `Case`); the key rule for a nested type is the library's.

**The translation walk proves only the case a stub carries** — `Sources/FOSTesting/LocalizableTestCase.swift:136-141`, verbatim:

```swift
        if let localizable = value as? (any Localizable) {
            guard !localizable.isEmpty else {
                throw FOSLocalizableError.error("\(path) -- Missing Translation -- \(locale.identifier)")
            }
            return
        }
```

**Where the library touches each localizable type** (found so far): the cast chain in `Sources/FOSMVVM/Localization/Localizer.swift:53`; the `@Localized…` wrappers in `Sources/FOSMVVM/Localization/LocalizedProperty.swift:167-168`; the Leaf bridge in `Sources/FOSMVVMVapor/Extensions/Localizable+Leaf.swift:46`; the key-echo store in `Sources/FOSTestingUI/KeyEchoLocalizationStore.swift`; `Sources/FOSTestingUI/XCTAssert+Localizable.swift`; `Sources/FOSTestingVapor/LocalizableTestCase.swift`.

## Suggested actions

- Rulings this item waits on are numbered in `planning/notes/fosline-request-rulings-2026-10-05.md`.
- Pending David's ruling (OQ2): resolve through `feat-localizable-hook.md`'s requirement (override `localized(in:store:)`) instead of the second non-generic cast protocol fosline's text names; that sequences the hook first.
- Ruled (OQ10): keys follow the library's existing enum rule, `LocalizableString.localized(case:parentType:)` (`Sources/FOSMVVM/Localization/LocalizableString.swift:95`): a nested enum sits under its parent type's YAML key, the case name is the leaf. Reuse that lookup rather than a second key rule. Whether `LocalizableCase` takes `parentType:` explicitly, as the existing call does, or derives it is the design's; bring it to David only if it changes how a ViewModel author writes it.
- The translation test proves every case of `Case` in every locale wherever a `LocalizableCase<Case>` appears, not only the stub's case.
- Survey every per-type touchpoint before the design is written; decide whether a `@LocalizedCase`-style wrapper is wanted or only the value type.
- Names are David's (OQ8, ruled): before building, bring him a naming table with just enough context per name; the type, the option's label, and the all-cases member go in the naming table.
- DocC first (a row's word and a picker, each with its call site); then the catalog entry (`FOSMVVM.md § Localization`) and the plugin bump.

## History

- 2026-10-02 — David: placement in FOSMVVM; the picker option; the test libraries must gain it.
- 2026-10-05 — minted from fosline's request; fosline's answers FQ1–FQ5 recorded above.
- 2026-10-05 — OQ9 ruled: ships in 0.20.0 with the rest of fosline's request.
- 2026-10-05 — OQ10 ruled: the existing enum-key rule and lookup are reused.
- 2026-10-05 — build order ruled by need: 2 of 5, with `feat-localizable-hook.md` (rulings file, OQ2).
- 2026-10-05 — BUILT on feat/0.20.0 for the single 0.20.0 PR; reviewed (standards, requirements trace, docs) and the findings fixed.
