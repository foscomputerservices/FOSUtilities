// JSONDecoder.swift
//
// Copyright © 2023 FOS Services, LLC. All rights reserved.
//

import Foundation

public enum JSONDecoderError: Error {
    case unknownFormat(_ dateString: String)
}

public extension JSONDecoder {
    @nonobjc static let defaultDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder -> Date in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            if let date = DateFormatter.JSONDateTimeFormatter.date(from: dateString) {
                return date
            }

            if let date = DateFormatter.ISO8601Formatter.date(from: dateString) {
                return date
            }

            if let date = DateFormatter.dateFormatter.date(from: dateString) {
                return date
            }

            if let date = DateFormatter.dateTimeFormatter.date(from: dateString) {
                return date
            }

            throw JSONDecoderError.unknownFormat(dateString)
        }

        return decoder
    }()
}
