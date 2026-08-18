// ScrollRegistrationTests.swift
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

@MainActor final class ScrollRegistrationTests: ViewModelDisplayTestCase<TallCardViewModel>, @unchecked Sendable {
    override func setUp() async throws {
        try await super.setUp(
            bundle: Bundle(for: ScrollRegistrationTests.self),
            appBundleIdentifier: probeBundleId
        )
        continueAfterFailure = true
    }

    /// The scrollable registration supplies the scrolling parent the card is designed for:
    /// a field buried past the window's bottom is reachable — XCUITest's scroll-to-visible
    /// finally has something to scroll — and typing proves the reach is real.
    func testScrollableRegistrationReachesTheBuriedField() throws {
        let app = try presentView()

        let field = app.uiTestingElement("scrollCardField")
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

@MainActor final class BarePresentationTests: ViewModelDisplayTestCase<BareCardViewModel>, @unchecked Sendable {
    override func setUp() async throws {
        try await super.setUp(
            bundle: Bundle(for: BarePresentationTests.self),
            appBundleIdentifier: probeBundleId
        )
        continueAfterFailure = true
    }

    /// The default presentation is unchanged: presented bare, the card overflows the window
    /// and its bottom field sits off screen with nothing to scroll — it exists, and is not
    /// visible. This is the guard that upgrading changes nothing for unregistered views.
    func testDefaultPresentationStaysBare() throws {
        let app = try presentView()

        let field = app.uiTestingElement("bareCardField")
        XCTAssertTrue(field.waitForExistence())

        // Judge the settled presentation, not a cold-launch mid-layout frame — on a first
        // launch the field's frame was measured inside the window once before layout finished.
        XCTAssertTrue(field.waitForStableFrame())
        XCTAssertFalse(field.isVisible)
    }
}
