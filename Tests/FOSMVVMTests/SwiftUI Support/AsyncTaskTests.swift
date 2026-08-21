// AsyncTaskTests.swift
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

/// Each ratified `task(error:)` semantic gets a test, driven through AsyncTaskEngine.run —
/// the seam both public overloads forward to. SwiftUI's own `.task` lifecycle (start on
/// appear, cancel on disappear/id-change) is Apple's contract and is not re-tested here.
@MainActor
struct AsyncTaskTests {
    // MARK: Clear-on-launch

    @Test func launch_clearsPreviousError_beforeTheActionCompletes() async {
        let error = ValueBox<Error?>(TestLoadError.previous)
        let gate = Gate()

        let invocation = Task { @MainActor in
            await AsyncTaskEngine.run(error: error.binding) { await gate.wait() }
        }

        await waitUntil { error.value == nil }
        gate.open()
        await invocation.value

        #expect(error.value == nil)
    }

    // MARK: Outcomes

    @Test func success_leavesErrorNil() async {
        let error = ValueBox<Error?>(nil)

        await AsyncTaskEngine.run(error: error.binding) {}

        #expect(error.value == nil)
    }

    @Test func failure_landsInErrorBinding() async {
        let error = ValueBox<Error?>(nil)

        await AsyncTaskEngine.run(error: error.binding) { throw TestLoadError.failed }

        #expect(error.value as? TestLoadError == .failed)
    }

    // MARK: Cancellation

    @Test func cancelledInvocation_writesNothing() async {
        let error = ValueBox<Error?>(nil)
        let started = Gate()

        let invocation = Task { @MainActor in
            await AsyncTaskEngine.run(error: error.binding) {
                await started.open()
                try await Task.sleep(for: .seconds(600))
            }
        }

        await started.wait()
        invocation.cancel()
        await invocation.value

        #expect(error.value == nil)
    }

    @Test func cancelledInvocation_discardsEvenNonCancellationFailures() async {
        let error = ValueBox<Error?>(nil)
        let started = Gate()

        let invocation = Task { @MainActor in
            await AsyncTaskEngine.run(error: error.binding) {
                await started.open()
                do {
                    try await Task.sleep(for: .seconds(600))
                } catch {
                    throw TestLoadError.failed
                }
            }
        }

        await started.wait()
        invocation.cancel()
        await invocation.value

        #expect(error.value == nil)
    }

    @Test func restart_supersededInvocationContributesNothing() async {
        let error = ValueBox<Error?>(nil)
        let started = Gate()
        let unwind = Gate()

        // Invocation A: cancelled mid-load, unwind held open so it finishes late
        let invocationA = Task { @MainActor in
            await AsyncTaskEngine.run(error: error.binding) {
                await started.open()
                do {
                    try await Task.sleep(for: .seconds(600))
                } catch {
                    await unwind.wait()
                    throw TestLoadError.stale
                }
            }
        }
        await started.wait()
        invocationA.cancel()

        // Invocation B: the superseding load, which fails
        await AsyncTaskEngine.run(error: error.binding) { throw TestLoadError.fresh }
        #expect(error.value as? TestLoadError == .fresh)

        // A unwinds after B already deposited — B's outcome must survive
        unwind.open()
        await invocationA.value
        #expect(error.value as? TestLoadError == .fresh)
    }

    // MARK: Cancellation sentinel

    @Test func cancellationError_fromNonCancelledInvocation_isDiscarded() async {
        let error = ValueBox<Error?>(nil)

        await AsyncTaskEngine.run(error: error.binding) { throw CancellationError() }

        #expect(error.value == nil)
    }

    @Test func domainCancellationVocabulary_isNotFiltered() async {
        let error = ValueBox<Error?>(nil)

        await AsyncTaskEngine.run(error: error.binding) { throw TestLoadError.domainCancelled }

        #expect(error.value as? TestLoadError == .domainCancelled)
    }

    // MARK: Public surface (compiles + forwards)

    @Test func overloads_construct() {
        let error = Binding<Error?>.constant(nil)

        _ = Text("Probe").task(error: error) {}
        _ = Text("Probe").task(error: error, priority: .background) {}
        _ = Text("Probe").task(id: 7, error: error) {}
        _ = Text("Probe").task(id: "doc", error: error, priority: .background) {}
    }

    // MARK: Support

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        var yields = 0
        while !condition(), yields < 100000 {
            await Task.yield()
            yields += 1
        }
        #expect(condition(), "condition not reached after \(yields) yields")
    }
}

// MARK: - Test Support

private enum TestLoadError: Error, Equatable {
    case previous
    case failed
    case stale
    case fresh
    case domainCancelled
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
