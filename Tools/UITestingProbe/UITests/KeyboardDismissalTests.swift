// KeyboardDismissalTests.swift
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

@MainActor final class KeyboardDismissalTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    /// The number pad offers no Return key, so dismissKeyboard() is the only way down — and
    /// after it, a tap reaches a control instead of the keyboard.
    func testDismissesTheNumberPad() {
        app.uiTestingElement("amountField").type("42")
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 10),
            "The software keyboard never appeared — on a simulator, check that the hardware keyboard is disconnected (I/O > Keyboard > Connect Hardware Keyboard off)"
        )

        app.dismissKeyboard()

        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.uiTestingElement("tapButton").tap()
        XCTAssertEqual(app.uiTestingElement("tapCounter").label, "taps-1")
    }

    /// With no keyboard up, the call is a no-op, so call sites stay unconditional.
    func testNoKeyboardIsANoOp() {
        XCTAssertFalse(app.keyboards.firstMatch.exists)

        app.dismissKeyboard()
    }
}

/// The KeyboardShiftProbe scene: keyboard avoidance shifts the whole content up when the
/// focused field would be covered, and the dismissal control must stay on screen through
/// that shift — 0.12.2's overlay rode the shift off-screen (measured at y = -48) and the
/// coordinate tap fired into nothing.
@MainActor final class KeyboardShiftDismissalTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["PROBE_SCENE"] = "keyboardShift"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    func testDismissesWhileAvoidanceShiftsTheContent() {
        app.uiTestingElement("shiftAmountField").type("42")
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 10),
            "The software keyboard never appeared — on a simulator, check that the hardware keyboard is disconnected (I/O > Keyboard > Connect Hardware Keyboard off)"
        )

        // The regression 0.12.2 shipped with: the control displaced out of the app frame
        // while the keyboard is up, where a tap cannot reach it.
        let control = app.uiTestingElement("__FOS_DismissKeyboard")
        XCTAssertTrue(control.exists)
        XCTAssertTrue(
            app.frame.contains(control.xcuiElement.frame),
            "dismissal control is outside the app frame: \(control.xcuiElement.frame)"
        )

        app.dismissKeyboard()

        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.uiTestingElement("shiftTapButton").tap()
        XCTAssertEqual(app.uiTestingElement("shiftTapCounter").label, "shift-taps-1")
    }
}
