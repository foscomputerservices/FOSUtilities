// ScrollRegistrationMacTests.swift
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

// The macOS twin of ScrollRegistrationTests / BarePresentationTests, and the first
// presentView()-based suite this platform has ever been able to run: until the Mac test
// bundle compiled the shared probe ViewModels and carried the YAML resource, the whole
// registration transport was unreachable here.
//
// Not a line-for-line port. The iOS suite proves its reach with the software keyboard —
// tap the buried field, wait for the keyboard, type. macOS has no software keyboard, so
// the reach is proven the way the platform actually works: click the field, type into it,
// read the value back.

@MainActor final class ScrollRegistrationMacTests: ViewModelDisplayTestCase<TallCardViewModel>, @unchecked Sendable {
    override func setUp() async throws {
        try await super.setUp(
            bundle: Bundle(for: ScrollRegistrationMacTests.self),
            appBundleIdentifier: probeBundleId
        )
        continueAfterFailure = true
    }

    /// The scrollable registration supplies the scrolling parent the card is designed for,
    /// so a field past the window's bottom is reachable and typing proves the reach is real.
    func testScrollableRegistrationReachesTheBuriedField() throws {
        let app = try presentView()

        let field = app.uiTestingElement("scrollCardField")
        XCTAssertTrue(field.waitForExistence())
        field.tap()
        field.type("42")

        XCTAssertEqual(field.value, "42")
    }
}

@MainActor final class BarePresentationMacTests: ViewModelDisplayTestCase<BareCardViewModel>, @unchecked Sendable {
    override func setUp() async throws {
        try await super.setUp(
            bundle: Bundle(for: BarePresentationMacTests.self),
            appBundleIdentifier: probeBundleId
        )
        continueAfterFailure = true
    }

    /// The default presentation is unchanged: presented bare, the card overflows the window
    /// and its bottom field sits outside it with nothing to scroll — present, and not visible.
    /// The guard that a registration nobody declared changes nothing.
    func testDefaultPresentationStaysBare() throws {
        let app = try presentView()

        let field = app.uiTestingElement("bareCardField")
        XCTAssertTrue(field.waitForExistence())

        // Judge the settled presentation, not a mid-layout frame — the iOS twin measured a
        // cold first launch reporting the field inside the window before layout finished.
        XCTAssertTrue(field.waitForStableFrame())
        XCTAssertFalse(field.isVisible)
    }
}
