// OperationBusTests.swift
//
// Copyright 2025 FOS Computer Services, LLC
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

@testable import FOSMVVM
import Foundation
import Testing

// MARK: - SyncOperationBus Tests

@Suite("SyncOperationBus Tests")
struct SyncOperationBusTests {
    // MARK: Basic Functionality Tests

    @Test func invokeWithNoOperations() {
        let bus = SyncOperationBus<String>()
        // Should not crash when invoked with no operations
        var test = "test"
        bus.invoke(&test)
    }

    @Test func singleOperation() {
        let bus = SyncOperationBus<String>()
        var receivedValue: String?

        bus.addOperation { value in
            receivedValue = value
        }

        var test = "test"
        bus.invoke(&test)
        #expect(receivedValue == "test")
    }

    @Test func multipleOperations() {
        let bus = SyncOperationBus<Int>()
        var receivedValues: [Int] = []

        bus.addOperation { value in
            receivedValues.append(value * 2)
        }

        bus.addOperation { value in
            receivedValues.append(value * 3)
        }

        bus.addOperation { value in
            receivedValues.append(value * 4)
        }

        var testValue = 5
        bus.invoke(&testValue)
        #expect(receivedValues == [10, 15, 20])
    }

    @Test func operationsExecuteInOrder() {
        let bus = SyncOperationBus<Int>()
        var executionOrder: [Int] = []

        for i in 1...5 {
            bus.addOperation { _ in
                executionOrder.append(i)
            }
        }

        var testValue = 0
        bus.invoke(&testValue)
        #expect(executionOrder == [1, 2, 3, 4, 5])
    }

    // MARK: Mutable Data Tests

    @Test func mutableStructUpdate() {
        struct FormData {
            var name: String = ""
            var age: Int = 0
            var email: String = ""
        }

        let bus = SyncOperationBus<FormData>()

        bus.addOperation { formData in
            formData.name = "Alice"
        }

        bus.addOperation { formData in
            formData.age = 30
        }

        bus.addOperation { formData in
            formData.email = "alice@example.com"
        }

        var data = FormData()
        bus.invoke(&data)

        #expect(data.name == "Alice")
        #expect(data.age == 30)
        #expect(data.email == "alice@example.com")
    }

    @Test func multipleInvocations() {
        let bus = SyncOperationBus<Int>()
        var counter = 0

        bus.addOperation { value in
            counter += value
        }

        var value1 = 5
        bus.invoke(&value1)
        #expect(counter == 5)

        var value2 = 10
        bus.invoke(&value2)
        #expect(counter == 15)

        var value3 = 3
        bus.invoke(&value3)
        #expect(counter == 18)
    }

    // MARK: Edge Cases

    @Test func operationWithComplexType() {
        struct ComplexData {
            let items: [String]
            let metadata: [String: Int]
        }

        let bus = SyncOperationBus<ComplexData>()
        var receivedData: ComplexData?

        bus.addOperation { data in
            receivedData = data
        }

        var testData = ComplexData(
            items: ["one", "two", "three"],
            metadata: ["count": 3, "version": 1]
        )

        bus.invoke(&testData)

        #expect(receivedData?.items == ["one", "two", "three"])
        #expect(receivedData?.metadata["count"] == 3)
    }

    @Test func operationCapturingExternalState() {
        let bus = SyncOperationBus<String>()
        var externalCounter = 0

        bus.addOperation { message in
            externalCounter += message.count
        }

        var message1 = "hello"
        bus.invoke(&message1)
        #expect(externalCounter == 5)

        var message2 = "world"
        bus.invoke(&message2)
        #expect(externalCounter == 10)
    }
}

// MARK: - AsyncOperationBus Tests

@Suite("AsyncOperationBus Tests")
struct AsyncOperationBusTests {
    // MARK: Basic Functionality Tests

    @Test func invokeWithNoOperations() async {
        let bus = AsyncOperationBus<String>()
        // Should not crash when invoked with no operations
        await bus.invoke("test")
    }

    @Test func singleAsyncOperation() async {
        actor ValueHolder {
            var value: String?
            
            func setValue(_ newValue: String) {
                value = newValue
            }
            
            func getValue() -> String? {
                value
            }
        }
        
        let bus = AsyncOperationBus<String>()
        let holder = ValueHolder()

        bus.addOperation { value in
            await holder.setValue(value)
        }

        await bus.invoke("test")
        #expect(await holder.getValue() == "test")
    }

    @Test func multipleAsyncOperations() async {
        actor ValueCollector {
            var values: [Int] = []

            func append(_ value: Int) {
                values.append(value)
            }

            func getValues() -> [Int] {
                values.sorted()
            }
        }

        let bus = AsyncOperationBus<Int>()
        let collector = ValueCollector()

        bus.addOperation { value in
            await collector.append(value * 2)
        }

        bus.addOperation { value in
            await collector.append(value * 3)
        }

        bus.addOperation { value in
            await collector.append(value * 4)
        }

        await bus.invoke(5)
        let values = await collector.getValues()
        #expect(values.sorted() == [10, 15, 20])
    }

    @Test func operationsExecuteConcurrently() async {
        actor ExecutionTracker {
            var startTimes: [Int: Date] = [:]
            var endTimes: [Int: Date] = [:]

            func recordStart(_ id: Int) {
                startTimes[id] = Date()
            }

            func recordEnd(_ id: Int) {
                endTimes[id] = Date()
            }

            func checkConcurrency() -> Bool {
                // If operations ran concurrently, some should start before others end
                guard let secondStart = startTimes[2],
                      let firstEnd = endTimes[1] else {
                    return false
                }

                // Second operation should start before first one ends (with some tolerance)
                return secondStart <= firstEnd.addingTimeInterval(0.01)
            }
        }

        let bus = AsyncOperationBus<Void>()
        let tracker = ExecutionTracker()

        bus.addOperation { _ in
            await tracker.recordStart(1)
            try? await Task.sleep(for: .milliseconds(50))
            await tracker.recordEnd(1)
        }

        bus.addOperation { _ in
            await tracker.recordStart(2)
            try? await Task.sleep(for: .milliseconds(50))
            await tracker.recordEnd(2)
        }

        await bus.invoke(())

        let isConcurrent = await tracker.checkConcurrency()
        #expect(isConcurrent)
    }

    // MARK: Mutable Data Tests (Thread-Safe)

    @Test func threadSafeDataUpdate() async {
        final class FormData: Sendable {
            let name = MutexBox<String>("")
            let age = MutexBox<Int>(0)
            let email = MutexBox<String>("")
        }

        // Simple mutex implementation for testing
        final class MutexBox<T>: @unchecked Sendable {
            private var value: T
            private let lock = NSLock()

            init(_ value: T) {
                self.value = value
            }

            func withLock<R>(_ body: (inout T) -> R) -> R {
                lock.lock()
                defer { lock.unlock() }
                return body(&value)
            }

            func get() -> T {
                lock.lock()
                defer { lock.unlock() }
                return value
            }
        }

        let bus = AsyncOperationBus<FormData>()

        bus.addOperation { formData in
            formData.name.withLock { $0 = "Bob" }
        }

        bus.addOperation { formData in
            formData.age.withLock { $0 = 25 }
        }

        bus.addOperation { formData in
            formData.email.withLock { $0 = "bob@example.com" }
        }

        let data = FormData()
        await bus.invoke(data)

        #expect(data.name.get() == "Bob")
        #expect(data.age.get() == 25)
        #expect(data.email.get() == "bob@example.com")
    }

    @Test func multipleAsyncInvocations() async {
        actor Counter {
            var value = 0

            func add(_ amount: Int) {
                value += amount
            }

            func getValue() -> Int {
                value
            }
        }

        let bus = AsyncOperationBus<Int>()
        let counter = Counter()

        bus.addOperation { value in
            await counter.add(value)
        }

        await bus.invoke(5)
        #expect(await counter.getValue() == 5)

        await bus.invoke(10)
        #expect(await counter.getValue() == 15)

        await bus.invoke(3)
        #expect(await counter.getValue() == 18)
    }

    // MARK: Edge Cases

    @Test func operationWithSendableComplexType() async {
        struct ComplexData: Sendable {
            let items: [String]
            let metadata: [String: Int]
        }

        actor DataCollector {
            var receivedData: ComplexData?

            func store(_ data: ComplexData) {
                receivedData = data
            }

            func getData() -> ComplexData? {
                receivedData
            }
        }

        let bus = AsyncOperationBus<ComplexData>()
        let collector = DataCollector()

        bus.addOperation { data in
            await collector.store(data)
        }

        let testData = ComplexData(
            items: ["one", "two", "three"],
            metadata: ["count": 3, "version": 1]
        )

        await bus.invoke(testData)

        let received = await collector.getData()
        #expect(received?.items == ["one", "two", "three"])
        #expect(received?.metadata["count"] == 3)
    }

    @Test func asyncOperationWithDelay() async {
        actor TimeTracker {
            var completed = false

            func markComplete() {
                completed = true
            }

            func isComplete() -> Bool {
                completed
            }
        }

        let bus = AsyncOperationBus<Void>()
        let tracker = TimeTracker()

        bus.addOperation { _ in
            try? await Task.sleep(for: .milliseconds(100))
            await tracker.markComplete()
        }

        await bus.invoke(())

        // Should wait for operation to complete
        #expect(await tracker.isComplete())
    }

    @Test func sendableConstraintEnforced() async {
        // This test verifies that the Sendable constraint is working
        struct SendableData: Sendable {
            let value: String
        }

        actor ValueHolder {
            var value: String?
            
            func setValue(_ newValue: String) {
                value = newValue
            }
            
            func getValue() -> String? {
                value
            }
        }

        let bus = AsyncOperationBus<SendableData>()
        let holder = ValueHolder()

        bus.addOperation { data in
            await holder.setValue(data.value)
        }

        await bus.invoke(SendableData(value: "test"))
        #expect(await holder.getValue() == "test")
    }
}
