// MutualTLS.swift
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
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Security)
import Security
#endif

#if !os(WASI)

// MARK: - MutualTLS

/// A client-side **mutual-TLS** policy for a `URLSession`: the server certificate pin(s) to verify,
/// and an optional client identity to present when the server requests one.
///
/// Mutual TLS authenticates *both* ends of the connection: ordinary TLS proves only the server's
/// identity, while mutual TLS additionally has the client present a certificate the server verifies.
/// This policy declares the client's half — *pin the server, present my identity* — and is wired
/// into a session by ``Foundation/URLSession/session(config:mutualTLS:)``; the caller supplies only
/// the policy values (which pins, which identity), never the handshake mechanics.
///
/// With ``clientIdentity`` `nil` the policy is **server-pinning-only** (no client authentication) —
/// the correct shape for a bearer-authenticated surface that still pins its server.
public struct MutualTLS: Sendable {
    /// The set of acceptable server ``SPKIPin``s. The handshake succeeds only if the server leaf's
    /// pin is a member.
    public let serverPins: Set<SPKIPin>

    /// The identity presented at the server's client-certificate challenge, or `nil` for
    /// server-pinning-only (no client authentication).
    public let clientIdentity: (any ClientIdentityProvider)?

    public init(serverPins: Set<SPKIPin>, clientIdentity: (any ClientIdentityProvider)? = nil) {
        self.serverPins = serverPins
        self.clientIdentity = clientIdentity
    }
}

// MARK: - ClientIdentityProvider

/// Supplies the client identity (certificate + private key) presented during a mutual-TLS
/// handshake, as a `URLCredential`. Abstracted so the transport depends on a seam rather than a
/// specific keystore (e.g. a Keychain-backed provider on Apple platforms).
public protocol ClientIdentityProvider: Sendable {
    /// Returns the `URLCredential` to present at the client-certificate challenge.
    ///
    /// - Throws: if the identity cannot be located or loaded.
    func clientCredential() throws -> URLCredential
}

#endif

// MARK: - URLSession factory + delegate

#if canImport(Security)

public extension URLSession {
    /// Builds a `URLSession` that enforces `mutualTLS` on every request: it SPKI-pins the server
    /// certificate to ``MutualTLS/serverPins`` and, when the policy carries one, presents
    /// ``MutualTLS/clientIdentity`` at the client-certificate challenge.
    ///
    /// This is the mutual-TLS sibling of `DataFetch.urlSessionConfiguration(forUserToken:)`: bearer
    /// auth rides the configuration (a header), but mutual TLS needs a `URLSessionDelegate` to answer
    /// the handshake challenges, so it is attached here at session construction. Hand the returned
    /// session to `MVVMEnvironment(session:)` or `processRequest(session:)`.
    ///
    /// The returned session **owns** the pinning delegate for its lifetime; keep the session alive
    /// for as long as its requests are in flight.
    ///
    /// - Parameters:
    ///   - config: The base session configuration (e.g. from
    ///     `DataFetch.urlSessionConfiguration()`).
    ///   - mutualTLS: The pin/identity policy to enforce.
    static func session(config: URLSessionConfiguration, mutualTLS: MutualTLS) -> URLSession {
        URLSession(
            configuration: config,
            delegate: MutualTLSSessionDelegate(policy: mutualTLS),
            delegateQueue: nil
        )
    }
}

/// The `URLSession` delegate that enforces a ``MutualTLS`` policy. **Fails closed**: a server whose
/// leaf SPKI pin is not in ``MutualTLS/serverPins`` is rejected, and a client identity that cannot
/// be loaded cancels the handshake rather than proceeding anonymously.
///
/// The server-trust branch alone (policy ``MutualTLS/clientIdentity`` `nil`) is the
/// server-pinning-only case; a non-nil identity makes it full mutual TLS.
private final class MutualTLSSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let policy: MutualTLS

    init(policy: MutualTLS) {
        self.policy = policy
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodClientCertificate:
            guard let clientIdentity = policy.clientIdentity else {
                // Server-pinning-only: no identity to present. Let default handling proceed — the
                // server may not actually require a client certificate.
                completionHandler(.performDefaultHandling, nil)
                return
            }
            do {
                try completionHandler(.useCredential, clientIdentity.clientCredential())
            } catch {
                // Fail closed: cancel rather than proceed anonymously.
                completionHandler(.cancelAuthenticationChallenge, nil)
            }

        case NSURLAuthenticationMethodServerTrust:
            // Pin the server's leaf by SPKI. Mismatch (or no trust/leaf) ⇒ cancel ⇒ fail closed.
            guard let trust = challenge.protectionSpace.serverTrust,
                  let leafDER = Self.leafCertificateDER(from: trust),
                  let pin = try? ServerCertPinning.spkiPin(ofCertificateDER: leafDER),
                  policy.serverPins.contains(pin) else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            completionHandler(.useCredential, URLCredential(trust: trust))

        default:
            completionHandler(.performDefaultHandling, nil)
        }
    }

    /// The DER of the leaf certificate from `trust` (the chain is leaf-first).
    private static func leafCertificateDER(from trust: SecTrust) -> Data? {
        guard let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else {
            return nil
        }
        return SecCertificateCopyData(leaf) as Data
    }
}

#endif
