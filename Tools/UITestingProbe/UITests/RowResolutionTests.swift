// RowResolutionTests.swift
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

@MainActor final class RowResolutionTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchEnvironment["PROBE_SCENE"] = "rowResolution"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    /// The measured failure: a tag spanning caption + field whose midpoint falls in the gap
    /// between them. Neither leaf contains the midpoint, so first-stage resolution answers
    /// with a container — the same midpoint, the same miss. The tap must land in the field,
    /// proven by the keyboard arriving.
    func testTapLandsInTheFieldAcrossTheGap() {
        app.uiTestingElement("gapRow").tap()

        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 10),
            "the tap missed the field — no keyboard arrived"
        )
    }

    /// The extrapolated edge, pinned: a caption long enough to contain the tag's midpoint.
    /// First-stage resolution answers with the caption itself — not a container, so only the
    /// hint rejects it — and the field must still be found. Typing proves the focus is real.
    func testTapLandsInTheFieldUnderALongCaption() {
        app.uiTestingElement("captionRow").tap()

        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 10),
            "the tap landed on the caption — no keyboard arrived"
        )

        app.typeText("42")
        XCTAssertEqual(app.uiTestingElement("captionField").value, "42")
    }

    /// The read half of the same blind spot: a row-spanning tag's `value` used to answer from
    /// the row's container — empty — instead of the field the row contains.
    func testRowSpanningTagReadsTheFieldsValue() {
        XCTAssertEqual(app.uiTestingElement("gapRow").value, "45")
    }

    /// The measured macOS failure (2026-08-21): the aimed-coordinate dispatch anchored at
    /// the app origin and offset by raw element-frame coordinates. Frames are
    /// app-origin-relative on iOS but SCREEN-relative on macOS, where the window origin is
    /// nonzero — the origin applied twice, and the tap dispatched without failure yet landed
    /// off-target: the control's action silently never fired. A caption + button composite
    /// forces the aimed path on every platform, and the fired count is the proof the tap
    /// landed — keyboard-free, so this claim holds on macOS, where the keyboard-arrival
    /// proofs above cannot run.
    func testAimedTapFiresTheActionAcrossTheComposite() {
        app.uiTestingElement("actionRow").tap()

        XCTAssertEqual(app.uiTestingElement("actionFireCount").label, "fired 1")
    }

    /// A tag on the control itself taps and reads that control; composite descent must not
    /// reroute it to a neighbour.
    func testDirectlyTaggedControlStillAnswersForItself() {
        let field = app.uiTestingElement("captionField")
        field.tap()

        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        app.typeText("9")

        XCTAssertEqual(field.value, "9")
    }
}
