// TargetedQuery.swift
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

/// A ``ServerRequestQuery`` that names which loaded record a write request targets.
///
/// ```swift
/// struct UpdateBerthQuery: TargetedQuery, RootedQuery {
///     let rootIdentity: ModelIdentity   // RootedQuery — the scope root
///     let target: ModelIdentity         // TargetedQuery — which berth
/// }
/// ```
///
/// The selector is the record's opaque ``ModelIdentity`` — the identity the
/// client received inside the ViewModel it displayed, echoed back verbatim. The
/// form body never carries a raw id: the server resolves this selector against
/// the auth-scoped candidate set it loaded itself, so a submit cannot retarget.
/// Resolution failure is indistinguishable from not-found.
///
/// Sibling of ``RootedQuery`` / ``PaginatedQuery`` — one trait per concern.
public protocol TargetedQuery: ServerRequestQuery {
    /// The targeted record's opaque identity, from the ViewModel the client
    /// displayed. Resolved server-side against the loaded candidate set.
    var target: ModelIdentity { get }
}
