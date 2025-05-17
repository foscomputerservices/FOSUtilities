// String+Crypto.swift
//
// Copyright 2024 FOS Computer Services, LLC
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

#if (os(Linux) && canImport(Crypto)) || canImport(CryptoKit)

#if canImport(CryptoKit)
import CryptoKit
#endif
#if os(Linux) && canImport(Crypto)
import Crypto
#endif

public extension String {
    /// Encrypts the string using [**SHA-256** encryption](https://w.wiki/KgC)
    func sha256() -> String {
        SHA256.hash(data: Data(utf8))
            .description
            .replacingOccurrences(of: "SHA256 digest: ", with: "")
    }

    /// Encrypts the **String** using [**HMAC SHA-256 encrypting**](https://w.wiki/8Bbj)
    ///
    /// - Parameter key: A secret key used to encrypt the **String**
    /// - Returns: The **String** encoding for HMAC binary data
    func hmacSha256(key: String) -> String {
        hmacSha256Data(key: key)
            .map { String(format: "%02hhx", $0) }
            .joined()
    }

    /// Encrypts the **String** using [**HMAC SHA-256 encrypting**](https://w.wiki/8Bbj)
    ///
    /// - Parameter key: A secret key used to encrypt the **String**
    /// - Returns: The binary encryption of the input **String**
    func hmacSha256Data(key: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(
            for: Data(utf8),
            using: SymmetricKey(data: Data(key.utf8))
        ))
    }
}

#endif
