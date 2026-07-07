// ServerCertPinning.swift
//
// Copyright 2026 FOS Computer Services, LLC
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
import SwiftASN1
import X509
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// The SPKI-SHA256 **pin** of a certificate (RFC 7469 form): `base64(SHA256(SubjectPublicKeyInfo))`.
///
/// SPKI pinning hashes the certificate's public-key info — algorithm identifier + key bits — not the
/// whole certificate, so a pin survives a renewal that keeps the same key. A pin computed on the
/// client and on the server are equal iff they hash identical canonical SPKI DER.
///
/// The pin is an opaque digest; its only representation is the base64 string it wraps. It is
/// `Hashable` so it can be a member of a pin set (``MutualTLS/serverPins``) and encodes as a **bare
/// string** so pins ride a flat configuration/JSON value.
public struct SPKIPin: Hashable, Sendable, Codable, CustomStringConvertible {
    /// The base64-encoded `SHA256(SubjectPublicKeyInfo)` digest.
    public let base64: String

    public var description: String {
        base64
    }

    public init(base64: String) {
        self.base64 = base64
    }

    public init(from decoder: any Decoder) throws {
        self.base64 = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(base64)
    }
}

/// Computes the ``SPKIPin`` of an X.509 certificate.
public enum ServerCertPinning {
    /// The ``SPKIPin`` of the certificate encoded in `der`.
    ///
    /// - Parameter der: The DER-encoded X.509 certificate (e.g. a server leaf extracted from a
    ///   `SecTrust` via `SecCertificateCopyData`).
    /// - Returns: The certificate's ``SPKIPin``.
    /// - Throws: A parsing/serialization error if `der` is not a valid X.509 certificate.
    public static func spkiPin(ofCertificateDER der: Data) throws -> SPKIPin {
        try spkiPin(of: Certificate(derEncoded: Array(der)))
    }

    /// The ``SPKIPin`` of an already-parsed X.509 `Certificate` — for callers holding a
    /// `Certificate` rather than raw DER (e.g. a Vapor server verifying a TLS peer chain).
    ///
    /// - Returns: The certificate's ``SPKIPin``.
    /// - Throws: A serialization error if the public key cannot be serialized.
    public static func spkiPin(of certificate: Certificate) throws -> SPKIPin {
        // Serialize the SubjectPublicKeyInfo to canonical DER, then SHA256 + base64 (RFC 7469).
        // Canonical SPKI bytes are platform-independent, so a pin computed here matches one
        // computed anywhere else — client or server.
        var serializer = DER.Serializer()
        try serializer.serialize(certificate.publicKey)
        let digest = SHA256.hash(data: Data(serializer.serializedBytes))
        return SPKIPin(base64: Data(digest).base64EncodedString())
    }
}
