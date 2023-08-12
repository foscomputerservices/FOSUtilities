// String+Crypto.swift
//
// Copyright © 2023 FOS Services, LLC. All rights reserved.
//

import Foundation

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

public extension String {
    #if os(iOS) || os(macOS) || os(Linux)

    // Encrypts the string using *sha256* encryption
    func sha256() -> String? {
        guard let data = data(using: .utf8) else { return nil }

        return SHA256.hash(data: data)
            .description
            .replacingOccurrences(of: "SHA256 digest: ", with: "")
    }
    #endif
}
