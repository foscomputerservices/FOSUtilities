// LandscapeBandTests.swift
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

/// The aim/scroll path against a band far shorter than one scroll fling.
///
/// Both defects this library has taken from a consumer's device matrix were the same
/// geometry: an aimable band — navigation bar's bottom to the keyboard's top, less the 44pt
/// accessory clearance — shorter than the ~345pt a single fling moves the content. A target
/// a few points outside such a band can never be landed inside it by a stroke, and the
/// symptom surfaces far away: a drained scroll budget, a stale aim, a double-tap into the
/// navigation bar.
///
/// **Rotation is how that geometry is reached on hardware CI actually has.** Measured
/// 2026-09-22, bar bottom to keyboard top less clearance:
///
/// - iPhone 17 Pro / iOS 27.0 landscape — **109pt**
/// - iPhone 17 Pro Max / iOS 26.5 landscape — **154pt**
/// - iPhone Duo cover screen, portrait — 307pt (the screen that produced the field report)
///
/// So a rotated stock phone sits two to three times deeper in the failing regime than the
/// device we cannot get onto a hosted runner, and needs no new runtime, image or device.
///
/// > This is deliberately the ONLY suite that rotates, and it restores portrait from a
/// > teardown block whether or not the test passed. Orientation is process-wide and sticky:
/// > a suite that leaves the device rotated hands every later suite a geometry its fixtures
/// > were not written for, and the resulting failures name the wrong cause.
///
/// What this does NOT cover: the iOS 27.1 toolbar relocation. That is tied to the 27.1 API
/// rather than to height — rotating on 26.5 and 27.0 leaves every toolbar item and the title
/// in place — and no hosted image carries 27.1. See `docs/deferrals.md`.
@MainActor final class LandscapeBandTests: ViewModelDisplayTestCase<FlingCardViewModel>, @unchecked Sendable {
    override func setUp() async throws {
        try await super.setUp(
            bundle: Bundle(for: LandscapeBandTests.self),
            appBundleIdentifier: probeBundleId
        )
        continueAfterFailure = true

        // Registered BEFORE the rotation, so the restore is in place even if setting the
        // orientation is itself what fails. A teardown block rather than a tearDown()
        // override because ViewModelDisplayTestCase.tearDown() is `public`, not `open` —
        // it cannot be overridden from outside FOSTestingUI.
        addTeardownBlock { @MainActor in
            XCUIDevice.shared.orientation = .portrait
        }

        XCUIDevice.shared.orientation = .landscapeLeft
    }

    /// Not the portrait budget. In portrait `FlingOvershootTests` asserts under 30s,
    /// because there the fix LANDS the field: its frame overlaps the band, so the aim
    /// reaches it without a stroke. Rotated, the same fixture's field sits entirely OUTSIDE
    /// the band — measured 6.9pt below it on iOS 26.5 and 10pt below on 27.0 — the
    /// intersection is empty, and six strokes cannot close a deficit smaller than the
    /// distance one fling travels. The budget drains by design, and asserting 30s here would
    /// red a CI leg for a documented limitation.
    ///
    /// This ceiling is a "not forever" guard instead: it catches a regression that retries
    /// past the budget without catching the drain itself. Measured drains — 33.3s on 26.5
    /// landscape, under 30s on 27.0 landscape, 67-73s in the portrait failing regime.
    private static let ceiling: TimeInterval = 90

    /// The value still arrives when the band cannot hold the field at all.
    ///
    /// This is the contract a consumer on a short screen actually leans on. The library does
    /// not promise to land every target inside the band — a stroke moves the content by its
    /// release velocity, not its length, so a target a few points outside a short band is
    /// unreachable by scrolling and `scrollIntoBand` reports it rather than chasing it. What
    /// it does promise is that the entry still commits and the field still reads what was
    /// asked for. That promise is what breaks silently, and this is where it is checked at
    /// the shortest band available on hosted hardware.
    ///
    /// Expect a `WARNING - FOSTestingUI` activity in the log naming the unreached target.
    /// That warning is the correct behaviour here, not a failure.
    func testTheValueArrivesWhenTheBandCannotHoldTheField() throws {
        let app = try presentView()

        let field = app.uiTestingElement("flingField")
        XCTAssertTrue(field.waitForExistence())

        reportGeometry(app, label: "landscape, before focus")

        let started = Date()
        field.setText("100")
        let elapsed = Date().timeIntervalSince(started)

        reportGeometry(app, label: "landscape, after setText")
        print("[landscape] setText elapsed: \(String(format: "%.1f", elapsed))s of \(Self.ceiling)s")

        XCTAssertEqual(
            field.value,
            "100",
            """
            The entry did not commit on a band too short to hold the field. Landing the             target is not promised here; the value arriving is.
            """
        )
        XCTAssertLessThan(
            elapsed,
            Self.ceiling,
            """
            setText took \(String(format: "%.1f", elapsed))s in landscape. The scroll budget             draining is expected on this geometry, but not this long — check that             scrollIntoBand still stops when a stroke moves the target nowhere.
            """
        )
    }

    /// The band's own geometry, asserted rather than assumed.
    ///
    /// Every claim this suite makes rests on the band being shorter rotated than the fling
    /// that crosses it. A destination whose rotated band is roomy is a pass that proves
    /// nothing — and it would pass silently — so the measurement is the test. The threshold
    /// is deliberately loose: it asks whether this run was in the regime at all, not whether
    /// it matched a number from one device.
    func testTheRotatedBandIsShorterThanASingleFling() throws {
        let app = try presentView()

        let field = app.uiTestingElement("flingField")
        XCTAssertTrue(field.waitForExistence())
        field.tap()

        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 10),
            "The software keyboard never appeared — on a simulator, check that the hardware keyboard is disconnected (I/O > Keyboard > Connect Hardware Keyboard off)"
        )

        // Mirrors FOSTestingUI's aimableBand() arithmetic: the navigation bar clips the top,
        // the keyboard clips the bottom, and the 44pt accessory strip is not in the
        // keyboard's reported frame.
        let navBar = app.navigationBars.firstMatch
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(navBar.exists, "no navigation bar, so there is no band to measure")

        let bandHeight = keyboard.frame.minY - 44 - navBar.frame.maxY
        reportGeometry(app, label: "landscape, keyboard up")
        print("[landscape] band height: \(bandHeight)pt")

        XCTAssertLessThan(
            bandHeight,
            300,
            """
            The rotated band is \(bandHeight)pt, which is no longer short enough for this \
            suite to be exercising the overshoot regime it exists for. Either the \
            destination changed or the fixture did; re-measure before trusting a pass here.
            """
        )
    }

    /// Tuning evidence, printed rather than asserted — the same reporting
    /// `FlingOvershootTests` carries, because which regime a run was in is device geometry
    /// and the log is what says so afterwards.
    private func reportGeometry(_ app: XCUIApplication, label: String) {
        let keyboard = app.keyboards.firstMatch
        let navBar = app.navigationBars.firstMatch
        let field = app.textFields.firstMatch

        print("[landscape] \(label): app=\(app.frame)")
        print("[landscape] \(label): navBar=\(navBar.exists ? "\(navBar.frame)" : "none")")
        print("[landscape] \(label): keyboard=\(keyboard.exists ? "\(keyboard.frame)" : "none")")
        print("[landscape] \(label): field=\(field.exists ? "\(field.frame)" : "none")")
    }
}
