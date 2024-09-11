// Encodable.swift
//
// Created by David Hunt on 9/4/24
// Copyright 2024 FOS Services, LLC
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

public extension Encodable {
    /// Converts the `Encodable` to a JSON string
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct MyCodable: Codable {
    ///   var myProperty = "myProperty"
    /// }
    ///
    /// let encodedString = try MyCodable().toJSON()
    /// ```
    ///
    /// - Parameter encoder: The **JSONEncoder** to use to encode the receiver to a
    ///   **String** (default: **JSONEncoder**.defaultEncoder)
    func toJSON(encoder: JSONEncoder? = nil) throws -> String {
        do {
            guard let result = try String(
                data: toJSONData(encoder: encoder),
                encoding: .utf8
            ) else {
                throw JSONError.utf8EncodingError
            }

            return result
        } catch let e {
            throw JSONError.jsonCodingError(e)
        }
    }

    /// Converts the `Encodable` to a JSON string encoded in `Data`
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct MyCodable: Codable {
    ///   var myProperty = "myProperty"
    /// }
    ///
    /// let encodedData = try MyCodable().toJSONData()
    /// ```
    ///
    /// - Parameter encoder: The **JSONEncoder** to use to encode the receiver to a
    ///   **String** (default: **JSONEncoder**.defaultEncoder)
    func toJSONData(encoder: JSONEncoder? = nil) throws -> Data {
        do {
            return try (encoder ?? JSONEncoder.defaultEncoder).encode(self)
        } catch let e {
            throw JSONError.jsonCodingError(e)
        }
    }
}
