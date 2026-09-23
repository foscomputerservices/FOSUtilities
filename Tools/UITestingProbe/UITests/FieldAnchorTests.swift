// FieldAnchorTests.swift
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

/// The scroll anchor `FormFieldView` publishes.
///
/// A form that shows a validation error has to be able to bring the offending field on
/// screen, and the identifier a caller holds for that field is its `fieldId` — the same one
/// validation messages and `focusField` name. The field's view is identified by that value,
/// so `ScrollViewReader` reaches it directly; nothing has to be derived or spelled.
@MainActor final class FieldAnchorTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchEnvironment["PROBE_SCENE"] = "fieldAnchor"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    /// The proof is displacement, not arrival: a lazily-rendered form materializes rows on
    /// its own, so a far field turning up says nothing, while the first field leaving the
    /// screen happens only if the form actually scrolled. An anchor `scrollTo` cannot match
    /// leaves the form where it stands and the first field in place.
    func testScrollsToAFieldByItsFieldId() {
        let first = app.uiTestingElement("anchorField0")

        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(first.isVisible, "the first field was not on screen to begin with")

        app.uiTestingElement("goToLastField").tap()

        XCTAssertTrue(
            app.uiTestingElement("anchorField39").waitForExistence(timeout: 10),
            "scrollTo(fieldId) did not reach the field"
        )
        XCTAssertFalse(
            first.isVisible,
            "the form never scrolled — the first field is still on screen"
        )
    }
}
