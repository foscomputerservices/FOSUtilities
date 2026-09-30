// SubjectScopeEngineTests.swift
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

private func configureWorkspace(_ app: Application) throws {
    app.migrations.add(CreatePier())
    try app.register(Workspace.self, migration: CreateWorkspace())
    try app.register(Board.self, migration: CreateBoard())
    app.migrations.add(CreateCard())
    try app.register(Member.self, migration: CreateMember()) // the plan's type must be registered
    app.migrations.add(CreateBoardMember())
    try app.useModelAuthorizationProvider(TestGrantsProvider())
}

private func makeRequest(on app: Application) -> Request {
    Request(application: app, method: .GET, url: URI(string: "/"), on: app.eventLoopGroup.next())
}

private func boardNames(_ records: [any DataModel]) throws -> Set<String> {
    try Set(records.map { try #require($0 as? Board).name })
}

@Suite("Subject-scope engine: named models and extended members, one refined load")
struct SubjectScopeEngineTests {
    @Test("A grant that names a Board with .read contributes that Board and nothing else")
    func namedModelOnly() async throws {
        try await withFluentTestApp(configure: configureWorkspace) { app, db in
            let (board1, _) = try await seedWorkspace(on: db)
            app.storage[TestGrantsKey.self] = try [
                TestGrant(authorizedModel: board1.modelIdentity, operations: [], recordTypes: [], modelOperations: [.read])
            ]
            let req = makeRequest(on: app)

            let boards = try await req.authorizedModels(ofType: Board.self, for: .readRecords)
            #expect(try boardNames(boards) == ["Board 1"])
        }
    }

    @Test("A grant on the Workspace extending readRecords of Board contributes every Board inside it")
    func extendedMembersOnly() async throws {
        try await withFluentTestApp(configure: configureWorkspace) { app, db in
            let (board1, _) = try await seedWorkspace(on: db)
            let workspace = try await board1.$workspace.get(on: db)
            app.storage[TestGrantsKey.self] = try [
                TestGrant(authorizedModel: workspace.modelIdentity, operations: [.readRecords], recordTypes: [Board.modelIdentityNamespace])
            ]
            let req = makeRequest(on: app)

            let boards = try await req.authorizedModels(ofType: Board.self, for: .readRecords)
            #expect(try boardNames(boards) == ["Board 1", "Board 2"])
        }
    }

    @Test("Both authorities union without duplicates")
    func unionDeduplicates() async throws {
        try await withFluentTestApp(configure: configureWorkspace) { app, db in
            let (board1, _) = try await seedWorkspace(on: db)
            let workspace = try await board1.$workspace.get(on: db)
            app.storage[TestGrantsKey.self] = try [
                TestGrant(authorizedModel: workspace.modelIdentity, operations: [.readRecords], recordTypes: [Board.modelIdentityNamespace]),
                TestGrant(authorizedModel: board1.modelIdentity, operations: [], recordTypes: [], modelOperations: [.read])
            ]
            let req = makeRequest(on: app)

            let boards = try await req.authorizedModels(ofType: Board.self, for: .readRecords)
            #expect(boards.count == 2)
            #expect(try boardNames(boards) == ["Board 1", "Board 2"])
        }
    }

    @Test("A grant that names a Board without model operations contributes nothing: the deny default")
    func denyDefaultContributesNothing() async throws {
        try await withFluentTestApp(configure: configureWorkspace) { app, db in
            let (board1, _) = try await seedWorkspace(on: db)
            app.storage[TestGrantsKey.self] = try [
                TestGrant(authorizedModel: board1.modelIdentity, operations: [.anyOperation], recordTypes: [Board.modelIdentityNamespace])
            ]
            let req = makeRequest(on: app)

            let boards = try await req.authorizedModels(ofType: Board.self, for: .readRecords)
            #expect(boards.isEmpty)
        }
    }

    @Test("The operation gates both authorities: a read grant does not make a Board archivable")
    func operationGatesBothAuthorities() async throws {
        try await withFluentTestApp(configure: configureWorkspace) { app, db in
            let (board1, _) = try await seedWorkspace(on: db)
            let workspace = try await board1.$workspace.get(on: db)
            app.storage[TestGrantsKey.self] = try [
                TestGrant(authorizedModel: workspace.modelIdentity, operations: [.readRecords], recordTypes: [Board.modelIdentityNamespace]),
                TestGrant(authorizedModel: board1.modelIdentity, operations: [], recordTypes: [], modelOperations: [.read])
            ]
            let req = makeRequest(on: app)

            let archivable = try await req.authorizedModels(ofType: Board.self, for: .archiveRecords)
            #expect(archivable.isEmpty)
        }
    }

    @Test("Members reached through a pivot count as extended members")
    func siblingsThroughThePivot() async throws {
        try await withFluentTestApp(configure: configureWorkspace) { app, db in
            let (board1, _) = try await seedWorkspace(on: db)
            app.storage[TestGrantsKey.self] = try [
                TestGrant(authorizedModel: board1.modelIdentity, operations: [.readRecords], recordTypes: [Member.modelIdentityNamespace])
            ]
            let req = makeRequest(on: app)

            let members = try await req.authorizedModels(ofType: Member.self, for: .readRecords)
            #expect(try Set(members.map { try #require($0 as? Member).name }) == ["Alice", "Bob"])
        }
    }

    @Test("A window pages across the union and the total counts the whole filtered set")
    func paginationAcrossTheUnion() async throws {
        try await withFluentTestApp(configure: configureWorkspace) { app, db in
            let (board1, _) = try await seedWorkspace(on: db)
            let workspace = try await board1.$workspace.get(on: db)
            app.storage[TestGrantsKey.self] = try [
                TestGrant(authorizedModel: workspace.modelIdentity, operations: [.readRecords], recordTypes: [Board.modelIdentityNamespace])
            ]
            let req = makeRequest(on: app)
            let window = Pagination(startIndex: 0, maxResults: 1)

            let page = try await req.authorizedModels(ofType: Board.self, for: .readRecords, pagination: window)
            #expect(page.count == 1)
            #expect(req.authorizedModelCount(ofType: Board.self, for: .readRecords, pagination: window) == 2)
            #expect(req.authorizedModelCount(ofType: Board.self, for: .readRecords) == nil)
        }
    }

    @Test("A subject with no grants loads empty, and the result is cached for the request")
    func emptyAndCached() async throws {
        try await withFluentTestApp(configure: configureWorkspace) { app, db in
            _ = try await seedWorkspace(on: db)
            app.storage[TestGrantsKey.self] = []
            let req = makeRequest(on: app)

            let first = try await req.authorizedModels(ofType: Board.self, for: .readRecords)
            #expect(first.isEmpty)
            app.storage[TestGrantsKey.self] = [] // grants are memoized: a later change never reaches this request
            let second = try await req.authorizedModels(ofType: Board.self, for: .readRecords)
            #expect(second.isEmpty)
        }
    }
}
