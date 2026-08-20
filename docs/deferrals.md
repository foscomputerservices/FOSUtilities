# Deferrals

Work items acknowledged and deliberately not done yet. Each entry names the evidence in hand, why it was deferred, and what reopens it. Removing an entry requires the work shipping or David striking it.

## The inert coordinate tap on iOS 27 (the "Fact A ghost")

**Recorded:** 2026-08-20, at David's direction, during the aimable-band occlusion round.

**What it is:** a synthesized coordinate tap dispatches at the demonstrably correct screen point and the control's action never fires — no press visual, no state change, intermittently but with a strong failure bias. First reported by a consumer as a deterministic launch-time failure under a scrollable-registered card on 0.12.5 (their "Fact A": `tap()` de-routed to its coordinate path and the dispatch was inert); their later probe on 0.12.6 could not reproduce it and changed two variables at once, so it was classified absorbed-not-explained.

**Why it is real:** our own probe now shows the same shape on **unmodified main** (0.12.6, `45763f3`): `UITestingElementTests.testExistenceFollowsTheViewHierarchy` and `testWaitsForAViewToLeaveTheHierarchy` fail intermittently on the iPhone 17 Pro simulator (iOS 27 beta) — the trace shows the `[0.50, 0.50]` element-anchored coordinate fallback synthesizing the event and the derived banner never appearing. Bisect-proven not caused by the occlusion branch. The iPhone 17e leg runs the same suite 55/55 green, so the failure is geometry-correlated (the affected control sits low in the main probe tree, near the iOS 27 tab bar — the neighborhood of the documented 2026-08-18 "never crowd the main probe tree" lesson).

**Current standing:** documented as the iOS gate baseline for the 17 Pro leg (precedent: the macOS 27 beta 3-failure baseline). The occlusion round's premise re-check narrows exposure — a premise-gone tap on a *hittable* element now takes the native path — but the non-hittable coordinate fallback remains the dispatch of last resort and is the path that goes inert.

**Reopen triggers:**
- Any consumer-side recurrence after 0.12.7 (the consumer's acceptance runs are the live watch).
- The baseline spreading to more tests, another device geometry, or a non-beta iOS.
- Starting the investigation arc proper: first steps would be pinning whether hit-testing routes the dispatch into the tab bar / an overlay at that geometry, and whether an app-anchored aimed dispatch at the same point behaves differently (the traces suggest it may).

## The accessory-margin occlusion geometry is not deterministically pinned

**Recorded:** 2026-08-20, at David's direction, during the aimable-band occlusion round.

**What it is:** a field can sit just *above* the keyboard's reported top edge — measured 15pt clear in the field evidence — and still be unreachable, because the accessory/input-assistant bar occupies that strip. `setText` handles the case (the edit menu failing to rise triggers a re-scroll, and the band carries a 44pt clearance above the reported keyboard top), but the occlusion pin fixture (`Tools/UITestingProbe`, `OcclusionScrollTests`) never deterministically manufactures a field at that exact geometry. The other two occlusion geometries — behind the keyboard, beyond the viewport bottom — are forced by the fixture on both ruled device widths; this one is covered only by the consumer's device matrix plus the mechanism.

**Why it was deferred:** placing a field at a fixed offset above the keyboard's top is device- and keyboard-height-dependent, so a deterministic fixture needs layout that measures the keyboard at runtime — more machinery than the round's scope. The failure mode is guarded by an arbiter, not by geometry, so the fix does not silently depend on the un-pinned case.

**What reopens it:** a regression report where the menu-rise re-scroll fails on a margin-occluded field; or the next probe-fixture round, where a runtime-measured margin field should join the composite card so all three geometries are forced in-house.
