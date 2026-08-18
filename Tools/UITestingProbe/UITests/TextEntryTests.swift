// TextEntryTests.swift
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

@MainActor final class TextEntryTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchEnvironment["PROBE_SCENE"] = "rowResolution"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    /// The replace contract through a row-spanning tag: the field is prefilled, so the whole
    /// value must be selected and replaced — no caret arithmetic, no appended remnant.
    func testReplacesAnExistingValueThroughARowTag() {
        app.uiTestingElement("gapRow").setText("42")

        XCTAssertEqual(app.uiTestingElement("gapRow").value, "42")
    }

    /// Entering into an empty field: nothing to select, typing inserts, read-back verifies.
    func testEntersIntoAnEmptyField() {
        app.uiTestingElement("captionField").setText("Fern")

        XCTAssertEqual(app.uiTestingElement("captionField").value, "Fern")
    }

    /// A right-aligned field: the aim is at the resolved control's frame, so the text's
    /// alignment inside it must not matter.
    func testTrailingAlignedField() {
        app.uiTestingElement("trailingField").setText("123")

        XCTAssertEqual(app.uiTestingElement("trailingField").value, "123")
    }

    /// A `.numberPad` field, prefilled: replace must work on a keyboard with no Return key,
    /// and the edit-menu selection must work over numeric content.
    func testNumberPadFieldReplaces() {
        app.uiTestingElement("padField").setText("77")

        XCTAssertEqual(app.uiTestingElement("padField").value, "77")
    }

    /// The F5 edge: a formatter-backed field renders "45" as "45.00" when the entry commits.
    /// `expecting:` declares the rendering and commits the entry before verifying.
    func testFormatterFieldWithExpecting() {
        app.uiTestingElement("priceField").setText("45", expecting: "45.00")

        XCTAssertEqual(app.uiTestingElement("priceField").value, "45.00")
    }

    /// SecureFields are excluded, loudly and teachably — bullets defeat any honest read-back.
    func testSecureFieldIsRejectedTeaching() {
        XCTExpectFailure {
            app.uiTestingElement("secretField").setText("hunter2")
        } issueMatcher: { issue in
            issue.compactDescription.contains("SecureField")
        }
    }
}
