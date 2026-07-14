// CredentialRejectedError.swift
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

/// The error thrown when a protected route rejects the request's credential
///
/// Routes grouped behind `ClientCredentialMiddleware` verify the presented
/// credential before the operation runs. When verification rejects the
/// request, this error crosses the wire and is rethrown by
/// ``ServerRequest/processRequest(mvvmEnv:)`` — catch it to recover:
///
/// ```swift
/// do {
///     try await request.processRequest(mvvmEnv: mvvmEnv)
/// } catch let error as CredentialRejectedError {
///     switch error.code {
///     case .missing: break // no credential was presented — check the
///                          // MVVMEnvironment's clientCredentialProvider
///     case .invalid: break // presented but refused — refresh the credential
///                          // and retry (safe: the operation never ran)
///     }
/// }
/// ```
///
/// The rejection happens **before** the operation runs, so retrying after
/// recovery never duplicates the operation's effects.
///
/// This error always throws to the call site — it is never routed to
/// ``MVVMEnvironment/requestErrorHandler``.
public struct CredentialRejectedError: ServerRequestError {
    /// Why the credential seam rejected the request
    ///
    /// `.missing` — no credential accompanied the request; typically the client
    /// has no `ClientCredentialProvider` configured (or it returned no headers).
    /// `.invalid` — a credential was presented and the server's verifier refused
    /// it; refresh the credential and retry.
    public enum Code: String, Codable, Sendable {
        case missing
        case invalid
    }

    /// Why the request was rejected
    public let code: Code

    /// The authentication challenge the verifier answers with (for example
    /// `"Bearer"`), used server-side to dress the response's
    /// `WWW-Authenticate` header. Never crosses the wire — always `nil` on
    /// a decoded value.
    public let challenge: String?

    /// Creates the rejection thrown by a `ServerCredentialVerifier`
    ///
    /// - Parameters:
    ///   - code: Why the request was rejected
    ///   - challenge: The scheme for the response's `WWW-Authenticate`
    ///     header (default: none)
    public init(code: Code, challenge: String? = nil) {
        self.code = code
        self.challenge = challenge
    }

    // swiftformat:disable docComments
    // Wire envelope — INTERNAL detail; never publish in DocC/CHANGELOG/README.
    // The discriminator key + fixed value make the decode strict: init(from:)
    // fails unless both match, so nothing puns into (or out of) this type.
    // Shape pinned by CredentialRejectedErrorTests.forwardCompat.
    private enum CodingKeys: String, CodingKey {
        case discriminator = "__fosServerError"
        case code
    }

    // swiftformat:enable docComments

    private static let discriminatorValue = "credentialRejected"

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .discriminator) == Self.discriminatorValue else {
            throw DecodingError.dataCorruptedError(
                forKey: .discriminator,
                in: container,
                debugDescription: "Not a credential rejection"
            )
        }
        self.code = try container.decode(Code.self, forKey: .code)
        self.challenge = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.discriminatorValue, forKey: .discriminator)
        try container.encode(code, forKey: .code)
    }
}
