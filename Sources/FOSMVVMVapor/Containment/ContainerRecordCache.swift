// ContainerRecordCache.swift
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

import FluentKit
import FOSMVVM
import Foundation
import Vapor

/// Names one cached load unit: (container identity, contained type, operation, anchor, refinement).
/// The refinement participates as a WHOLE Hashable value, so any future refinement field joins the
/// key automatically and can never resurrect the OQ-L1-4 collision.
struct ContainerRecordCacheKey: Hashable, Sendable {
    let container: ModelIdentity
    let containedType: ObjectIdentifier
    let operation: ContainerOperation
    // The anchor is an ENGINE parameter, not a refinement field — the refinement's
    // "additive fields join the key automatically" posture does not cover it; it joins the key
    // here, explicitly. Normalized at init (nil ⇒ the load container): same-anchor paths are the
    // same security question and MUST share one entry; different anchors must never merge (D-C7-16).
    let anchor: ModelIdentity
    let refinement: ContainmentQueryRefinement

    init(
        container: ModelIdentity,
        containedType: any DataModel.Type,
        operation: ContainerOperation,
        authorizedAs anchor: ModelIdentity? = nil,
        refinement: ContainmentQueryRefinement
    ) {
        self.container = container
        self.containedType = ObjectIdentifier(containedType)
        self.operation = operation
        self.anchor = anchor ?? container
        self.refinement = refinement
    }

    /// The exact key the engine deposits for one load call — the SINGLE construction point,
    /// shared by the engine's deposit and the executor's tuple→keys side map, so the two can
    /// never drift. Bakes in both normalizations: anchor (nil ⇒ the load container, via init)
    /// and the refinement's pagination boundary rules (`ContainmentQueryRefinement.normalized`).
    static func forLoad(
        of container: ModelIdentity,
        containing containedType: any DataModel.Type,
        for operation: ContainerOperation,
        authorizedAs anchor: ModelIdentity?,
        sortedBy sortTerms: [AnySortTerm],
        pagination: Pagination?
    ) -> ContainerRecordCacheKey {
        .init(
            container: container,
            containedType: containedType,
            operation: operation,
            authorizedAs: anchor,
            refinement: .normalized(sortTerms: sortTerms, pagination: pagination)
        )
    }
}

extension Vapor.Request {
    /// CONTRACT (one authorization set per Request): the key deliberately does NOT name the
    /// authorizations. This is structural — the provider is fetched and memoized once per Request
    /// (the sole authorization path since the C8 audit removed the `authorizedBy:` engine entry),
    /// so only one authorization set can ever reach this cache.
    /// CONTRACT (snapshot sharing): cached elements are shared class references — readers
    /// (projections) must NOT mutate them; only the write path mutates records, and after commit
    /// it calls invalidateContainerRecords(of:).
    /// The engine (authorizedRecords(via:of:containing:for:authorizedAs:sortedBy:pagination:))
    /// is the cache's ONLY writer; everything else reads or invalidates.
    var containerRecordCache: [ContainerRecordCacheKey: [any DataModel]] {
        get { storage[ContainerRecordCacheStore.self]?.entries ?? [:] }
        set { storage[ContainerRecordCacheStore.self] = ContainerRecordCacheEntries(entries: newValue) }
    }

    /// Pass-#2 support: a mutating caller invalidates after commit so its re-run recomputes.
    /// Drops ALL of the identity's entries — every contained type, operation, and refinement.
    func invalidateContainerRecords(of container: ModelIdentity) {
        containerRecordCache = containerRecordCache.filter { $0.key.container != container }
    }
}

extension Application {
    /// Observability, not truncation: an engine call whose result count exceeds this logs ONE
    /// warning and returns the full set. Deliberately no app-facing knob yet (internal var —
    /// promote only when a definitive consumer appears; C8 audit).
    var maxRecordsWarningThreshold: Int {
        get { storage[MaxRecordsWarningThresholdStore.self] ?? 1000 }
        set { storage[MaxRecordsWarningThresholdStore.self] = newValue }
    }
}

// @unchecked: the entries are live Fluent model classes (not statically Sendable). Vapor's
// Request.storage is lock-protected (NIOLockedValueBox), and entries are touched sequentially
// within the request's handler task — not a free pass; readers must still not mutate the shared
// model instances (see the snapshot-sharing contract above).
private struct ContainerRecordCacheEntries: @unchecked Sendable {
    var entries: [ContainerRecordCacheKey: [any DataModel]]
}

private struct ContainerRecordCacheStore: StorageKey {
    typealias Value = ContainerRecordCacheEntries
}

private struct MaxRecordsWarningThresholdStore: StorageKey {
    typealias Value = Int
}
