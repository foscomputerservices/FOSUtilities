// Decodable.swift
//
// Created by David Hunt on 4/11/23
// Copyright 2023 FOS Services, LLC
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

public extension String {
    /// Converts the **String** to an instance of `T` from JSON string
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct MyCodable: Codable {
    ///   var myProperty = "myProperty"
    /// }
    ///
    /// let encodedString = try MyCodable().toJSON()
    /// let myCodable: MyCodable = try encodedString.fromJSON()
    /// ```
    ///
    /// - Parameter decoder: A customized **JSONDecoder**
    ///      (default: **JSONDecoder.defaultDecoder**)
    ///
    /// - Throws: ``JSONError/noData`` if **String** is empty
    func fromJSON<T>(decoder: JSONDecoder? = nil) throws -> T where T: Decodable {
        guard !isEmpty else {
            throw JSONError.noData
        }

        return try Data(utf8).fromJSON(decoder: decoder)
    }
}

public extension Data {
    /// Converts the `Data` to `T` from the JSON string encoded in
    /// `Data` using `JSONDecoder`.defaultDecoder
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct MyCodable: Codable {
    ///   var myProperty = "myProperty"
    /// }
    ///
    /// let encodedData = try MyCodable().toJSONData()
    /// let myCodable: MyCodable = try encodedData.fromJSON()
    /// ```
    ///
    /// - Parameter decoder: A customized **JSONDecoder** (default: **JSONDecoder.defaultDecoder**)
    ///
    /// - Throws: ``JSONError/noData`` if **String** is empty
    func fromJSON<T>(decoder: JSONDecoder? = nil) throws -> T where T: Decodable {
        guard !isEmpty else {
            throw JSONError.noData
        }

        do {
            return try (decoder ?? JSONDecoder.defaultDecoder)
                .decode(T.self, from: self)
        } catch let error as DecodingError {
            throw JSONError.decodingError(error: error, data: self)
        } catch let e {
            throw e
        }
    }
}
