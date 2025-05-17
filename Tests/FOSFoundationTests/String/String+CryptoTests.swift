// String+CryptoTests.swift
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

#if (os(Linux) && canImport(Crypto)) || canImport(CryptoKit)

#if canImport(CryptoKit)
import CryptoKit
#endif
#if os(Linux) && canImport(Crypto)
import Crypto
#endif

import FOSFoundation
import Foundation
import Testing

@Suite("String Crypto Tests", .tags(.extensions, .string))
struct StringCryptoTests {
    @Test func sha256() {
        #expect("foo".sha256() == "foo".sha256())
        #expect("foo".sha256() != "bar".sha256())
        #expect("foo".sha256() != "foo")
    }

    @Test func hmacSha256() {
        #expect("foo".hmacSha256(key: "abc123") == "foo".hmacSha256(key: "abc123"))
        #expect("foo".hmacSha256(key: "abc123") != "foo".hmacSha256(key: "123abc"))
        #expect("foo".hmacSha256(key: "abc123") != "bar".hmacSha256(key: "abc123"))
        #expect("foo".hmacSha256(key: "abc123") != "foo")
    }
}
#endif
