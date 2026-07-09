// InvalidationSeamTests.swift
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

// First-ever tests for the pre-existing client invalidation seams (spec test group 10): the
// `viewModelInvalidated` teardown binding behind `invalidateBinding(_:)` (`View.swift:84`) and the
// `viewModelRefreshed` in-place-swap binding behind `refreshedViewModel(_:)` (`View.swift:90`, now
// gated through `swapThroughFreshnessGate`, Task 7). Both seams live as SwiftUI `@Entry` environment
// values consumed inside `VMServerResolverView`'s `body` (`ViewModelView.swift:403-445`).
//
// ── What these tests reach ──────────────────────────────────────────────────────────────────────
// The seams' EXTRACTABLE contract is their environment layer: the `@Entry` defaults (what a screen
// sees when the modifier is absent) and that the entry carries a caller-supplied binding intact.
// Those defaults are load-bearing — the `false` default is precisely why a screen with no
// `.invalidateBinding` is never torn down, and the `""` default is why no phantom refresh fires.
// Reached headless below via a bare `EnvironmentValues()`.
//
// ── Honest gap (needs a hosted SwiftUI test) ────────────────────────────────────────────────────
// The seams' REACTIONS are `.onChange` handlers inside `VMServerResolverView.body`; they only run
// when SwiftUI drives the view, so they are out of reach of a headless unit test. Not faked here.
// A hosted UI test (FOSTestingUI's `ViewModelDisplayTestCase` → `XCUIApplication`, which needs a
// host app target FOSUtilities itself does not ship — so this lives in a consumer app's UI-test
// target) must cover:
//   1. `invalidateBinding($flag)` → set `flag = true` → the resolver nils its ViewModel, shows the
//      `ProgressView`, and re-fetches (`ViewModelView.swift:429-434` + the `.task` reload).
//   2. `refreshedViewModel($vm)` → push a strictly-fresher VM → the resolver decodes it and swaps
//      in place THROUGH the freshness gate (`ViewModelView.swift:435-445`); push a stale-freshness
//      VM → the gate drops it, the visible VM is unchanged.
//   3. The `refreshedViewModel(_:)` modifier's own `Binding<String>` get/set closures
//      (`View.swift:91-100`): the get encodes the bound VM to JSON, the set decodes and reassigns —
//      these fire only under SwiftUI's binding machinery.
// The gate DECISION itself (older-drops / newer-swaps / equal-drops) is already pinned headless in
// `FreshnessGateTests`; the gap above is the WIRING from these bindings into that gate.

#if canImport(SwiftUI)
@testable import FOSMVVM
import Foundation
import SwiftUI
import Testing

@MainActor
@Suite("Invalidation seams (spec test group 10)")
struct InvalidationSeamTests {
    // MARK: viewModelInvalidated (invalidateBinding teardown seam)

    @Test("Absent `.invalidateBinding`, the teardown flag defaults to false — no screen is torn down")
    func invalidatedDefaultsFalse() {
        let env = EnvironmentValues()

        #expect(env.viewModelInvalidated.wrappedValue == false)
    }

    @Test("The default teardown binding ignores writes — its setter is a no-op")
    func invalidatedDefaultSetterIsNoOp() {
        let env = EnvironmentValues()

        // The default entry's setter discards writes (View.swift:105-108); a stray write must not
        // latch a phantom teardown into a screen that never applied `.invalidateBinding`.
        env.viewModelInvalidated.wrappedValue = true

        #expect(env.viewModelInvalidated.wrappedValue == false)
    }

    @Test("`invalidateBinding` plumbing: the entry carries a caller-supplied binding intact")
    func invalidatedEntryCarriesCallerBinding() {
        // Mirrors what `invalidateBinding($flag)` writes into the environment: the entry must return
        // exactly the caller's binding, both value and writes, so the resolver's `.onChange` sees the
        // app's teardown request.
        final class Box { var flag = false }
        let box = Box()
        var env = EnvironmentValues()
        env.viewModelInvalidated = Binding(get: { box.flag }, set: { box.flag = $0 })

        #expect(env.viewModelInvalidated.wrappedValue == false)

        env.viewModelInvalidated.wrappedValue = true
        #expect(box.flag == true)
        #expect(env.viewModelInvalidated.wrappedValue == true)
    }

    // MARK: viewModelRefreshed (refreshedViewModel in-place-swap seam)

    @Test("Absent `.refreshedViewModel`, the refresh binding defaults to empty — no phantom swap")
    func refreshedDefaultsEmpty() {
        let env = EnvironmentValues()

        #expect(env.viewModelRefreshed.wrappedValue == "")
    }

    @Test("The default refresh binding ignores writes — its setter is a no-op")
    func refreshedDefaultSetterIsNoOp() {
        let env = EnvironmentValues()

        // The default entry's setter discards writes (View.swift:110-113); the resolver's
        // `.onChange` must never observe a refresh a caller never pushed.
        env.viewModelRefreshed.wrappedValue = "phantom"

        #expect(env.viewModelRefreshed.wrappedValue == "")
    }

    @Test("`refreshedViewModel` plumbing: the entry carries a pushed payload intact")
    func refreshedEntryCarriesPushedPayload() {
        // The seam transports a VM as JSON — the entry is `Binding<String>`: `refreshedViewModel`
        // encodes on the way in, the resolver's `.onChange` decodes on the way out. The reachable
        // contract here is transport: the entry must return exactly the payload a caller pushed. The
        // decode-and-gate that consumes it runs only under SwiftUI (the hosted gap above).
        final class Box { var payload = "" }
        let box = Box()
        var env = EnvironmentValues()
        env.viewModelRefreshed = Binding(get: { box.payload }, set: { box.payload = $0 })

        let pushed = #"{"vmId":"sentinel"}"#
        env.viewModelRefreshed.wrappedValue = pushed
        #expect(box.payload == pushed)
        #expect(env.viewModelRefreshed.wrappedValue == pushed)
    }
}
#endif
