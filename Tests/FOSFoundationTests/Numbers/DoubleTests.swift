// DoubleTests.swift
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

@Suite("Double Extension Tests", .tags(.extensions))
struct DoubleTests {
    @Test(arguments: [
        (input: 1.1234567, places: 0, output: 1.0),
        (input: 1.1234567, places: 2, output: 1.12),
        (input: 1.1234567, places: 4, output: 1.1235),
        (input: 1.1234567, places: 5, output: 1.12346)
    ]) func rounded(tuple: (input: Double, places: Int, output: Double)) {
        #expect(tuple.input.rounded(toPlaces: tuple.places) == tuple.output)
    }
}
