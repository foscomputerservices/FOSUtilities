// VerticalToolbarTests.swift
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

/// What a raised keyboard does to a toolbar on iOS 27.1, pinned per item presentation.
///
/// A short screen with a keyboard up leaves the window vertically compressed, and iOS 27.1
/// answers by moving the toolbar's items into a vertical bar along the trailing edge. An item
/// whose label is text with no icon is not moved — it is dropped from the accessibility tree,
/// and the `navigationTitle` goes with it, leaving a navigation bar that is present and
/// entirely empty — with no overflow control anywhere in the tree, so the item is not merely
/// hidden behind a menu. Measured on iPhone Duo / iOS 27.1 (a 466x678 cover screen)
/// 2026-09-22; the identical tree on an iPhone 17 Pro / iOS 27.0 keeps every item and merely
/// shortens the bar from 106pt to 54pt.
///
/// That fork is why these tests read the bar rather than the device: the relocation is a
/// property of the geometry, and a destination that never compresses far enough is a control
/// rather than a hole. What holds on BOTH sides is the one thing a consumer can act on — an
/// item with an icon stays reachable — and `testAnIconItemIsReachableUnderARaisedKeyboard`
/// is that assertion, unconditional.
@MainActor final class VerticalToolbarTests: XCTestCase {
    private var app: XCUIApplication!

    private func launch(scene: String) {
        app = XCUIApplication()
        app.launchEnvironment["PROBE_SCENE"] = scene
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    private func raiseKeyboard() {
        app.uiTestingElement("vtField").tap()
        app.typeText("7")
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 10),
            "The software keyboard never appeared — on a simulator, check that the hardware keyboard is disconnected (I/O > Keyboard > Connect Hardware Keyboard off)"
        )
    }

    /// The signature of the relocation, asked of the bar rather than assumed from the device:
    /// a navigation bar that is in the tree holding nothing at all.
    /// `axisBehavior(_:)` arrived in iOS 27.1, so below that floor the item declaring it is
    /// not in the tree at all — absent because it was never built, which is not the finding
    /// these tests are about.
    private var horizontalOnlyItemWasDeclared: Bool {
        app.uiTestingElement("vtHorizontalOnlyItem").exists
    }

    private var itemsWereRelocated: Bool {
        let bar = app.navigationBars.firstMatch

        return bar.exists && bar.buttons.count == 0 && bar.staticTexts.count == 0
    }

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = true
    }

    /// The one guarantee that holds on every destination measured, and the only one a
    /// consumer can act on: an item carrying an icon is still there, and still reaches its
    /// action, once the keyboard is up. Asserted on the tap's *effect*, because a gesture
    /// that lands in a bar returns just as happily as one that lands on the control.
    func testAnIconItemIsReachableUnderARaisedKeyboard() {
        launch(scene: "verticalToolbar")
        XCTAssertTrue(app.uiTestingElement("vtLabelItem").waitForExistence())

        raiseKeyboard()

        let item = app.uiTestingElement("vtLabelItem")
        XCTAssertTrue(item.exists, "an item with an icon left the tree with the keyboard up")
        item.tap()

        XCTAssertEqual(app.uiTestingElement("vtCounter").label, "vt-taps-1")
    }

    /// The presentation rule itself. Both branches are asserted, so a destination that stops
    /// relocating — or starts — is reported rather than silently passing.
    func testATextOnlyItemDoesNotSurviveTheRelocation() {
        launch(scene: "verticalToolbar")
        XCTAssertTrue(app.uiTestingElement("vtTextItem").waitForExistence())

        raiseKeyboard()

        guard itemsWereRelocated else {
            XCTAssertTrue(
                app.uiTestingElement("vtTextItem").exists,
                "the navigation bar kept its content, so nothing should have been dropped"
            )

            return
        }

        XCTAssertFalse(
            app.uiTestingElement("vtTextItem").exists,
            "a text-only item survived the relocation — the rule this pins has changed"
        )
        XCTAssertTrue(app.uiTestingElement("vtLabelItem").exists)
        XCTAssertTrue(app.uiTestingElement("vtIconItem").exists)
    }

    /// `axisBehavior(.horizontalOnly)` is not the escape hatch its name suggests: the item it
    /// is applied to is text-only, and it is dropped exactly as the undeclared one is. Pinned
    /// because it is the first thing a reader reaches for after meeting the failure.
    func testDeclaringHorizontalOnlyDoesNotRescueATextOnlyItem() {
        launch(scene: "verticalToolbar")
        XCTAssertTrue(app.uiTestingElement("vtTextItem").waitForExistence())

        guard horizontalOnlyItemWasDeclared else { return }

        raiseKeyboard()

        guard itemsWereRelocated else { return }

        XCTAssertFalse(
            app.uiTestingElement("vtHorizontalOnlyItem").exists,
            "axisBehavior(.horizontalOnly) kept a text-only item — reopen the guidance"
        )
    }

    /// The failure message names the relocation, so a reader meeting this for the first time
    /// is not sent to audit an identifier that is correct.
    ///
    /// The only way to observe a failure message is to cause one, so the lookup is
    /// deliberately for an item that has been dropped and the failure is caught rather than
    /// reported. Pinned for the same reason `NotFoundHypothesisTests` pins its own: an
    /// unpinned message drifts back to "check the identifier" silently.
    func testTheMessageNamesTheDroppedToolbarItem() {
        launch(scene: "verticalToolbar")
        XCTAssertTrue(app.uiTestingElement("vtTextItem").waitForExistence())

        raiseKeyboard()

        guard itemsWereRelocated else { return }

        var captured = ""
        XCTExpectFailure("a deliberate miss, to read the message it produces") { issue in
            captured = issue.compactDescription
            return true
        }
        app.uiTestingElement("vtTextItem").tap()

        XCTAssertTrue(
            captured.contains("vertical bar along the trailing edge"),
            "the message did not name the relocation: \(captured)"
        )
        XCTAssertTrue(
            captured.contains("Label(_:systemImage:)"),
            "the message did not name the fix: \(captured)"
        )
    }

    /// `toolbarVerticalBehavior(.disabled)` does what its name says — the bar stays
    /// horizontal — and the items that no longer fit across it collapse into the system's
    /// overflow menu instead of moving. That is a different fate from the relocation's: the
    /// item is still there, one tap behind "More".
    ///
    /// But it arrives in that menu UNTAGGED. Measured on iPhone Duo / iOS 27.1: the overflow
    /// presents `Button, label: 'vtText'` with an empty identifier, so
    /// `uiTestingElement("vtTextItem")` cannot find it and only a label match resolves. Same
    /// shape as the tab-bar identifier gap of #126, and the reason this is pinned rather than
    /// described: at a call site an overflowed item and a dropped one both read as `exists ==
    /// false`, and only opening the menu tells them apart.
    func testDisablingVerticalBehaviourOverflowsRatherThanDropping() {
        launch(scene: "verticalToolbarDisabled")
        XCTAssertTrue(app.uiTestingElement("vtLabelItem").waitForExistence())

        // UIKit's own identifier for the bar's overflow control, measured on iOS 27.1. Its
        // absence means every item fits, which is the wide-destination branch.
        let overflow = app.buttons["TopOverflowBarButtonItem"]
        guard overflow.exists else {
            XCTAssertTrue(
                app.uiTestingElement("vtTextItem").exists,
                "nothing overflowed, so every item should be in the bar"
            )

            return
        }

        XCTAssertFalse(
            app.uiTestingElement("vtTextItem").exists,
            "an overflowed item should not be in the tree until the menu is opened"
        )

        overflow.tap()

        XCTAssertTrue(
            app.buttons["vtText"].waitForExistence(timeout: 10),
            "a text-only item was dropped rather than overflowed — the finding this pins has changed"
        )
        XCTAssertFalse(
            app.uiTestingElement("vtTextItem").exists,
            """
            the tag reached the overflow menu — the gap this pins has closed, and the \
            guidance that an overflowed item resolves by label only can go
            """
        )
    }
}
