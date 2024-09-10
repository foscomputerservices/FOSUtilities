// JSONError.swift
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

/// Errors generated during Encoding/Decoding of JSON-style data
public enum JSONError: Error {
    /// A **DecodingError** was received while decoding the data into the JSON value
    case decodingError(error: DecodingError, data: Data)

    /// An **EncodingError** was received while encoding the data
    case encodingError(error: EncodingError)

    /// Unable to encode the data to UTF-8 format
    case utf8EncodingError

    /// An unknown **Date** format was received during the decoding
    /// of JSON data
    ///
    /// The decoding of **Dates** is handled by **JSONDecoder.defaultDecoder**,
    /// which attempts to use all known date formats to decode a **Date** from
    /// JSON-formatted data during **JSONDecoder.decode()**.
    ///
    /// The known date formats are described by:
    ///
    /// - DateFormatter
    ///     - JSONDateTimeFormatter
    ///     - ISO8601Formatter
    ///     - dateTimeFormatter
    ///     - dateFormatter
    ///
    /// All of these formats will be attempted in the order shown above.
    ///
    /// ## Example
    ///
    /// ```
    /// struct MyData: Decodable {
    ///   let date: Date
    /// }
    ///
    /// // Data received from the server, but with an unknown
    /// // string format representing a date or date and time
    /// let jsonData: Data
    /// let myData: MyData = try jsonData.fromJSON() // Exception thrown
    ///
    /// ```
    ///
    /// - See also: **JSONDecoder.DateDecodingStrategy**
    case unknownDateFormat(_ dateString: String)

    /// The data being decoded was empty
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct MyJSONType: Decodable {
    ///   let myData: String
    /// }
    ///
    /// // fromJSON() throws JSONError.noData because the String ("") is empty
    /// let myJSON: MyJSONType = try "".fromJSON()
    /// ```
    case noData

    /// A general error was received during processing
    static func jsonCodingError(_ error: any Error, data: Data? = nil) -> any Error {
        if let e = error as? Self {
            e
        } else if let e = error as? EncodingError {
            JSONError.encodingError(error: e)
        } else if let e = error as? DecodingError {
            JSONError.decodingError(error: e, data: data ?? Data())
        } else {
            error
        }
    }
}
