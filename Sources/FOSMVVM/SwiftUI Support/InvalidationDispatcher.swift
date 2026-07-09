// InvalidationDispatcher.swift
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
import Foundation

/// Routes server invalidation nudges to the live screens that depend on the affected identities
/// (spec §3.3). One instance is owned by ``MVVMEnvironment``; the bind resolver registers a
/// re-fetch trigger per live screen and re-registers each response's derived identity set.
///
/// Not `Sendable`, `@MainActor`: every registration and every fired trigger touches SwiftUI state.
/// The consumption task inherits this isolation, so incoming events are handled on the main actor.
@MainActor
final class InvalidationDispatcher {
    /// A live registration handle. The registrant holds it for as long as its screen is bound;
    /// when it deallocates the dispatcher's weak reference clears and the registration stops firing.
    final class Token {
        fileprivate let trigger: @MainActor () -> Void

        fileprivate init(trigger: @escaping @MainActor () -> Void) {
            self.trigger = trigger
        }
    }

    /// The dispatcher-side record. `token` is weak — the registrant's release IS the unregister, so a
    /// vanished screen never fires (deref → nil → pruned). `identities`/`namespaces` are kept here (not
    /// read off the token) so pruning a dead token still knows which index buckets to clean.
    private final class Entry {
        weak var token: Token?
        var identities: Set<ModelIdentity>
        var namespaces: Set<ModelNamespace>

        init(token: Token, identities: Set<ModelIdentity>, namespaces: Set<ModelNamespace>) {
            self.token = token
            self.identities = identities
            self.namespaces = namespaces
        }
    }

    private let channel: (any InvalidationChannel)?
    private var consumeTask: Task<Void, Never>?

    private var entries: [ObjectIdentifier: Entry] = [:]
    private var exactIndex: [ModelIdentity: Set<ObjectIdentifier>] = [:]
    private var namespaceIndex: [ModelNamespace: Set<ObjectIdentifier>] = [:]

    init(channel: (any InvalidationChannel)?) {
        self.channel = channel
    }

    deinit {
        // `Task` is `Sendable`, so a nonisolated deinit may read this isolated stored property.
        consumeTask?.cancel()
    }

    /// Registers `trigger` to fire when the server nudges any of `identities`, or any identity whose
    /// namespace is in `namespaces`. The returned ``Token`` must be retained for the registration to
    /// live. The first registration opens the channel (an app with no live screens never connects).
    ///
    /// - Warning: `trigger` must not strongly capture the token's owner — the dispatcher holds the
    ///   token weakly, so a token → trigger → owner → token cycle is immortal.
    @discardableResult
    func register(
        identities: Set<ModelIdentity>,
        namespaces: Set<ModelNamespace>,
        trigger: @escaping @MainActor () -> Void
    ) -> Token {
        let token = Token(trigger: trigger)
        let id = ObjectIdentifier(token)
        // A brand-new token can share an address only with a dead one whose entry lingers — evict
        // that stale entry first so its old identities don't stay indexed against this id.
        remove(id)
        pruneDead(inBucketsFor: identities, namespaces: namespaces)
        entries[id] = Entry(token: token, identities: identities, namespaces: namespaces)
        addToIndices(id, identities: identities, namespaces: namespaces)
        startConsumingIfNeeded()
        return token
    }

    /// Replaces `token`'s identity/namespace set, keeping its trigger — the seam the resolver drives
    /// on every refresh so a screen whose plan touched new containers starts listening to them
    /// (spec §3.4). A no-op if `token` is no longer registered.
    func reregister(
        _ token: Token,
        identities: Set<ModelIdentity>,
        namespaces: Set<ModelNamespace>
    ) {
        let id = ObjectIdentifier(token)
        guard let entry = entries[id] else { return }

        pruneDead(inBucketsFor: identities, namespaces: namespaces)
        removeFromIndices(id, identities: entry.identities, namespaces: entry.namespaces)
        entry.identities = identities
        entry.namespaces = namespaces
        addToIndices(id, identities: identities, namespaces: namespaces)
    }

    /// Drops `token`'s registration explicitly. Token deallocation does the same lazily.
    func unregister(_ token: Token) {
        remove(ObjectIdentifier(token))
    }
}

private extension InvalidationDispatcher {
    func startConsumingIfNeeded() {
        // Opened once, on the first registration, and kept open for the app's foreground lifetime —
        // reconnects live inside the channel's own stream (spec §3.2). `events()` is called
        // synchronously here so "the socket opens at registration" holds without a scheduling hop.
        guard consumeTask == nil, let channel else { return }

        let stream = channel.events()
        consumeTask = Task { [weak self] in
            for await event in stream {
                guard let self else { break }
                handle(event)
            }
        }
    }

    func handle(_ event: InvalidationEvent) {
        switch event {
        case .connected:
            // Reconnect sweep (spec §3.2): fire every registration, so whatever was missed while
            // disconnected re-fetches. The freshness gate absorbs the redundancy.
            fire(Set(entries.keys))
        case .invalidated(let identities):
            fire(matching: identities)
        }
    }

    func fire(matching identities: Set<ModelIdentity>) {
        var matched: Set<ObjectIdentifier> = []
        for identity in identities {
            if let hits = exactIndex[identity] {
                matched.formUnion(hits)
            }
            if let hits = namespaceIndex[identity.namespace] {
                matched.formUnion(hits)
            }
        }
        fire(matched)
    }

    /// Deduped by construction: `matched` is a set of token ids, so a registration hit by several
    /// identities in one event fires exactly once.
    func fire(_ ids: Set<ObjectIdentifier>) {
        for id in ids {
            guard let entry = entries[id] else {
                purgeOrphan(id) // a bucket id with no entry — self-heal instead of firing forever
                continue
            }
            guard let token = entry.token else {
                remove(id) // dead registrant — prune lazily on first touch
                continue
            }
            token.trigger()
        }
    }

    func remove(_ id: ObjectIdentifier) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        removeFromIndices(id, identities: entry.identities, namespaces: entry.namespaces)
    }

    /// Incremental, not a full-table walk: sweeping only the buckets this (re)registration touches
    /// keeps the cost proportional to the registration's own set while bounding index growth to
    /// live entries + recent churn — dead never-firing namespaces can't accumulate unboundedly.
    func pruneDead(inBucketsFor identities: Set<ModelIdentity>, namespaces: Set<ModelNamespace>) {
        var dead: Set<ObjectIdentifier> = []
        for identity in identities {
            for id in exactIndex[identity] ?? [] where entries[id]?.token == nil {
                dead.insert(id)
            }
        }
        for namespace in namespaces {
            for id in namespaceIndex[namespace] ?? [] where entries[id]?.token == nil {
                dead.insert(id)
            }
        }
        for id in dead {
            if entries[id] != nil {
                remove(id)
            } else {
                purgeOrphan(id)
            }
        }
    }

    /// Defensive only — register's evict-first makes orphaned bucket ids unreachable by
    /// construction; if one ever appears, strip it from every bucket so it can't linger.
    func purgeOrphan(_ id: ObjectIdentifier) {
        for identity in Array(exactIndex.keys) {
            exactIndex[identity]?.remove(id)
            if exactIndex[identity]?.isEmpty == true {
                exactIndex.removeValue(forKey: identity)
            }
        }
        for namespace in Array(namespaceIndex.keys) {
            namespaceIndex[namespace]?.remove(id)
            if namespaceIndex[namespace]?.isEmpty == true {
                namespaceIndex.removeValue(forKey: namespace)
            }
        }
    }

    func addToIndices(
        _ id: ObjectIdentifier,
        identities: Set<ModelIdentity>,
        namespaces: Set<ModelNamespace>
    ) {
        for identity in identities {
            exactIndex[identity, default: []].insert(id)
        }
        for namespace in namespaces {
            namespaceIndex[namespace, default: []].insert(id)
        }
    }

    func removeFromIndices(
        _ id: ObjectIdentifier,
        identities: Set<ModelIdentity>,
        namespaces: Set<ModelNamespace>
    ) {
        for identity in identities {
            exactIndex[identity]?.remove(id)
            if exactIndex[identity]?.isEmpty == true {
                exactIndex.removeValue(forKey: identity)
            }
        }
        for namespace in namespaces {
            namespaceIndex[namespace]?.remove(id)
            if namespaceIndex[namespace]?.isEmpty == true {
                namespaceIndex.removeValue(forKey: namespace)
            }
        }
    }
}
