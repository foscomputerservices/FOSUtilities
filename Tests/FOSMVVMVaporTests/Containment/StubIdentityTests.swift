// StubIdentityTests.swift
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

import Fluent // app.migrations lives in vapor/fluent
import FluentKit
import FOSFoundation
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing
import Vapor

private func configureWorkspace(_ app: Application) throws {
    app.migrations.add(CreatePier()) // CreateBoard's DDL references piers
    try app.register(Workspace.self, migration: CreateWorkspace())
    try app.register(Board.self, migration: CreateBoard())
    app.migrations.add(CreateCard())
    app.migrations.add(CreateMember())
    app.migrations.add(CreateBoardMember())
    try app.useModelAuthorizationProvider(TestGrantsProvider())
}

private func makeRequest(on app: Application) -> Request {
    Request(application: app, method: .GET, url: URI(string: "/"), on: app.eventLoopGroup.next())
}

/// The identity a client would send in a request body: a stub that crossed the wire.
private func stubFromRequestBody() throws -> ModelIdentity {
    try ModelIdentity.stub().toJSON().fromJSON()
}

@Suite("A stub identity reaching the server")
struct StubIdentityTests {
    /// Even with a grant naming the stub, the load stops at the registry with its typed error.
    @Test func aStubIdentityIsATypedMissOnLoad() async throws {
        try await withFluentTestApp { app in
            try configureWorkspace(app)
        } _: { app, _ in
            let stub = try stubFromRequestBody()
            app.storage[TestGrantsKey.self] = [TestGrant(
                authorizedModel: stub,
                operations: [.readRecords],
                recordTypes: [Card.modelIdentityNamespace]
            )]
            do {
                _ = try await makeRequest(on: app).authorizedRecords(
                    of: stub,
                    containing: Card.self,
                    for: .readRecords
                )
                Issue.record("expected ContainmentError.unregisteredNamespace")
            } catch let error as ContainmentError {
                guard case .unregisteredNamespace = error else {
                    Issue.record("wrong ContainmentError case: \(error)")
                    return
                }
            }
        }
    }

    @Test func aStubIdentityIsATypedMissOnCreate() async throws {
        try await withFluentTestApp { app in
            try configureWorkspace(app)
        } _: { app, db in
            let stub = try stubFromRequestBody()
            let card = Card()
            card.number = 1
            card.boardName = "Backlog"
            do {
                try await makeRequest(on: app).createMember(card, in: stub, on: db)
                Issue.record("expected ContainmentError.unregisteredNamespace")
            } catch let error as ContainmentError {
                guard case .unregisteredNamespace = error else {
                    Issue.record("wrong ContainmentError case: \(error)")
                    return
                }
            }
            #expect(try await Card.query(on: db).count() == 0)
        }
    }
}
