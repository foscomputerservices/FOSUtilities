// ModelIdentityCodableTests.swift
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

struct ModelIdentityCodableTests {
    /// Persistence forward-compat CONTRACT: a previously-stored identity must keep decoding. If a
    /// CodingKey is ever renamed/removed (which silently breaks stored DB data), decoding this committed
    /// blob throws — the failure is caught here. Public `Codable` only (no `@testable`), and we assert
    /// *behavior* (decodes + round-trips idempotently), NOT the current encode byte/key shape. The blob
    /// is the persistence contract made concrete — the single internal home for the stored form; the
    /// public API never advertises it. (`ModelNamespace.init(from:)` accepts any string, so the fixture
    /// is decoupled from any marker type's reflected name — no churn on a rename/move.)
    @Test func storedIdentityStillDecodesAndRoundTrips() throws {
        let golden = #"{"namespace":"App.WidgetIdentity","id":"3F2504E0-4F89-41D3-9A0C-0305E82C3301"}"#
        let decoded: ModelIdentity = try golden.fromJSON() // throws if a key was renamed/removed
        let roundTripped: ModelIdentity = try decoded.toJSON().fromJSON() // encode→decode reproduces value
        #expect(roundTripped == decoded) // behavior, not a byte-shape assertion
    }
}
