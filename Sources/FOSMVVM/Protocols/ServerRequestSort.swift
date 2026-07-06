// ServerRequestSort.swift
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

import Foundation

/// The wire contract for a request's sort. See ``SortCriteria`` for the standard implementation.
public protocol ServerRequestSort: Codable, Hashable, Sendable {}

/// The sortable dimensions a container publishes to clients — *meanings*, never storage columns.
///
/// ```swift
/// enum BerthSortKey: String, SortKey { case number, dockName, updatedAt }
/// ```
///
/// The server maps each dimension to one or more sort keypaths; the client only ever names a dimension,
/// so renaming a column never reaches the wire.
public protocol SortKey: Codable, Hashable, Sendable {}

/// Ascending or descending order for a ``SortTerm``.
public enum SortDirection: Codable, Hashable, Sendable {
    case ascending
    case descending
}

/// One ordering term: a published ``SortKey`` dimension and its direction.
public struct SortTerm<Key: SortKey>: Codable, Hashable, Sendable {
    public let key: Key
    public let direction: SortDirection
    public init(key: Key, direction: SortDirection) {
        self.key = key
        self.direction = direction
    }
}

/// A client's chosen ordering for a container's records: an ordered list of ``SortTerm``s.
///
/// ```swift
/// // Sort berths by dock name, then by number descending:
/// let sort = SortCriteria<BerthSortKey>([
///     .init(key: .dockName, direction: .ascending),
///     .init(key: .number, direction: .descending),
/// ])
/// ```
///
/// Terms apply in order (primary, secondary, …).
public struct SortCriteria<Key: SortKey>: ServerRequestSort {
    public let terms: [SortTerm<Key>]
    public init(_ terms: [SortTerm<Key>]) {
        self.terms = terms
    }
}

/// The used-but-empty default sort for a request that exposes no ordering (mirrors `EmptyQuery`).
public struct EmptySort: ServerRequestSort {
    public init() {}
}
