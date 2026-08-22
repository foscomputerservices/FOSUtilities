// RowResolutionMacTests.swift
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

/// The aimed-coordinate dispatch on the platform where it silently missed.
///
/// Element frames are SCREEN-relative on macOS, where the window origin is nonzero. The
/// aimed dispatch used to anchor at the app origin and offset by raw frame coordinates —
/// applying that origin twice — so the tap dispatched without failure and landed
/// off-target: the control's action never fired (measured 2026-08-21 on a generated
/// FOSMVVM client-server app; a raw element click on the same control in the same run was
/// green). `appCoordinate(at:)` subtracts the origin; this suite holds the claim on macOS,
/// where the iOS suite's keyboard-arrival proofs cannot run.
@MainActor final class RowResolutionMacTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchEnvironment["PROBE_SCENE"] = "rowResolution"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    /// A caption + button composite whose tag midpoint sits in the caption forces the aimed
    /// path; the fired count is the proof the tap landed.
    func testAimedTapFiresTheActionAcrossTheComposite() {
        app.uiTestingElement("actionRow").tap()

        XCTAssertEqual(app.uiTestingElement("actionFireCount").label, "fired 1")
    }
}
