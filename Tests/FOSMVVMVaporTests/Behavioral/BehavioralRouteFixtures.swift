// BehavioralRouteFixtures.swift
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

// Fixtures for the archive route's boot check (design 1.11): one archive request whose target
// declares a delete timestamp, one whose target does not.

import Fluent
import FluentKit
import FOSFoundation
import FOSMVVM
import FOSMVVMVapor
import Foundation
import Vapor

// MARK: - A soft-deletable contained model

final class BehavioralRelic: DataModel, BehavioralRecording, @unchecked Sendable {
    static let schema = "behavioral_relics"
    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Parent(key: "vault_id") var vault: BehavioralVault
    @Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?
    init() {}
    init(name: String, vaultId: ModelIdType) {
        self.name = name
        $vault.id = vaultId
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

struct CreateBehavioralVault: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(BehavioralVault.schema).id().field("name", .string, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(BehavioralVault.schema).delete()
    }
}

struct CreateBehavioralCurio: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(BehavioralCurio.schema).id()
            .field("name", .string, .required)
            .field("vault_id", .uuid, .required, .references(BehavioralVault.schema, "id"))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(BehavioralCurio.schema).delete()
    }
}

struct CreateBehavioralRelic: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(BehavioralRelic.schema).id()
            .field("name", .string, .required)
            .field("vault_id", .uuid, .required, .references(BehavioralVault.schema, "id"))
            .field("deleted_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(BehavioralRelic.schema).delete()
    }
}

/// The container both archive requests root at.
final class BehavioralVault: ContainerDataModel, BehavioralRecording, @unchecked Sendable {
    static let schema = "behavioral_vaults"
    static var containedRecordTypes: [any FOSMVVM.Model.Type] {
        [BehavioralRelic.self, BehavioralCurio.self]
    }

    static var containment: [ContainmentRelation] {
        [.children(\BehavioralVault.$relics), .children(\BehavioralVault.$curios)]
    }

    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Children(for: \.$vault) var relics: [BehavioralRelic]
    @Children(for: \.$vault) var curios: [BehavioralCurio]
    init() {}
    init(name: String) {
        self.name = name
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

/// No delete timestamp — the archive route must refuse it at boot.
final class BehavioralCurio: DataModel, BehavioralRecording, @unchecked Sendable {
    static let schema = "behavioral_curios"
    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Parent(key: "vault_id") var vault: BehavioralVault
    init() {}
    init(name: String, vaultId: ModelIdType) {
        self.name = name
        $vault.id = vaultId
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

// MARK: - Queries

struct BehavioralVaultRootQuery: RootedQuery {
    let rootIdentity: ModelIdentity
}

struct BehavioralVaultTargetQuery: TargetedQuery, RootedQuery {
    let rootIdentity: ModelIdentity
    let target: ModelIdentity
}

// MARK: - The refresh body both archive requests answer with

struct BehavioralVaultVM: RequestableViewModel, ComposableFactory, VaporResponseBodyFactory {
    typealias Request = BehavioralVaultRequest

    static let relics = LoadRequirement.read(BehavioralRelic.self, in: .parentRoot)
    static var dataRequirements: [any DataRequirement] {
        [relics]
    }

    var vmId = ViewModelId()
    var relicNames: [String] = []

    init() {}
    init(relicNames: [String]) {
        self.relicNames = relicNames
    }

    func propertyNames() -> [LocalizableId: String] {
        [:]
    }

    static func stub() -> Self {
        .init()
    }

    static func body<R: ServerRequest>(context: ProjectionContext<R, Void>) throws -> Self where R.ResponseBody == Self {
        try .init(relicNames: context.records(Self.relics).map(\.name))
    }
}

extension BehavioralVaultVM: ArchiveResponseBody {}

final class BehavioralVaultRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = BehavioralVaultRootQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: BehavioralVaultRootQuery?
    var responseBody: BehavioralVaultVM?

    init(
        query: BehavioralVaultRootQuery? = nil,
        sort: EmptySort? = nil,
        fragment: EmptyFragment? = nil,
        requestBody: EmptyBody? = nil,
        responseBody: BehavioralVaultVM? = nil
    ) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

// MARK: - Archive of a model that declares a delete timestamp

struct ArchiveBehavioralRelicBody: ServerRequestBody, ValidatableModel {
    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

extension ArchiveBehavioralRelicBody: WriteTargetProviding {
    static let candidates = LoadRequirement.archive(BehavioralRelic.self, in: .parentRoot)
}

final class BehavioralRelicArchiveRequest: ArchiveRequest, @unchecked Sendable {
    typealias Query = BehavioralVaultTargetQuery
    typealias RequestBody = ArchiveBehavioralRelicBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = ValidationError
    typealias ResponseBody = BehavioralVaultVM

    let id: String
    let query: BehavioralVaultTargetQuery?
    let requestBody: ArchiveBehavioralRelicBody?
    var responseBody: BehavioralVaultVM?

    init(
        query: BehavioralVaultTargetQuery?,
        sort: EmptySort?,
        fragment: EmptyFragment?,
        requestBody: ArchiveBehavioralRelicBody?,
        responseBody: BehavioralVaultVM?
    ) {
        self.id = .random(length: 10)
        self.query = query
        self.requestBody = requestBody
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }
}

// MARK: - Archive of a model that declares none

struct ArchiveBehavioralCurioBody: ServerRequestBody, ValidatableModel {
    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

extension ArchiveBehavioralCurioBody: WriteTargetProviding {
    static let candidates = LoadRequirement.archive(BehavioralCurio.self, in: .parentRoot)
}

final class BehavioralCurioArchiveRequest: ArchiveRequest, @unchecked Sendable {
    typealias Query = BehavioralVaultTargetQuery
    typealias RequestBody = ArchiveBehavioralCurioBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = ValidationError
    typealias ResponseBody = BehavioralVaultVM

    let id: String
    let query: BehavioralVaultTargetQuery?
    let requestBody: ArchiveBehavioralCurioBody?
    var responseBody: BehavioralVaultVM?

    init(
        query: BehavioralVaultTargetQuery?,
        sort: EmptySort?,
        fragment: EmptyFragment?,
        requestBody: ArchiveBehavioralCurioBody?,
        responseBody: BehavioralVaultVM?
    ) {
        self.id = .random(length: 10)
        self.query = query
        self.requestBody = requestBody
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }
}

/// Registers the vault graph: the container, its soft-deletable child and its timestamp-less one.
func registerBehavioralVault(_ app: Application) throws {
    try app.register(BehavioralVault.self, migration: CreateBehavioralVault())
    app.migrations.add(CreateBehavioralRelic())
    app.migrations.add(CreateBehavioralCurio())
}
