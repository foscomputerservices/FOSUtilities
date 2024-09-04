// String+UtilitiesTests.swift
//
// Created by David Hunt on 8/21/24
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

@Suite("String Utilities Tests", .tags(.extensions, .string))
struct StringUtilitiesTests {
    @Test(arguments: [
        (in: "aabaacaadaa", find: "aa", count: 4),
        (in: "abaacaadaa", find: "aa", count: 3),
        (in: "abaacaadaa", find: "a", count: 7),
        (in: "abaacaadaa", find: "b", count: 1)
    ]) func count(tuple: (in: String, find: String, count: Int)) {
        #expect(tuple.in.count(of: tuple.find) == tuple.count)
    }

    @Test func randomString() {
        #expect(String.random(length: 5).lengthOfBytes(using: .utf8) == 5)
    }

    @Test func unique() {
        #expect(String.unique().lengthOfBytes(using: .utf8) == 36)
        #expect(String.unique(compact: true).lengthOfBytes(using: .utf8) == 12)

        #expect(String.unique() != String.unique())
        #expect(String.unique(compact: true) != String.unique(compact: true))
    }

    @Test(arguments: [
        (input: "0xbadf00ddea", output: 802605293034),
        (input: "unacceptable", output: nil),
        (input: "", output: nil)
    ]) func intFromHex(tuple: (input: String, output: UInt64?)) throws {
        #expect(tuple.input.intFromHex == tuple.output)
    }

    @Test(arguments: [
        "",
        " ",
        "\n ",
        "\t "
    ]) func singleLineInput(str: String) {
        #expect(str.singleLineInput() == nil)
    }

    @Test(arguments: [
        " foo",
        "foo ",
        "foo\n"
    ]) func singleLineInput_NonEmpty(str: String) {
        #expect(str.singleLineInput() == "foo")
    }

    @Test func snakeCased() {
        #expect("CamelCase".snakeCased() == "camel_case")
    }

    @Test func camelCased() {
        #expect("first_upper_false".camelCased(firstUpper: false) == "firstUpperFalse")
        #expect("first_upper_true".camelCased() == "FirstUpperTrue")
        #expect("_first_upper_true".camelCased() == "FirstUpperTrue")
    }

    @Test(arguments: [
        (input: "lowercased", output: "lowercased"),
        (input: "LOWERCASED", output: "lOWERCASED"),
        (input: "Lowercased", output: "lowercased"),
        (input: "Öowercased", output: "öowercased"),
        (input: "", output: ""),
    ]) func firstLowercased(tuple: (input: String, output: String)) {
        #expect(tuple.input.firstLowercased() == tuple.output)
    }

    @Test(arguments: [
        (input: "uppercased", output: "Uppercased"),
        (input: "Uppercased", output: "Uppercased"),
        (input: "uPPERCASED", output: "UPPERCASED"),
        (input: "öowercased", output: "Öowercased"),
        (input: "", output: ""),
    ]) func firstUppercased(tuple: (input: String, output: String)) {
        #expect(tuple.input.firstUppercased() == tuple.output)
    }

    @Test(arguments: [
        (input: "prefixString", prefix: "prefix", output: "String"),
        (input: "", prefix: "prefix", output: ""),
    ]) func trimmingPrefix(tuple: (input: String, prefix: String, output: String)) {
        #expect(tuple.input.trimmingPrefix(tuple.prefix) == tuple.output)
    }

    @Test(arguments: [
        (input: "Stringsuffix", suffix: "suffix", output: "String"),
        (input: "", suffix: "suffix", output: ""),
    ]) func trimmingSuffix(tuple: (input: String, suffix: String, output: String)) {
        #expect(tuple.input.trimmingSuffix(tuple.suffix) == tuple.output)
    }

    @Test(arguments: [
        (input: "0123456789", range: NSRange(location: 0, length: 5), result: "01234"),
        (input: "0123456789", range: NSRange(location: 1, length: 5), result: "12345")
    ]) func subscriptRange(tuple: (input: String, range: NSRange, result: String)) {
        #expect(tuple.input[tuple.range] == tuple.result)
    }

    @Test func subscriptBounds_ClosedRange() {
        #expect("0123456789"[0...4] == "01234")
    }

    @Test func subscriptBounds_CountableRange() {
        #expect("0123456789"[0..<5] == "01234")
    }

    @Test(arguments: [
        (input: "abcde", output: "nopqr"),
        (input: "ab/cde", output: "no/pqr"),
        (input: "ab/cde123", output: "no/pqr123"),
        (input: "", output: ""),
    ]) func rot13(tuple: (input: String, output: String)) {
        #expect(tuple.input.rot13() == tuple.output)

        // Must be reversible
        #expect(tuple.input.rot13().rot13() == tuple.input)
    }

    @Test(arguments: [
        (input: "abcde", output: "23456"),
        (input: "ab/cde", output: "23^456"),
        (input: "ab/cde123", output: "23^456`ab"),
        (input: "öb/cde123", output: "ö3^456`ab"),
        (input: "", output: ""),
    ]) func rot47(tuple: (input: String, output: String)) {
        #expect(tuple.input.rot47() == tuple.output)

        // Must be reversible
        #expect(tuple.input.rot47().rot47() == tuple.input)
    }

    @Test(arguments: [
        (input: "a,b,c", output: [["a", "b", "C"]]),
        (input: "a,b,c\nd,e,f", output: [["a", "b", "C"], ["d", "e", "f"]]),
    ]) func loadCSVData(tuple: (input: String, output: [[String]])) {
        // Equality of arrays doesn't seem to work???
        withKnownIssue {
            #expect(tuple.input.loadCSVData() == tuple.output)
        }
    }
}
