// FormFocusProbeTests.swift
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

import FOSTestingUI
import XCTest

/// Drives FormFieldView's focus plumbing: focus the first field, edit it, then move focus
/// to the second — the blur runs validation-on-blur through the local `@FocusState`. The
/// assertions here are only the sanity floor; the FocusState runtime-warning verdict comes
/// from the simulator's runtime-issue log, which the invoking harness captures around this
/// test (SwiftUI logs the warning in the app process, outside XCTest's sight).
@MainActor final class FormFocusProbeTests: XCTestCase {
    func testFocusTravelsBetweenFields() {
        let app = XCUIApplication()
        app.launchEnvironment["PROBE_SCENE"] = "formFocus"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        let first = app.uiTestingElement("focusFirstField")
        first.tap()
        app.typeText("a")

        app.uiTestingElement("focusSecondField").tap()
        app.typeText("b")

        // The un-waited reads prove both focus hand-offs actually happened.
        XCTAssertEqual(first.value, "a")
        XCTAssertEqual(app.uiTestingElement("focusSecondField").value, "b")
    }
}
