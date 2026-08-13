// TabTaggingMacTests.swift
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

/// A tag applied to a `Tab` on macOS, where a tab bar is a different control than it is on iOS.
///
/// Unlike iOS, macOS tags the tab at its own floor — measured on macOS 26.4 — so there is no
/// version gate here.  The matrix is in `README.md`.
@MainActor final class TabTaggingMacTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    /// The reported failure (#126), as it reads on macOS: the first thing the test does is tap a
    /// tab.
    func testTapsATabAsTheFirstThingATestDoes() {
        app.uiTestingElement("secondTab").tap()

        XCTAssertTrue(app.uiTestingElement("secondContent").waitForExistence())
    }

    /// The tag holds however the tab was written.
    func testTagHoldsOnEveryFormOfTab() {
        for identifier in ["probeTab", "secondTab", "thirdLabel"] {
            XCTAssertTrue(
                app.uiTestingElement(identifier).waitForExistence(),
                "\(identifier) was not found"
            )
        }
    }

    /// Tags inside a tab's content are untouched by the tab carrying one of its own.
    func testTagsInsideATabHold() {
        app.uiTestingElement("thirdLabel").tap()

        XCTAssertTrue(app.uiTestingElement("thirdContent").waitForExistence())
    }

    /// The views on screen are found straight away, as they are on iOS.
    func testViewsOnScreenAreFoundWithoutWaiting() {
        XCTAssertTrue(app.uiTestingElement("tapButton").isVisible)
    }
}
