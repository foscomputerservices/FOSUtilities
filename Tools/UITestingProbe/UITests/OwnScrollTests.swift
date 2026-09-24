// OwnScrollTests.swift
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

/// A view that owns its scroll view, registered without `.scrolling` because nothing scrolls
/// around it in production. The harness supplies no scrolling parent, so a field buried past
/// the window's bottom can only be reached through the view's own scroll view.
@MainActor final class OwnScrollTests: ViewModelDisplayTestCase<OwnScrollCardViewModel>, @unchecked Sendable {
    override func setUp() async throws {
        try await super.setUp(
            bundle: Bundle(for: OwnScrollTests.self),
            appBundleIdentifier: probeBundleId
        )
        continueAfterFailure = true
    }

    /// The buried field is off screen at presentation, so the tap takes the off-screen branch.
    /// Measured: handed the tag overlay, XCUITest scrolled it into the window and then refused
    /// it as not hittable, and the test ended there. The tap must reach the field through the
    /// view's own scroll view, proven by the keyboard arriving and the typed value landing.
    func testTapReachesAFieldBuriedInTheViewsOwnScrollView() throws {
        let app = try presentView()

        let field = app.uiTestingElement("ownScrollCardField")
        XCTAssertTrue(field.waitForExistence())
        field.tap()

        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 10),
            "the buried field was not reached"
        )
        app.typeText("42")
        XCTAssertEqual(field.value, "42")
    }
}
