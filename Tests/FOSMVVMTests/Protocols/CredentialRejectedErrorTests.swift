// CredentialRejectedErrorTests.swift
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

import FOSFoundation
import FOSMVVM
import Foundation
import Testing

@Suite("CredentialRejectedError contract")
struct CredentialRejectedErrorTests {
    @Test("Round-trips through JSON: code preserved, challenge transient")
    func roundTrip() throws {
        let original = CredentialRejectedError(code: .invalid, challenge: "Bearer")
        let decoded: CredentialRejectedError = try original.toJSON().fromJSON()

        #expect(decoded.code == .invalid)
        #expect(decoded.challenge == nil) // transient: never crosses the wire
    }

    @Test("Both codes round-trip")
    func bothCodes() throws {
        for code in [CredentialRejectedError.Code.missing, .invalid] {
            let decoded: CredentialRejectedError =
                try CredentialRejectedError(code: code).toJSON().fromJSON()
            #expect(decoded.code == code)
        }
    }

    @Test("Does NOT decode from bodies lacking the envelope")
    func strictDecode() {
        // Vapor's stock abort body, a plain reason string, an empty object,
        // and a wrong discriminator VALUE must all fail — nothing puns into
        // the rejection.
        for body in [
            #"{"error":true,"reason":"Unauthorized"}"#,
            #""Invalid bearer credential""#,
            "{}",
            #"{"__fosServerError":"someOtherError","code":"invalid"}"#
        ] {
            let decoded: CredentialRejectedError? = try? body.fromJSON()
            #expect(decoded == nil, "must not decode from: \(body)")
        }
    }

    @Test("Unknown code value is rejected")
    func unknownCode() {
        let body = #"{"__fosServerError":"credentialRejected","code":"bogus"}"#
        let decoded: CredentialRejectedError? = try? body.fromJSON()
        #expect(decoded == nil)
    }

    @Test("Forward-compat: the committed wire form still decodes")
    func forwardCompat() throws {
        // INTERNAL representation pin (golden blob). The ONE place the envelope
        // shape is asserted — see the maintainer comment beside CodingKeys.
        let committedWireForm = #"{"__fosServerError":"credentialRejected","code":"invalid"}"#
        let decoded: CredentialRejectedError = try committedWireForm.fromJSON()
        #expect(decoded.code == .invalid)
    }
}
