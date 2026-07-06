// PaginatedQuery.swift
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

/// A window into a result set: where to start and how many to return.
///
/// ```swift
/// let firstPage = Pagination(startIndex: 0, maxResults: 25)
/// ```
public struct Pagination: Codable, Hashable, Sendable {
    /// Zero-based index of the first record to return; `nil` starts at the beginning.
    public let startIndex: Int?
    /// Maximum records to return; `nil` is unbounded (subject to the server's max-records guard).
    public let maxResults: Int?
    public init(startIndex: Int? = nil, maxResults: Int? = nil) {
        self.startIndex = startIndex
        self.maxResults = maxResults
    }
}

/// A ``ServerRequestQuery`` that pages through a large result set.
///
/// Conform your query only when it needs paging — non-paginated queries stay as they are:
///
/// ```swift
/// struct BerthsQuery: PaginatedQuery {
///     var pagination: Pagination { .init(startIndex: 0, maxResults: 25) }
///     // ...ServerRequestQuery requirements...
/// }
/// ```
///
/// The load engine applies the window when a request's query conforms, and returns the full authorized
/// set otherwise.
public protocol PaginatedQuery: ServerRequestQuery {
    var pagination: Pagination { get }
}
