// Expectations.swift
//
// Created by David Hunt on 4/9/23
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

import FOSFoundation
import Foundation
import Testing

/// Performs tests to ensure that the **Codable**s implementation can encode and decode properly
///
/// - Parameter codableType: A `System.Type` of a type that conforms to **Codable** and **Stubbable**
/// - Parameter message: An optional message to add to error messages (default message contains the missing key information)
public func expectCodable<C>(_ codableType: C.Type, _ message: @autoclosure () -> String = "") throws where C: Codable, C: Stubbable {
    let instance = codableType.stub()
    let message = message() + ": "

    let encodedData: Data
    do {
        let encoder = JSONEncoder()
        encodedData = try encoder.encode(instance)

        if encodedData.count == 0 {
            throw FOSCodableError.error(message + "Encoded 0 bytes")
        }
    } catch let e {
        throw FOSCodableError.error(message + "Exception encoding \(C.self): \(e.localizedDescription)")
    }

    do {
        let decoder = JSONDecoder()
        _ = try decoder.decode(codableType, from: encodedData)
    } catch let e {
        throw FOSCodableError.error(message + "Exception decoding \(C.self): \(e.localizedDescription) from json \(String(decoding: encodedData, as: UTF8.self))")
    }
}

enum FOSCodableError: Error {
    case error(_ message: String)
}
