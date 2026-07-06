// WriteTargetProviding.swift
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

/// Declares a write request's **candidate set**: the records the caller is authorized to
/// mutate, loaded auth-scoped *before* the write runs. Adopt it on the write request's
/// `RequestBody` in the server target:
///
/// ```swift
/// extension DeleteBerthRequest.RequestBody: WriteTargetProviding {
///     static let candidates = LoadRequirement.delete(Berth.self, in: .parentRoot)
/// }
/// ```
///
/// Declare `candidates` as a stored `static let` — anything else fails fast at boot. On a
/// writer, `.parentRoot`
/// anchors at the write request's own query root (there is no parent factory). The submitted
/// ``TargetedQuery`` target must resolve to a member of this set, or the request fails with
/// not-found semantics (not-yours is indistinguishable from not-found).
///
/// A `DeleteRequest` body conforms to this protocol **alone** — deletion is framework-owned,
/// so there is nothing to apply. An update or create body adds ``DataModelWriter``.
public protocol WriteTargetProviding: Sendable {
    /// The persisted model this request writes.
    associatedtype Target: DataModel

    /// The write-verb requirement (`.write` / `.create` / `.delete`) naming what this request
    /// may touch, and from where. Declare it as a stored `static let`.
    static var candidates: LoadRequirement<Target> { get }
}

/// The write half of an update or create request: applies the submitted, validated body onto
/// the target model. Adopt it on the write request's `RequestBody` in the server target:
///
/// ```swift
/// extension UpdateBerthRequest.RequestBody: DataModelWriter {
///     static let candidates = LoadRequirement.write(Berth.self, in: .parentRoot)
///
///     func apply(to berth: Berth) throws {
///         berth.name = name
///         berth.capacity = capacity
///     }
/// }
/// ```
///
/// `apply` is the exact mirror of a ``VaporResponseBodyFactory``'s projection — synchronous, and
/// it **cannot touch the database**: the framework owns all I/O (loading, saving, the container
/// foreign key, deletion, the refresh). By the time `apply` runs the body has validated
/// (structurally — `apply` is otherwise unreachable), the candidate set has loaded, and the
/// target has resolved from the query, never from the body. After it returns the framework
/// saves, invalidates the mutated containers' cached records, and re-serves the refresh request
/// through the genuine read pipeline.
///
/// Create uses the *same* method: the framework instantiates a fresh `Target()`, calls `apply`,
/// sets the container foreign key from the candidate scope, and saves. One authored method
/// covers update and create — field application only.
public protocol DataModelWriter: WriteTargetProviding {
    /// Applies the submitted, validated values onto `target`. Field assignment only — no
    /// database access, no cross-record side effects.
    func apply(to target: Target) throws
}
