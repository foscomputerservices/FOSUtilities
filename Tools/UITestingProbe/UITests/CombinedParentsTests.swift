// CombinedParentsTests.swift
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

private let probeBundleId = "com.foscomputerservices.uitestingprobe.UITestingProbe"

/// `designedFor: [.navigation, .scrolling]` — both parents, and the cases a view with a
/// toolbar *and* a focusable field actually hits.
///
/// A screen with actions in the bar and fields in the body is, in production, essentially
/// always inside a scroll parent too, so this pairing is the common shape rather than an
/// exotic one.
@MainActor final class CombinedParentsTests: ViewModelViewTestCase<ScrollingToolbarCardViewModel, ToolbarCardOps>, @unchecked Sendable {
    override func setUp() async throws {
        try await super.setUp(
            bundle: Bundle(for: CombinedParentsTests.self),
            appBundleIdentifier: probeBundleId
        )
        continueAfterFailure = true
    }

    /// Both parents are applied: the toolbar renders (navigation) and the buried field is
    /// reachable (scrolling). One assertion per parent, on one presentation, so a
    /// regression in either is attributable.
    func testBothParentsAreApplied() throws {
        let app = try presentView()

        XCTAssertTrue(app.uiTestingElement("scrollingToolbarCardSaveButton").waitForExistence())

        let field = app.uiTestingElement("scrollingToolbarCardField")
        XCTAssertTrue(field.waitForExistence())
        field.tap()
        field.type("42")
        XCTAssertEqual(field.value, "42")
    }

    /// The toolbar item is reachable while the keyboard is up and a field below it holds
    /// focus.
    ///
    /// With no scroll parent, keyboard avoidance shifts the whole hosted tree upward rather
    /// than scrolling — a navigation bar sits at the top of that tree, so it is the first
    /// thing displaced off-screen. A scroll parent absorbs the avoidance instead, which is
    /// why this pairing is the answer rather than a framework change. Measured in the field
    /// before it was pinned here.
    func testToolbarItemSurvivesARaisedKeyboard() throws {
        let app = try presentView()

        let field = app.uiTestingElement("scrollingToolbarCardField")
        XCTAssertTrue(field.waitForExistence())
        field.tap()
        field.type("7")

        let save = app.uiTestingElement("scrollingToolbarCardSaveButton")
        XCTAssertTrue(save.waitForExistence(), "the bar left the tree once the keyboard rose")

        save.tap()

        let ops = try viewModelOperations()
        XCTAssertEqual(ops.saveCount, 1, "the tap did not reach the control with the keyboard up")
    }

    /// Reading the operations transporter mid-flow does not cost the next toolbar tap.
    ///
    /// Reported from the field as deterministic: tap a toolbar item, read
    /// `viewModelOperations()`, edit a field, tap a second toolbar item — and the second tap
    /// reports its target missing. It reproduced only with a scrolling parent declared,
    /// which is this registration, and a near-twin without the mid-flow read passed.
    ///
    /// The read is the variable under test, so the sequence keeps it and asserts the second
    /// tap's *effect*. If this fails, the mid-flow read is the cause and the question is
    /// whether that is a framework defect or a call pattern the harness should refuse
    /// teachably — not something to paper over by moving the read to the end.
    func testAToolbarTapSurvivesAMidFlowOperationsRead() throws {
        let app = try presentView()

        app.uiTestingElement("scrollingToolbarCardSaveButton").tap()

        let afterFirst = try viewModelOperations()
        XCTAssertEqual(afterFirst.saveCount, 1)

        let field = app.uiTestingElement("scrollingToolbarCardField")
        XCTAssertTrue(field.waitForExistence())
        field.tap()
        field.type("9")

        app.uiTestingElement("scrollingToolbarCardResetButton").tap()

        let afterSecond = try viewModelOperations()
        XCTAssertEqual(
            afterSecond.resetCount, 1,
            "the second toolbar tap did not land after a mid-flow operations read"
        )
    }
}
