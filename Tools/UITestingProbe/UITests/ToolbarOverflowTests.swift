// ToolbarOverflowTests.swift
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

/// What an identifier is worth inside the system's toolbar overflow menu: nothing, measured
/// both ways.
///
/// A toolbar item that collapses into "More" is rebuilt by the system as a menu row carrying
/// its label and nothing else. Our tag is carried on a sibling element, which cannot follow
/// the item into a menu the system builds — and an `accessibilityIdentifier` applied directly
/// to the button does not survive either, which is the half worth pinning: it is the obvious
/// remedy, and it does not work. A test reaching an overflowed item has only its label.
///
/// This suite fails if that ever changes, which is the point — the wall is Apple's, and we
/// would want to know the day it moves.
@MainActor final class ToolbarOverflowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchEnvironment["PROBE_SCENE"] = "toolbarOverflow"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    func testAnOverflowedItemKeepsItsLabelAndLosesEveryIdentifier() {
        let more = app.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), "the items never collapsed into an overflow menu")

        more.tap()
        XCTAssertTrue(
            app.buttons["tagged"].waitForExistence(timeout: 5),
            "the overflow menu never presented its rows"
        )

        XCTAssertFalse(
            app.uiTestingElement("overflowTaggedButton").exists,
            "the View tag now follows an item into the overflow menu — the documented limitation has lifted"
        )
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "overflowDirectButton").firstMatch.exists,
            "a directly-applied accessibilityIdentifier now survives into the overflow menu — the documented limitation has lifted"
        )

        XCTAssertTrue(app.buttons["direct"].exists, "the label is all that is left to match on")
    }
}
