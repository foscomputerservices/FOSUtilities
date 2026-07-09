// InvalidationDispatcherTests.swift
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

// Marker types anchoring test namespaces — distinct kinds of model.
private enum AlphaModel {}
private enum BetaModel {}

@MainActor
@Suite("InvalidationDispatcher")
struct InvalidationDispatcherTests {
    @Test("An exact-tier nudge fires the matching registration and only it")
    func exactMatchFiresOnlyTheMatch() async {
        let channel = ScriptedChannel()
        let dispatcher = InvalidationDispatcher(channel: channel)

        let a = Self.identity(AlphaModel.self)
        let c = Self.identity(AlphaModel.self)

        let hitA = Counter()
        let hitC = Counter()
        let tokenA = dispatcher.register(identities: [a], namespaces: []) { hitA.count += 1 }
        let tokenC = dispatcher.register(identities: [c], namespaces: []) { hitC.count += 1 }

        channel.send(.invalidated([a]))
        await waitUntil { hitA.count == 1 }

        #expect(hitA.count == 1)
        #expect(hitC.count == 0)

        withExtendedLifetime(tokenA) {}
        withExtendedLifetime(tokenC) {}
    }

    @Test("A namespace-tier registration fires for any identity in that namespace")
    func namespaceMatchFiresForAnyIdentityInNamespace() async {
        let channel = ScriptedChannel()
        let dispatcher = InvalidationDispatcher(channel: channel)

        let namespace = ModelNamespace(for: AlphaModel.self)
        let hit = Counter()
        let token = dispatcher.register(identities: [], namespaces: [namespace]) { hit.count += 1 }

        // An identity the registration never named exactly, but sharing its namespace.
        channel.send(.invalidated([Self.identity(AlphaModel.self)]))
        await waitUntil { hit.count == 1 }
        #expect(hit.count == 1)

        // A different namespace does not fire it.
        channel.send(.invalidated([Self.identity(BetaModel.self)]))
        await pump()
        #expect(hit.count == 1)

        withExtendedLifetime(token) {}
    }

    @Test("Several identities in one event matching one registration fire it once")
    func oneEventManyIdentitiesFiresOnce() async {
        let channel = ScriptedChannel()
        let dispatcher = InvalidationDispatcher(channel: channel)

        let a = Self.identity(AlphaModel.self)
        let b = Self.identity(AlphaModel.self)
        let hit = Counter()
        let token = dispatcher.register(identities: [a, b], namespaces: []) { hit.count += 1 }

        channel.send(.invalidated([a, b]))
        await waitUntil { hit.count >= 1 }
        await pump()
        #expect(hit.count == 1)

        withExtendedLifetime(token) {}
    }

    @Test("A released token unregisters — its registration no longer fires")
    func releasedTokenUnregisters() async {
        let channel = ScriptedChannel()
        let dispatcher = InvalidationDispatcher(channel: channel)

        let a = Self.identity(AlphaModel.self)
        let hit = Counter()
        var token: InvalidationDispatcher.Token? =
            dispatcher.register(identities: [a], namespaces: []) { hit.count += 1 }
        weak var weakToken = token

        // Sanity: alive and firing.
        channel.send(.invalidated([a]))
        await waitUntil { hit.count == 1 }

        token = nil // the registrant releases — the only strong reference is gone
        #expect(weakToken == nil, "the dispatcher must hold the token weakly")

        channel.send(.invalidated([a]))
        await pump()
        #expect(hit.count == 1, "a dead registration must not fire")
    }

    @Test("Re-registration replaces the identity set — old identities stop firing")
    func reregistrationReplacesTheSet() async {
        let channel = ScriptedChannel()
        let dispatcher = InvalidationDispatcher(channel: channel)

        let old = Self.identity(AlphaModel.self)
        let new = Self.identity(BetaModel.self)
        let hit = Counter()
        let token = dispatcher.register(identities: [old], namespaces: []) { hit.count += 1 }

        dispatcher.reregister(token, identities: [new], namespaces: [])

        channel.send(.invalidated([old]))
        await pump()
        #expect(hit.count == 0, "the replaced identity must no longer fire")

        channel.send(.invalidated([new]))
        await waitUntil { hit.count == 1 }
        #expect(hit.count == 1)

        withExtendedLifetime(token) {}
    }

    @Test("A .connected event sweeps every registration once")
    func connectedSweepsAll() async {
        let channel = ScriptedChannel()
        let dispatcher = InvalidationDispatcher(channel: channel)

        let hit1 = Counter()
        let hit2 = Counter()
        let hit3 = Counter()
        let t1 = dispatcher.register(identities: [Self.identity(AlphaModel.self)], namespaces: []) { hit1.count += 1 }
        let t2 = dispatcher.register(identities: [Self.identity(BetaModel.self)], namespaces: []) { hit2.count += 1 }
        let t3 = dispatcher.register(identities: [], namespaces: [ModelNamespace(for: AlphaModel.self)]) { hit3.count += 1 }

        channel.send(.connected)
        await waitUntil { hit1.count == 1 && hit2.count == 1 && hit3.count == 1 }
        await pump()

        #expect(hit1.count == 1)
        #expect(hit2.count == 1)
        #expect(hit3.count == 1)

        withExtendedLifetime(t1) {}
        withExtendedLifetime(t2) {}
        withExtendedLifetime(t3) {}
    }

    @Test("The channel opens on the first registration only")
    func channelOpensOnFirstRegistrationOnly() {
        let channel = ScriptedChannel()
        let dispatcher = InvalidationDispatcher(channel: channel)

        #expect(channel.eventsCallCount == 0, "no registration ⇒ no socket")

        let t1 = dispatcher.register(identities: [Self.identity(AlphaModel.self)], namespaces: []) {}
        #expect(channel.eventsCallCount == 1, "the first registration opens the channel")

        let t2 = dispatcher.register(identities: [Self.identity(BetaModel.self)], namespaces: []) {}
        #expect(channel.eventsCallCount == 1, "a later registration must not reopen the channel")

        withExtendedLifetime(t1) {}
        withExtendedLifetime(t2) {}
    }

    @Test("Explicit unregister stops the registration firing while the token stays alive")
    func explicitUnregisterStopsFiring() async {
        let channel = ScriptedChannel()
        let dispatcher = InvalidationDispatcher(channel: channel)

        let a = Self.identity(AlphaModel.self)
        let hit = Counter()
        let token = dispatcher.register(identities: [a], namespaces: []) { hit.count += 1 }

        channel.send(.invalidated([a]))
        await waitUntil { hit.count == 1 }

        dispatcher.unregister(token)

        channel.send(.invalidated([a]))
        await pump()
        #expect(hit.count == 1, "an explicitly unregistered token must not fire")

        withExtendedLifetime(token) {}
    }

    @Test("A trigger may register and unregister during a fire (reentrancy snapshot safety)")
    func triggerMayMutateRegistrationsDuringFire() async {
        let channel = ScriptedChannel()
        let dispatcher = InvalidationDispatcher(channel: channel)

        let a = Self.identity(AlphaModel.self)
        let b = Self.identity(BetaModel.self)
        let selfHit = Counter()
        let lateHit = Counter()

        // Deterministic reentrancy: the trigger unregisters ITSELF and registers a new
        // registration mid-fire — pins that fire iterates a snapshot and survives mutation.
        let holder = TokenHolder()
        holder.token = dispatcher.register(identities: [a], namespaces: []) {
            selfHit.count += 1
            if let token = holder.token {
                dispatcher.unregister(token)
            }
            holder.lateToken = dispatcher.register(identities: [b], namespaces: []) {
                lateHit.count += 1
            }
        }

        channel.send(.invalidated([a]))
        await waitUntil { selfHit.count == 1 }
        #expect(lateHit.count == 0, "a registration added mid-fire must not fire for that event")

        channel.send(.invalidated([a]))
        await pump()
        #expect(selfHit.count == 1, "the self-unregistered trigger must not fire again")

        channel.send(.invalidated([b]))
        await waitUntil { lateHit.count == 1 }
        #expect(lateHit.count == 1, "the mid-fire registration must fire for later events")
    }

    @Test("A .connected sweep over a dead token prunes it and fires only the living")
    func connectedSweepPrunesDeadToken() async {
        let channel = ScriptedChannel()
        let dispatcher = InvalidationDispatcher(channel: channel)

        let liveHit = Counter()
        let deadHit = Counter()
        let liveToken = dispatcher.register(identities: [Self.identity(AlphaModel.self)], namespaces: []) {
            liveHit.count += 1
        }
        var deadToken: InvalidationDispatcher.Token? =
            dispatcher.register(identities: [Self.identity(BetaModel.self)], namespaces: []) {
                deadHit.count += 1
            }
        deadToken = nil // dead but never nudged — only the sweep's fire→remove prune touches it
        _ = deadToken

        channel.send(.connected)
        await waitUntil { liveHit.count == 1 }
        await pump()

        #expect(liveHit.count == 1)
        #expect(deadHit.count == 0, "a dead token must be pruned by the sweep, not fired")

        withExtendedLifetime(liveToken) {}
    }
}

/// Lets a trigger closure reach its own token without capturing it before `register` returns.
@MainActor
private final class TokenHolder {
    var token: InvalidationDispatcher.Token?
    var lateToken: InvalidationDispatcher.Token?
}

private extension InvalidationDispatcherTests {
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

/// A MainActor-confined tally the fired triggers increment — no cross-actor sharing.
@MainActor
private final class Counter {
    var count = 0
}

/// A channel whose events are pushed by the test and that records when `events()` is first
/// consumed — the "opens on first registration" probe (the Task 1 channel idiom, made drivable).
private final class ScriptedChannel: InvalidationChannel, @unchecked Sendable {
    private let stream: AsyncStream<InvalidationEvent>
    private let continuation: AsyncStream<InvalidationEvent>.Continuation
    private let lock = NSLock()
    private var _eventsCallCount = 0

    var eventsCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _eventsCallCount
    }

    init() {
        var captured: AsyncStream<InvalidationEvent>.Continuation!
        self.stream = AsyncStream { captured = $0 }
        self.continuation = captured
    }

    func events() -> AsyncStream<InvalidationEvent> {
        lock.lock(); _eventsCallCount += 1; lock.unlock()
        return stream
    }

    func send(_ event: InvalidationEvent) {
        continuation.yield(event)
    }
}
