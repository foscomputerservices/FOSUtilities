---
status: open
last_updated: 2026-10-06
origin: a consumer's field report on 0.20.0 (relayed 2026-10-06); ruled by David (OQ42)
---

A form ViewModel fails `expectFullViewModelTests()` under strict localization out of the box: `@FormFieldModel`'s default save title is the YAML key `FOSForms.save`, FOSUtilities ships no translation for it, and nothing tells the client to provide one.

## Goal

A client knows, before its first form test fails, that it supplies the `FOSForms` stock-title translations, and a scaffolded project already has them.

Done means: DocC on the three stock titles and on `FormFieldModel`'s save title naming the keys; the catalog and generator skills saying the same; the scaffolder's YAML carrying the keys in every locale it generates.

## Input

**David's ruling, 2026-10-06 (OQ42):** "client provides the mappings". FOSUtilities ships no translations for them.

**The keys** — `Sources/FOSMVVM/Localization/LocalizableString.swift:209-221`, verbatim:

```swift
public extension LocalizableString {
    static var defaultOkTitle: Self {
        .localized(.value(keys: "FOSForms", "ok"))
    }

    static var defaultCancelTitle: Self {
        .localized(.value(keys: "FOSForms", "cancel"))
    }

    static var defaultSaveTitle: Self {
        .localized(.value(keys: "FOSForms", "save"))
    }
}
```

None of the three has DocC. `FormFieldModel.swift:149` defaults `saveButtonTitle` to `.defaultSaveTitle`. The catalog (`.claude/skills/shared/api-catalog/FOSMVVM.md:192`) says they "cover stock button labels", which reads as working out of the box. No template YAML defines `FOSForms`.

## Suggested actions

- DocC on the three statics: the YAML the client provides (`FOSForms: { ok:, cancel:, save: }`), example-first.
- `FormFieldModel`'s DocC: the save title's default key and that the client translates it.
- Catalog line and the fields and viewmodel generator skills: the same, briefly.
- Scaffolder templates: add the `FOSForms` keys to the generated YAML for each generated locale; regenerate fixtures per the bootstrap recipe.

## History

- 2026-10-06 — minted from the field report; David ruled the client provides the translations.
