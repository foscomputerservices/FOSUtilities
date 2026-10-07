---
status: open
last_updated: 2026-10-07
origin: a consumer's request, relayed 2026-10-07 at David's word ("file a work item for a future version")
---

Shipping code cannot name the locales FOSUtilities' tests use without writing `Locale(identifier: "en")`: the constants `en`, `enUS`, `enGB`, and `es` exist only on FOSTesting's `LocalizableTestCase`, which a shipping library cannot import.

A consumer declares the locales its shipping ViewModels library covers (a public `Set<Locale>`), and its test suites set `locales` from that same set, so library code and tests should share one spelling.

## Goal

A shipping library and its tests name the same locale with the same typed constant, without importing FOSTesting.

Done means: public `Locale` constants in a non-test module; `LocalizableTestCase`'s members forward to them so `Self.en` keeps working; DocC with an example; a catalog entry.

## Input

**Today** — `Sources/FOSTesting/LocalizableTestCase.swift:259-288`: `static var en`, `enUS`, `enGB`, `es` (and instance twins), each `Locale(identifier: …)`. `Sources/FOSMVVM/Localization/Localizer.swift:52` and `:116` extend `Locale`, internal and private.

**The consumer's suggested shape:** a public `extension Locale` in FOSFoundation with `static var en`, `enUS`, `enGB`, `es`, and whichever others are standard.

## Suggested actions

- Design first; two questions for David before any name ships:
  - **Which locales.** `en`, `enUS`, `enGB`, `es` are FOSUtilities' own test locales, not a standard set. A library-blessed list implies coverage the library does not have. Options: exactly the four the test base uses, or a broader list, or no list at all.
  - **Collisions.** A public `static var en` on a Foundation type can clash with a consumer's or another package's own `Locale.en`, making `.en` ambiguous at call sites. Options: the extension as proposed, a namespaced spelling, or constants on a FOS type.
- Then the names to David's naming table, DocC first, and `LocalizableTestCase` forwarding to the new constants.

## History

- 2026-10-07 — minted from the consumer's request; for a future version, not 0.20.1.
