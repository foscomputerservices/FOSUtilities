// UITestingElementTests.swift
//
// Copyright 2026 FOS Computer Services, LLC
//
// Licensed under the Apache License, Version 2.0 (the  License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import FOSMVVM
import FOSTestingUI
import XCTest

@MainActor final class UITestingElementTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    /// A tag holds on controls that bridge to a native element, which is where an
    /// identifier applied to the view itself is silently discarded.
    func testFindsBridgedControls() {
        for identifier in ["innerPicker", "nameField", "datePicker", "colorPicker", "flagToggle"] {
            XCTAssertTrue(
                app.uiTestingElement(identifier).isVisible,
                "\(identifier) was not found"
            )
        }
    }

    /// A tagged container must not disturb the tags of the sub-view it composes.
    func testTaggedContainerLeavesInnerTagsIntact() {
        XCTAssertTrue(app.uiTestingElement("outerPanel").isVisible)
        XCTAssertTrue(app.uiTestingElement("innerPanel").isVisible)
        XCTAssertTrue(app.uiTestingElement("innerPicker").isVisible)
    }

    func testTagHoldsWhenAppliedAfterOtherModifiers() {
        XCTAssertTrue(app.uiTestingElement("lateTaggedButton").isVisible)
    }

    func testDisabledTagIsNotApplied() {
        XCTAssertFalse(app.uiTestingElement("disabledTag").exists)
    }

    func testTapReachesTheControl() {
        app.uiTestingElement("tapButton").tap()

        XCTAssertEqual(app.uiTestingElement("tapCounter").label, "taps-1")
    }

    func testTapOpensABridgedControl() async throws {
        app.uiTestingElement("innerPicker").tap()

        XCTAssertTrue(app.uiTestingElement("optionB").waitForExistence())
        app.uiTestingElement("optionB").tap()

        // The menu's dismissal is animated and the picker reports no label while it runs, so the
        // selection is waited for rather than read on the next line. `label` answers about the
        // screen as it is now — settling is the test's job, as it is anywhere else.
        // A picker's options stay in the tree while the menu is closed, so there is nothing to
        // wait for the disappearance of.
        var label = ""
        for _ in 0..<40 where label != "program, optB" {
            label = app.uiTestingElement("innerPicker").label
            try await Task.sleep(for: .milliseconds(250))
        }

        XCTAssertEqual(label, "program, optB")
    }

    /// Displayed text is compared against a Localizable, not a literal.
    func testLabelMatchesALocalizable() {
        XCTAssertEqual(app.uiTestingElement("tapButton").label, LocalizableString.constant("tap me"))
    }

    func testValueMatchesALocalizable() {
        let field = app.uiTestingElement("nameField")
        field.type("Fern")

        XCTAssertEqual(field.value, LocalizableString.constant("Fern"))
    }

    /// A Localizable whose translation was never realized cannot match displayed text.
    func testUnrealizedLocalizableNeverMatches() {
        XCTAssertNotEqual(
            app.uiTestingElement("tapButton").label,
            LocalizableString.localized(key: "never.realized")
        )
    }

    /// A view whose identifier is on the control itself — a raw accessibilityIdentifier here, a
    /// tagged `Tab` in `TabTaggingTests` — reports its own state, not a neighbour's.
    func testStateOfADirectlyIdentifiedView() {
        let raw = app.uiTestingElement("rawTaggedButton")

        XCTAssertEqual(raw.label, "raw")
        XCTAssertFalse(raw.isEnabled)
    }

    /// A missing tag names itself rather than surfacing as an opaque XCUITest failure.
    func testMissingTagNamesTheIdentifier() {
        XCTExpectFailure {
            app.uiTestingElement("noSuchTag").tap()
        } issueMatcher: { issue in
            issue.compactDescription.contains("noSuchTag")
        }
    }

    /// A menu reports itself as not hittable while being perfectly tappable; isVisible must
    /// agree with tap() about that, or a test asserts one thing and does another.
    func testVisibilityAgreesWithTappability() {
        let picker = app.uiTestingElement("innerPicker")

        XCTAssertTrue(picker.isVisible)
        picker.tap()

        XCTAssertTrue(app.uiTestingElement("optionB").waitForExistence())
        app.uiTestingElement("optionB").tap()
    }

    func testExistenceFollowsTheViewHierarchy() {
        let banner = app.uiTestingElement("savedBanner")
        XCTAssertFalse(banner.exists)

        app.uiTestingElement("bannerToggle").tap()

        XCTAssertTrue(banner.waitForExistence())
    }

    func testWaitsForAViewToLeaveTheHierarchy() {
        let banner = app.uiTestingElement("savedBanner")
        app.uiTestingElement("bannerToggle").tap()
        XCTAssertTrue(banner.waitForExistence())

        app.uiTestingElement("bannerToggle").tap()

        XCTAssertTrue(banner.waitForDisappearance())
    }

    /// Present but off screen: exists, but not visible.
    func testEnablementReflectsTheControl() {
        XCTAssertFalse(app.uiTestingElement("disabledButton").isEnabled)
        XCTAssertTrue(app.uiTestingElement("enabledButton").isEnabled)
    }

    func testLabelReflectsTheControl() {
        XCTAssertEqual(app.uiTestingElement("tapButton").label, "tap me")
    }

    /// Typing reaches the field, and the field's own contents are what is read back.
    func testTypingReachesTheField() {
        let field = app.uiTestingElement("nameField")
        field.type("Fern")

        XCTAssertEqual(field.value, "Fern")
    }

    func testExistenceAndVisibilityAreDistinct() {
        let offscreen = app.uiTestingElement("offscreenLabel")

        XCTAssertTrue(offscreen.exists)
        XCTAssertFalse(offscreen.isVisible)

        app.swipeUp()
        app.swipeUp()
        app.swipeUp()

        XCTAssertTrue(offscreen.isVisible)
    }
}
