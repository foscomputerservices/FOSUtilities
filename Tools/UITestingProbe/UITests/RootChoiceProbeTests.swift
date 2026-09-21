// RootChoiceProbeTests.swift
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

/// Holds the app's root fixed while the OS varies, so a behaviour that appears on a new
/// runtime can be told apart from the change of root that the runtime triggers.
///
/// `ProbeApp` picks its root by OS: iOS 27 and above get `ProbeTabs` (a `TabView`), older
/// runtimes get `ToolbarProbe` directly. Anything measured only on the newer OS is therefore
/// confounded — the OS changed AND the view tree changed. `PROBE_SCENE=untabbed` pins the
/// older tree on any runtime, which is the control this pair needs.
@MainActor final class RootChoiceProbeTests: XCTestCase {
    /// The conditional-branch tag is reachable when the root is the untabbed tree, on every
    /// runtime. Paired with `UITestingElementTests.testExistenceFollowsTheViewHierarchy`,
    /// which drives the same tag through whichever root the runtime selects.
    func testConditionalBranchTagIsReachableUntabbed() {
        let app = XCUIApplication()
        app.launchEnvironment["PROBE_SCENE"] = "untabbed"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        let banner = app.uiTestingElement("savedBanner")
        XCTAssertFalse(banner.exists)

        app.uiTestingElement("bannerToggle").tap()

        XCTAssertTrue(banner.waitForExistence())
    }

    /// The disappearance half of the same claim, under the pinned root.
    func testConditionalBranchTagLeavesTheHierarchyUntabbed() {
        let app = XCUIApplication()
        app.launchEnvironment["PROBE_SCENE"] = "untabbed"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        let banner = app.uiTestingElement("savedBanner")
        app.uiTestingElement("bannerToggle").tap()
        XCTAssertTrue(banner.waitForExistence())

        app.uiTestingElement("bannerToggle").tap()

        XCTAssertTrue(banner.waitForDisappearance())
    }
}
