// JSONDecoder.swift
//
// Copyright 2023 FOS Computer Services, LLC
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

public extension JSONDecoder {
    static var defaultDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder -> Date in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            if let date = DateFormatter.JSONDateTimeFormatter.date(from: dateString) {
                return date
            }

            if let date = DateFormatter.ISO8601Formatter.date(from: dateString) {
                return date
            }

            // This line should be before dateFormatter as dateFormatter is
            // a subset of dateTimeFormatter and will thus grab both if
            // placed before dateTimeFormatter
            if let date = DateFormatter.dateTimeFormatter.date(from: dateString) {
                return date
            }

            if let date = DateFormatter.dateFormatter.date(from: dateString) {
                return date
            }
            throw JSONError.unknownDateFormat(dateString)
        }

        return decoder
    }
}
