// ModelIdentityViewModelIdTests.swift
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

struct ModelIdentityViewModelIdTests {
    /// Group 5: vmId derivation — stable & equal for equal identities, distinct for distinct.
    @Test func vmIdIsStableForEqualIdentities() throws {
        let uuid = UUID()
        let a = try TestWidget(id: uuid).modelIdentity.viewModelId
        let b = try TestWidget(id: uuid).modelIdentity.viewModelId
        #expect(a == b)
    }

    @Test func vmIdDiffersForDistinctIdentities() throws {
        let a = try TestWidget(id: UUID()).modelIdentity.viewModelId
        let b = try TestWidget(id: UUID()).modelIdentity.viewModelId
        #expect(a != b)
        // Namespace participates: same UUID under a different namespace ⇒ different vmId.
        let uuid = UUID()
        let w = try TestWidget(id: uuid).modelIdentity.viewModelId
        let g = try TestGadget(id: uuid).modelIdentity.viewModelId
        #expect(w != g)
    }
}
