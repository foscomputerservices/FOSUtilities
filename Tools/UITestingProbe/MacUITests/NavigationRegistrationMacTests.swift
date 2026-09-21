// NavigationRegistrationMacTests.swift
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

private let probeBundleId = "com.foscomputerservices.uitestingprobe.UITestingProbeMac"

// The macOS twin of NavigationRegistrationTests, and deliberately not a copy of it.
//
// A `.toolbar` inside a `NavigationStack` renders into the WINDOW toolbar here, not into an
// in-view bar, so the claim being tested is the same but the thing rendering it is not. The
// iOS suite's keyboard cases have no counterpart at all — there is no software keyboard to
// displace anything — and the bar-occlusion guard is `#if os(iOS)`, so nothing in this file
// exercises it.
//
// What must hold on both platforms is the contract itself: a declared navigation parent
// renders the toolbar and a tap on it reaches the ViewModel; declaring nothing does not.

@MainActor final class NavigationRegistrationMacTests: ViewModelViewTestCase<ToolbarCardViewModel, ToolbarCardOps>, @unchecked Sendable {
    override func setUp() async throws {
        try await super.setUp(
            bundle: Bundle(for: NavigationRegistrationMacTests.self),
            appBundleIdentifier: probeBundleId
        )
        continueAfterFailure = true
    }

    /// The declared parent renders the toolbar item — into the window toolbar on this
    /// platform, which is the bridge `ToolbarTaggingMacTests` already proves tags survive.
    func testToolbarItemIsPresent() throws {
        let app = try presentView()

        XCTAssertTrue(
            app.uiTestingElement("toolbarCardSaveButton").waitForExistence(),
            "the toolbar item never reached the tree"
        )
    }

    /// And the tap reaches the ViewModel. Asserted on the recorded operation, because a
    /// gesture that lands nowhere returns just as happily here as it does on iOS.
    func testTappingTheToolbarItemReachesTheViewModel() throws {
        let app = try presentView()

        app.uiTestingElement("toolbarCardSaveButton").tap()

        let ops = try viewModelOperations()
        XCTAssertEqual(ops.saveCount, 1)
    }

    /// The transporter survives the navigation parent on this platform too.
    func testOperationsAreReadableUnderTheNavigationParent() throws {
        let app = try presentView()
        XCTAssertTrue(app.uiTestingElement("toolbarCardBody").waitForExistence())

        XCTAssertNoThrow(try viewModelOperations())
    }

    /// The host publishes what it resolved here as well — the diagnostic channel is not
    /// platform-gated, so neither is its evidence.
    func testTheHostPublishesTheResolvedParents() throws {
        let app = try presentView()
        XCTAssertTrue(app.uiTestingElement("toolbarCardBody").waitForExistence())

        let facts = app.descendants(matching: .any)
            .matching(identifier: "__testing_host_facts__")
            .firstMatch

        XCTAssertTrue(facts.waitForExistence(timeout: 10), "the host published nothing")
        let published = ProductionParents(rawValue: Int(facts.value as? String ?? "") ?? 0)
        XCTAssertTrue(published.contains(.navigation))
    }
}

/// The negative twin, on macOS. Same body, no declared parent.
@MainActor final class UnparentedCardMacTests: ViewModelDisplayTestCase<UnparentedCardViewModel>, @unchecked Sendable {
    override func setUp() async throws {
        try await super.setUp(
            bundle: Bundle(for: UnparentedCardMacTests.self),
            appBundleIdentifier: probeBundleId
        )
        continueAfterFailure = true
    }

    /// The body renders, so a failure below is about the missing parent rather than a
    /// broken fixture.
    func testTheViewItselfIsPresented() throws {
        let app = try presentView()

        XCTAssertTrue(app.uiTestingElement("unparentedCardBody").waitForExistence())
    }

    /// Declared nothing, so there is no ancestor to render the toolbar into.
    func testToolbarItemIsAbsentWithoutTheDeclaration() throws {
        let app = try presentView()
        XCTAssertTrue(app.uiTestingElement("unparentedCardBody").waitForExistence())

        XCTAssertFalse(
            app.uiTestingElement("unparentedCardSaveButton").exists,
            "the toolbar item resolved without a declared navigation parent — the default changed"
        )
    }
}
