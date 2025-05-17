// String+Obfuscation.swift
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
    /// Obfuscates a **String** so that its value is not immediately apparent
    ///
    /// While obfuscation is not an encryption technology, the string will not be easily
    /// discernible as readable text.  Additionally the string will be [Base64](https://w.wiki/ZmK)
    /// encoded so that it can easily be transmitted as a [URL Query](https://w.wiki/3qgc) string.
    ///
    /// ## Example
    ///
    /// ```swift
    /// print("I am a string".obfuscate) // Prints: eCAyPiAyIERFQzo/OA==
    /// ```
    ///
    /// - See also: *reveal*
    var obfuscate: String {
        Data(rot47().utf8)
            .base64EncodedString()
    }

    /// Removes the obfuscation from a string
    ///
    /// ## Example
    ///
    /// ```swift
    /// print("I am a string".obfuscate.reveal) // Prints: I am a string
    /// ```
    ///
    /// - Returns: The original string before obfuscation, or nil if the string is not
    ///   in the proper format (i.e., not previously obfuscated)
    ///
    /// - See also: *obfuscate*
    var reveal: String? {
        guard let data = Data(base64Encoded: self) else {
            return nil
        }

        return String(data: data, encoding: .utf8)?.rot47()
    }
}
