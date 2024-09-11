// String+Utilities.swift
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

public extension String {
    /// Returns the number of times that a string occurs  in **String**
    ///
    /// ## Example
    ///
    /// ```swift
    /// print("aabaacaadaa".count(of: "aa")) // Prints: 4
    /// ```
    ///
    /// - Parameter substring: The substring to locate
    func count(of substring: String) -> Int {
        components(separatedBy: substring).count - 1
    }

    private static let defaultRandomLetters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

    /// Generates a string with random number of characters
    ///
    /// ## Example
    ///
    /// ```swift
    /// print(String.random(length: 5)) // Prints: <random 5 chars>
    /// ```
    ///
    /// - Parameters:
    ///   - length: Number of characters to return
    ///   - letters: A set of characters to derive the result characters from (default: [a-z,A-Z,0-9])
    static func random(length: Int, letters: String? = nil) -> String {
        let letters = letters ?? Self.defaultRandomLetters
        return String((0..<length).map { _ in letters.randomElement()! })
    }

    /// Returns a unique string
    ///
    /// The implementation uses **UUID** to generate a unique string.  The *compact* case
    /// uses just the right-most sector of the **UUID**.
    ///
    /// ## Example
    ///
    /// ```swift
    /// print(String.unique()) // Prints: 2F5A06BD-00D1-48D7-9EA5-857E51D2271F
    /// print(String.unique(compact: true)) // Prints: 857E51D2271F
    /// ```
    ///
    /// - NOTE: If compact == true, the result cannot be guaranteed
    ///     to be globally unique, but should be unique in smaller contexts
    ///
    /// - Parameter compact: Generates a shorter unique string (default: false)
    @inlinable static func unique(compact: Bool = false) -> String {
        let result = UUID().uuidString

        guard !compact else {
            return String(result.split(separator: "-").last!)
        }

        return result
    }

    /// Given that the **String** is of the form "#FF" or "0xFF" convert to UInt64
    ///
    /// ## Example:
    ///
    /// ```swift
    /// let uintValue = "0xbadf00ddea".intFromHex
    /// print(uintValue == nil ? "nil" : uintValue!)
    ///
    /// // Result: 802605293034
    /// ```
    ///
    /// - Note: The algorithm is case insensitive.
    ///
    /// - Returns: The value of the **String** if it can be converted from hex, **nil** otherwise
    var intFromHex: UInt64? {
        guard !isEmpty, !contains(where: { !($0.isHexDigit || $0 == "#" || $0 == "x" || $0 == "X") }) else {
            return nil
        }

        var hexInt: UInt64 = 0
        let scanner = Scanner(string: lowercased())
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: "#")
        scanner.scanHexInt64(&hexInt)
        return hexInt
    }

    /// Trims newlines and whitespaces from the *beginning* **and** *ending* of the **String**
    ///
    /// This can be helpful when cleaning user-provide input.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let userInput = textField.singleLineInput()
    /// print(userInput ?? "Please enter some text")
    ///
    /// // Prints user's input with no spaces or newlines or message
    /// ```
    ///
    /// - Note: This function also converts **empty** **String**s to **nil**
    func singleLineInput() -> String? {
        guard !isEmpty else {
            return nil
        }

        let result = trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    /// Converts the string from *CamelCase* to *snake_case*
    ///
    /// ## Example
    ///
    /// ```swift
    /// print("CamelCase") // Prints: camel_case
    /// ```
    ///
    /// - Note: This method only works with chars "A"..."Z"
    func snakeCased() -> String {
        var wasUpper = false

        return reduce("") { result, nextChar in
            var result = result

            if "A"..."Z" ~= nextChar {
                if !result.isEmpty, !wasUpper {
                    result += "_"
                }
                wasUpper = true
            } else {
                wasUpper = false
            }

            return result + nextChar.lowercased()
        }
    }

    /// Converts the string from snake_case to CamelCase or camelCase
    ///
    /// ## Example
    ///
    /// ```swift
    /// print("first_upper_true".camelCased())
    /// // Prints: FirstUpperTrue
    ///
    /// print("first_upper_false".camelCased(firstUpper: false))
    /// // Prints: firstUpperFalse
    /// ```
    ///
    /// - Parameters:
    ///   - firstUpper: True indicates that the first character should be *upper cased* (default: **true**)
    func camelCased(firstUpper: Bool = true) -> String {
        var nextUpper = firstUpper

        return reduce("") { result, nextChar in
            var result = result

            if nextChar == "_" {
                nextUpper = result.isEmpty ? firstUpper : true
            } else if nextUpper {
                result += nextChar.uppercased()
                nextUpper = false
            } else {
                result += "\(nextChar)"
            }

            return result
        }
    }

    // MARK: Range Support

    /// **CountableRange** support for **String**
    ///
    /// # Example
    ///
    /// ```swift
    /// "0123456789"[0..<5] // "01234"
    /// ```
    ///
    /// - Returns: a `String` containing the characters described by *bounds*
    subscript(bounds: CountableRange<Int>) -> String {
        String(self[index(startIndex, offsetBy: bounds.lowerBound)..<index(startIndex, offsetBy: bounds.upperBound)])
    }

    /// **CountableClosedRange** support for **String**
    ///
    /// # Example
    ///
    /// ```swift
    /// "my string"[0...2] // "my "
    /// ```
    ///
    /// - Returns: a `String` containing the characters described by *bounds*
    subscript(bounds: CountableClosedRange<Int>) -> String {
        String(self[index(startIndex, offsetBy: bounds.lowerBound)...index(startIndex, offsetBy: bounds.upperBound)])
    }

    /// **NSRange** support for **String** via a *subscript*
    ///
    /// ## Example
    ///
    /// ```swift
    /// let range = NSRange(location: 0, length: 5)
    /// print("0123456789"[range]) // Prints: 01234
    /// ```
    ///
    /// - Returns: a `String` containing the characters described by **NSRange**
    subscript(range: NSRange) -> String {
        self[range.location...(range.location + range.length - 1)]
    }

    // MARK: Upper/Lower/Prefix/Suffix Support

    /// Ensures that the 1st character of the string is a lowercased letter
    ///
    /// ```swift
    /// print("LOWER".firstLowercased())
    ///
    /// // Prints: lOWER
    /// ```
    func firstLowercased() -> String {
        prefix(1).lowercased() + dropFirst()
    }

    /// Ensures that the 1st character of the string is a uppercased letter
    ///
    /// ```swift
    /// print("upper".firstUppercased())
    ///
    /// // Prints: Upper
    /// ```
    func firstUppercased() -> String {
        prefix(1).uppercased() + dropFirst()
    }

    /// Removes *prefix* from the beginning of the string if it exits
    func trimmingPrefix(_ prefix: String) -> String {
        guard hasPrefix(prefix) else { return self }
        return String(dropFirst(prefix.count))
    }

    /// Removes *suffix* from the end of the string if it exits
    func trimmingSuffix(_ suffix: String) -> String {
        guard hasSuffix(suffix) else { return self }
        return String(dropLast(suffix.count))
    }

    // MARK: Rotations

    /// *Rotates* the string 13 characters to the *right*
    ///
    /// A trivial obfuscation technique simply to make strings
    /// less legible.  To *undo* the rotation, rotate it a second time.
    ///
    /// ```swift
    /// print("abc".rot13()) // Prints: nop
    /// print("abc.rot13().rot13()) // Prints: abc
    /// ```
    ///
    /// - Note: This is obfuscation, **NOT** encryption.
    ///
    /// - See also:  **obfuscate** and **reveal** extension methods
    func rot13() -> String {
        rotN(intervals: ["A"..."Z", "a"..."z"])
    }

    /// *Rotates* the string 47 characters to the *right*
    ///
    /// A trivial obfuscation technique simply to make strings
    /// less legible.  To *undo* the rotation, rotate it a second time.
    ///
    /// ```swift
    /// print("abc".rot13()) // Prints: 234
    /// print("abc.rot13().rot13()) // Prints: abc
    /// ```
    ///
    /// - Note: This is obfuscation, **NOT** encryption.
    ///
    /// - See also:  **obfuscate** and **reveal** extension methods
    func rot47() -> String {
        rotN(intervals: ["!"..."~"])
    }

    // MARK: CSV Support

    /// Interprets the **String** as a '\n' separated string for rows and ',' for columns
    ///
    /// - NOTE: The processing is *trivial* and there is **no** support for escaping the delimiters.
    func loadCSVData() -> [[String]] {
        components(separatedBy: "\n").map {
            $0.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
}

private extension String {
    /// Copied from [StackOverflow](https://stackoverflow.com/a/37759041/608569)
    func rotN(_ unicodeScalar: UnicodeScalar, intervals: [ClosedRange<UnicodeScalar>]) -> Character {
        var result = unicodeScalar.value

        for interval in intervals {
            let half = (interval.upperBound.value - interval.lowerBound.value + 1) / 2
            let halfway = UnicodeScalar(interval.lowerBound.value + half)!

            switch unicodeScalar {
            case interval.lowerBound..<halfway:
                result += half
            case halfway...interval.upperBound:
                result -= half
            default:
                break
            }
        }

        return Character(UnicodeScalar(result)!)
    }

    func rotN(intervals: [ClosedRange<UnicodeScalar>]) -> String {
        String(unicodeScalars.map { rotN($0, intervals: intervals) })
    }
}
