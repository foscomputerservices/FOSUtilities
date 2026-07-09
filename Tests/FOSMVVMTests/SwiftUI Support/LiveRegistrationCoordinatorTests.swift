// LiveRegistrationCoordinatorTests.swift
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
import FOSFoundation
@testable import FOSMVVM
import Foundation
import Testing

// Marker types anchoring distinct test namespaces.
private enum AlphaModel {}
private enum BetaModel {}

@MainActor
@Suite("LiveRegistrationCoordinator")
struct LiveRegistrationCoordinatorTests {
    @Test("A response's set registers exactly, and only a matching nudge advances the refresh signal")
    func registersExactSetAndFiresOnMatch() async {
        let channel = ScriptedChannel()
        let dispatcher = InvalidationDispatcher(channel: channel)
        let coordinator = LiveRegistrationCoordinator()

        let a = Self.identity(AlphaModel.self)
        coordinator.update(registrations: [a], dispatcher: dispatcher)
        #expect(coordinator.isRegistered)

        channel.send(.invalidated([a]))
        await waitUntil { coordinator.refreshSignal == 1 }
        #expect(coordinator.refreshSignal == 1)

        // An identity the coordinator never registered must not advance the signal.
        channel.send(.invalidated([Self.identity(BetaModel.self)]))
        await pump()
        #expect(coordinator.refreshSignal == 1)
    }

    @Test("A second response re-registers — the prior identity stops firing, the new one fires")
    func secondUpdateReRegisters() async {
        let channel = ScriptedChannel()
        let dispatcher = InvalidationDispatcher(channel: channel)
        let coordinator = LiveRegistrationCoordinator()

        let old = Self.identity(AlphaModel.self)
        let new = Self.identity(BetaModel.self)

        coordinator.update(registrations: [old], dispatcher: dispatcher)
        coordinator.update(registrations: [new], dispatcher: dispatcher)

        channel.send(.invalidated([old]))
        await pump()
        #expect(coordinator.refreshSignal == 0, "the replaced identity must no longer fire")

        channel.send(.invalidated([new]))
        await waitUntil { coordinator.refreshSignal == 1 }
        #expect(coordinator.refreshSignal == 1)
    }

    @Test("Releasing the coordinator frees the token — no retain cycle, and the dead registration is inert")
    func releaseFreesTokenNoCycle() async {
        let channel = ScriptedChannel()
        let dispatcher = InvalidationDispatcher(channel: channel)

        let a = Self.identity(AlphaModel.self)
        var coordinator: LiveRegistrationCoordinator? = .init()
        weak var weakCoordinator = coordinator
        coordinator?.update(registrations: [a], dispatcher: dispatcher)

        // Sanity: alive and firing.
        channel.send(.invalidated([a]))
        await waitUntil { coordinator?.refreshSignal == 1 }

        coordinator = nil
        #expect(
            weakCoordinator == nil,
            "the token's trigger must capture the coordinator weakly — a strong capture would leak it"
        )

        // The now-dead registration must be a harmless no-op (the dispatcher pruned its weak token).
        channel.send(.invalidated([a]))
        await pump()
    }

    @Test("With no channel configured the dispatcher is inert — registration is safe and never fires")
    func degradesInertWithoutChannel() async {
        let dispatcher = InvalidationDispatcher(channel: nil)
        let coordinator = LiveRegistrationCoordinator()

        coordinator.update(registrations: [Self.identity(AlphaModel.self)], dispatcher: dispatcher)

        #expect(coordinator.isRegistered, "registration must succeed even with no channel")
        await pump()
        #expect(coordinator.refreshSignal == 0, "an inert dispatcher never delivers events")
    }

    // Pins the resolver's failed-refresh guard (`refreshInPlace`/`loadAndBind`,
    // ViewModelView.swift): the guard itself lives in the SwiftUI view — unreachable headless —
    // so its load-bearing contract is asserted here at the coordinator+dispatcher seam it protects.
    @Test("A failed refresh skips update — the prior set keeps firing; a successful empty response replaces it")
    func failedRefreshPreservesPriorSet() async {
        let channel = ScriptedChannel()
        let dispatcher = InvalidationDispatcher(channel: channel)
        let coordinator = LiveRegistrationCoordinator()

        let a = Self.identity(AlphaModel.self)
        coordinator.update(registrations: [a], dispatcher: dispatcher)

        // A transient fetch failure returns (nil, []) and the resolver's guard makes NO update
        // call — the original identity must still fire.
        channel.send(.invalidated([a]))
        await waitUntil { coordinator.refreshSignal == 1 }
        #expect(coordinator.refreshSignal == 1, "the prior registration must survive a failed refresh")

        // The regression the guard prevents: reregistering to the error path's empty set would
        // deafen the screen. Only a genuinely-empty SUCCESSFUL response reregisters to empty —
        // and then, correctly, the old identity stops firing.
        coordinator.update(registrations: [], dispatcher: dispatcher)
        channel.send(.invalidated([a]))
        await pump()
        #expect(coordinator.refreshSignal == 1, "an empty successful response replaces the set")
    }
}

private extension LiveRegistrationCoordinatorTests {
    static func identity(_ type: Any.Type) -> ModelIdentity {
        .init(namespace: ModelNamespace(for: type), id: UUID())
    }

    func pump(_ times: Int = 20) async {
        for _ in 0..<times {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 500000)
        }
    }

    func waitUntil(_ predicate: @MainActor () -> Bool) async {
        for _ in 0..<200 {
            if predicate() { return }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 500000)
        }
    }
}

/// A channel whose events are pushed by the test (the dispatcher-test idiom, reused here).
private final class ScriptedChannel: InvalidationChannel, @unchecked Sendable {
    private let stream: AsyncStream<InvalidationEvent>
    private let continuation: AsyncStream<InvalidationEvent>.Continuation

    init() {
        var captured: AsyncStream<InvalidationEvent>.Continuation!
        self.stream = AsyncStream { captured = $0 }
        self.continuation = captured
    }

    func events() -> AsyncStream<InvalidationEvent> {
        stream
    }

    func send(_ event: InvalidationEvent) {
        continuation.yield(event)
    }
}
#endif
