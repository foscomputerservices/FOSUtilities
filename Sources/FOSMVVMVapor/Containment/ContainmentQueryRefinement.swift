// ContainmentQueryRefinement.swift
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

/// The erased sort term crossing the engine/refinement/cache seams. `Any` prefix per Swift's
/// meaning-preserving erased-wrapper convention (AnyHashable/AnyView). Constructed ONLY from a typed
/// SortTerm — the factory captures the concrete key for the downcast inside the relation's closure.
struct AnySortTerm: Hashable, Sendable {
    // No `& Sendable` needed on the stored existential: SortKey itself refines Sendable.
    let key: any SortKey // downcast to To.RequestSortKey inside the typed closure
    let direction: SortDirection

    init(_ term: SortTerm<some SortKey>) {
        self.key = term.key
        self.direction = term.direction
    }

    /// MANUAL Hashable: `any SortKey` can't drive synthesis. AnyHashable carries both the key value
    /// and its dynamic type, so terms are equal iff key type, key value, and direction all match.
    static func == (lhs: Self, rhs: Self) -> Bool {
        AnyHashable(lhs.key) == AnyHashable(rhs.key) && lhs.direction == rhs.direction
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(AnyHashable(key))
        hasher.combine(direction)
    }
}

extension SortCriteria {
    /// The sanctioned eraser — C8 and tests bridge a request's typed criteria with this; the engine
    /// never sees SortCriteria<Key> directly.
    var erasedTerms: [AnySortTerm] {
        terms.map(AnySortTerm.init)
    }
}

/// The erased load instructions the engine hands a ContainmentRelation (which alone knows `To`).
/// Hashable so the CACHE KEYS ON THE WHOLE VALUE — additive future fields (filter, eager-loads) join
/// the key automatically and can never resurrect the OQ-L1-4 collision.
struct ContainmentQueryRefinement: Hashable, Sendable {
    var sortTerms: [AnySortTerm]
    var pagination: Pagination?

    /// Empty — the unrefined path's value (C4's members(of:on:) forwards this).
    static let none = ContainmentQueryRefinement()

    init(sortTerms: [AnySortTerm] = [], pagination: Pagination? = nil) {
        self.sortTerms = sortTerms
        self.pagination = pagination
    }

    /// The refinement the engine actually applies (and keys the cache on) for raw request
    /// axes. Pagination decodes straight from client input, and FluentKit's range() turns a
    /// negative component into a crashing/garbage query, so the boundary semantics are pinned
    /// here: negative ⇒ treated as absent (that component ignored); zero maxResults ⇒
    /// deliberately an empty page (not "absent") — a boundary guard, never silent truncation
    /// of valid input. The ONE normalization point: the engine's deposit and the executor's
    /// key reconstruction both go through it (via `ContainerRecordCacheKey.forLoad`).
    static func normalized(sortTerms: [AnySortTerm], pagination: Pagination?) -> ContainmentQueryRefinement {
        .init(
            sortTerms: sortTerms,
            pagination: pagination.flatMap { window in
                let startIndex = window.startIndex.flatMap { $0 >= 0 ? $0 : nil }
                let maxResults = window.maxResults.flatMap { $0 >= 0 ? $0 : nil }
                return startIndex == nil && maxResults == nil
                    ? nil
                    : Pagination(startIndex: startIndex, maxResults: maxResults)
            }
        )
    }
}

extension ContainmentQueryRefinement {
    /// Push-down application, called inside a relation's typed closure before `.all()`: sort via
    /// To's SortableDataModel mappings (in term order), then the window via QueryBuilder.range.
    /// Sort terms against a non-sortable To fail fast — NEVER a silently unsorted result.
    func apply<To: DataModel>(to query: QueryBuilder<To>) throws -> QueryBuilder<To> {
        var query = query
        if let firstTerm = sortTerms.first {
            guard let sortableType = To.self as? any SortableDataModel.Type else {
                throw ContainmentError.unsortableContainedType(
                    modelType: String(describing: To.self),
                    keyType: String(describing: type(of: firstTerm.key))
                )
            }
            query = try sortableType.applyErasedSortTerms(sortTerms, to: query)
        }
        if let pagination {
            let lower = pagination.startIndex ?? 0
            // FluentKit's range(lower:upper:) takes `upper` as an INCLUSIVE index (limit becomes
            // upper - lower + 1); a nil upper applies the offset with no bound.
            query = query.range(lower: lower, upper: pagination.maxResults.map { lower + $0 - 1 })
        }
        return query
    }
}

private extension SortableDataModel {
    /// Opened-existential seam: the caller opens `To.self as? any SortableDataModel.Type`, so Self
    /// IS M at runtime; QueryBuilder is invariant, so the two conditional casts re-prove statically
    /// what the opening established dynamically. They are backstops, not code paths (same posture as
    /// ContainmentRelation's container cast) — a failure means framework-invariant breakage.
    static func applyErasedSortTerms<M: DataModel>(
        _ terms: [AnySortTerm],
        to query: QueryBuilder<M>
    ) throws -> QueryBuilder<M> {
        guard let opened = query as? QueryBuilder<Self> else {
            throw ContainmentError.containerTypeMismatch(
                expected: String(describing: Self.self),
                actual: String(describing: M.self)
            )
        }
        var typed = opened
        for term in terms {
            guard let key = term.key as? RequestSortKey else {
                throw ContainmentError.unsortableContainedType(
                    modelType: String(describing: Self.self),
                    keyType: String(describing: type(of: term.key))
                )
            }
            for mapping in sortMappings(for: key) {
                typed = mapping.apply(to: typed, direction: term.direction)
            }
        }
        guard let result = typed as? QueryBuilder<M> else {
            throw ContainmentError.containerTypeMismatch(
                expected: String(describing: M.self),
                actual: String(describing: Self.self)
            )
        }
        return result
    }
}
