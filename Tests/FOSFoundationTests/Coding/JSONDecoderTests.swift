// JSONDecoderTests.swift
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

import FOSFoundation
import Foundation
import Testing

@Suite("JSON Decoding Tests", .tags(.json))
struct JSONDecodingTests {
    @Test(arguments: [
        (format: DTTest.jsonDateStr, dateComps: nil), // yyyy-MM-dd'T'HH:mm:ssZZZZZ
        (format: DTTest.iso8601DateStr, dateComps: nil), // yyyy-MM-dd'T'HH:mm:ssZ
        (format: DTTest.mdyDateStr, dateComps: Set([Calendar.Component.year, .month, .day])), // yyyy-MM-dd
        (format: DTTest.mdyhmsDateStr, dateComps: nil) // yyyy-MM-dd HH:mm:ss
    ]) func dateTimeDecoding(tuple: (format: String, dateComps: Set<Calendar.Component>?)) throws {
        let dateTimeData = try #require(
            DTTest
                .jsonRep(dateTimeStr: tuple.format)
                .data(using: .utf8)
        )
        let dtTest = try JSONDecoder.defaultDecoder.decode(
            DTTest.self,
            from: dateTimeData
        )
        try dtTest.assertEqualToDefault(
            comparisonDateComps: tuple.dateComps
        )
    }

    @Test func invalidDateFormat() throws {
        let dateTimeData = try #require(
            DTTest
                .invalidJsonRep()
                .data(using: .utf8)
        )
        #expect(throws: JSONError.self) {
            try JSONDecoder.defaultDecoder.decode(
                DTTest.self,
                from: dateTimeData
            )
        }
    }
}
