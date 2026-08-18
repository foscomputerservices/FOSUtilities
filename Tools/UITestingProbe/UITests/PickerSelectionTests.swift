// PickerSelectionTests.swift
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

@MainActor final class PickerSelectionTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    /// The postcondition contract: selectPickerItem does not return until the selection
    /// committed, so the very next read of selection-derived state — un-waited — is correct.
    /// Cycling distinct items proves each round's selection actually changed.
    func testSelectionDerivedStateIsCorrectWithoutAWait() {
        let picker = app.uiTestingElement("settlePicker")

        for target in [3, 6, 1, 7, 2, 5] {
            picker.selectPickerItem("settleOption-\(target)")

            XCTAssertEqual(
                app.uiTestingElement("settleSelectionLabel").label,
                "settle-sel-\(target)",
                "the un-waited read after selecting item \(target) was stale"
            )
        }
    }

    /// A menu with more rows than its presented card can show clips part of the list
    /// behind the menu's internal scroll — while the accessibility tree reports clipped
    /// rows with on-screen frames at the positions they would occupy, so a tap at such a
    /// frame lands on the scrim and dismisses the menu without selecting (red-first on the
    /// pre-ladder implementation). selectPickerItem must scroll within the menu; because
    /// the menu re-anchors its scroll at the checked item, cycling targets on both sides
    /// of the anchor proves both scroll directions.
    func testOverflowingMenuReachesClippedItems() {
        let picker = app.uiTestingElement("overflowPicker")

        // 0 → 15: the target is clipped just past the fold with its would-be frame still
        // inside the window — the frame every visibility signal believes, whose midpoint
        // tap lands on the scrim (the field-failure class). 15 → 2: the menu re-anchors at
        // the new selection and the target hides above the fold. 2 → 23: clipped so deep
        // the row is not in the accessibility tree at all.
        for target in [15, 2, 23] {
            picker.selectPickerItem("overflowOption-\(target)")

            XCTAssertEqual(
                app.uiTestingElement("overflowSelectionLabel").label,
                "overflow-sel-\(target)",
                "the un-waited read after selecting item \(target) was stale"
            )
        }
    }

    /// A nonexistent item identifier fails loudly at the call site, naming the item.
    func testNonexistentItemFailsLoudly() {
        XCTExpectFailure {
            app.uiTestingElement("settlePicker").selectPickerItem("noSuchOption")
        } issueMatcher: { issue in
            issue.compactDescription.contains("noSuchOption")
        }
    }
}
