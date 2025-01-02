// AsyncSemaphoreTests.swift
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

private nonisolated(unsafe) var maxCount = 0

@Suite("AsyncSemaphore Tests", .tags(.async), .serialized)
final class AsyncSemaphoreTests {
    @Test func singleExecution() async throws {
        let semaphore = AsyncSemaphore(maxConcurrentTasks: 1)
        maxCount = 0

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await Self.slowFunc(semaphore: semaphore)
            }
            group.addTask {
                await Self.slowFunc(semaphore: semaphore)
            }
            group.addTask {
                await Self.slowFunc(semaphore: semaphore)
            }
        }

        #expect(maxCount == 0)
    }

    @Test func multipleExecution() async throws {
        let semaphore = AsyncSemaphore(maxConcurrentTasks: 3)
        maxCount = 0

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await Self.slowFunc(semaphore: semaphore)
            }
            group.addTask {
                await Self.slowFunc(semaphore: semaphore)
            }
            group.addTask {
                await Self.slowFunc(semaphore: semaphore)
            }
        }

        #expect(maxCount == 3)
    }

    private static func slowFunc(semaphore: AsyncSemaphore) async {
        await semaphore.wait()
        defer {
            if maxCount == 1 {
                maxCount -= 1
            }
            Task { await semaphore.signal() }
        }

        maxCount += 1
        // 1 seconds
        try! await Task.sleep(nanoseconds: UInt64(1000000000))
    }
}
