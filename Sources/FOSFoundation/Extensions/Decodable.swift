// Decodable.swift
//
// Copyright © 2023 FOS Services, LLC. All rights reserved.
//

import Foundation

public enum JSONError: Error {
    case error(message: String, failureReason: String)
}

public extension String {
    /// Converts the `String` to and instance of `T` from JSON string using `JSONDecoder`.defaultDecoder
    func fromJSON<T>() throws -> T where T: Decodable {
        guard let jsonData = data(using: .utf8), !jsonData.isEmpty else {
            throw JSONError.error(
                message: "Unable to convert the string to .utf8 data",
                failureReason: isEmpty ? "String is empty" : "Unknown"
            )
        }

        return try jsonData.fromJSON()
    }
}

public extension Data {
    /// Converts the `Data` to `T` from the JSON string encoded in
    /// `Data` using `JSONDecoder`.defaultDecoder
    ///
    /// - Parameter decoder: <#decoder description#>
    func fromJSON<T>(decoder: JSONDecoder? = nil) throws -> T where T: Decodable {
        try (decoder ?? JSONDecoder.defaultDecoder).decode(T.self, from: self)
    }
}
