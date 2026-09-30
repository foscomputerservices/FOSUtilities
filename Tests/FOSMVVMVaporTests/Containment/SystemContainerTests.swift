// SystemContainerTests.swift
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

import Fluent
import FluentKit
import FOSFoundation
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing
import Vapor

/// The Workspace graph and the Quay graph, every type Suite and Fleet own registered, Suite
/// registered, grants through the storage-backed provider; live enabled on request.
private func configureSuite(_ app: Application, live: Bool = false, registerFleet: Bool = false) throws {
    app.migrations.add(CreatePier())
    try app.register(Workspace.self, migration: CreateWorkspace())
    try app.register(Board.self, migration: CreateBoard())
    app.migrations.add(CreateCard())
    app.migrations.add(CreateMember())
    app.migrations.add(CreateBoardMember())
    try app.register(Quay.self, migration: CreateQuay())
    try app.register(Mooring.self, migration: CreateMooring())
    try app.register(Suite.self)
    if registerFleet {
        try app.register(Fleet.self)
    }
    try app.useModelAuthorizationProvider(TestGrantsProvider())
    if live {
        try app.useLiveInvalidation(on: app.routes)
    }
}

private func makeRequest(on app: Application) -> Vapor.Request {
    Request(application: app, method: .GET, url: URI(string: "/"), on: app.eventLoopGroup.next())
}

/// Two Workspaces, nothing inside them.
private func seedWorkspaces(on db: any Database) async throws -> (Workspace, Workspace) {
    let first = Workspace(name: "First")
    let second = Workspace(name: "Second")
    try await first.save(on: db)
    try await second.save(on: db)
    return (first, second)
}

private func suiteGrant(_ operations: [ContainerOperation], types: [ModelNamespace] = [Workspace.modelIdentityNamespace]) -> TestGrant {
    TestGrant(authorizedModel: Suite.identity, operations: operations, recordTypes: types)
}

private func workspaceNames(_ records: [any DataModel]) throws -> [String] {
    try records.map { try #require($0 as? Workspace).name }.sorted()
}

// MARK: - B1: the identity

@Suite("SystemContainer identity")
struct SystemContainerIdentityTests {
    @Test("Equal across calls")
    func equalAcrossCalls() {
        #expect(Suite.identity == Suite.identity)
        #expect(Suite.identity.hashValue == Suite.identity.hashValue)
    }

    @Test("Unequal across types")
    func unequalAcrossTypes() {
        #expect(Suite.identity != Fleet.identity)
    }

    @Test("Round-trips through JSON as a whole")
    func roundTripsThroughJSON() throws {
        let json = try Suite.identity.toJSON()
        let decoded: ModelIdentity = try json.fromJSON()
        #expect(decoded == Suite.identity)
        #expect(decoded != Fleet.identity)
    }

    /// Internal pin: the namespace is the type's and the id part is the one framework constant —
    /// changing either orphans every stored grant on a system container.
    @Test("The id part is the framework constant; the namespace is the type's")
    func identityIsMintedFromTheTypeAndTheConstant() {
        #expect(Suite.identity.namespace == ModelNamespace(for: Suite.self))
        let pinned = UUID(uuidString: "5F05C0DE-0000-4000-8000-000000000001")
        #expect(Suite.identity.id == pinned)
        #expect(Fleet.identity.id == pinned)
    }
}

// MARK: - B2: the `.all` relation

@Suite("ContainmentRelation.all: every row, no container")
struct AllRelationTests {
    @Test("members loads every row of the type, refinement applied")
    func membersLoadsEveryRow() async throws {
        try await withFluentTestApp { app in
            try configureSuite(app)
        } _: { _, db in
            _ = try await seedWorkspaces(on: db)
            let relation = ContainmentRelation.all(Workspace.self)
            let all = try await relation.members(of: nil, on: db)
            #expect(try workspaceNames(all) == ["First", "Second"])
            let windowed = try await relation.members(of: nil, on: db, applying: .normalized(sortTerms: [], pagination: .init(startIndex: 0, maxResults: 1), filter: nil))
            #expect(windowed.count == 1)
        }
    }

    @Test("memberCount counts the whole type")
    func memberCountCountsTheType() async throws {
        try await withFluentTestApp { app in
            try configureSuite(app)
        } _: { _, db in
            _ = try await seedWorkspaces(on: db)
            let count = try await ContainmentRelation.all(Workspace.self).memberCount(of: nil, on: db)
            #expect(count == 2)
        }
    }

    @Test("createMember saves the row with no join")
    func createMemberSavesWithNoJoin() async throws {
        try await withFluentTestApp { app in
            try configureSuite(app)
        } _: { _, db in
            let fresh = Workspace(name: "Created at the top")
            try await ContainmentRelation.all(Workspace.self).createMember(fresh, into: nil, on: db)
            let persisted = try await Workspace.query(on: db).count()
            #expect(persisted == 1)
            #expect(fresh.id != nil)
        }
    }

    @Test("memberIds ignores the named containers: a granted system container reaches the whole type")
    func memberIdsIgnoresTheNamedIds() async throws {
        try await withFluentTestApp { app in
            try configureSuite(app)
        } _: { _, db in
            let (first, second) = try await seedWorkspaces(on: db)
            let ids = try await ContainmentRelation.all(Workspace.self).memberIds(ofContainers: [], on: db)
            #expect(try Set(ids) == [first.requireId(), second.requireId()])
        }
    }

    @Test("Bound to its owner, a mutated row of the type inverts to the owner's identity; other types do not")
    func boundInvertAttributesToTheOwner() async throws {
        try await withFluentTestApp { app in
            try configureSuite(app)
        } _: { app, db in
            let (first, _) = try await seedWorkspaces(on: db)
            let descriptor = try #require(app.modelTypeRegistry.registered(for: Suite.identity.namespace))
            let relation = try #require(descriptor.containment.first { ObjectIdentifier($0.containedType) == ObjectIdentifier(Workspace.self) })
            #expect(relation.staleContainerIdentities(forMutated: first, isRegisteredContainer: { _ in true }) == [Suite.identity])
            #expect(relation.staleContainerIdentities(forMutated: Board(), isRegisteredContainer: { _ in true }).isEmpty)
            #expect(try ObjectIdentifier(#require(relation.containerType)) == ObjectIdentifier(Suite.self))
        }
    }

    @Test("A row relation reached with no container throws typed, never loads")
    func rowRelationWithNoContainerThrows() async throws {
        try await withFluentTestApp { app in
            try configureSuite(app)
        } _: { _, db in
            await #expect(throws: ContainmentError.self) {
                _ = try await ContainmentRelation.children(\Workspace.$boards).members(of: nil, on: db)
            }
        }
    }
}

// MARK: - B3: registration

@Suite("SystemContainer registration")
struct SystemContainerRegistrationTests {
    @Test("A container with rows may not declare .all")
    func allOnAContainerWithRowsIsRefused() async throws {
        try await withFluentTestApp { app in
            do {
                try app.register(AllDeclaringBoard.self, migration: CreateBoard())
                Issue.record("expected ContainmentError.systemRelationOnContainer")
            } catch let error as ContainmentError {
                guard case .systemRelationOnContainer = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
        } _: { _, _ in }
    }

    @Test("A system container may declare only .all")
    func rowRelationOnASystemContainerIsRefused() async throws {
        try await withFluentTestApp { app in
            do {
                try app.register(RowRelationSuite.self)
                Issue.record("expected ContainmentError.rowRelationOnSystemContainer")
            } catch let error as ContainmentError {
                guard case .rowRelationOnSystemContainer = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
        } _: { _, _ in }
    }

    @Test("A system container registers once")
    func duplicateSystemContainerIsRefused() async throws {
        try await withFluentTestApp { app in
            try configureSuite(app)
            do {
                try app.register(Suite.self)
                Issue.record("expected ContainmentError.duplicateNamespace")
            } catch let error as ContainmentError {
                guard case .duplicateNamespace = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
        } _: { _, _ in }
    }

    @Test("An owned type left unregistered is refused when the application boots, whatever the order")
    func unregisteredOwnedTypeIsRefusedAtBoot() async throws {
        do {
            try await withFluentTestApp { app in
                try app.register(Fleet.self) // owns Quay, which nothing registers — before or after
                try app.register(Workspace.self, migration: CreateWorkspace())
                try app.useModelAuthorizationProvider(TestGrantsProvider())
            } _: { _, _ in
                Issue.record("expected the boot to refuse")
            }
        } catch let error as ContainmentError {
            guard case .unregisteredSystemMember(let container, let memberType) = error else {
                Issue.record("wrong case: \(error)")
                return
            }
            #expect(container == "Fleet")
            #expect(memberType == "Quay")
        }
    }

    @Test("The boot check is order-independent: a system container registered after its owned type boots")
    func systemContainerRegisteredLastBoots() async throws {
        try await withFluentTestApp { app in
            try app.register(Quay.self, migration: CreateQuay())
            try app.register(Mooring.self, migration: CreateMooring())
            try app.register(Fleet.self)
            try app.useModelAuthorizationProvider(TestGrantsProvider())
        } _: { app, _ in
            #expect(app.modelTypeRegistry.registered(for: Fleet.identity.namespace) != nil)
        }
    }

    @Test("The engine loads through the system container on a grant on its identity, and empty without one")
    func loadsThroughTheSystemContainer() async throws {
        try await withFluentTestApp { app in
            try configureSuite(app)
        } _: { app, db in
            _ = try await seedWorkspaces(on: db)
            app.storage[TestGrantsKey.self] = [suiteGrant([.readRecords])]
            let granted = try await makeRequest(on: app).authorizedRecords(of: Suite.identity, containing: Workspace.self, for: .readRecords)
            #expect(try workspaceNames(granted) == ["First", "Second"])

            app.storage[TestGrantsKey.self] = []
            let denied = try await makeRequest(on: app).authorizedRecords(of: Suite.identity, containing: Workspace.self, for: .readRecords)
            #expect(denied.isEmpty)
        }
    }

    @Test("The registry entry has no rows: no type of its own for the sweeps, one identity, container")
    func registryEntryIsTableless() async throws {
        try await withFluentTestApp { app in
            try configureSuite(app)
            let descriptor = try #require(app.modelTypeRegistry.registered(for: Suite.identity.namespace))
            #expect(descriptor.isTableless)
            #expect(descriptor.isContainer)
            #expect(descriptor.modelType == nil)
            #expect(descriptor.identity == Suite.identity)
        } _: { _, _ in }
    }
}

// MARK: - B4: the application-scope default

@Suite("The application scope defaults to a lone system container")
struct ApplicationScopeDefaultTests {
    @Test("With nothing registered and one system container, plans within .application bind to it")
    func loneSystemContainerBindsTheApplicationScope() async throws {
        try await withFluentTestApp { app in
            try configureSuite(app)
            try app.registerRecordLoadPlan(for: WorkspaceListRequest.self) // no useApplicationScope
        } _: { app, db in
            _ = try await seedWorkspaces(on: db)
            app.storage[TestGrantsKey.self] = [suiteGrant([.readRecords])]
            let req = makeRequest(on: app)
            try await req.executeRecordLoadPlan(for: WorkspaceListRequest())

            let tuple = try #require(req.tupleCacheKeys.keys.first)
            let names = try (req.recordsByTuple()[tuple] ?? []).map { try #require($0 as? Workspace).name }.sorted()
            #expect(names == ["First", "Second"])
            #expect(req.registrationSet.contains(Suite.identity))
        }
    }

    @Test("A registered application scope wins over the lone system container")
    func registeredScopeWins() async throws {
        try await withFluentTestApp { app in
            try configureSuite(app)
            try app.useApplicationScope { _ in Fleet.identity } // Fleet owns no Workspace
            try app.registerRecordLoadPlan(for: WorkspaceListRequest.self)
        } _: { app, _ in
            // Suite would have satisfied the plan; the registered Fleet does not — and it is unregistered here.
            do {
                try await makeRequest(on: app).executeRecordLoadPlan(for: WorkspaceListRequest())
                Issue.record("expected ContainmentError.unregisteredNamespace")
            } catch let error as ContainmentError {
                guard case .unregisteredNamespace = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
        }
    }

    @Test("Two system containers and nothing registered is the existing refusal")
    func twoSystemContainersNeedARegistration() async throws {
        try await withFluentTestApp { app in
            try configureSuite(app, registerFleet: true)
            do {
                try app.registerRecordLoadPlan(for: WorkspaceListRequest.self)
                Issue.record("expected ContainmentError.invalidLoadPlan")
            } catch let error as ContainmentError {
                guard case .invalidLoadPlan(_, let reason) = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
                #expect(reason.contains("application scope"))
            }
        } _: { _, _ in }
    }
}

// MARK: - B5: together with model authority

@Suite("System container and model authority together")
struct SystemContainerTogetherTests {
    @Test("A grant on the system container makes the reach the whole type, with no id list gathered")
    func grantOnSystemContainerReachesTheWholeType() async throws {
        try await withFluentTestApp { app in
            try configureSuite(app)
        } _: { app, db in
            let (first, _) = try await seedWorkspaces(on: db)
            app.storage[TestGrantsKey.self] = [suiteGrant([.readRecords])]
            let whole = try await makeRequest(on: app).subjectReach(ofType: Workspace.self, for: .readRecords)
            #expect(whole == .everyModel)

            app.storage[TestGrantsKey.self] = try [
                TestGrant(authorizedModel: first.modelIdentity, operations: [], recordTypes: [], modelOperations: [.read])
            ]
            let named = try await makeRequest(on: app).subjectReach(ofType: Workspace.self, for: .readRecords)
            #expect(try named == .models([first.requireId()]))
        }
    }

    @Test("A read within the subject scope includes the system container's members through a grant on its identity")
    func subjectScopeReachesTheSystemContainersMembers() async throws {
        try await withFluentTestApp { app in
            try configureSuite(app)
            try app.registerRecordLoadPlan(for: SubjectWorkspacesRequest.self)
        } _: { app, db in
            let (first, second) = try await seedWorkspaces(on: db)
            app.storage[TestGrantsKey.self] = [suiteGrant([.readRecords])]
            let req = makeRequest(on: app)
            try await req.executeRecordLoadPlan(for: SubjectWorkspacesRequest())

            let tuple = try #require(req.tupleCacheKeys.keys.first)
            let names = try (req.recordsByTuple()[tuple] ?? []).map { try #require($0 as? Workspace).name }.sorted()
            #expect(names == ["First", "Second"])
            #expect(try req.registrationSet == [first.modelIdentity, second.modelIdentity])
        }
    }

    @Test("A create within the application scope persists at the top with no join, and the refresh lists it")
    func createAtTheTopPersists() async throws {
        try await withFluentTestApp { app in
            try configureSuite(app)
            try app.register(request: CreateWorkspaceRequest.self, app: app)
        } _: { app, db in
            _ = try await seedWorkspaces(on: db)
            app.storage[TestGrantsKey.self] = [suiteGrant([.readRecords, .createRecords])]

            let vmRequest = CreateWorkspaceRequest(query: nil, sort: nil, fragment: nil, requestBody: .init(name: "Third"), responseBody: nil)
            let req = makeRequest(on: app)
            let refreshed = try await req.serveCreate(vmRequest, body: #require(vmRequest.requestBody))

            #expect(refreshed.names == ["First", "Second", "Third"])
            let persisted = try await Workspace.query(on: db).filter(\.$name == "Third").count()
            #expect(persisted == 1)
        }
    }

    @Test("A create at the top without a create grant on the system container is not-found")
    func createAtTheTopWithoutTheGrantIsNotFound() async throws {
        try await withFluentTestApp { app in
            try configureSuite(app)
            try app.register(request: CreateWorkspaceRequest.self, app: app)
        } _: { app, db in
            app.storage[TestGrantsKey.self] = [suiteGrant([.readRecords])]
            let vmRequest = CreateWorkspaceRequest(query: nil, sort: nil, fragment: nil, requestBody: .init(name: "Third"), responseBody: nil)
            await #expect(throws: Abort.self) {
                _ = try await makeRequest(on: app).serveCreate(vmRequest, body: #require(vmRequest.requestBody))
            }
            let persisted = try await Workspace.query(on: db).count()
            #expect(persisted == 0)
        }
    }

    @Test("Creating, archiving, and destroying an owned row each emit the system container's identity")
    func writesAtTheTopEmitTheSystemIdentity() async throws {
        try await withFluentTestApp { app in
            try configureSuite(app, live: true)
        } _: { app, db in
            let quay = Quay(name: "East Quay")
            try await quay.save(on: db)
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            let workspace = Workspace(name: "Created")
            try await workspace.save(on: db)
            let created = await events.next()
            #expect(try created == [workspace.modelIdentity, Suite.identity])

            let mooring = try Mooring(tag: "A", quayId: quay.requireId())
            try await mooring.save(on: db)
            let mooringCreated = await events.next()
            #expect(try mooringCreated == [mooring.modelIdentity, quay.modelIdentity, Suite.identity])

            try await mooring.delete(on: db) // archive: the delete timestamp is set
            let archived = await events.next()
            #expect(try archived == [mooring.modelIdentity, quay.modelIdentity, Suite.identity])

            try await workspace.delete(force: true, on: db) // destroy
            let destroyed = await events.next()
            #expect(try destroyed == [workspace.modelIdentity, Suite.identity])
        }
    }
}
