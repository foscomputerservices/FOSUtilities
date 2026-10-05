// ModelIdentityStubTests.swift
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

struct ModelIdentityStubTests {
    @Test func eachStubIsADifferentIdentity() {
        #expect(ModelIdentity.stub() != ModelIdentity.stub())
    }

    @Test func aHeldStubEqualsItselfAcrossARoundTrip() throws {
        let held = ModelIdentity.stub()
        let roundTripped: ModelIdentity = try held.toJSON().fromJSON()
        #expect(roundTripped == held)
    }

    @Test func aStubNeverEqualsARealModelsIdentity() throws {
        let stub = ModelIdentity.stub()
        // The same row id as the stub, so only the namespace can tell them apart.
        let gadget = TestGadget(id: stub.id)
        let widget = TestWidget(id: stub.id)

        #expect(!(stub == gadget))
        #expect(!(stub == widget))
        #expect(try stub != gadget.modelIdentity)
        #expect(try stub != widget.modelIdentity)
    }

    @Test func distinctStubsRootDistinctViewModelIds() {
        #expect(ModelIdentity.stub().viewModelId != ModelIdentity.stub().viewModelId)
    }
}
