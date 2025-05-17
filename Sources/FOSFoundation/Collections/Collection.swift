// Collection.swift
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

import Foundation

public extension Collection {
    /// Groups the elements of the sequence into a dictionary
    ///
    /// The keys are determined by the provided criteria, and the values are arrays of
    /// elements that match each key.
    ///
    /// ## Example
    /// ```swift
    /// let numbers = [1, 2, 3, 4, 5, 6]
    /// let groupedByParity = numbers.grouped { $0 % 2 == 0 }
    /// // groupedByParity is now [false: [1, 3, 5], true: [2, 4, 6]]
    /// ```
    ///
    /// - Note: The order of elements within each group is preserved from the
    ///    original sequence.
    ///
    /// - Complexity: O(n), where n is the number of elements in the sequence.
    ///
    /// - Parameter criteria: A closure that takes an element of the sequence as
    ///    its argument and returns a value of type `T` that represents the key for grouping
    ///    the element.
    ///
    /// - Returns: A dictionary where each key is a value returned by the `criteria`
    ///   closure, and the associated value is an array of elements that correspond to that key.
    ///
    /// - Credit: [Fernando Martín Ortiz](https://medium.com/ios-os-x-development/little-snippet-group-by-in-swift-3-5be0a06307db)
    func grouped<T>(by criteria: (Element) -> T) -> [T: [Element]] {
        var groups = [T: [Element]]()
        for element in self {
            let key = criteria(element)
            if groups.index(forKey: key) == nil {
                groups[key] = [Element]()
            }
            groups[key]?.append(element)
        }
        return groups
    }

    /// Restricts execution of *aFunc* over a **Collection** to a given rate
    ///
    /// Iterates over  the **Collection**'s **Element**s passing each element to *aFunc*.  *aFunc *
    /// is called no more often than *rate.quantity* per *rate.per*.
    ///
    /// ```swift
    /// struct MyData: Decodable {}
    /// let loadURLS = Array<URL>()
    ///
    /// // Executes fetch no more than 20 times every 2 seconds
    /// let myData = try await loadURLS.throttleExecute(
    ///     rate: (quantity: 20, per: 2)
    /// ) { url in
    ///     try await url.fetch() as MyData
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - rate: The maximum rate at which *aFunc* is called
    ///   - aFunc: A function to execute over each **Element** of the **Collection**
    func throttleExecute<ResultValue>(rate: (quantity: Int, per: TimeInterval), aFunc: (Element) async throws -> ResultValue) async throws -> [ResultValue] {
        guard !isEmpty, rate.quantity > 0, rate.per > 0 else { return [] }

        var result = [ResultValue]()

        let rateTimeInterval = rate.per
        var batchCounter = rate.quantity
        var batchStartTime = Date.now
        var elements = Array(self)

        repeat {
            if batchCounter == 0 {
                let start = batchStartTime.timeIntervalSince1970
                let now = Date.now.timeIntervalSince1970
                let sleepTime = rateTimeInterval - (now - start)
                try await sleepTime.sleep()

                batchCounter = rate.quantity
                batchStartTime = .now
            }

            try await result.append(aFunc(elements[0]))

            elements.remove(at: 0)
            batchCounter -= 1
        } while !elements.isEmpty

        return result
    }
}

private extension TimeInterval {
    func sleep() async throws {
        try await Task.sleep(nanoseconds: UInt64(self * Double(1000000000)))
    }
}
