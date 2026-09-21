// FrameAgreementTests.swift
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

/// The frame XCUITest reports for a view agrees with where that view actually renders.
///
/// `tap()` computes a coordinate from the reported frame whenever an element is on screen
/// but reports not-hittable, so that frame is load-bearing: if it drifted, every coordinate
/// tap would land beside its target and nothing would say so.
///
/// This pins the premise ``BarOcclusionTests`` rests on. When a correctly-aimed tap fails,
/// these tests are what let the next reader rule out the aim and go looking for the
/// occluder — the investigation that produced this file spent a round on the wrong one.
@MainActor final class FrameAgreementTests: XCTestCase {
    /// The frame the app published for itself, parsed from `FrameReporter`.
    private func renderedFrame(_ app: XCUIApplication) throws -> CGRect {
        let raw = try XCTUnwrap(
            app.uiTestingElement("bannerToggleFrame").value,
            "the app did not publish a frame"
        )
        let parts = raw.split(separator: ",").compactMap { Double($0) }
        try XCTSkipUnless(parts.count == 4, "unparseable frame: \(raw)")

        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    private func assertFramesAgree(untabbed: Bool) throws {
        let app = XCUIApplication()
        if untabbed {
            app.launchEnvironment["PROBE_SCENE"] = "untabbed"
        }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        let button = app.uiTestingElement("bannerToggle")
        XCTAssertTrue(button.waitForExistence())
        XCTAssertTrue(button.waitForStableFrame())

        let reported = button.xcuiElement.frame
        let rendered = try renderedFrame(app)

        // A point of tolerance: the two sides round differently, and a disagreement that
        // matters is tens of points — a whole bar's height — not a fraction of one.
        XCTAssertEqual(reported.midX, rendered.midX, accuracy: 1.0, "midX disagrees")
        XCTAssertEqual(reported.midY, rendered.midY, accuracy: 1.0, "midY disagrees")
    }

    /// The default root for the runtime — `ProbeTabs` on iOS 27 and above.
    func testFramesAgreeInTheDefaultRoot() throws {
        try assertFramesAgree(untabbed: false)
    }

    /// The same view with the root pinned to the untabbed tree. Paired with the above so a
    /// drift that appears under only one root cannot hide.
    func testFramesAgreeUntabbed() throws {
        try assertFramesAgree(untabbed: true)
    }
}
