// FilterableDataModel.swift
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

/// Declares how your model reads a request's query as a database `WHERE` — one hand-written
/// translation, applied everywhere the framework loads this model for that request.
///
/// A query *is* a filter (selecting records is what a query does), so there is no separate filter
/// type — you translate the request's own ``ServerRequestQuery`` to Fluent, by hand:
///
/// ```swift
/// extension Berth: FilterableDataModel {
///     static func apply(filter: BerthQuery, to query: QueryBuilder<Berth>) -> QueryBuilder<Berth> {
///         guard let name = filter.dockName else { return query }
///         return query.filter(\.$dockName == name)   // your Fluent, your columns
///     }
/// }
/// ```
///
/// No filter vocabulary and no column names reach the wire. The framework rides the request's query
/// into the one query it counts, paginates, and caches, so counts and windows reflect the narrowed
/// set. `Filter` is the **one** query type this model narrows by — a request whose query is a
/// different type simply doesn't narrow this model (its records load unfiltered).
public protocol FilterableDataModel: DataModel {
    /// The request query this model reads as a filter — the one ``ServerRequestQuery`` type whose
    /// `WHERE` you translate below.
    associatedtype Filter: ServerRequestQuery

    /// Translate the request's query to this model's query as a `WHERE`, by hand. Return `query`
    /// unchanged when the query carries nothing to narrow by — never a silent match-nothing.
    static func apply(filter: Filter, to query: QueryBuilder<Self>) -> QueryBuilder<Self>
}
