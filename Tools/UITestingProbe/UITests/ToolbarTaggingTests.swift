// ToolbarTaggingTests.swift
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

/// A tag applied to a control in a toolbar, which bridges to a native bar item the way a tab bar
/// item does — and, unlike a tab bar item, carries the tag on every runtime measured.
@MainActor final class ToolbarTaggingTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    /// The tag holds on a control inside a `ToolbarItem`, and the tap reaches the control.
    func testTapsATaggedToolbarControl() {
        app.uiTestingElement("saveToolbarButton").tap()

        XCTAssertEqual(app.uiTestingElement("toolbarCounter").label, "toolbar-taps-1")
    }

    /// The tag holds inside a `ToolbarItemGroup` as well as a `ToolbarItem`.
    func testTagHoldsInAToolbarItemGroup() {
        XCTAssertTrue(app.uiTestingElement("plainToolbarButton").waitForExistence())
    }

    /// A toolbar control reports its own label through the tag beside it.
    func testLabelOfATaggedToolbarControl() {
        XCTAssertEqual(app.uiTestingElement("saveToolbarButton").label, "save")
    }

    /// A raw accessibility identifier in the same position reports its own state, as elsewhere.
    func testStateOfADirectlyIdentifiedToolbarControl() {
        let raw = app.uiTestingElement("rawToolbarButton")

        XCTAssertTrue(raw.waitForExistence())
        XCTAssertEqual(raw.label, "raw")
    }
}
