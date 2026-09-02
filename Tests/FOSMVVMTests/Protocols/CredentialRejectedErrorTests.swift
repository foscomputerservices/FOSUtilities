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
    @Test("Round-trips through JSON with its reason and challenge")
    func roundTrip() throws {
        let original = CredentialRejectedError(reason: .invalid, challenge: .bearerRealm("api"))
        let decoded: CredentialRejectedError = try original.toJSON().fromJSON()

        #expect(decoded == original)
    }

    @Test("Both reasons and every challenge round-trip")
    func reasonsAndChallenges() throws {
        let challenges: [CredentialChallenge?] = [nil, .bearer, .bearerRealm("api"), .basicRealm("api")]
        for reason in [CredentialRejectedError.Reason.missing, .invalid] {
            for challenge in challenges {
                let original = CredentialRejectedError(reason: reason, challenge: challenge)
                let decoded: CredentialRejectedError = try original.toJSON().fromJSON()
                #expect(decoded == original)
            }
        }
    }

    @Test("A body that is not a rejection does not decode as one")
    func strictDecode() {
        for body in [
            #"{"error":true,"reason":"Unauthorized"}"#,
            #""Invalid bearer credential""#,
            "{}"
        ] {
            let decoded: CredentialRejectedError? = try? body.fromJSON()
            #expect(decoded == nil, "must not decode from: \(body)")
        }
    }
}
