// TaskTests.swift
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

@Suite(.tags(.async, .extensions))
struct TaskTests {
    @Test func syncTask() throws {
        let startTime = Date()

        try Task.synchronous {
            try await Self.asyncFunc()
        }

        let endTime = Date()
        #expect(endTime.timeIntervalSince(startTime) > 1)
    }

    @Test func syncTaskPropagatesError() {
        #expect(throws: TestError.self) {
            try Task.synchronous {
                throw TestError.expected
            }
        }
    }

    @Test func syncTaskReturnsValue() throws {
        let value: Int = try Task.synchronous {
            try await Self.asyncValueFunc()
        }

        #expect(value == 42)
    }

    private static func asyncFunc() async throws {
        // 1.5 seconds
        try await Task.sleep(nanoseconds: UInt64(1500000000))
    }

    private static func asyncValueFunc() async throws -> Int {
        42
    }

    private enum TestError: Error {
        case expected
    }
}
