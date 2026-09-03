// WireErrorTests.swift
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
@testable import FOSMVVM
import Foundation
import Testing

private struct StrictError: ServerRequestError {
    let errorCode: Int
}

@Suite("WireError envelope")
struct WireErrorTests {
    @Test("A surface rejection round-trips, whatever E is")
    func surfaceRoundTrips() throws {
        let rejection = CredentialRejectedError(reason: .invalid, challenge: .bearer)
        let encoded = try WireError<StrictError>.surface(rejection).toJSON()

        let strict: WireError<StrictError> = try encoded.fromJSON()
        guard case .surface(let decoded) = strict else {
            Issue.record("Expected .surface, got \(strict)"); return
        }
        #expect(decoded == rejection)

        // The envelope, not a trial decode, decides — so a permissive E
        // (EmptyError decodes from anything) cannot swallow the rejection.
        let permissive: WireError<EmptyError> = try encoded.fromJSON()
        guard case .surface = permissive else {
            Issue.record("EmptyError swallowed the rejection"); return
        }
    }

    @Test("A request error round-trips as .response")
    func responseRoundTrips() throws {
        let encoded = try WireError<StrictError>.response(StrictError(errorCode: 42)).toJSON()
        let wire: WireError<StrictError> = try encoded.fromJSON()
        guard case .response(let error) = wire else {
            Issue.record("Expected .response, got \(wire)"); return
        }
        #expect(error.errorCode == 42)
    }

    @Test("A bare error body — the pre-envelope form — does not decode")
    func bareBodyFallsThrough() {
        let wire: WireError<StrictError>? = try? #"{"errorCode":42}"#.fromJSON()
        #expect(wire == nil)
    }
}
