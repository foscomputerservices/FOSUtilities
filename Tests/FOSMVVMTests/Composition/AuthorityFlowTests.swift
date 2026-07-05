// AuthorityFlowTests.swift
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

@Suite("AuthorityFlow")
struct AuthorityFlowTests {
    /// A container with no ``Container/authorityFlow`` declaration — inherits the default.
    struct Dock: Container {
        var id: ModelIdType?
        init(id: ModelIdType? = nil) {
            self.id = id
        }
    }

    /// A container that overrides ``Container/authorityFlow`` to ``AuthorityFlow/guards``.
    struct PersonnelFolder: Container {
        var id: ModelIdType?
        static var authorityFlow: AuthorityFlow {
            .guards
        }

        init(id: ModelIdType? = nil) {
            self.id = id
        }
    }

    @Test("A container with no declaration inherits the .inherits default")
    func defaultInherits() {
        #expect(Dock.authorityFlow == .inherits)
    }

    @Test("An override to .guards reads back")
    func overrideGuardsReadsBack() {
        #expect(PersonnelFolder.authorityFlow == .guards)
    }
}

@Suite("RootedQuery")
struct RootedQueryTests {
    struct Harbor: Model {
        var id: ModelIdType?
        init(id: ModelIdType? = nil) {
            self.id = id
        }
    }

    struct HarborBerthsQuery: RootedQuery {
        let rootIdentity: ModelIdentity
    }

    @Test("A RootedQuery conformance vends the rootIdentity minted from a model")
    func vendsMintedRootIdentity() throws {
        let harbor = Harbor(id: .init())
        let identity = try harbor.modelIdentity

        let query = HarborBerthsQuery(rootIdentity: identity)

        #expect(query.rootIdentity == identity)
    }
}
