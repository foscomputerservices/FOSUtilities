// JSONDecoderTests.swift
//
// Copyright © 2023 FOS Services, LLC. All rights reserved.
//

import FOSFoundation
import XCTest

final class JSONDecoderTests: XCTestCase {
    func testJSONDateTimeDecoding() throws {
        // yyyy-MM-dd'T'HH:mm:ssZZZZZ
        let dateTimeString = """
            { "dateTime":  "2023-02-06T11:19:56.000Z" }
        """
        let dateTimeData = dateTimeString.data(using: .utf8)!
        struct DTTest: Decodable {
            let dateTime: Date
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .init(secondsFromGMT: 0)!

        let dtTest: DTTest = try JSONDecoder.defaultDecoder.decode(DTTest.self, from: dateTimeData)
        let dateComps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: dtTest.dateTime)

        XCTAssertEqual(dateComps.year, 2023)
        XCTAssertEqual(dateComps.month, 2)
        XCTAssertEqual(dateComps.day, 6)
        XCTAssertEqual(dateComps.hour, 11)
        XCTAssertEqual(dateComps.minute, 19)
        XCTAssertEqual(dateComps.second, 56)
    }

    func testISO8601Decoding() throws {
        let dateTimeString = """
            { "dateTime":  "2023-02-06T11:19:56Z" }
        """
        let dateTimeData = dateTimeString.data(using: .utf8)!
        struct DTTest: Decodable {
            let dateTime: Date
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .init(secondsFromGMT: 0)!

        let dtTest: DTTest = try JSONDecoder.defaultDecoder.decode(DTTest.self, from: dateTimeData)
        let dateComps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: dtTest.dateTime)

        XCTAssertEqual(dateComps.year, 2023)
        XCTAssertEqual(dateComps.month, 2)
        XCTAssertEqual(dateComps.day, 6)
        XCTAssertEqual(dateComps.hour, 11)
        XCTAssertEqual(dateComps.minute, 19)
        XCTAssertEqual(dateComps.second, 56)
    }

    func testDateDecoding() throws {
        let dateTimeString = """
            { "date":  "2023-02-06" }
        """
        let dateTimeData = dateTimeString.data(using: .utf8)!
        struct DTTest: Decodable {
            let date: Date
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .init(secondsFromGMT: 0)!

        let dtTest: DTTest = try JSONDecoder.defaultDecoder.decode(DTTest.self, from: dateTimeData)
        let dateComps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: dtTest.date)

        XCTAssertEqual(dateComps.year, 2023)
        XCTAssertEqual(dateComps.month, 2)
        XCTAssertEqual(dateComps.day, 6)
        XCTAssertEqual(dateComps.hour, 0)
        XCTAssertEqual(dateComps.minute, 0)
        XCTAssertEqual(dateComps.second, 0)
    }

    func testDateTimeDecoding() throws {
        let dateTimeString = """
            { "dateTime":  "2023-02-06 11:19:56" }
        """
        let dateTimeData = dateTimeString.data(using: .utf8)!
        struct DTTest: Decodable {
            let dateTime: Date
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .init(secondsFromGMT: 0)!

        let dtTest: DTTest = try JSONDecoder.defaultDecoder.decode(DTTest.self, from: dateTimeData)
        let dateComps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: dtTest.dateTime)

        XCTAssertEqual(dateComps.year, 2023)
        XCTAssertEqual(dateComps.month, 2)
        XCTAssertEqual(dateComps.day, 6)
        XCTAssertEqual(dateComps.hour, 11)
        XCTAssertEqual(dateComps.minute, 19)
        XCTAssertEqual(dateComps.second, 56)
    }
}
