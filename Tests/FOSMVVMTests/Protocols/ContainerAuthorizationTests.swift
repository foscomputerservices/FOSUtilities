// ContainerAuthorizationTests.swift
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

/// A Sendable value-snapshot fixture composed exactly as the spec's ``ContainerAuthorization`` DocC
/// example (the DockGrant sketch) — the shared-core contract under pure-logic test, no persistence involved.
private struct TestAuthorization: ContainerAuthorization {
    let authorizedContainer: ModelIdentity
    let operations: [ContainerOperation]
    let recordTypes: [ModelNamespace]

    func authorizes(
        _ operation: ContainerOperation,
        ofType recordType: any FOSMVVM.Model.Type,
        in container: ModelIdentity
    ) -> Bool {
        container == authorizedContainer
            && operations.authorizes(operation) // honors the wildcard — never `contains`
            && recordTypes.contains(recordType.modelIdentityNamespace)
    }
}

@Suite("ContainerAuthorization")
struct ContainerAuthorizationTests {
    @Test("A covering grant authorizes the operation, type, and container")
    func coveringGrantAuthorizes() throws {
        let containerIdentity = try TestGadget(id: UUID()).modelIdentity
        let auth = TestAuthorization(
            authorizedContainer: containerIdentity,
            operations: [.readRecords],
            recordTypes: [TestWidget.modelIdentityNamespace]
        )

        #expect(auth.authorizes(.readRecords, ofType: TestWidget.self, in: containerIdentity))
    }

    @Test("A different container identity is never authorized")
    func differentContainerIdentityNotAuthorized() throws {
        let containerIdentity = try TestGadget(id: UUID()).modelIdentity
        let otherIdentity = try TestGadget(id: UUID()).modelIdentity
        let auth = TestAuthorization(
            authorizedContainer: containerIdentity,
            operations: [.readRecords],
            recordTypes: [TestWidget.modelIdentityNamespace]
        )

        #expect(!auth.authorizes(.readRecords, ofType: TestWidget.self, in: otherIdentity))
    }

    @Test("A wildcard grant authorizes read but never destroy, through the protocol")
    func wildcardGrantExcludesDestroy() throws {
        let containerIdentity = try TestGadget(id: UUID()).modelIdentity
        let auth = TestAuthorization(
            authorizedContainer: containerIdentity,
            operations: [.anyOperation],
            recordTypes: [TestWidget.modelIdentityNamespace]
        )

        #expect(auth.authorizes(.readRecords, ofType: TestWidget.self, in: containerIdentity))
        #expect(!auth.authorizes(.destroyRecords, ofType: TestWidget.self, in: containerIdentity))
    }

    @Test("A record type outside recordTypes is never authorized")
    func recordTypeMismatchNotAuthorized() throws {
        let containerIdentity = try TestGadget(id: UUID()).modelIdentity
        let auth = TestAuthorization(
            authorizedContainer: containerIdentity,
            operations: [.anyOperation],
            recordTypes: [TestWidget.modelIdentityNamespace]
        )

        #expect(!auth.authorizes(.readRecords, ofType: TestGadget.self, in: containerIdentity))
    }
}
