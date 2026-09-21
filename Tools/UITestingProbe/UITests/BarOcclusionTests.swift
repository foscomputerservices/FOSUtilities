// BarOcclusionTests.swift
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

/// A target under a system bar is still tappable.
///
/// Content scrolls *under* a navigation bar and a tab bar, and every signal XCUITest offers
/// says the target is fine: it exists, its frame is stable, and that frame is measured
/// correctly — `FrameAgreementTests` pins the last part. Only `isHittable` dissents, and
/// `tap()`'s coordinate fallback used to ignore it and dispatch into the bar. The gesture
/// succeeded, the action never ran, and the failure surfaced later somewhere unrelated.
@MainActor final class BarOcclusionTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    /// The premise: this fixture really does put the target under the tab bar. Without this,
    /// the tap test below could pass for the wrong reason on a geometry where nothing covers
    /// anything — a silent loss of the only case the guard exists for.
    func testTheTargetStartsUnderTheTabBar() throws {
        let bar = app.tabBars.firstMatch
        try XCTSkipUnless(bar.exists, "no tab bar in this runtime's root")

        let target = app.uiTestingElement("bannerToggle")
        XCTAssertTrue(target.waitForExistence())
        XCTAssertTrue(target.waitForStableFrame())

        let frame = target.xcuiElement.frame
        XCTAssertTrue(
            bar.frame.contains(CGPoint(x: frame.midX, y: frame.midY)),
            "the tab bar no longer covers the target — this fixture has stopped testing occlusion"
        )
        XCTAssertFalse(
            target.xcuiElement.isHittable,
            "a covered target should report not-hittable; if it does not, the premise changed"
        )
    }

    /// The claim: `tap()` reaches it anyway, and the control actually fires.
    ///
    /// The assertion is the *effect* — the banner appearing — not the gesture returning. A
    /// tap dispatched into a bar returns perfectly happily.
    func testTapReachesATargetUnderTheTabBar() throws {
        try XCTSkipUnless(app.tabBars.firstMatch.exists, "no tab bar in this runtime's root")

        let banner = app.uiTestingElement("savedBanner")
        XCTAssertFalse(banner.exists)

        app.uiTestingElement("bannerToggle").tap()

        XCTAssertTrue(banner.waitForExistence(), "the tap never reached the control")
    }

    /// Clearing the bottom bar must not strand the target under the top one.
    ///
    /// The first cut of this guard clipped the band at the tab bar alone. It scrolled the
    /// covered target straight up into the navigation bar, where it was equally unreachable
    /// and the band called it aimable — the symptom was unchanged and the cause had moved.
    func testTapDoesNotStrandTheTargetUnderTheNavigationBar() throws {
        try XCTSkipUnless(app.tabBars.firstMatch.exists, "no tab bar in this runtime's root")
        let navigationBar = app.navigationBars.firstMatch
        try XCTSkipUnless(navigationBar.exists, "no navigation bar in this runtime's root")

        let target = app.uiTestingElement("bannerToggle")
        XCTAssertTrue(target.waitForExistence())

        app.uiTestingElement("bannerToggle").tap()
        XCTAssertTrue(app.uiTestingElement("savedBanner").waitForExistence())

        // Where the guard left it: cleared of the bottom bar, and not pushed under the top.
        let frame = target.xcuiElement.frame
        XCTAssertFalse(
            navigationBar.frame.contains(CGPoint(x: frame.midX, y: frame.midY)),
            "the target was scrolled out from under one bar and under the other"
        )
    }
}
