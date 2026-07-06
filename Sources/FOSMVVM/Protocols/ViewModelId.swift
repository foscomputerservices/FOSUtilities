// ViewModelId.swift
//
// Copyright 2024 FOS Computer Services, LLC
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

/// An identity for a ``ViewModel``
///
/// # Overview
///
/// Whenever possible, the ``ViewModelId`` should be bound to some identifying characteristic
/// of the ``Model`` that was used to project the ``ViewModel``.  This will greatly stabilize the
/// SwiftUI View hierarchy and caching structure.
///
/// ```swift
/// @ViewModel struct UserViewModel {
///   let firstName: String
///   let lastName: String
///
///   let vmId: ViewModelId
///
///   init(user: User) {
///     self.firstName = user.firstName
///     self.lastName = user.lastName
///     self.vmId = .init(id: user.id)
///   }
/// }
/// ```
///
/// # Singleton ViewModels
///
/// For ``ViewModel``s that are singleton in identity, that is the ``ViewModel``s
/// properties are always set the same values,  the ``ViewModel``s type
/// should be used to initialize the identity.
///
/// ```swift
/// @ViewModel struct MyViewModel {
///   @LocalizedString var aProperty
///
///   let vmId: ViewModelId
///
///   init() {
///     self.vmId = .init(type: Self.self)
///   }
/// }
/// ```
///
/// # Last Resort
///
/// When there isn't an established ``Model`` and the model cannot be established as
/// a singleton ``ViewModel``, the default constructor can be used to create a random
/// ``ViewModelId``.  Note that every update of the ``ViewModel`` will have a new
/// identity and thus the caching system in SwiftUI will be hampered by this variability.
public struct ViewModelId: Codable, Hashable, Sendable {
    private let id: String
    private let isRandom: Bool

    /// This vmId's birth moment — a version clock. You rarely read it directly; the framework uses it
    /// to tell a newer copy of a ViewModel from an older one (and drop stale refreshes). `==` and
    /// `hash` ignore it, so two versions of the same entity stay equal. To compare versions yourself:
    ///
    /// ```swift
    /// if incoming.freshness > current.freshness { current = incoming }   // keep the newer copy
    /// ```
    public let freshness: Freshness

    public init(id: String? = nil) {
        self.id = id ?? String.unique()
        self.isRandom = id == nil
        self.freshness = Freshness()
    }

    public init(id: Int) {
        self.init(id: "\(id)")
    }

    public init(id: UUID) {
        self.init(id: "\(id.uuidString)")
    }

    public init(type: (some ViewModel).Type) {
        self.init(id: String(reflecting: type))
    }

    // MARK: Codable Protocol

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let id = try container.decodeIfPresent(String.self, forKey: .id)
        self.isRandom = id == nil
        self.id = id ?? String.unique()
        // Missing fsh (legacy payload) ⇒ now; present ⇒ preserved (decode never re-stamps).
        self.freshness = try container.decodeIfPresent(Freshness.self, forKey: .freshness) ?? Freshness()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        if !isRandom {
            try container.encode(id, forKey: .id)
        }
        try container.encode(freshness, forKey: .freshness) // always encoded, unlike id
    }

    // MARK: Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: Equatable

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

private extension ViewModelId {
    enum CodingKeys: String, CodingKey {
        case id
        case freshness = "fsh" // short key: ViewModelId is embedded in every streamed VM
    }
}

public extension ViewModelId {
    /// A version clock for a ``ViewModelId``. It only compares (`<`, `==`) — no `Date` arithmetic,
    /// calendar, or formatting — which is exactly what you want to tell a newer version from an older
    /// one: `a.freshness < b.freshness`.
    struct Freshness: Comparable, Sendable {
        private let timestamp: Date

        init() {
            self.timestamp = .now
        } // internal ⇒ a Freshness can't be forged with an arbitrary moment

        public static func < (lhs: Freshness, rhs: Freshness) -> Bool {
            lhs.timestamp < rhs.timestamp
        }
    }
}

extension ViewModelId.Freshness: Codable {
    public init(from decoder: Decoder) throws {
        self.timestamp = try decoder.singleValueContainer().decode(Date.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(timestamp)
    }
}
