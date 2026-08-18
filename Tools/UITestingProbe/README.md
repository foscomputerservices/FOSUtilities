# UI Testing Probe

An XCUITest harness for `uiTestingIdentifier(_:isEnabled:)` (FOSMVVM) and
`uiTestingElement(_:)` (FOSTestingUI).

SwiftUI's accessibility behaviour is the contract these two rest on, and none of it is
verifiable from a unit test — the accessibility tree only exists while an application is
running under XCUITest. This harness is where that contract is checked.

## Running

```bash
cd Tools/UITestingProbe
xcodegen generate
xcodebuild test -project UITestingProbe.xcodeproj -scheme UITestingProbe \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

`xcodegen` (`brew install xcodegen`) generates the project from `project.yml`; the generated
`.xcodeproj` is not committed. The package is consumed from `../..`, so the harness always
tests the working tree.

## What it covers

- a tag holds on controls that bridge to a native element — `Picker`, `DatePicker`,
  `TextField`, `ColorPicker`, `Toggle`
- a tagged container leaves the tags of the sub-views it composes intact
- a tag applied after other modifiers still holds
- `isEnabled: false` leaves the view untagged
- taps reach the control, including opening a menu
- typing reaches the field
- `exists` follows the view hierarchy across a conditional branch
- `exists` and `isVisible` are distinct for a view that is present but scrolled off screen
- `waitForDisappearance()` resolves when a view leaves the hierarchy
- `label`, `value` and `isEnabled` report the tagged control's own state
- a `Picker`'s options carry their tags into the menu it presents, so a selection can be made
  and asserted through the tag
- displayed text compares against a `Localizable`, and a `Localizable` that was never localized
  cannot match
- a `Tab` holds its tag — through either initializer, and on the label as well as on the `Tab`
  — and tapping one as the first thing a test does switches tabs
- `dismissKeyboard()` puts away a `.numberPad` keyboard — which has no Return key — and a tap
  then reaches a control instead of the keyboard; with no keyboard up the call is a no-op
  (the app is wrapped in `.testHost()`, which is what plants the dismissal control)
- `setText(_:expecting:)` replaces and verifies across the geometry matrix: a prefilled
  field behind a row-spanning tag, an empty field, a trailing-aligned field, a prefilled
  `.numberPad` field, and a formatter-backed field committed via `expecting:`; a
  `SecureField` is rejected with the teaching failure (`TextEntryTests`)
- `selectPickerItem(_:)` returns only after the selection committed: a six-round cycle
  through distinct menu items reads selection-derived state immediately after each call,
  with no wait — and a nonexistent item identifier fails loudly naming the item
  (`PickerSelectionTests`)
- `selectPickerItem(_:)` reaches items clipped behind a long menu's internal scroll — a
  24-row picker is selected into on both sides of the checked anchor, including a row so
  deep it starts outside the accessibility tree (`PickerSelectionTests`)
- `setToggle(_:)` flips a leading-label `Toggle` — the geometry whose merged accessibility
  element defeats a midpoint tap — and returns only after the switch reports the state;
  already-at-state is a verified, idempotent no-op (`ToggleFlippingTests`)
- `FormFieldView` focus plumbing survives a real focus hand-off — two fields sharing the
  owner's `@FocusState`: focus, edit, blur (validation-on-blur), refocus, with un-waited
  value reads (`FormFocusProbeTests`, the `PROBE_SCENE=formFocus` scene)
- a view registered `scrollable: true` is presented inside a vertical `ScrollView`: a field
  buried past the window's bottom is reachable (tap auto-scrolls, keyboard arrives, typing
  reads back), while the unregistered twin presents bare — the field exists but is not
  visible (`ScrollRegistrationTests` / `BarePresentationTests`, riding the full
  `ViewModelDisplayTestCase.presentView` transport with shared probe ViewModels)
- `dismissKeyboard()` still works while keyboard avoidance has shifted the whole content up —
  the `KeyboardShiftProbe` scene (`PROBE_SCENE=keyboardShift`: tall filler, `.numberPad` field
  near the bottom, no scroll container) forces the shift that displaced 0.12.2's overlay
  control off screen

## What the tab bar taught us

Two separate things, and #126 reported them as one.

**A tab bar item carries no identifier before iOS 27, and the defect is iOS-only.** Apple's
`TabContent.accessibilityIdentifier` is declared from iOS 18 and does nothing on iOS until 27.
Measured one variable at a time, tagging the `Tab` (either initializer), tagging its label, and
applying Apple's modifier raw all behave identically — the tab bar buttons come back with `id=""`:

- Xcode 27 → iOS 27.0 — **identifier present**
- Xcode 27 → iOS 26.5 — absent
- Xcode 27 → iOS 18.5 — absent
- Xcode 26.5 → iOS 26.5 — absent
- Xcode 26.5 → iOS 18.6 — absent
- Xcode 26.5 → macOS 26.4 — **present** (a tab is a radio button here, not a `UITabBarItem`)
- Xcode 27 → macOS 27.0 beta (26A5406e) — **present**, but **taps on bar items do not land**
  (tab bar and toolbar buttons; every in-window control still taps fine) — see the macOS 27
  note below
- Xcode 26.5 → tvOS 26.5 — **present**

The runtime decides and the SDK does not, which is why `TabContent.uiTestingIdentifier` raises its
floor for **iOS only** and `TabTaggingTests` skips below iOS 27. Re-run this matrix against a new
OS before widening that floor. Everything a tab *contains* is found by its own tag on every
runtime; only the iOS bar item is affected.

Not measured: **visionOS** (the run was lost when the VM hosting it was recycled) and **watchOS**
(no XCUITest). Both keep Apple's declared floors rather than a guessed one — measure before
changing that.

**On iOS 27, where the tag does land, it lands late** — a few hundred milliseconds after launch,
whereas every tagged view on screen resolves on the first query. `tap()` asked once and gave up,
so it raced the tab bar and lost. Actions wait now; questions still answer about the screen as it
is, so a test that *opens* by asking about a tab (`isVisible`, `exists`) still wants
`waitForExistence()` first.

**macOS 27.0 beta (26A5406e, Xcode 27.0/27A5237l, measured 2026-08-17):** two distinct
regressions, both deterministic across repeated runs on an idle desktop. First, with the app's
`WindowGroup` root being a bare `if #available` conditional, XCUITest finds **nothing in the
window at all** — all eight tab and toolbar tests fail, including plain on-screen label reads
that pass everywhere else. Wrapping the root in `Group { ... }.testHost()` (an `AnyView` root)
restores discovery; why an `AnyView` root re-anchors the accessibility tree on this beta is not
yet root-caused. Second, with discovery restored, **synthesized taps on native-bridged bar
items do not land** — a tab bar button or toolbar button receives the tap and nothing happens
(the tag is present and the elements are found; only the tap is lost). Every in-window control
taps normally. Re-measure both on the next beta before treating either as the platform's
behaviour.

Every assertion goes through `uiTestingElement(_:)`. The harness contains no XCUITest
element-type queries — if one appears, it is either a gap in the strategy that needs stating
or a shortcut that needs removing.

## Adding a case

Add the view to `App/ProbeApp.swift` with a tag, then assert against it in
`UITests/UITestingElementTests.swift`. Keep each test to one claim — the harness is evidence,
and evidence that bundles claims is hard to read when it fails.
