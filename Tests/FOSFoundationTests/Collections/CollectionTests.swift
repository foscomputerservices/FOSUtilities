// CollectionTests.swift
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

@Suite("Collection extension tests", .tags(.extensions))
struct CollectionTests {
    @Test func groupedBy() {
        let numbers = [1, 2, 3, 4, 5, 6]
        let groupedByParity = numbers.grouped { $0 % 2 == 0 }

        #expect(groupedByParity == [false: [1, 3, 5], true: [2, 4, 6]])
    }

    @Test func throttleExecute() async throws {
        let array = (0...20).map(\.self)
        let start = Date()
        var lastNum = 0

        let result = try await array.throttleExecute(rate: (quantity: 10, per: 0.5)) { num in
            lastNum = num

            return num
        }

        let stop = Date()
        #expect(lastNum == array.last!)
        #expect(result.count == array.count)
        #expect(stop.timeIntervalSince(start) > TimeInterval(array.count / 10) * 0.5)
    }

    @Test func throttleExecute_NoWork() async throws {
        let noWork1 = try await [].throttleExecute(rate: (quantity: 1, per: 1)) { $0 }
        #expect(noWork1.isEmpty)

        let noWork2 = try await [0, 1, 2].throttleExecute(rate: (quantity: -1, per: 1)) { $0 }
        #expect(noWork2.isEmpty)

        let noWork3 = try await [0, 1, 2].throttleExecute(rate: (quantity: 1, per: -1)) { $0 }
        #expect(noWork3.isEmpty)
    }
}
