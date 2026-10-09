---
status: open
last_updated: 2026-10-09
origin: PopTalk session relaying a FOSTestingUI 0.20.2 field report (PopTalk PR #119, pipeline 567), 2026-10-09; David: record it, deal with it after his vacation
---

On iPad, `selectPickerItem` cannot select a picker row that is not yet in the accessibility tree. The picker's rows are recycled, the last row has not been drawn when the tap is attempted, and the tap fails with "No matches found". The same test passes on iPhone.

PopTalk worked around it on their side; their PR #119 is not blocked (David, 2026-10-09).

## Goal

`selectPickerItem` selects any row of an open picker on iPad, including rows the picker has not drawn yet.

Done means: a picker whose target row is outside the drawn range is scrolled until the row exists, then tapped, on iPad and iPhone alike.

## Input

**Field report (PopTalk, FOSTestingUI 0.20.2):**

- Test: `XPGImpedanceStimViewUITests.testElectrodePicker_ContainsFullChannelRange`.
- Legs: CI iPad A16 (Xcode 26.5 / iOS 26.5); also local iPad Pro 13-inch, iOS 26.5. Passes on iPhone.
- Failure text: `Failed to tap "sourceElectrodePickerChannel26" Any: No matches found for first query match sequence: Descendants matching type Any -> Elements matching predicate '"sourceElectrodePickerChannel26" IN identifiers'`.
- Row identifiers are `sourceElectrodePickerChannel<N>`, N in 0...26; the target is the last row.
- The trace goes through the native tap path at `UITestingElement.swift:406` after the picker opens.
- 0.20.2's `selectPickerItem` settle changes (`UITestingElement.swift` ~1469-1555) did not change the outcome: same trace at 0.17.3 and 0.20.2.
- Evidence (hierarchy dumps, activity traces, CI step logs for pipelines 566 and 567) is in the PopTalk session's scratchpad; ask PopTalk for it verbatim.

Not yet investigated on the FOSUtilities side. Related history: the picker in-menu scroll shipped in 0.12.5 and the picker fold settle in 0.18.0; check what those assume about iPad's picker presentation.

## Suggested actions

1. Reproduce in a FOSTestingUI test on an iPad simulator: a menu picker with enough rows that the last is not drawn when it opens; watch `selectPickerItem` fail on the last row.
2. Find how iPad presents the picker and why the in-menu scroll does not bring the row into the tree.
3. Fix, then run the picker tests on iPad and iPhone.
4. CHANGELOG (Fixed). Tell PopTalk after release.

## History

- 2026-10-09 — Opened from PopTalk's relay at David's request; deferred until David returns from vacation.
