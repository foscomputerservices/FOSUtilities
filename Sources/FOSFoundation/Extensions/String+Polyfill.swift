// String+Polyfill.swift
//
// Copyright © 2023 FOS Services, LLC. All rights reserved.
//

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

    /// A mutating version simpler version of the macOS 13+, iOS 16+ version for us on all swift versions
    ///
    /// - Parameters:
    ///   - pattern: A regex pattern to match
    ///   - replacement: The replacement of each regex matched string
    mutating func replace(pattern: String, with replacement: String = "") throws {
        self = try replacing(pattern: pattern, with: replacement)
    }
}
