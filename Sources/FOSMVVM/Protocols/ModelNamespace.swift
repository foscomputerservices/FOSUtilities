// ModelNamespace.swift
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

/// Identifies the *kind* of a ``Model`` (its type) as an opaque token.
///
/// You rarely build one yourself — every ``Model`` supplies a default via
/// ``Model/modelIdentityNamespace``. Reach for it only to **override** that default: when you persist
/// a model's identity and need the stored value to survive a future rename of the model type. Anchor
/// the namespace to a dedicated marker type instead of the model, so renaming `User` can't shift it:
///
/// ```swift
/// enum UserIdentity {}   // a stable name you'll never rename; it exists only to anchor the token
///
/// extension User {
///     static var modelIdentityNamespace: ModelNamespace { .init(for: UserIdentity.self) }
/// }
/// ```
///
/// A namespace can be made only from a *type*, never a raw string, and its contents can't be read
/// back out — so it can't be forged or parsed. It is `Hashable` and `Codable`.
public struct ModelNamespace: Hashable, Sendable {
    private let value: String
    var rawValue: String {
        value
    } // read by ModelIdentity to build the vmId token

    /// Creates the namespace identifying `type`.
    public init(for type: Any.Type) {
        // Reflecting, NOT describing: the module-qualified name avoids cross-module collisions.
        self.value = String(reflecting: type)
    }
}

extension ModelNamespace: Codable {
    public init(from decoder: Decoder) throws {
        self.value = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
