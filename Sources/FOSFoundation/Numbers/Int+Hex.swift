// Int+Hex.swift
//
// Created by David Hunt on 8/24/24
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

/// Describes the style of the Hexadecimal **String** generated
public enum HexadecimalPrefixStyle: Codable, Sendable {
    /// Generates a hexadecimal **String** prefixed with "0x" (e.g. "0xFF")
    case zeroX

    /// Generates a hexadecimal **String** prefixed with "#"  (e.g., #FF)
    case sharp

    var prefix: String {
        switch self {
        case .zeroX: "0x"
        case .sharp: "#"
        }
    }
}

public extension UInt64 {
    /// - Returns: A hexadecimal representation of the value
    ///
    /// ## Example:
    ///
    /// ```swift
    /// print(256.hexString()) // Prints: 0xFF
    /// ```
    ///
    /// - Parameters:
    ///   - prefixStyle: The ``HexadecimalPrefixStyle`` of the generated
    ///      **String** (default: .zeroX)
    func hexString(prefixStyle: HexadecimalPrefixStyle = .zeroX) -> String {
        .init(format: "\(prefixStyle.prefix)%lX", self)
    }
}

public extension Int64 {
    /// - Returns: A hexadecimal representation of the value
    ///
    /// ## Example:
    ///
    /// ```swift
    /// print(256.hexString()) // Prints: 0xFF
    /// ```
    ///
    /// - Parameters:
    ///   - prefixStyle: The ``HexadecimalPrefixStyle`` of the generated
    ///      **String** (default: .zeroX)
    func hexString(prefixStyle: HexadecimalPrefixStyle = .zeroX) -> String {
        UInt64(self).hexString(prefixStyle: prefixStyle)
    }
}

public extension UInt {
    /// - Returns: A hexadecimal representation of the value
    ///
    /// ## Example:
    ///
    /// ```swift
    /// print(256.hexString()) // Prints: 0xFF
    /// ```
    ///
    /// - Parameters:
    ///   - prefixStyle: The ``HexadecimalPrefixStyle`` of the generated
    ///      **String** (default: .zeroX)
    func hexString(prefixStyle: HexadecimalPrefixStyle = .zeroX) -> String {
        UInt64(self).hexString(prefixStyle: prefixStyle)
    }
}

public extension Int {
    /// - Returns: A hexadecimal representation of the value
    ///
    /// ## Example:
    ///
    /// ```swift
    /// print(256.hexString()) // Prints: 0xFF
    /// ```
    ///
    /// - Parameters:
    ///   - prefixStyle: The ``HexadecimalPrefixStyle`` of the generated
    ///      **String** (default: .zeroX)
    func hexString(prefixStyle: HexadecimalPrefixStyle = .zeroX) -> String {
        UInt64(self).hexString(prefixStyle: prefixStyle)
    }
}
