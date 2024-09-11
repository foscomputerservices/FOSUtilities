// DTTest.swift
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

struct DTTest: Codable {
    let dateTime: Date

    init(dateTime: Date? = nil) {
        self.dateTime = dateTime ?? Self.date
    }

    func assertEqualToDefault(comparisonDateComps: Set<Calendar.Component>? = nil) throws {
        let comparisonDateComps = comparisonDateComps ?? [.year, .month, .day, .hour, .minute, .second]
        let dateComps = DTTest.calendar.dateComponents(
            comparisonDateComps,
            from: dateTime
        )

        if comparisonDateComps.contains(.year) {
            if dateComps.year != DTTest.dateYear {
                throw DTTestError.error("years not equal")
            }
        }
        if comparisonDateComps.contains(.month) {
            if dateComps.month != DTTest.dateMonth {
                throw DTTestError.error("months not equal")
            }
        }
        if comparisonDateComps.contains(.day) {
            if dateComps.day != DTTest.dateDay {
                throw DTTestError.error("days not equal")
            }
        }
        if comparisonDateComps.contains(.hour) {
            if dateComps.hour != DTTest.dateHour {
                throw DTTestError.error("hours not equal")
            }
        }
        if comparisonDateComps.contains(.minute) {
            if dateComps.minute != DTTest.dateMinute {
                throw DTTestError.error("minutes not equal")
            }
        }
        if comparisonDateComps.contains(.second) {
            if dateComps.second != DTTest.dateSecond {
                throw DTTestError.error("seconds not equal")
            }
        }
    }

    static func jsonRep(dateTimeStr: String = Self.jsonDateStr) -> String {
        """
            { "dateTime": \"\(dateTimeStr)\" }
        """
    }

    static func invalidJsonRep() -> String {
        """
            { "dateTime": \"invalid_date_time_string\" }
        """
    }

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .init(secondsFromGMT: 0)!
        return calendar
    }

    /// yyyy-MM-dd'T'HH:mm:ssZZZZZ
    static var jsonDateStr: String {
        "\(dateYear)-0\(dateMonth)-0\(dateDay)T\(dateHour):\(dateMinute):\(dateSecond).000Z"
    }

    /// yyyy-MM-dd'T'HH:mm:ssZ
    static var iso8601DateStr: String {
        "\(dateYear)-0\(dateMonth)-0\(dateDay)T\(dateHour):\(dateMinute):\(dateSecond)Z"
    }

    /// yyyy-MM-dd
    static var mdyDateStr: String {
        "\(dateYear)-0\(dateMonth)-0\(dateDay)"
    }

    /// yyyy-MM-dd HH:mm:ss
    static var mdyhmsDateStr: String {
        "\(dateYear)-0\(dateMonth)-0\(dateDay) \(dateHour):\(dateMinute):\(dateSecond)"
    }

    static var date: Date {
        calendar.date(from: dateComps)!
    }

    static let dateSecond = 56
    static let dateMinute = 19
    static let dateHour = 11
    static let dateDay = 6
    static let dateMonth = 2
    static let dateYear = 2023

    static var dateComps: DateComponents {
        .init(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: dateYear,
            month: dateMonth,
            day: dateDay,
            hour: dateHour,
            minute: dateMinute,
            second: dateSecond
        )
    }
}

enum DTTestError: Error {
    case error(_ message: String)
}
