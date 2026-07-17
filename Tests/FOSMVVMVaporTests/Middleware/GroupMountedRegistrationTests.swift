// GroupMountedRegistrationTests.swift
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

// The read door lives on `RoutesBuilder`: where a request mounts is the caller's
// decision (mount privileged reads behind a credential group), while its plan is
// derived regardless. These contracts pin that end to end through the served pipeline:
//   • a group's credential middleware guards the mounted read — no token → the TYPED
//     rejection (asserted on `credentialRejection`, never status alone); token → the body,
//   • root mounting through the Application receiver (an `Application` IS a `RoutesBuilder`)
//     serves normally,
//   • a path-prefixing group is rejected at registration, naming the request type — the
//     client derives the URL from the type, so a silent prefix would 404 at runtime.

import Fluent
import FluentKit
import FOSFoundation
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing
import Vapor
import VaporTesting

@Suite("Group-mounted registration (read door on RoutesBuilder)", .serialized)
struct GroupMountedRegistrationTests {
    /// Contract 1: a read mounted behind a credential group is guarded by that group's
    /// middleware. Without a token the request is rejected with the typed credential
    /// rejection; with the token the body arrives.
    @Test func groupMiddlewareGuardsTheMountedRead() async throws {
        try await withGuardApp { app in
            let authed = app.grouped(
                ClientCredentialMiddleware(verifier: BearerCredentialVerifier { $0 == "current-token" })
            )
            try authed.register(request: TestViewModelRequest.self, app: app)
        } _: { app in
            // No credential → the middleware rejects before the route runs.
            try await app.testing().test(TestViewModelRequest()) { response in
                #expect(response.status == .unauthorized)
                #expect(response.credentialRejection?.code == .missing) // typed, not status alone
                #expect(response.body == nil)
            }

            // Valid credential → the route runs and the body arrives.
            try await app.testing().test(
                TestViewModelRequest(),
                headers: ["Authorization": "Bearer current-token"]
            ) { response in
                #expect(response.status == .ok)
                #expect(response.credentialRejection == nil)
                #expect(response.body != nil)
            }
        }
    }

    /// Contract 3: mounting at the root through the Application receiver — an `Application`
    /// conforms to `RoutesBuilder`, so the same door serves an unguarded request normally.
    @Test func rootMountingThroughApplicationReceiverServes() async throws {
        try await withGuardApp { app in
            try app.register(request: TestViewModelRequest.self, app: app)
        } _: { app in
            try await app.testing().test(TestViewModelRequest()) { response in
                #expect(response.status == .ok)
                #expect(response.body != nil)
            }
        }
    }

    /// Contract 2: a write mounted behind a credential group is guarded BEFORE it mutates.
    /// A PATCH with no token is rejected by the middleware with the typed credential rejection
    /// and the record is unchanged in the database; a PATCH with the token mutates and returns
    /// the refreshed body.
    @Test func groupMiddlewareGuardsTheMountedWriteBeforeMutation() async throws {
        try await withGuardWriteApp { app in
            let authed = app.grouped(
                ClientCredentialMiddleware(verifier: BearerCredentialVerifier { $0 == "current-token" })
            )
            try authed.register(request: UpdateBerthRequest.self, app: app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            app.storage[TestGrantsKey.self] = try [TestGrant(
                authorizedContainer: dock1.modelIdentity,
                operations: [.readRecords, .writeRecords],
                recordTypes: [Berth.modelIdentityNamespace]
            )]
            let berth = try #require(try await Berth.query(on: db).filter(\.$dock.$id == dock1.requireId()).first())
            let originalNumber = berth.number
            let originalName = berth.dockName

            // No credential → the middleware rejects before the handler mutates anything.
            let unauthed = try UpdateBerthRequest(
                query: .init(rootIdentity: dock1.modelIdentity, target: berth.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: UpdateBerthBody(number: originalNumber + 100, dockName: "Hijacked"),
                responseBody: nil
            )
            try await app.testing().test(unauthed) { response in
                #expect(response.status == .unauthorized)
                #expect(response.credentialRejection?.code == .missing) // typed, not status alone
            }
            // The record is untouched — the write never ran.
            let afterReject = try #require(try await Berth.find(berth.requireId(), on: db))
            #expect(afterReject.number == originalNumber)
            #expect(afterReject.dockName == originalName)

            // Valid credential → the write commits and the response is the refreshed body.
            let authedReq = try UpdateBerthRequest(
                query: .init(rootIdentity: dock1.modelIdentity, target: berth.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: UpdateBerthBody(number: 88, dockName: "Wired"),
                responseBody: nil
            )
            try await app.testing().test(
                authedReq,
                headers: ["Authorization": "Bearer current-token"]
            ) { response in
                #expect(response.status == .ok)
                #expect(response.credentialRejection == nil)
                let body = try #require(response.body)
                #expect(body.berthNumbers.contains(88))
            }
            let afterWrite = try #require(try await Berth.find(berth.requireId(), on: db))
            #expect(afterWrite.number == 88)
            #expect(afterWrite.dockName == "Wired")
        }
    }

    /// Contract 4: a path-prefixing group changes the served URL while the client keeps
    /// deriving it from the request type — registration rejects that at boot, naming the
    /// request type and the actual mounted path.
    @Test func pathPrefixingGroupIsRejectedAtRegistration() async throws {
        try await withGuardApp { app in
            do {
                try app.grouped("admin").register(request: TestViewModelRequest.self, app: app)
                Issue.record("expected registration on a path-prefixing group to throw")
            } catch ContainmentError.pathPrefixedMount(let request, let mountedPath) {
                #expect(request.contains("TestViewModelRequest"))
                #expect(mountedPath.contains("admin"))
            }
        } _: { _ in }
    }

    /// Contract 6: a plan-bearing request mounted behind the credential middleware still carries
    /// its executed plan's staleness surface as `X-FOS-Registrations` when served with the token —
    /// guarding the route does not strip the live-invalidation header.
    @Test func registrationsHeaderRidesAGuardedRoute() async throws {
        try await withGuardWriteApp { app in
            let authed = app.grouped(
                ClientCredentialMiddleware(verifier: BearerCredentialVerifier { $0 == "current-token" })
            )
            try authed.register(request: BerthListRequest.self, app: app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            app.storage[TestGrantsKey.self] = try [TestGrant(
                authorizedContainer: dock1.modelIdentity,
                operations: [.readRecords],
                recordTypes: [Berth.modelIdentityNamespace]
            )]

            try await app.testing().test(
                BerthListRequest(query: .init(rootIdentity: dock1.modelIdentity)),
                headers: ["Authorization": "Bearer current-token"]
            ) { response in
                #expect(response.status == .ok)
                let value = try #require(response.headers.first(name: ModelIdentity.registrationsHeader))
                let carried: [ModelIdentity] = try value.fromJSON()
                #expect(try Set(carried) == [dock1.modelIdentity]) // membership via public equality
            }
        }
    }
}

/// Boots an in-process `.testing` Application with the YAML localization store and FOS
/// `ErrorMiddleware.default` installed (so a credential rejection surfaces as the typed
/// envelope `credentialRejection` decodes), runs `configure` then `body`, and shuts the
/// app down on both the success and failure paths.
private func withGuardApp(
    configure: (Application) throws -> Void,
    _ body: (Application) async throws -> Void
) async throws {
    let app = try await Application.make(.testing)
    do {
        try app.initYamlLocalization(bundle: Bundle.module, resourceDirectoryName: "TestYAML")
        app.middleware = .init()
        app.middleware.use(FOSMVVMVapor.ErrorMiddleware.default(environment: app.environment))
        try configure(app)
        // asyncBoot (not app.testing()'s sync boot): the YAML localization store loads through an
        // async lifecycle handler that only runs under async boot.
        try await app.asyncBoot()
        try await body(app)
    } catch {
        try await app.asyncShutdown()
        throw error
    }
    try await app.asyncShutdown()
}

/// The write-guard variant of `withGuardApp`: a fresh in-memory SQLite database (the write reads
/// its record back), the Harbor→Dock→Berth container graph plus an authorization provider, YAML
/// localization, and FOS `ErrorMiddleware.default` (so a credential rejection surfaces as the typed
/// envelope `credentialRejection` decodes). Runs `configure` then `body`, always shutting down.
private func withGuardWriteApp(
    configure: @Sendable (Application) throws -> Void,
    _ body: @Sendable (Application, any Database) async throws -> Void
) async throws {
    try await withFluentTestApp { app in
        try app.initYamlLocalization(bundle: Bundle.module, resourceDirectoryName: "TestYAML")
        app.middleware = .init()
        app.middleware.use(FOSMVVMVapor.ErrorMiddleware.default(environment: app.environment))
        app.migrations.add(CreatePier()) // CreateDock's DDL references piers
        try app.register(Harbor.self, migration: CreateHarbor())
        try app.register(Dock.self, migration: CreateDock())
        app.migrations.add(CreateBerth())
        app.migrations.add(CreateCrewMember())
        app.migrations.add(CreateDockCrew())
        try app.useContainerAuthorizationProvider(TestGrantsProvider())
        try configure(app)
    } _: { app, db in
        try await body(app, db)
    }
}
