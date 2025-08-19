// Model.swift
//
// Copyright 2025 FOS Computer Services, LLC
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

/// Declares a ``Model`` type
///
/// Conforming to ``Model`` declares that the type takes on the **Model** role in the **M-V-VM**
/// architecture.
///
/// > The protocol provides default implementations of: Hashable, Equatable and ``requireId()``
public protocol Model: Codable, Hashable {
    static var modelType: String { get }

    /// A unique identifier for the instance
    var id: ModelIdType? { get }

    /// Returns the model's ``id``
    ///
    /// - Throws: ``ModelError/missingId(modelType:)`` if the model's id is nil
    func requireId() throws -> ModelIdType
}

public extension Model {
    // MARK: Hashable Protocol

    @inlinable func hash(into hasher: inout Hasher) {
        hasher.combine(id ?? .init())
    }

    // MARK: Equatable Protocol

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    @inlinable static var modelType: String { String(describing: Self.self) }

    @inlinable var modelType: String { Self.modelType }

    func requireId() throws -> ModelIdType {
        guard let id else {
            throw ModelError.missingId(modelType: String(describing: Self.self))
        }

        return id
    }
}

public enum ModelError: Error, CustomDebugStringConvertible {
    case missingId(modelType: String)

    public var debugDescription: String {
        switch self {
        case .missingId(let modelType):
            "Missing identifier for model of type \(modelType)"
        }
    }
}
