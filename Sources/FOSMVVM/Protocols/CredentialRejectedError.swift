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
/// request, this error crosses the wire; the client first offers it to its
/// ``ClientCredentialProvider/credentialHeaders(afterRejection:)`` — a provider
/// that returns fresh headers has the request retried once, and the caller
/// never sees the rejection. Only an unrecovered rejection is rethrown by
/// ``ServerRequest/processRequest(mvvmEnv:)``:
///
/// ```swift
/// do {
///     try await request.processRequest(mvvmEnv: mvvmEnv)
/// } catch let rejection as CredentialRejectedError {
///     switch rejection.reason {
///     case .missing: break // no credential was presented — check the
///                          // MVVMEnvironment's clientCredentialProvider
///     case .invalid: break // presented and refused, and the provider could
///                          // not refresh — sign the user in again
///     }
/// }
/// ```
///
/// The rejection happens **before** the operation runs, so a retry after
/// recovery never duplicates the operation's effects.
///
/// > Note: A rejection that reaches the call site is never routed to
/// > ``MVVMEnvironment/requestErrorHandler``.
public struct CredentialRejectedError: ServerRequestError, Equatable {
    /// Why the credential seam refused the request
    public enum Reason: Codable, Sendable, Equatable {
        /// No credential accompanied the request; typically the client has
        /// no `ClientCredentialProvider` configured, or it returned no headers
        case missing

        /// A credential was presented and the server's verifier refused it
        case invalid
    }

    public let reason: Reason

    /// What the server demands — rendered to `WWW-Authenticate` by the
    /// transport, and readable here on the client as the same typed value
    public let challenge: CredentialChallenge?

    /// Creates the rejection a ``ServerCredentialVerifier`` throws
    ///
    /// - Parameters:
    ///   - reason: Why the request was refused
    ///   - challenge: What the server demands (default: none)
    public init(reason: Reason, challenge: CredentialChallenge? = nil) {
        self.reason = reason
        self.challenge = challenge
    }
}
