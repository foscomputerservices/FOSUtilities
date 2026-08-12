// View+Testing.swift
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

#if canImport(SwiftUI)
import SwiftUI

public extension View {
    /// Tags the view so that an XCUITest can find it
    ///
    /// Tag the view with ``uiTestingIdentifier(_:isEnabled:)``, then find it in the test with
    /// `XCUIApplication.uiTestingElement(_:)` (**FOSTestingUI**).  The test names the
    /// identifier and nothing else — no XCUITest element type, no displayed text.
    ///
    /// ## Example
    ///
    /// ### View
    ///
    /// ```swift
    /// Button(action: save) { Text(viewModel.saveTitle) }
    ///   .uiTestingIdentifier("saveButton")
    /// ```
    ///
    /// ### XCUITest
    ///
    /// ```swift
    /// func testSaves() async throws {
    ///     let app = try presentView()
    ///
    ///     app.uiTestingElement("saveButton").tap()
    ///
    ///     XCTAssertTrue(app.uiTestingElement("savedBanner").waitForExistence())
    /// }
    /// ```
    ///
    /// ## Where to Apply It
    ///
    /// Anywhere a view accepts a modifier.  The tag holds on controls that bridge to a native
    /// element — `Picker`, `DatePicker`, `TextField`, `ColorPicker`, `Toggle` — at any depth of
    /// nesting, and at any position in the modifier chain.  Tagging a container does not
    /// disturb tags applied inside it, so a composed view and each of its sub-views can each
    /// carry their own tag and each be verified by its own test suite:
    ///
    /// ```swift
    /// struct ProgramPanel: View {
    ///     var body: some View {
    ///         HStack {
    ///             ProgramPicker()  // carries its own tags
    ///         }
    ///         .uiTestingIdentifier("programPanel")
    ///     }
    /// }
    /// ```
    ///
    /// The tagged view is found while it is part of the view hierarchy, whether or not it is
    /// currently on screen; `UITestingElement.isVisible` reports the latter.
    ///
    /// ## Release Builds
    ///
    /// The tag is applied in `DEBUG` builds only and compiles away to nothing otherwise, so it
    /// never reaches the accessibility tree that ships to VoiceOver users.
    ///
    /// - Parameters:
    ///   - string: The identifier used to find the view in an XCUITest.
    ///   - isEnabled: If `true` the view is tagged; otherwise the view is left untagged.
    func uiTestingIdentifier(_ string: String, isEnabled: Bool = true) -> some View {
        #if DEBUG
        // The tag is carried by an overlay, not by the view itself, and deliberately so.
        // An accessibility identifier applied to a view propagates down and overwrites the
        // identifiers of its descendants, so a tagged container erases the tags of everything
        // composed inside it. Sealing the subtree with .accessibilityElement() stops the
        // propagation but replaces the native element of a bridged control (Picker, DatePicker,
        // TextField, ColorPicker), which removes it from the accessibility tree entirely.
        // An overlay is a sibling of the content rather than an ancestor of it, so neither
        // happens. allowsHitTesting(false) keeps taps passing through to the real control.
        overlay {
            if isEnabled {
                Color.clear
                    .allowsHitTesting(false)
                    .accessibilityElement()
                    .accessibilityIdentifier(string)
            }
        }
        #else
        self
        #endif
    }
}
#endif
