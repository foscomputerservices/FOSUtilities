// FOSAssert.swift
//
// Copyright © 2023 FOS Services, LLC. All rights reserved.
//

import FOSFoundation
import Foundation
import XCTest

/** This file provides a number of *XCTAssert-style* functions that make writing tests easier and more succinct  **/

/// Performs tests to ensure that the `Codable`s implementation can encode and decode properly
///
/// - Parameter codableType: A `System.Type` of a type that conforms to `Codable`
/// - Parameter message: An optional message to add to error messages (default message contains the missing key information)
/// - Parameter file: The file containing the test (default: call site)
/// - Parameter line: The line number of the test (default: call site)
public func FOSAssertCodable<C>(_ codableType: C.Type, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) throws where C: Codable, C: Stubbable {
    let instance = codableType.stub()
    let message = message() + ": "

    let encodedData: Data
    do {
        let encoder = JSONEncoder()
        encodedData = try encoder.encode(instance)

        XCTAssertNotEqual(encodedData.count, 0, message + "Encoded 0 bytes", file: file, line: line)
    } catch let e {
        XCTFail(message + "Exception encoding \(C.self): \(e.localizedDescription)", file: file, line: line)
        return
    }

    do {
        let decoder = JSONDecoder()
        let _ = try decoder.decode(codableType, from: encodedData)
    } catch let e {
        XCTFail(message + "Exception decoding \(C.self): \(e.localizedDescription) from json \(String(data: encodedData, encoding: .utf8)!)", file: file, line: line)
    }
}
