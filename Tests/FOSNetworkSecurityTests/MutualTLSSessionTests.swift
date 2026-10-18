// MutualTLSSessionTests.swift
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

// A session from `URLSession.session(config:mutualTLS:)` decides a server-trust challenge by the
// server certificate's SPKI pin. The challenge is handed straight to the session's delegate:
// URLSession copies a protection space before delivering it, which drops a scripted server trust,
// so it cannot be raised through a URLProtocol. That the stream forwards server-trust challenges
// to this delegate is proven in DataFetchStreamTests.

#if canImport(Security)
import FOSNetworkSecurity
import Foundation
import Security
import Testing

struct MutualTLSSessionTests {
    @Test func pinnedServerIsTrusted() throws {
        let disposition = try serverTrustDisposition(pins: [SPKIPin(base64: fixturePin)])
        #expect(disposition == .useCredential)
    }

    @Test func unpinnedServerIsRefused() throws {
        let disposition = try serverTrustDisposition(pins: [SPKIPin(base64: otherPin)])
        #expect(disposition == .cancelAuthenticationChallenge)
    }
}

// MARK: - Helpers

/// The ServerCertPinningTests fixture's SPKI pin, computed there independently by openssl.
private let fixturePin = "KbA9PQtIGba3/nsl+0V3boi1Zxi/XV6DGsoTZx6Gveo="

/// A pin no certificate here has.
private let otherPin = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

/// The ServerCertPinningTests fixture certificate, DER, base64-encoded.
private let fixtureCertB64 = """
MIIDDTCCAfWgAwIBAgIUVqX8ro252adaSXxeIvKKNkcAYFEwDQYJKoZIhvcNAQELBQAwFjEUMBIGA1UEAwwLaGFyYm9yLXRlc3QwHhcNMjYwNjE5MDc1ODMxWhcNMjYwNjIwMDc1ODMxWjAWMRQwEgYDVQQDDAtoYXJib3ItdGVzdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAOGPqeGOuLC/jxhj3/evHGKSvzdrq1E5m9O1wRWnHwdewFHtK9GuJi7JBXfS3vWPI+vlOe3v7oT0kmXyS2/ZLUM/GNYM+V2ySriWKdMchndPiECYgRP9v1flAI2eEo38d6mskr4TF3cHzySNl5vv0TC5yyWw+VQhr6E2KLi2Q8da0E34E2wUoVcXYW/2kfCewqKz+nLtXSN7rf+Yy30aDRFqbj6yL/+xyaYozJgjLGXpGiIeadFxXKQHT95gjvr9x1KTPTwLfjBTFKGGN2G63ulGmlJ2dD20sFPNTLn1pe2C9wVzm2lL261MYqwNqysU4nSjEp+GdNGIZ5GLwGbO/FkCAwEAAaNTMFEwHQYDVR0OBBYEFI5EsWMyAvDAKgvDfKxcJkv9XXhyMB8GA1UdIwQYMBaAFI5EsWMyAvDAKgvDfKxcJkv9XXhyMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEBAMRszQ+scO4p/PG1oq7gnlMo4spM/O+yRwBRJBqQJsu0c3Hn2JAFVeZWtHbWNqjvxiy/XToZR1eP7XHj0ojwc5/oXMPF3dF+GBpiigiYAfdXc+8H21b6N5UzMuUk95cIWhDHNwud83Eo1mybDws/Xyj41EmPH5y42O8lR3U3vjBEL8Ry14ggzcwmfr39bGAMTrhrWuwYiGUaq4bth5V1Qen+4ezwVtaFUBbBKOLi6j/1RwzTef0YGGISLouEHmzMDcclX37/F2VzDp4bH0zag5vLvb9zkJjJ/+u0UPxLS++s7dDhqIl6b4cH92qeAaSmZpJ4OgEoFDjJcYuIspDSzm0=
"""

/// What a `mutualTLS` session's delegate answers to the fixture server's trust challenge.
private func serverTrustDisposition(pins: Set<SPKIPin>) throws -> URLSession.AuthChallengeDisposition {
    let session = URLSession.session(config: .ephemeral, mutualTLS: MutualTLS(serverPins: pins))
    defer { session.invalidateAndCancel() }
    let delegate = try #require(session.delegate)

    let der = try #require(Data(base64Encoded: fixtureCertB64))
    let certificate = try #require(SecCertificateCreateWithData(nil, der as CFData))
    var trust: SecTrust?
    SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &trust)
    let challenge = try URLAuthenticationChallenge(
        protectionSpace: ServerTrustProtectionSpace(trust: #require(trust)),
        proposedCredential: nil,
        previousFailureCount: 0,
        failureResponse: nil,
        error: nil,
        sender: UnusedChallengeSender()
    )

    var disposition: URLSession.AuthChallengeDisposition?
    delegate.urlSession?(session, didReceive: challenge) { answer, _ in disposition = answer }
    return try #require(disposition)
}

/// The protection space of a TLS handshake: it carries the server's trust.
private final class ServerTrustProtectionSpace: URLProtectionSpace, @unchecked Sendable {
    private let trust: SecTrust

    init(trust: SecTrust) {
        self.trust = trust
        super.init(
            host: "workspace.invalid",
            port: 443,
            protocol: NSURLProtectionSpaceHTTPS,
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var serverTrust: SecTrust? {
        trust
    }
}

/// A delegate answers through its completion handler, so the sender is never called.
private final class UnusedChallengeSender: NSObject, URLAuthenticationChallengeSender, @unchecked Sendable {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}
#endif
