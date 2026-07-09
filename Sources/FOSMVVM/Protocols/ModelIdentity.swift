// ModelIdentity.swift
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

import FOSFoundation
import Foundation

/// Answers "which entity is this?" for a ``Model`` — an opaque, value-comparable identity that stays
/// stable across the wire, persistence, and authorization.
///
/// Get one from a model, then compare, route on, or store it — without ever touching the underlying
/// id or type:
///
/// ```swift
/// let identity = try user.modelIdentity
///
/// if identity == changedModel { refresh() }     // compare to a live model of any type, safely
/// grantedContainers.contains(identity)          // Hashable — use it as a Set member or dictionary key
/// ```
///
/// You can't build one from raw values (only ``Model/modelIdentity`` or decoding mints one), and you
/// can't read its contents back out.
///
/// - Important: Treat it as opaque. Encode/decode it *as a whole* to persist or transmit it; never
///   parse or hand-build its encoded form. The encoding is stable — it changes only on a library major
///   version — so a stored identity always round-trips.
public struct ModelIdentity: Hashable, Codable, Sendable {
    // `package`, NOT public — server-side targets read these to drive the ModelTypeRegistry lookup +
    // Fluent find; clients still cannot read identity contents (opacity is a public-surface guarantee, L0).
    package let namespace: ModelNamespace
    package let id: ModelIdType

    // Kept explicit (not synthesized): this init IS the minting seam.
    // swiftlint:disable:next unneeded_synthesized_initializer
    init(namespace: ModelNamespace, id: ModelIdType) { // internal ⇒ only Model.modelIdentity mints one
        self.namespace = namespace
        self.id = id
    }

    // Frozen: L1 persists these in DB columns — never rename/reorder/remove a key (breaks stored
    // data; a change here is a library major-version bump).
    private enum CodingKeys: String, CodingKey {
        case namespace
        case id
    }
}

public extension ModelIdentity {
    /// The HTTP response header FOSMVVM uses to keep ``LiveViewModel`` screens current
    ///
    /// The framework attaches it to served responses and the live bind resolver consumes
    /// it — application code never reads, parses, or constructs its value. The constant
    /// exists so infrastructure (proxies, logging filters, tests) can reference the header
    /// **by name**; its value is an opaque framework contract that may evolve.
    static let registrationsHeader = "X-FOS-Registrations"
}

public extension ModelIdentity {
    /// Whether this identity is the one rooted in `model` — sugar for `models.filter { changed == $0 }`.
    ///
    /// An unpersisted `model` (`id == nil`) compares `false`; it never throws.
    static func == (lhs: ModelIdentity, rhs: some Model) -> Bool {
        (try? lhs == rhs.modelIdentity) ?? false
    }
}

public extension ModelIdentity {
    /// A stable ``ViewModelId`` derived from this identity. Bind your ViewModel's `vmId` to it so
    /// SwiftUI keeps the view stable as the model's data changes:
    ///
    /// ```swift
    /// self.vmId = try user.modelIdentity.viewModelId
    /// ```
    var viewModelId: ViewModelId {
        .init(id: "\(namespace.rawValue)|\(id.uuidString)")
    }
}
