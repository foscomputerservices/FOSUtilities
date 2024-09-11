// Array.swift
//
// Created by David Hunt on 9/4/24
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

import Foundation

public extension Array {
    /// Adds two arrays together and returns the result
    ///
    /// This overload allows for *rhs* to be nil, in which case *lhs* will be the result.
    ///
    /// - Parameters:
    ///   - lhs: The base **Array** to be added to
    ///   - rhs: An optional **Array** containing elements to add to the end of *lhs*
    ///
    /// - Returns: An **Array** with *rhs*'s elements appended to the end of *lhs*
    static func + (lhs: [Element], rhs: [Element]?) -> [Element] {
        guard let rhs else { return lhs }

        return lhs + rhs
    }

    /// Appends the elements of one **Array** to the other
    ///
    /// This overload allows for *rhs* to be nil, in which case nothing changes.
    ///
    /// - Parameters:
    ///   - lhs: The base **Array** to be added to
    ///   - rhs: An optional **Array** containing elements to add to the end of *lhs*
    static func += (lhs: inout [Element], rhs: [Element]?) {
        guard let rhs else { return }

        lhs += rhs
    }

    /// Safely lookup an element in an **Array**
    ///
    /// Allows for looking up an element at an index in an array even if that index doesn't exist.
    /// If the element is missing, **nil** is returned.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let array = [0, 1, 2]
    /// print(array[safe: 2] ?? "nil") // Prints: 2
    /// print(array[safe: 4] ?? "nil") // Prints: nil
    /// ```
    /// - Returns: The **Element** at index *safe* if the index exists in the array, **nil** otherwise.
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }

        return self[index]
    }
}
