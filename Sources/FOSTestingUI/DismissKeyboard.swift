// DismissKeyboard.swift
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

#if os(iOS) || os(tvOS) || os(watchOS) || os(macOS) || os(visionOS)
import XCTest

public extension XCUIApplication {
    /// Dismisses the software keyboard, if one is up
    ///
    /// ```swift
    /// app.uiTestingElement("quantityField").type("42")
    /// app.dismissKeyboard()
    /// app.uiTestingElement("saveButton").tap()
    /// ```
    ///
    /// A raised keyboard covers the lower part of the screen, and a tap aimed at a covered
    /// control lands on the keyboard instead. XCUITest offers no way to put the keyboard away,
    /// and a `.numberPad` keyboard has no Return key to tap — nor does tapping a neutral view
    /// dismiss it, however much that idiom looks like it should. This call is the way down: it
    /// taps the invisible control that `testHost()` (**FOSMVVM**) plants for exactly this
    /// purpose, so it works for every keyboard type and needs nothing from the application
    /// beyond the `.testHost()` it already has.
    ///
    /// With no keyboard up the call is a no-op, so call sites stay unconditional. If the
    /// keyboard cannot be dismissed — the application is not wrapped in `.testHost()`, or the
    /// keyboard stays up after the tap — the test fails, naming the cause; a helper that looks
    /// like it worked but didn't is the trap this API replaces.
    func dismissKeyboard(file: StaticString = #filePath, line: UInt = #line) {
        let keyboard = keyboards.firstMatch
        guard keyboard.exists else {
            return
        }

        // Mirrors the literal in FOSMVVM's TestHost.swift; the two modules share no target, so
        // the name is tethered by comment, as the __FOS_ launch environment keys are.
        let control = descendants(matching: .any)
            .matching(identifier: "__FOS_DismissKeyboard").firstMatch
        guard control.waitForExistence(timeout: 10) else {
            XCTFail(
                """
                The keyboard is up, but the dismissal control ("__FOS_DismissKeyboard") is not \
                in the view hierarchy. testHost() (FOSMVVM) plants it; check that the \
                application's root view is wrapped in .testHost().
                """,
                file: file,
                line: line
            )
            return
        }

        // The control renders nothing, so XCUITest may report it as not hittable; it is hosted
        // in its own fixed-frame window above the application, so a coordinate tap is exact.
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let departed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: keyboard
        )
        if XCTWaiter().wait(for: [departed], timeout: 10) != .completed {
            XCTFail(
                """
                The keyboard did not dismiss after tapping the dismissal control \
                ("__FOS_DismissKeyboard"). The control is hosted in its own window above the \
                application, so the tap reached it; check for a first responder that refuses \
                to resign, such as a custom input view that re-takes focus.
                """,
                file: file,
                line: line
            )
        }
    }
}
#endif
