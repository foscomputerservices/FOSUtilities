// InvalidationHub.swift
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
import Foundation

/// The single-process broadcast point of L2 live invalidation (spec §3.1): every committed
/// mutation's derived identity set arrives at `emit`, which fans it out to every subscriber
/// (DEF-1: no per-client filtering). Owned by `Application.storage`
/// (`Application.invalidationHub`); injected into each emit middleware and into `liveTransaction`
/// — never attached to `Database`. It is the seam behind which multi-instance fan-out plugs in
/// later (DEF-L2-4). Task 4's SSE endpoint is the production subscriber.
actor InvalidationHub {
    /// Per-subscriber buffer bound — overflow terminates that subscriber's stream (spec §3.2
    /// slow-client policy). No nudge is silently dropped on a healthy stream; a terminated
    /// client recovers through its reconnect sweep.
    static let subscriberBufferLimit = 64

    private var subscribers: [UUID: AsyncStream<Set<ModelIdentity>>.Continuation] = [:]
    private var suppressionWarnedTypes: Set<String> = []

    /// One subscriber's live feed of emitted identity sets. The stream ends when the hub
    /// terminates it (buffer overflow) or the consumer cancels.
    func subscribe() -> AsyncStream<Set<ModelIdentity>> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Set<ModelIdentity>>.makeStream(
            bufferingPolicy: .bufferingOldest(Self.subscriberBufferLimit)
        )
        continuation.onTermination = { _ in
            Task { [weak self] in
                await self?.removeSubscriber(id)
            }
        }
        subscribers[id] = continuation
        return stream
    }

    /// Fans one emitted identity set out to every subscriber. An empty set is a no-op — nothing
    /// went stale, no client is nudged.
    func emit(_ identities: Set<ModelIdentity>) {
        guard !identities.isEmpty else {
            return
        }

        // COW-safe: the iterator holds a snapshot, so removing from `subscribers` below is sound.
        for (id, continuation) in subscribers {
            switch continuation.yield(identities) {
            case .enqueued:
                break
            case .dropped, .terminated:
                continuation.finish()
                subscribers.removeValue(forKey: id)
            @unknown default:
                break
            }
        }
    }

    /// True exactly once per model type — gates the bare-transaction suppress warning
    /// (spec §3.1: "suppresses the emit and logs one warning naming the model type").
    func shouldWarnSuppressedEmit(for modelType: String) -> Bool {
        suppressionWarnedTypes.insert(modelType).inserted
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers.removeValue(forKey: id)?.finish()
    }
}
