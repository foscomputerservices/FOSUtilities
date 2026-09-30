// ScopedQuery.swift
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

/// A ``ServerRequestQuery`` that names the container its request is scoped within.
///
/// Conform your query only when a plan of the request is declared `within: .request` — the
/// trait-overlay idiom used by ``PaginatedQuery``:
///
/// ```swift
/// struct BoardPageQuery: ScopedQuery {
///     let scopeIdentity: ModelIdentity   // the Board this page is about
/// }
/// static let cards = Card.loadingPlan(.read, within: .request)
/// ```
///
/// A request names at most one container this way: one query supplies one scope. A second
/// query-named scope in a single request is intentionally not modeled.
public protocol ScopedQuery: ServerRequestQuery {
    /// The container the request's plans are scoped within.
    var scopeIdentity: ModelIdentity { get }

    /// The scope's identity under its former name. Conform with ``scopeIdentity`` instead.
    @available(*, deprecated, renamed: "scopeIdentity")
    var rootIdentity: ModelIdentity { get }
}

public extension ScopedQuery {
    /// Declare ``scopeIdentity``. A query still declaring the former `rootIdentity` answers
    /// through it; one declaring neither fails at its first request, by name.
    @available(*, deprecated, message: "declare scopeIdentity; this default forwards from the former rootIdentity")
    var scopeIdentity: ModelIdentity {
        rootIdentity
    }

    @available(*, deprecated, renamed: "scopeIdentity")
    var rootIdentity: ModelIdentity {
        // Reached only by a query declaring neither spelling — the trap is the compile error a
        // protocol cannot express for "one of two".
        preconditionFailure("\(Self.self) declares neither scopeIdentity nor rootIdentity — declare scopeIdentity")
    }
}

/// The former name of ``ScopedQuery``.
@available(*, deprecated, renamed: "ScopedQuery")
public typealias RootedQuery = ScopedQuery
