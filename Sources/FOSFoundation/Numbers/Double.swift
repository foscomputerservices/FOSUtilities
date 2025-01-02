// Double.swift
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

import Foundation

public extension Double {
    /// Rounds the **Double** to the number of decimal places
    ///
    /// ## Example
    ///
    /// ```swift
    /// (1.1234567).rounded(toPlaces: 0) // 1
    /// (1.1234567).rounded(toPlaces: 2) // 1.12
    /// (1.1234567).rounded(toPlaces: 4) // 1.1235
    /// (1.1234567).rounded(toPlaces: 5) // 1.12346
    /// ```
    ///
    /// - Parameter places: The number of decimal places to round to
    /// - Returns: The rounded number
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
