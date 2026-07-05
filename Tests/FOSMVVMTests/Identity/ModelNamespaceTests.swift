// ModelNamespaceTests.swift
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

private enum AlphaMarker {}
private enum BetaMarker {}

struct ModelNamespaceTests {
    @Test func equalForSameType() {
        #expect(ModelNamespace(for: AlphaMarker.self) == ModelNamespace(for: AlphaMarker.self))
    }

    @Test func unequalForDifferentType() {
        #expect(ModelNamespace(for: AlphaMarker.self) != ModelNamespace(for: BetaMarker.self))
    }

    @Test func codableRoundTripIsIdentityPreserving() throws {
        // Contract: encode→decode preserves the value. We assert the round-trip identity, NOT the
        // encoded shape (the "bare string" wire form is a representation detail, not a public contract).
        // `toJSON()`/`fromJSON()` are the repo's encoder-agnostic round-trip helpers (FOSFoundation).
        let ns = ModelNamespace(for: AlphaMarker.self)
        let back: ModelNamespace = try ns.toJSON().fromJSON()
        #expect(back == ns)
    }
}
