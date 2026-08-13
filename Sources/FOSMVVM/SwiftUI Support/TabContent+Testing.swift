// TabContent+Testing.swift
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

// swiftformat:disable docComments
// The wildcard in an @available list claims every UNLISTED platform at the
// package floor — TabContent itself is tvOS 18 / watchOS 11 / visionOS 2, so
// omitting those platforms is a floor-level lie that only an honest
// device-platform compile exposes.
//
// iOS alone is raised above TabContent's own floor. Apple's
// TabContent.accessibilityIdentifier is declared from iOS 18 but reaches the
// tab bar item only from iOS 27; macOS and tvOS tag the tab at their declared
// floors. Measured one platform at a time — the matrix is in
// Tools/UITestingProbe/README.md. Declaring what Apple declares would compile
// on the broken runtime and silently do nothing, which is the failure mode the
// customer reported, so availability is the compile-time gate for iOS only.
// swiftformat:enable docComments
@available(iOS 27.0, macOS 15.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
public extension TabContent {
    /// Tags the tab so that an XCUITest can find it
    ///
    /// Tag the tab with ``uiTestingIdentifier(_:isEnabled:)``, then find it in the test with
    /// `XCUIApplication.uiTestingElement(_:)` (**FOSTestingUI**), exactly as for a view.
    ///
    /// ## Example
    ///
    /// ### View
    ///
    /// ```swift
    /// Tab("Settings", systemImage: "gear") { SettingsView() }
    ///   .uiTestingIdentifier("settingsTab")
    /// ```
    ///
    /// ### XCUITest
    ///
    /// ```swift
    /// func testShowsSettings() async throws {
    ///     let app = try presentView()
    ///
    ///     app.uiTestingElement("settingsTab").tap()
    ///
    ///     XCTAssertTrue(app.uiTestingElement("settingsTitle").waitForExistence())
    /// }
    /// ```
    ///
    /// The tag holds for either initializer, and for a tab whose label is built in a closure.
    ///
    /// A tab bar reaches the accessibility tree a moment after the application launches, later
    /// than the views on screen.  `tap()` and `type(_:)` wait, so they need nothing said; a test
    /// that opens by *asking* about a tab —  ``UITestingElement/isVisible`` or
    /// ``UITestingElement/exists`` — asks before the tab bar is there, and wants
    /// ``UITestingElement/waitForExistence(timeout:)`` first.
    ///
    /// ## On iOS, Tagging a Tab Requires iOS 27
    ///
    /// This method is unavailable below iOS 27, so an iOS project whose deployment target is
    /// lower will not compile a call to it.  That is deliberate.  Apple's underlying
    /// `TabContent.accessibilityIdentifier` is declared from iOS 18 but puts no identifier on
    /// the tab bar item until iOS 27, on any Xcode — so below that floor the call would compile
    /// and do nothing, and the test would fail saying no view carries the tag.
    ///
    /// The other platforms tag the tab at their own floors and need nothing said: macOS and
    /// tvOS were measured directly, and a tagged tab is found there exactly as a tagged view is.
    ///
    /// ### Working Around It, and Deleting the Workaround
    ///
    /// **What follows is a workaround for a defect, not a pattern.**  It finds the tab by the
    /// text it displays — the very thing ``uiTestingIdentifier(_:isEnabled:)`` exists to stop a
    /// test doing — and it earns its place only for as long as Apple's identifier is inert.
    ///
    /// Resolve the title from the same ViewModel property the tab's label is built from, never a
    /// literal, so the lookup holds in every locale; and scope it to `tabBars`, or it matches any
    /// button on screen displaying that title:
    ///
    /// ```swift
    /// app.tabBars.buttons[try viewModel.settingsTabTitle.localizedString].firstMatch.tap()
    /// ```
    ///
    /// A project that ships below iOS 27 but *runs tests* on iOS 27 can have the real thing
    /// today, with the workaround quarantined where it deletes in one edit — in the test:
    ///
    /// ```swift
    /// if #available(iOS 27, *) {
    ///     app.uiTestingElement("settingsTab").tap()
    /// } else {
    ///     app.tabBars.buttons[try viewModel.settingsTabTitle.localizedString].firstMatch.tap()
    /// }
    /// ```
    ///
    /// and the matching `#available` branch around the tagged `Tab` in the view.  That branch
    /// costs a duplicated `Tab` declaration, because the tag chains onto the whole value — weigh
    /// that against having the tag path exercised on every iOS 27 machine you own rather than
    /// on the day you raise the floor.
    ///
    /// **Delete the `else` branch when the deployment target reaches iOS 27.**  That is the
    /// trigger; nothing else about the workaround expires on its own.
    ///
    /// Tag the tab anyway where the floor allows: everything the tab *contains* is found by its
    /// own tag on every platform, and only the tab bar item itself needs any of this.
    ///
    /// ## Release Builds
    ///
    /// The tag is applied in `DEBUG` builds only, as it is for a view.
    ///
    /// - Parameters:
    ///   - string: The identifier used to find the tab in an XCUITest.
    ///   - isEnabled: If `true` the tab is tagged; otherwise the tab is left untagged.
    func uiTestingIdentifier(_ string: String, isEnabled: Bool = true) -> some TabContent<Self.TabValue> {
        #if DEBUG
        accessibilityIdentifier(string, isEnabled: isEnabled)
        #else
        self
        #endif
    }
}
#endif
