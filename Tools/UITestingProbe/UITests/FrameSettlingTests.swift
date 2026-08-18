// FrameSettlingTests.swift
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

@MainActor final class FrameSettlingTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    /// A menu row tapped immediately after opening the menu, in a loop, with zero misses
    /// allowed. The row exists while the menu is still animating in, so a coordinate computed
    /// from its in-flight frame lands where the row *was* — before tap() settled, this was
    /// probabilistic under host load.
    func testMenuRowTapsImmediatelyAfterOpening() async throws {
        for round in 1...10 {
            // Alternating targets so every round's selection must observably change.
            let target = round.isMultiple(of: 2) ? 3 : 6

            app.uiTestingElement("settlePicker").tap()

            let row = app.uiTestingElement("settleOption-\(target)")
            XCTAssertTrue(row.waitForExistence(), "round \(round): the menu row never arrived")
            row.tap()

            // The menu's dismissal is animated; the selection is waited for, not read next line.
            var label = ""
            for _ in 0..<40 where label != "settle-sel-\(target)" {
                label = app.uiTestingElement("settleSelectionLabel").label
                try await Task.sleep(for: .milliseconds(250))
            }

            XCTAssertEqual(label, "settle-sel-\(target)", "round \(round): the tap missed the row")
        }
    }

    /// A control that is not moving settles on the first pair of samples.
    func testStableFrameOnAStaticControl() {
        XCTAssertTrue(app.uiTestingElement("tapButton").waitForStableFrame())
    }

    /// A view that is not in the hierarchy can never settle: `false` immediately, not after
    /// the timeout — a gone element previously meant polling out the full wait.
    func testStableFrameOnAMissingViewFailsFast() {
        let started = Date()

        XCTAssertFalse(app.uiTestingElement("noSuchTag").waitForStableFrame(timeout: 8))

        XCTAssertLessThan(Date().timeIntervalSince(started), 4)
    }

    /// The hittable branch gained no settle. Latency alone cannot prove a negative under
    /// simulator load, so the bound is generous — it exists to catch the settle's sampling
    /// cadence being accidentally added to the native-tap path.
    func testHittableTapLatencyUnchanged() {
        let button = app.uiTestingElement("tapButton")
        XCTAssertTrue(button.waitForExistence())

        let started = Date()
        button.tap()

        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }
}
