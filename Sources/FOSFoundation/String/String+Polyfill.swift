// String+Polyfill.swift
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

public extension String {
    /// Replaces a RegEx with
    ///
    /// - Parameters:
    ///   - pattern: A regex pattern to match
    ///   - replacement: The replacement of each regex matched string
    func replacing(pattern: String, with replacement: String = "") throws -> String {
        try NSRegularExpression(pattern: pattern, options: .init())
            .stringByReplacingMatches(
                in: self,
                options: [],
                range: NSRange(startIndex..., in: self),
                withTemplate: replacement
            )
    }
}
