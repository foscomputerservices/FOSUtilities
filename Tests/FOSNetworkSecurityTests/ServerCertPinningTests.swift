// ServerCertPinningTests.swift
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

// The SPKI pin computed over a certificate DER must equal the value derived INDEPENDENTLY by
// openssl from the same certificate's public key — so the assertion is not circular, and a pin
// computed here matches one computed by any other RFC-7469 implementation (client or server).
//
// Fixture provenance (regenerable):
//   openssl req -x509 -newkey rsa:2048 -keyout k.pem -out c.pem -days 1 -nodes \
//       -subj "/CN=harbor-test"
//   openssl x509 -in c.pem -outform DER -out c.der
//   base64 -i c.der                                            → certB64
//   openssl x509 -in c.der -inform DER -pubkey -noout \
//       | openssl pkey -pubin -outform DER \
//       | openssl dgst -sha256 -binary | openssl enc -base64   → expectedPin

import FOSNetworkSecurity
import Foundation
import Testing

/// A self-signed `CN=harbor-test` certificate (RSA-2048), DER, base64-encoded.
private let certB64 = """
MIIDDTCCAfWgAwIBAgIUVqX8ro252adaSXxeIvKKNkcAYFEwDQYJKoZIhvcNAQELBQAwFjEUMBIGA1UEAwwLaGFyYm9yLXRlc3QwHhcNMjYwNjE5MDc1ODMxWhcNMjYwNjIwMDc1ODMxWjAWMRQwEgYDVQQDDAtoYXJib3ItdGVzdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAOGPqeGOuLC/jxhj3/evHGKSvzdrq1E5m9O1wRWnHwdewFHtK9GuJi7JBXfS3vWPI+vlOe3v7oT0kmXyS2/ZLUM/GNYM+V2ySriWKdMchndPiECYgRP9v1flAI2eEo38d6mskr4TF3cHzySNl5vv0TC5yyWw+VQhr6E2KLi2Q8da0E34E2wUoVcXYW/2kfCewqKz+nLtXSN7rf+Yy30aDRFqbj6yL/+xyaYozJgjLGXpGiIeadFxXKQHT95gjvr9x1KTPTwLfjBTFKGGN2G63ulGmlJ2dD20sFPNTLn1pe2C9wVzm2lL261MYqwNqysU4nSjEp+GdNGIZ5GLwGbO/FkCAwEAAaNTMFEwHQYDVR0OBBYEFI5EsWMyAvDAKgvDfKxcJkv9XXhyMB8GA1UdIwQYMBaAFI5EsWMyAvDAKgvDfKxcJkv9XXhyMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEBAMRszQ+scO4p/PG1oq7gnlMo4spM/O+yRwBRJBqQJsu0c3Hn2JAFVeZWtHbWNqjvxiy/XToZR1eP7XHj0ojwc5/oXMPF3dF+GBpiigiYAfdXc+8H21b6N5UzMuUk95cIWhDHNwud83Eo1mybDws/Xyj41EmPH5y42O8lR3U3vjBEL8Ry14ggzcwmfr39bGAMTrhrWuwYiGUaq4bth5V1Qen+4ezwVtaFUBbBKOLi6j/1RwzTef0YGGISLouEHmzMDcclX37/F2VzDp4bH0zag5vLvb9zkJjJ/+u0UPxLS++s7dDhqIl6b4cH92qeAaSmZpJ4OgEoFDjJcYuIspDSzm0=
"""

/// The canonical SPKI pin of `certB64`, computed independently by openssl (see header).
private let expectedPin = "KbA9PQtIGba3/nsl+0V3boi1Zxi/XV6DGsoTZx6Gveo="

@Test func spkiPinMatchesOpenSSLCanonicalPin() throws {
    let der = try #require(Data(base64Encoded: certB64))
    let pin = try ServerCertPinning.spkiPin(ofCertificateDER: der)
    #expect(pin.base64 == expectedPin)
}

@Test func spkiPinThrowsOnNonCertificateData() {
    #expect(throws: (any Error).self) {
        _ = try ServerCertPinning.spkiPin(ofCertificateDER: Data([0x00, 0x01, 0x02]))
    }
}
