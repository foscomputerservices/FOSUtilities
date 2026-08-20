// OcclusionScrollTests.swift
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

/// The occlusion pin: a settled frame can still be an occluded frame. The card combines
/// everything the original scrollable pin lacked — its own internal `ScrollView`, sections
/// populated by a tapped async action, an action row below the fields, and a transporter
/// behind the card's opaque background — registered `scrollable: true`. Built red-first:
/// on unpatched code these tests reproduce the 0.12.5 field failures (aims dispatched into
/// the keyboard; the transporter pruned from the AX tree).
@MainActor final class OcclusionScrollTests: ViewModelViewTestCase<OcclusionCardViewModel, OcclusionCardOps>, @unchecked Sendable {
    override func setUp() async throws {
        try await super.setUp(
            bundle: Bundle(for: OcclusionScrollTests.self),
            appBundleIdentifier: probeBundleId
        )
        continueAfterFailure = true
    }

    /// Mechanism 3: behind the card's opaque background, under the wrapper's ScrollView,
    /// the transporter was pruned from the accessibility tree and the operations were
    /// unreadable. Fronted at 1×1, they read and decode.
    func testTransporterSurvivesTheWrapper() throws {
        let app = try presentView()

        app.uiTestingElement("occlusionLoadButton").tap()
        XCTAssertTrue(app.uiTestingElement("occlusionAlphaField").waitForExistence())

        let ops: OcclusionCardOps = try viewModelOperations()
        XCTAssertEqual(ops.loadCount, 1)
    }

    /// Mechanism 1 and its variants: after focus, the field's frame is honest, stable —
    /// and occluded (behind the keyboard, or beyond the viewport bottom, by device
    /// height). setText must clear the target before aiming; the read-back is the
    /// arbiter that no aim landed on keys.
    func testSetTextIntoFieldsTheKeyboardOccludes() throws {
        let app = try presentView()

        app.uiTestingElement("occlusionLoadButton").tap()

        let alpha = app.uiTestingElement("occlusionAlphaField")
        XCTAssertTrue(alpha.waitForExistence())
        alpha.setText("42")
        XCTAssertEqual(alpha.value, "42")

        // The keyboard is up from the first entry; the deeper field starts occluded.
        let gamma = app.uiTestingElement("occlusionGammaField")
        gamma.setText("77")
        XCTAssertEqual(gamma.value, "77")
    }

    /// Mechanism 2: the action row sits below the fields, under the still-raised
    /// keyboard, where hittability and app-frame containment are both blind. tap() must
    /// scroll it into the aimable band; the recorded operation proves the action fired —
    /// the 0.12.5 failure was this tap dispatching into the keys, silently.
    func testTapReachesTheActionRowBeyondTheKeyboard() throws {
        let app = try presentView()

        app.uiTestingElement("occlusionLoadButton").tap()

        let alpha = app.uiTestingElement("occlusionAlphaField")
        XCTAssertTrue(alpha.waitForExistence())
        alpha.setText("42")

        app.uiTestingElement("occlusionSetButton").tap()

        let deadline = Date(timeIntervalSinceNow: 10)
        var ops = OcclusionCardOps()
        while Date() < deadline, ops.setCount == 0 {
            ops = (try? viewModelOperations()) ?? ops
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
        }
        XCTAssertEqual(ops.setCount, 1)
        XCTAssertEqual(ops.lastAmount, "42")
    }
}
