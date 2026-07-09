// LiveRegistrationsDecodeTests.swift
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

private enum AlphaModel {}
private enum BetaModel {}

@Suite("LiveRegistrations header decode")
struct LiveRegistrationsDecodeTests {
    @Test("An absent header decodes to the empty set")
    func absentHeaderIsEmpty() {
        #expect(LiveRegistrations.decode(nil).isEmpty)
    }

    @Test("An empty header value decodes to the empty set")
    func emptyHeaderIsEmpty() {
        #expect(LiveRegistrations.decode("").isEmpty)
    }

    @Test("A valid header round-trips to exactly the encoded identity set")
    func validHeaderRoundTrips() throws {
        let identities = [
            ModelIdentity(namespace: ModelNamespace(for: AlphaModel.self), id: UUID()),
            ModelIdentity(namespace: ModelNamespace(for: BetaModel.self), id: UUID())
        ]
        // The server frames this header exactly this way (Response+FOS.swift): the JSON array of
        // the identity set via the frozen `ModelIdentity` encoding.
        let headerValue = try identities.toJSON()

        let decoded = LiveRegistrations.decode(headerValue)
        #expect(Set(decoded) == Set(identities))
    }

    @Test("A malformed header value decodes to empty — a broken header never fails the fetch")
    func malformedHeaderIsEmpty() {
        #expect(LiveRegistrations.decode("not json at all").isEmpty)
        #expect(LiveRegistrations.decode("{\"unexpected\":true}").isEmpty)
    }
}
