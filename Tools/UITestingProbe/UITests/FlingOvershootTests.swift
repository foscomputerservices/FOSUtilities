// FlingOvershootTests.swift
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

private let probeBundleId = "com.foscomputerservices.uitestingprobe.UITestingProbe"

/// The overshoot pin. A field that keyboard avoidance leaves a few points below the
/// aimable band cannot be landed inside the band by a band-length stroke: the stroke moves
/// the content further than the band is tall, so the raising stroke flings past and the
/// lowering stroke returns, forever. Built red-first: on unpatched code the scroll budget
/// drains silently, the double-taps aim at a frame five strokes stale, and the aim lands in
/// the navigation bar — which dismisses the keyboard and turns one miss into a cascade.
@MainActor final class FlingOvershootTests: ViewModelDisplayTestCase<FlingCardViewModel>, @unchecked Sendable {
    override func setUp() async throws {
        try await super.setUp(
            bundle: Bundle(for: FlingOvershootTests.self),
            appBundleIdentifier: probeBundleId
        )
        continueAfterFailure = true
    }

    /// The budget, not the verdict, is what the overshoot always costs. Whether the
    /// cascade ends in a wrong value or in a lucky recovery is parity — how the field
    /// happens to sit when the last stroke lands — which is exactly why the same call
    /// passed on one destination and failed on another. What never varies is that a
    /// band-length stroke cannot land this field, so the full stroke budget drains every
    /// time: measured at 67-73s here against 13s for the same call on a field the band
    /// already holds. A stroke sized to the deficit lands it in one.
    private static let budget: TimeInterval = 30

    func testSetTextLandsAFieldTheBandOvershoots() throws {
        let app = try presentView()

        let field = app.uiTestingElement("flingField")
        XCTAssertTrue(field.waitForExistence())

        reportGeometry(app, label: "before focus")

        let started = Date()
        field.setText("100")
        let elapsed = Date().timeIntervalSince(started)

        reportGeometry(app, label: "after setText")

        XCTAssertEqual(field.value, "100")
        XCTAssertLessThan(
            elapsed,
            Self.budget,
            """
            setText took \(String(format: "%.1f", elapsed))s: the scroll budget drained \
            before the field was landed, which means the strokes are not sized to the \
            deficit they are closing.
            """
        )
    }

    /// Tuning evidence, printed rather than asserted: the deficit and the band height are
    /// what decide whether this destination is in the failing regime at all, and both are
    /// device geometry. A destination whose band comfortably holds the field is a pass that
    /// proves nothing, and the log is what says which one this run was.
    private func reportGeometry(_ app: XCUIApplication, label: String) {
        let keyboard = app.keyboards.firstMatch
        let navBar = app.navigationBars.firstMatch
        let field = app.textFields.firstMatch

        print("[fling] \(label): app=\(app.frame)")
        print("[fling] \(label): navBar=\(navBar.exists ? "\(navBar.frame)" : "none")")
        print("[fling] \(label): keyboard=\(keyboard.exists ? "\(keyboard.frame)" : "none")")
        print("[fling] \(label): field=\(field.exists ? "\(field.frame)" : "none")")
    }
}
