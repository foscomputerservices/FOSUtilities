// RootedQuery.swift
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

/// A ``ServerRequestQuery`` that names the container its request is rooted in.
///
/// Conform your query only when it roots a fresh containment scope — the trait-overlay idiom used by
/// ``PaginatedQuery``:
///
/// ```swift
/// struct HarborBerthsQuery: RootedQuery {
///     let rootIdentity: ModelIdentity   // the Harbor this request is scoped to
/// }
/// ```
///
/// A requirement rooted with `.newRoot(.query)` reads this property to resolve its scope at load time.
///
/// A request roots at most one `.query`-vended container: one query supplies one root. A second
/// query-vended root in a single request is intentionally not modeled.
public protocol RootedQuery: ServerRequestQuery {
    /// The container identity this request's containment scope roots at.
    var rootIdentity: ModelIdentity { get }
}
