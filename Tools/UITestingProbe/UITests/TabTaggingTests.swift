// TabTaggingTests.swift
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

/// A tag applied to a `Tab`, which reaches the accessibility tree later than the views on screen.
///
/// iOS 27 and later only.  Apple's `TabContent.accessibilityIdentifier` is declared from iOS 18
/// and puts no identifier on the tab bar item until iOS 27, so below that the probe shows no
/// `TabView` at all and there is nothing here to assert.  The matrix that establishes this is in
/// `README.md`; re-run it against a new OS before widening the floor.
@MainActor final class TabTaggingTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(
            ProcessInfo.processInfo.isOperatingSystemAtLeast(
                .init(majorVersion: 27, minorVersion: 0, patchVersion: 0)
            ),
            "Tab bar items carry no identifier before iOS 27"
        )
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    /// The reported failure (#126): the first thing the test does is tap a tab.  A tap waits, so
    /// the tab bar arriving after the views on screen is not the test's problem.
    func testTapsATabAsTheFirstThingATestDoes() {
        app.uiTestingElement("secondTab").tap()

        XCTAssertTrue(app.uiTestingElement("secondContent").waitForExistence())
    }

    /// The tag holds however the tab was written: either initializer, and on the label as well as
    /// on the `Tab`.
    func testTagHoldsOnEveryFormOfTab() {
        for identifier in ["probeTab", "secondTab", "thirdLabel"] {
            XCTAssertTrue(
                app.uiTestingElement(identifier).waitForExistence(),
                "\(identifier) was not found"
            )
        }
    }

    /// A tab reports the tab bar item's own state, the tag being on the item rather than beside it.
    func testStateOfATaggedTab() {
        let tab = app.uiTestingElement("secondTab")
        XCTAssertTrue(tab.waitForExistence())

        XCTAssertEqual(tab.label, "second")
        XCTAssertTrue(tab.isEnabled)
    }

    /// Tags inside a tab's content are untouched by the tab carrying one of its own.
    func testTagsInsideATabHold() {
        app.uiTestingElement("thirdLabel").tap()

        XCTAssertTrue(app.uiTestingElement("thirdContent").waitForExistence())
    }

    /// The views on screen are found straight away, which is what makes the tab bar's later
    /// arrival worth stating: the two are not asked about in the same way.
    func testViewsOnScreenAreFoundWithoutWaiting() {
        XCTAssertTrue(app.uiTestingElement("tapButton").isVisible)
    }
}
