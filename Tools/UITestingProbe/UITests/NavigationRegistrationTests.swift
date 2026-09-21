// NavigationRegistrationTests.swift
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

/// `designedFor: .navigation` supplies the navigation parent the view was designed for.
///
/// `.toolbar` is a preference the *ancestor* renders. With no navigation parent the view
/// still appears and every other tag on it resolves, but its toolbar items are absent from
/// the accessibility tree — not off-screen, not un-hittable, absent. A test looking for one
/// is told the identifier is wrong, which is the one thing it is not.
///
/// Paired with ``UnparentedCardTests`` below: same body, same tags, and the only difference
/// is what each registration declares.
@MainActor final class NavigationRegistrationTests: ViewModelViewTestCase<ToolbarCardViewModel, ToolbarCardOps>, @unchecked Sendable {
    override func setUp() async throws {
        try await super.setUp(
            bundle: Bundle(for: NavigationRegistrationTests.self),
            appBundleIdentifier: probeBundleId
        )
        continueAfterFailure = true
    }

    /// The declared parent renders the toolbar item, and the item is reachable.
    func testToolbarItemIsPresentAndHittable() throws {
        let app = try presentView()

        let save = app.uiTestingElement("toolbarCardSaveButton")
        XCTAssertTrue(save.waitForExistence(), "the toolbar item never reached the tree")
        XCTAssertTrue(save.isVisible)
    }

    /// Present in the tree is not the same as reachable: the assertion is the *effect*,
    /// read back from the ViewModel, not the gesture returning.
    func testTappingTheToolbarItemReachesTheViewModel() throws {
        let app = try presentView()

        app.uiTestingElement("toolbarCardSaveButton").tap()

        let ops = try viewModelOperations()
        XCTAssertEqual(ops.saveCount, 1)
    }

    /// `navigationTitle` rides the same mechanism as `.toolbar`, and consuming apps reach
    /// for it next.
    func testNavigationTitleIsQueryable() throws {
        let app = try presentView()

        XCTAssertTrue(app.staticTexts["card-title"].waitForExistence(timeout: 10))
    }

    /// The hypothesis stays silent when a navigation parent IS declared.
    ///
    /// This is the half that justifies asking about the target instead of appending a
    /// standing sentence to every not-found failure: a message that always says the same
    /// thing teaches nothing, and dilutes the two hypotheses that are usually right.
    func testTheMessageStaysSilentWhenTheParentIsDeclared() throws {
        let app = try presentView()
        XCTAssertTrue(app.uiTestingElement("toolbarCardBody").waitForExistence())

        var captured = ""
        XCTExpectFailure("a deliberate miss against a declared-parent host") { issue in
            captured = issue.compactDescription
            return true
        }
        app.uiTestingElement("noSuchTagAnywhere").tap()

        XCTAssertFalse(captured.isEmpty, "no failure was captured")
        XCTAssertFalse(
            captured.contains("declares no navigation parent"),
            "the hypothesis fired for a view that has a navigation parent: \(captured)"
        )
    }

    /// The transporter survives the navigation parent.
    ///
    /// `registerTestView(_:scrollable:)` shipped in 0.12.4 and needed a fix in 0.12.7
    /// because a zero-sized transporter was culled from the accessibility tree inside a
    /// `ScrollView`. A `NavigationStack` is the same class of container, so the read is
    /// claimed here by name rather than left to fail obscurely inside another assertion.
    func testOperationsAreReadableUnderTheNavigationParent() throws {
        let app = try presentView()
        XCTAssertTrue(app.uiTestingElement("toolbarCardBody").waitForExistence())

        XCTAssertNoThrow(try viewModelOperations())
    }
}

/// The default is unchanged: a view that declares nothing is presented bare, and its
/// toolbar items are absent. This pins the default and documents the symptom.
@MainActor final class UnparentedCardTests: ViewModelDisplayTestCase<UnparentedCardViewModel>, @unchecked Sendable {
    override func setUp() async throws {
        try await super.setUp(
            bundle: Bundle(for: UnparentedCardTests.self),
            appBundleIdentifier: probeBundleId
        )
        continueAfterFailure = true
    }

    /// The body renders — so a failure below is about the missing parent, not a broken
    /// fixture or a mistyped tag.
    func testTheViewItselfIsPresented() throws {
        let app = try presentView()

        XCTAssertTrue(app.uiTestingElement("unparentedCardBody").waitForExistence())
    }

    /// Declared nothing, so the toolbar item has no ancestor to render into.
    func testToolbarItemIsAbsentWithoutTheDeclaration() throws {
        let app = try presentView()
        XCTAssertTrue(app.uiTestingElement("unparentedCardBody").waitForExistence())

        XCTAssertFalse(
            app.uiTestingElement("unparentedCardSaveButton").exists,
            "the toolbar item resolved without a declared navigation parent — the default changed"
        )
    }
}

/// The not-found message names the missing navigation parent — and only when that is
/// actually the cause.
///
/// The failure this whole arc started from was legible but misleading: a toolbar item
/// dropped for want of an ancestor reports as a wrong identifier, sending the reader to
/// audit the one thing that is correct. The harness knows the registration; the test
/// process does not, so `testHost()` publishes it and the message reads it back.
///
/// These tests assert on the message text rather than on a failure, so they never need a
/// deliberately failing assertion to observe it.
@MainActor final class NotFoundHypothesisTests: ViewModelDisplayTestCase<UnparentedCardViewModel>, @unchecked Sendable {
    override func setUp() async throws {
        try await super.setUp(
            bundle: Bundle(for: NotFoundHypothesisTests.self),
            appBundleIdentifier: probeBundleId
        )
        continueAfterFailure = true
    }

    /// The host publishes what it resolved, so the test process can tell a missing parent
    /// from a missing identifier.
    func testTheHostPublishesTheResolvedParents() throws {
        let app = try presentView()
        XCTAssertTrue(app.uiTestingElement("unparentedCardBody").waitForExistence())

        let facts = app.descendants(matching: .any)
            .matching(identifier: "__testing_host_facts__")
            .firstMatch

        XCTAssertTrue(facts.waitForExistence(timeout: 10), "the host published nothing")
        // This view declares no parents, so the published set is empty.
        XCTAssertEqual(facts.value as? String, "0")
    }

    /// The hypothesis reaches the message, and names the missing parent.
    ///
    /// The only way to observe a failure message is to cause one, so the lookup below is
    /// deliberately for a tag that does not exist and the failure is caught rather than
    /// reported. `XCTExpectFailure` returns the issues it swallowed, which is what makes the
    /// text assertable instead of merely visible in a log.
    ///
    /// Worth the oddity: this arc began because a message was accurate and misleading at the
    /// same time — "check the identifier" when the identifier was the one correct thing. An
    /// unpinned message drifts back to that silently.
    func testTheMessageNamesTheMissingNavigationParent() throws {
        let app = try presentView()
        XCTAssertTrue(app.uiTestingElement("unparentedCardBody").waitForExistence())

        var captured = ""
        XCTExpectFailure("a deliberate miss, to read the message it produces") { issue in
            captured = issue.compactDescription
            return true
        }
        app.uiTestingElement("unparentedCardSaveButton").tap()

        XCTAssertTrue(
            captured.contains("declares no navigation parent"),
            "the message did not name the missing parent: \(captured)"
        )
        XCTAssertTrue(
            captured.contains(".toolbar"),
            "the message did not say what a missing parent costs: \(captured)"
        )
    }
}
