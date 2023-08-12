// String+Utilities.swift
//
// Copyright © 2023 FOS Services, LLC. All rights reserved.
//

import Foundation

public extension String {
    /// Returns the number of times that a string occurs  in ``String``
    ///
    /// - Parameter substring: The substring to locate
    func count(of substring: String) -> Int {
        components(separatedBy: substring).count - 1
    }

    private static let defaultRandomLetters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

    /// Generates a string with random number of characters
    ///
    /// - Parameters:
    ///   - length: Number of characters to return
    ///   - letters: A set of characters to derive the result characters from (default: [a-z,A-Z,0-9])
    static func randomString(length: Int, letters: String? = nil) -> String {
        let letters = letters ?? Self.defaultRandomLetters
        return String((0..<length).map { _ in letters.randomElement()! })
    }

    /// Returns a unique string (see NOTE)
    ///
    /// - NOTE: If compact == true, the result cannot be guaranteed
    ///     to be unique, but should be in smaller contexts
    ///
    /// - Parameter short: Generates a shorter unique string (default: false)
    static func unique(compact: Bool = false) -> String {
        guard !compact else {
            return String(UUID().uuidString.split(separator: "-").last!)
        }

        return UUID().uuidString
    }

    /// Returns a stable integer for the given `String`
    ///
    /// - See also: https://stackoverflow.com/a/43149500/608569
    @inlinable func stableUInt() -> UInt64 {
        var result = UInt64(5381)
        let buf = [UInt8](utf8)
        for b in buf {
            result = 127 * (result & 0x00FFFFFFFFFFFFFF) + UInt64(b)
        }

        return result
    }

    /// Given that the receiver is of the form "#FF" or "0xFF" convert to UInt64
    var intFromHex: UInt64? {
        guard !contains(where: { !($0.isHexDigit || $0 == "#" || $0 == "x") }) else { return nil }

        var hexInt: UInt64 = 0
        let scanner = Scanner(string: lowercased())
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: "#")
        scanner.scanHexInt64(&hexInt)
        return hexInt
    }

    /// Trims newlines and whitespaces from the receiver
    ///
    /// This can be helpful when cleaning user-provide input.
    func singleLineInput() -> String? {
        (isEmpty ? nil : self)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Converts the string from *CamelCase* to *snake_case*
    func snakeCased() -> String {
        var prevUpper = false

        return reduce("") { result, nextChar in
            var result = result

            if "A"..."Z" ~= nextChar {
                if !result.isEmpty, !prevUpper {
                    result += "_"
                }
                prevUpper = true
            } else {
                prevUpper = false
            }

            result += "\(nextChar.lowercased())"

            return result
        }
    }

    /// Converts the string from snake_case to CamelCase
    ///
    /// - Parameter firstUpper: Prescribes which case the initial character
    ///    should be; ``uppercased`` or ``lowercased`` (default is ``uppercased``)
    func camelCased(firstUpper: Bool = true) -> String {
        var toUpper = firstUpper

        return reduce("") { result, nextChar in
            var result = result

            if nextChar == "_" {
                toUpper = result.isEmpty ? firstUpper : true
            } else if toUpper {
                result += "\(nextChar.uppercased())"
                toUpper = false
            } else {
                result += "\(nextChar)"
            }

            return result
        }
    }

    /// Returns a `String` containing the characters described by ``NSRange``
    subscript(range: NSRange) -> String {
        self[range.location...(range.location + range.length - 1)]
    }

    /// Returns a `String` containing the characters described by *bounds*
    ///
    /// # Example
    ///
    /// ```swift
    /// "my string"[0...2] // "my "
    /// ```
    subscript(bounds: CountableClosedRange<Int>) -> String {
        String(self[index(startIndex, offsetBy: bounds.lowerBound)...index(startIndex, offsetBy: bounds.upperBound)])
    }

    /// Returns a `String` containing the characters described by *bounds*
    ///
    /// # Example
    ///
    /// ```swift
    /// "my string"[0..<2] // "my"
    /// ```
    subscript(bounds: CountableRange<Int>) -> String {
        let start = index(startIndex, offsetBy: bounds.lowerBound)
        let end = index(startIndex, offsetBy: bounds.upperBound)
        return String(self[start..<end])
    }

    func rot5() -> String {
        rotN(intervals: ["0"..."9"])
    }

    func rot13() -> String {
        rotN(intervals: ["A"..."Z", "a"..."z"])
    }

    func rot13and5() -> String {
        rotN(intervals: ["A"..."Z", "a"..."z", "0"..."9"])
    }

    func rot47() -> String {
        rotN(intervals: ["!"..."~"])
    }

    var tokenizeForURLQuery: String {
        Data(rot47().utf8)
            .base64EncodedString()
    }

    var unTokenizeFromURLQuery: String? {
        guard let data = Data(base64Encoded: self) else {
            return nil
        }

        return String(data: data, encoding: .utf8)?.rot47()
    }

    /// Ensures that the 1st character of the string is a ``lowercased`` letter
    func firstLowercased() -> String {
        prefix(1).lowercased() + dropFirst()
    }

    /// Ensures that the 1st character of the string is a ``uppercased`` letter
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
}

extension String: Identifiable {
    public var id: String { self }
}

private extension String {
    // Copied from here: https://stackoverflow.com/a/37759041/608569
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
