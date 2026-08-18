// ToggleFlippingTests.swift
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

@MainActor final class ToggleFlippingTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    /// The postcondition contract: setToggle does not return until the switch reports the
    /// state, so the very next read of state derived from it — un-waited — is correct. The
    /// fixture's Toggle has a leading label, the geometry whose merged accessibility
    /// element defeats a midpoint tap (measured: the framework's own tap() flips nothing
    /// there), so each committed flip also proves the aim.
    func testDerivedStateIsCorrectWithoutAWait() {
        let toggle = app.uiTestingElement("flagToggle")

        for on in [true, false, true] {
            toggle.setToggle(on)

            XCTAssertEqual(
                app.uiTestingElement("flagStateLabel").label,
                "flag-\(on ? "on" : "off")",
                "the un-waited read after setting \(on) was stale"
            )
        }
    }

    /// A Toggle already in the requested state is a verified no-op — the call returns
    /// without flipping anything, so driving it twice is idempotent.
    func testAlreadyAtStateIsAVerifiedNoOp() {
        let toggle = app.uiTestingElement("flagToggle")

        toggle.setToggle(false)
        toggle.setToggle(false)
        XCTAssertEqual(app.uiTestingElement("flagStateLabel").label, "flag-off")

        toggle.setToggle(true)
        toggle.setToggle(true)
        XCTAssertEqual(app.uiTestingElement("flagStateLabel").label, "flag-on")
    }
}
