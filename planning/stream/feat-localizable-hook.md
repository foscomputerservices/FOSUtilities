---
status: open
last_updated: 2026-10-05
origin: fosline (cross-session message, at David's word of 2026-10-05); ratified by David 2026-10-01 (fosline's OQ-C1, "Ratified")
---

A `Localizable` declared outside FOSUtilities cannot be localized by the encoder: the localizer resolves only the library's own types through a chain of concrete casts and throws `unknownLocalizationType` for any other, and the one call a value's `encode(to:)` can use to reach the encoder's locale and store is internal.

Minted 2026-10-05 from fosline's request (its protocols document, C9 and § 11 OQ-C1). The consumer is CryptoScraper's localization library (an amount, a price, a fraction), declared outside FOSUtilities at David's ruling of 2026-10-01. Without the hook the only alternatives are a `LocalizableString.constant` that drops the locale's grouping separator, or a `LocalizableDouble` that is inexact past 2^53 base units.

## Goal

A type outside FOSUtilities localizes itself through the same encoder as every library type, and the library's own types resolve exactly as they do today.

Done means: the two edits below in one PR; a test conformer declared in a test target localizes through `localizingEncoder()` and reads `localizationStatus == .localized` after a round trip; every existing localization test passes unchanged.

## Input

**The asked-for declaration** — fosline's `docs/fosline-suite-protocols.md`, C9, verbatim:

```swift
public protocol Localizable: Codable, Hashable, Identifiable, Sendable, Stubbable {
    // … the existing requirements …

    func localized(in locale: Locale, store: LocalizationStore) throws -> String?
}

public extension Localizable {
    /// The library's own types resolve as they do today; any other type throws `LocalizerError.unknownLocalizationType`
    func localized(in locale: Locale, store: LocalizationStore) throws -> String?
}

public extension Encoder {
    func localizeString(_ localizable: some Localizable) throws -> String?
}
```

**The cast chain the default takes over** — `Sources/FOSMVVM/Localization/Localizer.swift:52-70`, verbatim:

```swift
extension Locale {
    func localize(_ localizable: some Localizable, localizationStore: LocalizationStore) throws -> String? {
        if let string = localizable as? LocalizableString {
            return localize(string, localizationStore: localizationStore)
        } else if let compound = localizable as? LocalizableCompoundValue<LocalizableString> {
            return try localize(compound, localizationStore: localizationStore)
        } else if let subs = localizable as? LocalizableSubstitutions {
            return try localize(subs, localizationStore: localizationStore)
        } else if let int = localizable as? LocalizableInt {
            return localize(int)
        } else if let double = localizable as? LocalizableDouble {
            return localize(double)
        } else if let date = localizable as? LocalizableDate {
            return localize(date)
        } else {
            throw LocalizerError.unknownLocalizationType(
                String(describing: localizable.self)
            )
        }
    }
```

**The internal encoder call** — `Sources/FOSMVVM/Extensions/JSONEncoder.swift:65`, `func localizeString(_ localizable: some Localizable) throws -> String?`, which also applies strict localization (`missingTranslation`) when the store returns `nil`.

## Suggested actions

- Rulings this item waits on are numbered in `planning/notes/fosline-request-rulings-2026-10-05.md`.
- Requirement + Default: the requirement on `Localizable`, the default in a public extension that runs today's cast chain; `Locale.localize` calls the requirement so a conformer's override dispatches through the protocol.
- Make `Encoder.localizeString(_:)` public; strict localization stays inside it, so an outside conformer gets the same `missingTranslation` behavior.
- Sequence with `feat-localizable-case.md`: `LocalizableCase` can resolve through this hook instead of a second cast protocol (pending David's ruling on the order, OQ2).
- Names are David's (OQ8, ruled): before building, bring him a naming table with just enough context per name; the requirement's labels (`in:store:` as asked, against the library's existing `localizationStore:`) go in the naming table.
- DocC first, with the outside-conformer example; then the catalog entry (`FOSMVVM.md § Localization`) and the plugin bump.

## History

- 2026-10-01 — fosline's OQ-C1 ratified by David ("Ratified").
- 2026-10-05 — minted from fosline's request.
- 2026-10-05 — OQ9 ruled: ships in 0.20.0 with the rest of fosline's request.
- 2026-10-05 — build order ruled by need: 2 of 5, with `feat-localizable-case.md` (rulings file, OQ2).
- 2026-10-05 — BUILT on feat/0.20.0 for the single 0.20.0 PR; reviewed (standards, requirements trace, docs) and the findings fixed.
