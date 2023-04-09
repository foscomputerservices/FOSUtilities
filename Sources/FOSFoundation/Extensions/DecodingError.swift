// DecodingError.swift
//
// Copyright © 2023 FOS Services, LLC. All rights reserved.
//

import Foundation

public extension DecodingError {
    var localizedDescription: String {
        let message: String
        switch self {
        case .dataCorrupted(let context):
            message = "Data Corrupted: \(context.codingPath) - \(context.debugDescription)"
        case .keyNotFound(let key, let context):
            message = "Key Not Found: \(key) - \(context.codingPath) - \(context.debugDescription)"
        case .typeMismatch(let type, let context):
            message = "Type Mismatch: \(type) - \(context.codingPath) - \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            message = "Value Not Found: \(type) - \(context.codingPath) - \(context.debugDescription)"
        @unknown default:
            message = "Unknown **new** error"
        }

        return message
    }
}
