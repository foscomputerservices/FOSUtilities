// Int+HexTests.swift
//
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

import FOSFoundation
import Foundation
import Testing

@Suite("Integer Hexadecimal Conversion Testing", .tags(.extensions))
struct IntHexTests {
    @Test(arguments: [
        (value: UInt64(0), style: HexadecimalPrefixStyle.zeroX, result: "0x0"),
        (value: UInt64(255), style: HexadecimalPrefixStyle.zeroX, result: "0xFF"),
        (value: UInt64(255), style: HexadecimalPrefixStyle.sharp, result: "#FF")
    ])
    func uint64HexString(tuple: (value: UInt64, style: HexadecimalPrefixStyle, result: String)) async throws {
        #expect(tuple.value.hexString(prefixStyle: tuple.style) == tuple.result)
    }

    @Test(arguments: [
        (value: Int64(0), style: HexadecimalPrefixStyle.zeroX, result: "0x0"),
        (value: Int64(255), style: HexadecimalPrefixStyle.zeroX, result: "0xFF"),
        (value: Int64(255), style: HexadecimalPrefixStyle.sharp, result: "#FF")
    ])
    func int64HexString(tuple: (value: Int64, style: HexadecimalPrefixStyle, result: String)) async throws {
        #expect(tuple.value.hexString(prefixStyle: tuple.style) == tuple.result)
    }

    @Test(arguments: [
        (value: UInt(0), style: HexadecimalPrefixStyle.zeroX, result: "0x0"),
        (value: UInt(255), style: HexadecimalPrefixStyle.zeroX, result: "0xFF"),
        (value: UInt(255), style: HexadecimalPrefixStyle.sharp, result: "#FF")
    ])
    func uintHexString(tuple: (value: UInt, style: HexadecimalPrefixStyle, result: String)) async throws {
        #expect(tuple.value.hexString(prefixStyle: tuple.style) == tuple.result)
    }

    @Test(arguments: [
        (value: Int(0), style: HexadecimalPrefixStyle.zeroX, result: "0x0"),
        (value: Int(255), style: HexadecimalPrefixStyle.zeroX, result: "0xFF"),
        (value: Int(255), style: HexadecimalPrefixStyle.sharp, result: "#FF")
    ])
    func intHexString(tuple: (value: Int, style: HexadecimalPrefixStyle, result: String)) async throws {
        #expect(tuple.value.hexString(prefixStyle: tuple.style) == tuple.result)
    }
}
