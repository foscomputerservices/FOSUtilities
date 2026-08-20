// AsyncButtonActivityTests.swift
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
@testable import FOSMVVM
import Foundation
import SwiftUI
import Testing

/// Each ratified tap semantic gets a test, driven through AsyncButtonEngine.handleTap —
/// the seam every async Button init forwards to.
@MainActor
struct AsyncButtonActivityTests {
    // MARK: Public surface

    @Test func freshActivity_isIdle() {
        let activity = AsyncButtonActivity()

        #expect(activity.phase == .idle)
        #expect(!activity.isRunning)
    }

    @Test func cancel_onIdle_isNoOp() {
        var activity = AsyncButtonActivity()

        activity.cancel()

        #expect(activity.phase == .idle)
    }

    @Test func isRunning_coversRunningAndCancelling() async {
        let harness = Harness()
        let gate = Gate()

        harness.tap(.refuse) { await gate.wait() }
        #expect(harness.activity.value.isRunning)

        gate.open()
        await harness.waitUntilIdle()
        #expect(!harness.activity.value.isRunning)
    }

    // MARK: Clear-on-launch

    @Test func launch_clearsPreviousErrorSynchronously() {
        let harness = Harness()
        harness.error.value = TestTapError.previous

        harness.tap(.refuse) {}

        // Before the action even completes: the clear happens at the tap
        #expect(harness.error.value == nil)
    }

    // MARK: Outcomes

    @Test func failure_landsInErrorBinding_andActivityReturnsToIdle() async {
        let harness = Harness()

        harness.tap(.refuse) { throw TestTapError.failed }
        await harness.waitUntilIdle()

        #expect(harness.error.value as? TestTapError == .failed)
        #expect(harness.activity.value.phase == .idle)
    }

    @Test func success_writesNothing_andActivityReturnsToIdle() async {
        let harness = Harness()

        harness.tap(.refuse) {}
        await harness.waitUntilIdle()

        #expect(harness.error.value == nil)
        #expect(harness.activity.value.phase == .idle)
    }

    // MARK: Refuse mode

    @Test func refuseMode_tapWhileRunning_hasNoObservableEffect() async {
        let harness = Harness()
        let gate = Gate()
        let starts = Counter()

        harness.tap(.refuse) { await starts.increment(); await gate.wait() }
        #expect(harness.activity.value.phase == .running)

        harness.tap(.refuse) { await starts.increment(); await gate.wait() }
        #expect(harness.activity.value.phase == .running)

        gate.open()
        await harness.waitUntilIdle()
        #expect(starts.count == 1)
    }

    @Test func fireAndForget_withoutActivity_everyTapStartsAnInvocation() async {
        let harness = Harness()
        let starts = Counter()

        harness.tap(.refuse, withActivity: false) { await starts.increment() }
        harness.tap(.refuse, withActivity: false) { await starts.increment() }

        await harness.waitUntil { starts.count == 2 }
        #expect(starts.count == 2)
    }

    // MARK: Toggle mode

    @Test func toggleMode_tapWhileRunning_cancelsCooperatively() async {
        let harness = Harness()

        harness.tap(.toggle) { try await Task.sleep(for: .seconds(600)) }
        #expect(harness.activity.value.phase == .running)

        harness.tap(.toggle) {}
        #expect(harness.activity.value.phase == .cancelling)

        await harness.waitUntilIdle()
        #expect(harness.error.value == nil)
    }

    @Test func cancelledInvocation_writesNothingToError() async {
        let harness = Harness()

        harness.tap(.toggle) { try await Task.sleep(for: .seconds(600)) }
        harness.tap(.toggle) {}
        await harness.waitUntilIdle()

        #expect(harness.error.value == nil)
        #expect(harness.activity.value.phase == .idle)
    }

    @Test func externalCancel_viaActivity_worksInRefuseMode() async {
        let harness = Harness()

        harness.tap(.refuse) { try await Task.sleep(for: .seconds(600)) }
        #expect(harness.activity.value.phase == .running)

        harness.activity.value.cancel()
        #expect(harness.activity.value.phase == .cancelling)

        await harness.waitUntilIdle()
        #expect(harness.error.value == nil)
    }

    @Test func cancellingPhase_refusesTaps() async {
        let harness = Harness()
        let unwindGate = Gate()
        let starts = Counter()

        harness.tap(.toggle) {
            await starts.increment()
            do {
                try await Task.sleep(for: .seconds(600))
            } catch {
                // Hold the unwind open so the cancelling phase is observable
                await unwindGate.wait()
            }
        }
        harness.tap(.toggle) { await starts.increment() }
        #expect(harness.activity.value.phase == .cancelling)

        harness.tap(.toggle) { await starts.increment() }
        #expect(harness.activity.value.phase == .cancelling)

        unwindGate.open()
        await harness.waitUntilIdle()
        #expect(starts.count == 1)
    }

    // MARK: Refractory window

    @Test func toggleMode_tapInsideRefractoryWindow_isDiscarded() {
        let harness = Harness()
        let flip = ContinuousClock().now
        harness.activity.value.lastIdleFlip = flip

        harness.tap(.toggle, now: flip + .milliseconds(1)) {}

        #expect(harness.activity.value.phase == .idle)
    }

    @Test func toggleMode_tapAfterRefractoryWindow_starts() {
        let harness = Harness()
        let flip = ContinuousClock().now
        harness.activity.value.lastIdleFlip = flip

        harness.tap(.toggle, now: flip + AsyncButtonEngine.refractoryWindow + .milliseconds(1)) {}

        #expect(harness.activity.value.phase == .running)
    }

    @Test func refuseMode_isUnaffectedByRefractoryWindow() {
        let harness = Harness()
        let flip = ContinuousClock().now
        harness.activity.value.lastIdleFlip = flip

        harness.tap(.refuse, now: flip + .milliseconds(1)) {}

        #expect(harness.activity.value.phase == .running)
    }

    @Test func toggleCompletion_recordsTheIdleFlip_refuseDoesNot() async {
        let toggleHarness = Harness()
        toggleHarness.tap(.toggle) {}
        await toggleHarness.waitUntilIdle()
        #expect(toggleHarness.activity.value.lastIdleFlip != nil)

        let refuseHarness = Harness()
        refuseHarness.tap(.refuse) {}
        await refuseHarness.waitUntilIdle()
        #expect(refuseHarness.activity.value.lastIdleFlip == nil)
    }

    /// Pins the internal tunable so an accidental change is a conscious one; the duration is
    /// deliberately NOT public contract.
    @Test func refractoryWindow_pinnedValue() {
        #expect(AsyncButtonEngine.refractoryWindow == .milliseconds(500))
    }

    // MARK: Primitive surface (compiles + forwards)

    @Test func primitives_construct() {
        let activity = Binding.constant(AsyncButtonActivity())
        let error = Binding<Error?>.constant(nil)

        let _: Button<Text> = Button(error: error, action: {}, label: { Text("Go") })
        let _: Button<Text> = Button(role: .destructive, activity: activity, error: error, action: {}, label: { Text("Go") })
        let _: Button<Text> = Button(activity: activity, error: error, action: {}, label: { phase in
            Text(phase == .idle ? "Go" : "Stop")
        })
        let _: Button<Text> = Button(role: nil, activity: activity, error: error, action: {}, label: { phase in
            Text(phase == .idle ? "Go" : "Stop")
        })
    }
}

// MARK: - Test Support

private enum TestTapError: Error, Equatable {
    case previous
    case failed
}

/// Caller-side state (what a view's `@State` would hold) plus the tap entry point
@MainActor
private final class Harness {
    let activity = ValueBox<AsyncButtonActivity>(.init())
    let error = ValueBox<Error?>(nil)

    func tap(
        _ mode: AsyncButtonEngine.Mode,
        withActivity: Bool = true,
        now: ContinuousClock.Instant = ContinuousClock().now,
        action: @escaping @Sendable () async throws -> Void
    ) {
        AsyncButtonEngine.handleTap(
            mode: mode,
            activity: withActivity ? activity.binding : nil,
            error: error.binding,
            now: now,
            action: action
        )
    }

    func waitUntilIdle() async {
        await waitUntil { self.activity.value.phase == .idle }
    }

    func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        var yields = 0
        while !condition(), yields < 100000 {
            await Task.yield()
            yields += 1
        }
        #expect(condition(), "condition not reached after \(yields) yields")
    }
}

@MainActor
private final class ValueBox<V> {
    var value: V

    var binding: Binding<V> {
        Binding(
            get: { self.value },
            set: { self.value = $0 }
        )
    }

    init(_ value: V) {
        self.value = value
    }
}

@MainActor
private final class Counter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}

@MainActor
private final class Gate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func open() {
        isOpen = true
        continuations.forEach { $0.resume() }
        continuations.removeAll()
    }

    func wait() async {
        if isOpen {
            return
        }
        await withCheckedContinuation { continuations.append($0) }
    }
}
#endif
