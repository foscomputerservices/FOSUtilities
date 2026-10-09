---
status: open
last_updated: 2026-10-09
origin: PopTalk session relaying a FOSTestingUI 0.20.2 field report (PopTalk PR #119, pipeline 567), 2026-10-09; David: record it, deal with it after his vacation
---

`setText` taps a text field whose frame is partly on screen but whose centre is below the screen edge. The tap lands nowhere, no keyboard rises, no edit menu appears, and the entry never happens.

PopTalk worked around it on their side; their PR #119 is not blocked (David, 2026-10-09).

## Goal

`setText` (and any tap that aims at a target's centre) reaches a field that straddles the screen edge.

Done means: when the point `setText` would tap lies outside the visible band, it scrolls the target in first, keyboard or no keyboard.

## Input

**Field report (PopTalk, FOSTestingUI 0.20.2):**

- Tests: `XPGGeneralCalibrationViewUITests.swift:165` (`testSetBatteryPreChargeField`, enters "100") and `:128` (`testSetGeneralCalibration`, enters "42").
- Legs: CI iPhone 17 Pro, Xcode 26.5 / iOS 26.5; also local on the 26.5 simulator with Xcode 27.1.
- Failure text: `The field tagged "preChargeTextField" reads "26" after attempting to enter "100"; expected "100". ... An unchanged value can also mean no selection was ever proven: the edit menu never rose over the field's text.`
- Hierarchy at failure (874 pt tall screen): `preChargeTextField` frame `{{230.0, 865.3}, {140.0, 42.0}}` — 9 pt visible, centre at y 886, off screen. The activity trace shows `setText` treating it as in band and coordinate-tapping that centre: no scroll, no keyboard, no edit menu.
- The next field down, `constantCurrentTextField` at `{{230.0, 932.0}, {140.0, 42.0}}`, is wholly off screen, takes the scroll path, and passes.
- The field is a `FormFieldView` inside a `ParameterRow` in a `ScrollView`; the view is registered `designedFor: [.navigation, .scrolling]`.
- Not a 0.20.2 regression: PopTalk PR #118 made the rows taller and moved this field into the straddle.
- PopTalk's suggestion: scroll when the tap point, not just the frame, is outside the visible band.
- Evidence (hierarchy dumps, activity traces, CI step logs for pipelines 566 and 567) is in the PopTalk session's scratchpad; ask PopTalk for it verbatim.

**Likely cause (read, not yet proven by a test)** — `Sources/FOSTestingUI/UITestingElement.swift:1242`, `isAimable`: with no keyboard up and no bar covering the target, it returns `true` before the band is consulted, so an off-screen midpoint counts as aimable:

```swift
        let barOcclusion = !hittable && barsCover(midpoint)
        guard app.keyboards.firstMatch.exists || barOcclusion else { return true }

        let band = aimableBand()

        return band.contains(midpoint) && frame.maxY <= band.maxY
    }
```

The keyboardless early return is deliberate (its comment: the guard firing keyboardless was measured scrolling an open menu and failing rows that had left the tree), so a fix must keep that case fixed. `setText`'s focus loop (`UITestingElement.swift:929-942`) also coordinate-taps `focusTarget.frame.midX/midY` directly on its second strategy, with no band check.

## Suggested actions

1. Reproduce in a FOSTestingUI test: a field in a `ScrollView` placed so its frame straddles the bottom screen edge with its centre off screen; watch `setText` fail.
2. Make the aim decision ask whether the tap point is inside the app's visible frame when no keyboard is up, without reviving the open-menu regression the early return guards.
3. Run the FOSTestingUI UI test suites on iPhone and the Duo cover screen.
4. CHANGELOG (Fixed). Tell PopTalk after release.

## History

- 2026-10-09 — Opened from PopTalk's relay at David's request; deferred until David returns from vacation.
