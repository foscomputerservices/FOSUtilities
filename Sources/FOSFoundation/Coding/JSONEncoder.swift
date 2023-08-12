// JSONEncoder.swift
//
// Copyright © 2023 FOS Services, LLC. All rights reserved.
//

import Foundation

public extension JSONEncoder {
    static var defaultEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(DateFormatter.JSONDateTimeFormatter)
        return encoder
    }
}
