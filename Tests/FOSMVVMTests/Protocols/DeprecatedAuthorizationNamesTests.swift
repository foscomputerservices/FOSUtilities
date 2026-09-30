// DeprecatedAuthorizationNamesTests.swift
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

import FOSMVVM
import Foundation
import Testing

@available(*, deprecated)
private struct FormerGrant: ContainerAuthorization {
    let authorizedContainer: ModelIdentity
    let operations: [ContainerOperation]
    let recordTypes: [ModelNamespace]

    func authorizes(
        _ operation: ContainerOperation,
        ofType recordType: any FOSMVVM.Model.Type,
        in container: ModelIdentity
    ) -> Bool {
        container == authorizedContainer
            && operations.authorizes(operation)
            && recordTypes.contains(recordType.modelIdentityNamespace)
    }
}

@Suite("Former authorization spellings")
struct DeprecatedAuthorizationNamesTests {
    @available(*, deprecated)
    @Test("authorizedContainer answers as authorizedModel, and the member question still holds")
    func formerConformerBehavesAsBefore() throws {
        let container = try TestGadget(id: UUID()).modelIdentity
        let grant = FormerGrant(
            authorizedContainer: container,
            operations: [.readRecords],
            recordTypes: [TestWidget.modelIdentityNamespace]
        )

        #expect(grant.authorizedModel == container)
        #expect(grant.authorizes(.readRecords, ofType: TestWidget.self, in: container))
        #expect(!grant.authorizes(.writeRecords, ofType: TestWidget.self, in: container))
    }

    @available(*, deprecated)
    @Test("A former conformer denies every model-level operation by default")
    func formerConformerDeniesModelLevel() throws {
        let container = try TestGadget(id: UUID()).modelIdentity
        let grant = FormerGrant(
            authorizedContainer: container,
            operations: [.anyOperation],
            recordTypes: [TestWidget.modelIdentityNamespace]
        )

        #expect(!grant.authorizes(.read, on: container))
        #expect(!grant.authorizes(.anyOperation, on: container))
    }
}
