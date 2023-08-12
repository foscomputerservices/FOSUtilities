// Encodable.swift
//
// Copyright © 2023 FOS Services, LLC. All rights reserved.
//

import Foundation

public extension Encodable {
    /// Converts the `Encodable` to a JSON string
    ///
    /// - Parameter encoder: The ``JSONEncoder`` to use to encode the receiver to a
    ///   ``String`` (default: ``JSONEncoder``.defaultEncoder)
    func toJSON(encoder: JSONEncoder? = nil) throws -> String {
        guard let result = try String(data: toJSONData(encoder: encoder), encoding: .utf8) else {
            throw JSONError.error(
                message: "Unable convert toJSONData to a String???",
                failureReason: "Unknown"
            )
        }

        return result
    }

    /// Converts the `Encodable` to a JSON string encoded in `Data`
    ///
    /// - Parameter encoder: The ``JSONEncoder`` to use to encode the receiver to a
    ///   ``String`` (default: ``JSONEncoder``.defaultEncoder)
    func toJSONData(encoder: JSONEncoder? = nil) throws -> Data {
        try (encoder ?? JSONEncoder.defaultEncoder).encode(self)
    }
}
