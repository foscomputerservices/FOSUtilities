// ViewModelIdFreshnessTests.swift
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

struct ViewModelIdFreshnessTests {
    // Public contract only (no @testable, no raw-JSON inspection). The 2020 canonical payload stands
    // in for "an old wire moment"; comparing by ordering avoids the sub-millisecond precision caveat.

    /// Ordering — a later birth sorts after an earlier one.
    /// async because of Task.sleep — Swift Testing supports async @Test functions.
    @Test func freshnessOrdersByBirthMoment() async throws {
        let a = ViewModelId(id: "x").freshness
        try await Task.sleep(nanoseconds: 2000000) // ~2ms so the canonical (ms-precision) clock advances
        let b = ViewModelId(id: "y").freshness
        #expect(a < b)
    }

    /// Identity ignores freshness — same logical id, different freshness ⇒ still ==, equal hash.
    @Test func identityIgnoresFreshness() throws {
        let born = ViewModelId(id: "same")
        let decoded: ViewModelId = try #"{"id":"same","fsh":"2020-01-01T00:00:00.000Z"}"#.fromJSON()
        #expect(born == decoded) // identity is id-only …
        #expect(born.hashValue == decoded.hashValue)
        #expect(decoded.freshness < born.freshness) // … yet freshness differs and orders correctly
    }

    /// Wire preserves the moment — decode does NOT re-stamp to the client's now.
    @Test func decodePreservesWireMomentNotNow() throws {
        let decoded: ViewModelId = try #"{"id":"x","fsh":"2020-01-01T00:00:00.000Z"}"#.fromJSON()
        #expect(decoded.freshness < ViewModelId(id: "z").freshness)
    }

    /// Freshness survives the wire (proves it IS encoded AND preserved): a round-trip of an old
    /// moment stays equivalent — if freshness weren't encoded, decode would re-stamp to now and the
    /// two would differ. Ordering-equivalence, never a byte/key-shape assertion.
    @Test func freshnessSurvivesRoundTrip() throws {
        let original: ViewModelId = try #"{"id":"x","fsh":"2020-01-01T00:00:00.000Z"}"#.fromJSON()
        let roundTripped: ViewModelId = try original.toJSON().fromJSON()
        #expect(!(original.freshness < roundTripped.freshness))
        #expect(!(roundTripped.freshness < original.freshness)) // equivalent ⇒ preserved
    }

    /// Lenient decode — a payload lacking `fsh` still decodes (no throw) and yields a usable vmId.
    @Test func decodeToleratesMissingFreshness() throws {
        let decoded: ViewModelId = try #"{"id":"legacy"}"#.fromJSON()
        #expect(decoded == ViewModelId(id: "legacy")) // decoded correctly, asserted via public ==
    }
}
