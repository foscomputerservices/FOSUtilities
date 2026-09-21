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
