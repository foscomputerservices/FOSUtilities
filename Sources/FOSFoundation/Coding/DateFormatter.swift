// DateFormatter.swift
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

public extension DateFormatter {
    /// Formats dates without times using **GMT-0** and the **en_US_POSIX Locale**
    ///
    /// - Note: This property returns a singleton **DateFormatter**.  **DateFormatter**
    ///   is **not** a *value* type, thus, changes should not be made to the resulting value
    ///   or all references will be affected.
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Formats dates with times using **GMT-0** and the **en_US_POSIX Locale**
    ///
    /// - Note: This property returns a singleton **DateFormatter**.  **DateFormatter**
    ///   is **not** a *value* type, thus, changes should not be made to the resulting value
    ///   or all references will be affected.
    static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// A full date-time representation for encoding in JSON using **GMT-0**
    /// and the **en_US_POSIX Locale**
    ///
    /// JSON date time formats [generally specify strings in the format](https://stackoverflow.com/a/15952652)
    /// of '2012-04-23T18:25:43.511Z', which is the format
    /// used by this **DateFormatter**.  This format is [ISO 8601](https://w.wiki/8G7)
    /// with milliseconds support.
    ///
    /// - Note: This property returns a singleton **DateFormatter**.  **DateFormatter**
    ///   is **not** a *value* type, thus, changes should not be made to the resulting value
    ///   or all references will be affected.
    static let JSONDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'.'SSS'Z'"
        return formatter
    }()

    /// A full date-time representation for encoding in [ISO 8601](https://w.wiki/8G7)
    /// format using **GMT-0** and the **en_US_POSIX Locale**
    ///
    ///
    /// The difference between **JSONDateTimeFormatter** and **ISO8601Formatter**
    /// is that the **ISO** version does not accept milliseconds.  That is, the
    /// [ISO 8601](https://w.wiki/8G7) standard *can* accept milliseconds, but
    /// this formatter does not.  If milliseconds are required, use **JSONDateTimeFormatter**.
    ///
    /// - Note: This property returns a singleton **DateFormatter**.  **DateFormatter**
    ///   is **not** a *value* type, thus, changes should not be made to the resulting value
    ///   or all references will be affected.
    static let ISO8601Formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter
    }()
}
