// FreshnessGateTests.swift
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

import FOSFoundation
@testable import FOSMVVM
import Foundation
import Testing

// ── Honest gap (needs a hosted SwiftUI test) ──────────────────────────────────────────────────────
// The gate DECISION (older-drops / newer-swaps / equal-drops) is pinned headless below. The gate's
// one deliberate BYPASS is not reachable here: a navigation whose URL differs only by query/fragment
// takes the full-reload path rather than the in-place gated swap ("query/fragment change bypasses the
// gate" — spec §8 group 8). That routing is structural in private view methods — `loadAndBind` vs
// `refreshInPlace` (`ViewModelView.swift`) — which only run when SwiftUI drives the view, so a
// headless unit test cannot reach it. A hosted UI test (FOSTestingUI's `ViewModelDisplayTestCase` →
// `XCUIApplication`, which needs a host app target FOSUtilities itself does not ship — so this lives
// in a consumer app's UI-test target) must cover: a same-path/different-query navigation reloads
// (bypasses the gate) while a same-URL push swaps through it. The gate decision itself is pinned here.

@Suite("FreshnessGate")
struct FreshnessGateTests {
    // Freshness comes only from construction-order `ViewModelId()` (public path); never forged —
    // `Freshness.init` is internal. Two `.now` reads are distinct; the sleep removes any doubt.

    @Test("A newer arrival replaces the current ViewModel")
    func newerSwaps() async throws {
        let older = TestViewModel()
        try await Task.sleep(nanoseconds: 2000000)
        let newer = TestViewModel()

        #expect(FreshnessGate.shouldReplace(current: older, with: newer))
    }

    @Test("An older arrival is dropped")
    func olderDrops() async throws {
        let older = TestViewModel()
        try await Task.sleep(nanoseconds: 2000000)
        let newer = TestViewModel()

        #expect(!FreshnessGate.shouldReplace(current: newer, with: older))
    }

    @Test("A nil current always accepts the arrival")
    func nilCurrentAccepts() {
        let incoming = TestViewModel()

        #expect(FreshnessGate.shouldReplace(current: nil, with: incoming))
    }

    @Test("An equal-freshness self-nudge is dropped")
    func equalFreshnessDrops() {
        // The redundant nudge a client's own write races back to it: same vmId (same birth moment)
        // ⇒ not strictly fresher ⇒ drop.
        let current = TestViewModel()
        var echo = TestViewModel()
        echo.vmId = current.vmId

        #expect(!FreshnessGate.shouldReplace(current: current, with: echo))
    }
}
