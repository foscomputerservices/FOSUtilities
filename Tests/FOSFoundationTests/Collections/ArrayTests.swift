// ArrayTests.swift
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

import FOSFoundation
import Foundation
import Testing

@Suite("Array extension tests", .tags(.extensions))
struct ArrayTests {
    @Test(arguments: [
        (lhs: [0, 1], rhs: [2, 3], expected: [0, 1, 2, 3]),
        (lhs: [0, 1], rhs: nil, expected: [0, 1])
    ]) func add(tuple: (lhs: [Int], rhs: [Int]?, expected: [Int])) {
        let result = tuple.lhs + tuple.rhs

        #expect(result.count == tuple.expected.count)
        #expect(result == tuple.expected)
    }

    @Test(arguments: [
        (lhs: [0, 1], rhs: [2, 3], expected: [0, 1, 2, 3]),
        (lhs: [0, 1], rhs: nil, expected: [0, 1])
    ]) func addInline(tuple: (lhs: [Int], rhs: [Int]?, expected: [Int])) {
        var lhs = tuple.lhs
        lhs += tuple.rhs

        #expect(lhs.count == tuple.expected.count)
        #expect(lhs == tuple.expected)
    }

    @Test func safeAccess() {
        let array = [0, 1, 2]
        #expect(array[safe: 0] == 0)
        #expect(array[safe: 2] == 2)
        #expect(array[safe: 4] == nil)
        #expect(array[safe: -1] == nil)
    }
}
