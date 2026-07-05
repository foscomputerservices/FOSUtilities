// SortableDataModel.swift
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

/// Declares how your model's published sort *meanings* become database ordering — one declaration,
/// applied everywhere the framework sorts this model.
///
/// ```swift
/// extension Berth: SortableDataModel {
///     static func sortMappings(for key: BerthSortKey) -> [SortMapping<Berth>] {
///         switch key {
///         case .number:   [.keyPath(\Berth.$number)]
///         case .dockName: [.keyPath(\Berth.$dockName), .keyPath(\Berth.$number)]  // stable tiebreak
///         }
///     }
/// }
/// ```
///
/// Clients only ever send the ``SortKey`` meaning; column names never reach the wire, so renaming a
/// field is invisible to every client. `RequestSortKey` is your model's **one** published sort
/// vocabulary — every request that sorts this model shares it (that's what makes it a vocabulary).
public protocol SortableDataModel: DataModel {
    /// The request-vocabulary key this model sorts by (the shared ``SortKey`` enum your requests use).
    associatedtype RequestSortKey: SortKey
    /// The ordered database mappings for one key — several entries make composite/tiebreak ordering.
    static func sortMappings(for key: RequestSortKey) -> [SortMapping<Self>]
}

/// One database ordering for a ``SortableDataModel`` — build it from a Fluent field KeyPath.
public struct SortMapping<M: SortableDataModel>: Sendable {
    /// Erased at the factory (same discipline as ContainmentRelation): the factory is the only
    /// construction path, so no column strings exist anywhere.
    private let sort: @Sendable (QueryBuilder<M>, SortDirection) -> QueryBuilder<M>

    /// Order by this Fluent field (direction comes from the request's ``SortTerm``).
    public static func keyPath<Field: QueryableProperty>(_ keyPath: KeyPath<M, Field> & Sendable) -> SortMapping<M>
        where Field.Model == M {
        .init { query, direction in
            query.sort(keyPath, direction.fluentDirection)
        }
    }
}

extension SortMapping {
    // The engine-side application seam (C6.3's refined members loop calls this per mapping, in
    // sortMappings(for:) declaration order, with the term's direction).
    func apply(to query: QueryBuilder<M>, direction: SortDirection) -> QueryBuilder<M> {
        sort(query, direction)
    }
}

private extension SortDirection {
    var fluentDirection: DatabaseQuery.Sort.Direction {
        switch self {
        case .ascending: .ascending
        case .descending: .descending
        }
    }
}
