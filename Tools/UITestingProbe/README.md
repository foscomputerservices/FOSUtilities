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

Every assertion goes through `uiTestingElement(_:)`. The harness contains no XCUITest
element-type queries — if one appears, it is either a gap in the strategy that needs stating
or a shortcut that needs removing.

## Adding a case

Add the view to `App/ProbeApp.swift` with a tag, then assert against it in
`UITests/UITestingElementTests.swift`. Keep each test to one claim — the harness is evidence,
and evidence that bundles claims is hard to read when it fails.
