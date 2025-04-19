// DataFetchError.swift
//
// Created by David Hunt on 9/4/24
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

import Foundation

/// Errors resulting from calls to various ``DataFetch`` APIs
public enum DataFetchError: Error, CustomDebugStringConvertible {
    /// An error occurred during decoding
    case decoding(error: DecodingError, responseData: Data)

    /// An error occurred during encoding
    case encoding(error: EncodingError)

    /// A non-200 status code was received in the server response
    case badStatus(httpStatusCode: Int)

    /// The server response contained no data
    case noDataReceived

    /// A response was received, but an unexpected [mime type](FOSFoundation/)
    /// was received in the server response
    case badResponseMimeType(_ mimeType: String)

    /// A response was received that was expected to be in a Date format, but
    /// failed to parse with the expected structure
    case badDateFormat(_ message: String)

    case badURL(_ message: String)

    case utf8EncodingError
    case utf8DecodingError

    static func fromJSONError(_ jsonError: JSONError) -> any Error {
        switch jsonError {
        case .decodingError(let error, let data):
            DataFetchError.decoding(error: error, responseData: data)
        case .encodingError(let error):
            DataFetchError.encoding(error: error)
        case .unknownDateFormat(let dateString):
            DataFetchError.badDateFormat("Unknown JSON date format: \(dateString)")
        case .noData:
            DataFetchError.noDataReceived
        case .utf8EncodingError:
            DataFetchError.utf8EncodingError
        }
    }

    public var debugDescription: String {
        switch self {
        case .decoding(let error, let responseData):
            // swiftlint:disable:next optional_data_string_conversion
            "DataFetchError: \(error) - \(String(decoding: responseData, as: UTF8.self))"
        case .encoding(let error):
            "DataFetchError: Error Encoding - \(error)"
        case .badStatus(let code):
            "DataFetchError: Status code: \(code)"
        case .noDataReceived:
            "DataFetchError: No data received"
        case .badResponseMimeType(let mimeTime):
            "DataFetchError: Received unexpected mime type: '\(mimeTime)'"
        case .badDateFormat(let message):
            "DataFetchError: Bad date format: \(message)"
        case .badURL(let message):
            "DataFetchError: Bad URL: \(message)"
        case .utf8EncodingError:
            "DataFetchError: Unable to encode the data to UTF-8"
        case .utf8DecodingError:
            "DataFetchError: Unable to decode the data from UTF-8"
        }
    }

    public var localizedDescription: String {
        debugDescription
    }
}
