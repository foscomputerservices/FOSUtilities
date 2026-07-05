// WriteFixtures.swift
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

// Write-path fixtures (C8 T6). The write requests live in the "shared module" (query + refresh
// bridge); the `DataModelWriter` / `WriteTargetProviding` conformances live "server-side" (this
// same test target). NO RequestBody stores a ModelIdType — a submit cannot retarget.

import Fluent
import FluentKit
import FOSFoundation
import FOSMVVM
import FOSMVVMVapor
import Foundation
import Vapor

// MARK: - Queries

/// Roots a request at a Dock (the berths' container).
struct DockRootQuery: RootedQuery {
    let rootIdentity: ModelIdentity
}

/// Names both the scope root (RootedQuery) and the targeted berth (TargetedQuery). The target is
/// an opaque identity echoed from the ViewModel — never a raw id in the body.
struct BerthTargetQuery: TargetedQuery, RootedQuery {
    let rootIdentity: ModelIdentity
    let target: ModelIdentity
}

// MARK: - Refresh read screen (the write's fall-through body)

/// A read screen that surfaces its dock's berths — the body every write request refreshes to.
/// It reflects post-write state because it re-reads through the genuine load pipeline.
struct BerthListVM: RequestableViewModel, ComposableFactory, VaporResponseBodyFactory {
    typealias Request = BerthListRequest

    static let berths = LoadRequirement.read(Berth.self, in: .parentRoot)
    static var dataRequirements: [any DataRequirement] {
        [berths]
    }

    var vmId = ViewModelId()
    var berthNumbers: [Int] = []
    var berthNames: [String] = []

    init() {}
    init(berthNumbers: [Int], berthNames: [String]) {
        self.berthNumbers = berthNumbers
        self.berthNames = berthNames
    }

    func propertyNames() -> [LocalizableId: String] {
        [:]
    }

    static func stub() -> Self {
        .init()
    }

    static func body(context: ProjectionContext<BerthListRequest, Void>) throws -> Self {
        let berths = try context.records(Self.berths)
        return .init(
            berthNumbers: berths.map(\.number).sorted(),
            berthNames: berths.map(\.dockName)
        )
    }
}

/// The refresh body doubles as the write requests' ResponseBody — it adopts the write markers.
extension BerthListVM: UpdateResponseBody, CreateResponseBody {}

final class BerthListRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = DockRootQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: DockRootQuery?
    var responseBody: BerthListVM?

    init(query: DockRootQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: BerthListVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

// MARK: - Update

/// A bespoke per-request body — validated (number must be non-negative), never EmptyBody.
struct UpdateBerthBody: ServerRequestBody, ValidatableModel {
    var number: Int
    var dockName: String

    func validate(fields _: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        guard number >= 0 else {
            validations.validations.append(
                .init(status: .error, fieldId: .init(id: "number"), message: .constant("number must be non-negative"))
            )
            return .error
        }
        return nil
    }
}

/// SERVER target: one conformance carries candidates + sync apply (no Database).
extension UpdateBerthBody: DataModelWriter {
    static let candidates = LoadRequirement.write(Berth.self, in: .parentRoot)

    func apply(to berth: Berth) throws {
        berth.number = number
        berth.dockName = dockName
    }
}

final class UpdateBerthRequest: UpdateRequest, @unchecked Sendable {
    typealias Query = BerthTargetQuery
    typealias RequestBody = UpdateBerthBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = EmptyError
    typealias RefreshRequest = BerthListRequest
    typealias ResponseBody = BerthListVM

    let id: String
    let query: BerthTargetQuery?
    let requestBody: UpdateBerthBody?
    var responseBody: BerthListVM?

    init(query: BerthTargetQuery?, sort: EmptySort?, fragment: EmptyFragment?, requestBody: UpdateBerthBody?, responseBody: BerthListVM?) {
        self.id = .random(length: 10)
        self.query = query
        self.requestBody = requestBody
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }

    func refreshRequest() -> BerthListRequest {
        BerthListRequest(query: query.map { DockRootQuery(rootIdentity: $0.rootIdentity) })
    }
}

// MARK: - Create

struct CreateBerthBody: ServerRequestBody, ValidatableModel {
    var number: Int
    var dockName: String

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

extension CreateBerthBody: DataModelWriter {
    static let candidates = LoadRequirement.create(Berth.self, in: .parentRoot)

    func apply(to berth: Berth) throws {
        berth.number = number
        berth.dockName = dockName
    }
}

final class CreateBerthRequest: CreateRequest, @unchecked Sendable {
    typealias Query = DockRootQuery
    typealias RequestBody = CreateBerthBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = EmptyError
    typealias RefreshRequest = BerthListRequest
    typealias ResponseBody = BerthListVM

    let id: String
    let query: DockRootQuery?
    let requestBody: CreateBerthBody?
    var responseBody: BerthListVM?

    init(query: DockRootQuery?, sort: EmptySort?, fragment: EmptyFragment?, requestBody: CreateBerthBody?, responseBody: BerthListVM?) {
        self.id = .random(length: 10)
        self.query = query
        self.requestBody = requestBody
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }

    func refreshRequest() -> BerthListRequest {
        BerthListRequest(query: query.map { DockRootQuery(rootIdentity: $0.rootIdentity) })
    }
}

// MARK: - Delete Body

/// A bespoke empty body — conforming a shared empty-body type to WriteTargetProviding would be one
/// global retroactive conformance colliding across every delete request.
struct DeleteBerthBody: ServerRequestBody {}

extension DeleteBerthBody: WriteTargetProviding {
    static let candidates = LoadRequirement.delete(Berth.self, in: .parentRoot)
}

final class DeleteBerthRequest: DeleteRequest, @unchecked Sendable {
    typealias Query = BerthTargetQuery
    typealias RequestBody = DeleteBerthBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = EmptyError
    typealias RefreshRequest = BerthListRequest
    typealias ResponseBody = BerthListVM

    let id: String
    let query: BerthTargetQuery?
    let requestBody: DeleteBerthBody?
    var responseBody: BerthListVM?

    init(query: BerthTargetQuery?, sort: EmptySort?, fragment: EmptyFragment?, requestBody: DeleteBerthBody?, responseBody: BerthListVM?) {
        self.id = .random(length: 10)
        self.query = query
        self.requestBody = requestBody
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }

    func refreshRequest() -> BerthListRequest {
        BerthListRequest(query: query.map { DockRootQuery(rootIdentity: $0.rootIdentity) })
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// MARK: - Boot fail-fast fixtures (group 15)

// These are deliberately misconfigured; each exists to prove one boot-time rejection.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

// MARK: A ReplaceRequest — a not-yet-supported write protocol, reaches the read door.

struct ReplaceEchoBody: ServerRequestBody, VaporResponseBodyFactory, ReplaceResponseBody {
    typealias Request = EchoReplaceRequest
    static func body(context _: ProjectionContext<EchoReplaceRequest, Void>) throws -> Self {
        .init()
    }
}

struct EchoReplaceRequestBody: ServerRequestBody, ValidatableModel {
    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

final class EchoReplaceRequest: ReplaceRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias RequestBody = EchoReplaceRequestBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = EmptyError
    typealias ResponseBody = ReplaceEchoBody

    let id: String
    var requestBody: EchoReplaceRequestBody? {
        nil
    }

    var responseBody: ReplaceEchoBody?

    init(query _: EmptyQuery?, sort _: EmptySort?, fragment _: EmptyFragment?, requestBody _: EchoReplaceRequestBody?, responseBody: ReplaceEchoBody?) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }
}

// MARK: An UpdateRequest whose RequestBody is NOT a DataModelWriter — misses the write door, and

// whose RefreshRequest is itself, so it binds the base read door instead of failing to compile.

struct SelfEchoBody: ServerRequestBody, VaporResponseBodyFactory, UpdateResponseBody {
    typealias Request = SelfRefreshUpdateRequest
    static func body(context _: ProjectionContext<SelfRefreshUpdateRequest, Void>) throws -> Self {
        .init()
    }
}

struct NonWriterBody: ServerRequestBody, ValidatableModel {
    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

final class SelfRefreshUpdateRequest: UpdateRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias RequestBody = NonWriterBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = EmptyError
    typealias RefreshRequest = SelfRefreshUpdateRequest
    typealias ResponseBody = SelfEchoBody

    let id: String
    var requestBody: NonWriterBody? {
        nil
    }

    var responseBody: SelfEchoBody?

    init(query _: EmptyQuery?, sort _: EmptySort?, fragment _: EmptyFragment?, requestBody _: NonWriterBody?, responseBody: SelfEchoBody?) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }

    func refreshRequest() -> SelfRefreshUpdateRequest {
        self
    }
}

// MARK: An UpdateRequest whose candidate roots at `.query` but whose query is not RootedQuery.

struct TargetOnlyQuery: TargetedQuery {
    let target: ModelIdentity
}

final class NoRootUpdateRequest: UpdateRequest, @unchecked Sendable {
    typealias Query = TargetOnlyQuery
    typealias RequestBody = UpdateBerthBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = EmptyError
    typealias RefreshRequest = BerthListRequest
    typealias ResponseBody = BerthListVM

    let id: String
    var requestBody: UpdateBerthBody? {
        nil
    }

    let query: TargetOnlyQuery?
    var responseBody: BerthListVM?

    init(query: TargetOnlyQuery?, sort _: EmptySort?, fragment _: EmptyFragment?, requestBody _: UpdateBerthBody?, responseBody: BerthListVM?) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }

    func refreshRequest() -> BerthListRequest {
        BerthListRequest(query: nil)
    }
}

// MARK: An UpdateRequest whose candidate roots at `.apex` with no resolver registered.

struct ApexUpdateBody: ServerRequestBody, ValidatableModel {
    var number: Int

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

extension ApexUpdateBody: DataModelWriter {
    static let candidates = LoadRequirement.write(Berth.self, in: .newRoot(.apex), via: Dock.self)

    func apply(to berth: Berth) throws {
        berth.number = number
    }
}

final class ApexUpdateRequest: UpdateRequest, @unchecked Sendable {
    typealias Query = BerthTargetQuery
    typealias RequestBody = ApexUpdateBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = EmptyError
    typealias RefreshRequest = BerthListRequest
    typealias ResponseBody = BerthListVM

    let id: String
    var requestBody: ApexUpdateBody? {
        nil
    }

    let query: BerthTargetQuery?
    var responseBody: BerthListVM?

    init(query: BerthTargetQuery?, sort _: EmptySort?, fragment _: EmptyFragment?, requestBody _: ApexUpdateBody?, responseBody: BerthListVM?) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }

    func refreshRequest() -> BerthListRequest {
        BerthListRequest(query: query.map { DockRootQuery(rootIdentity: $0.rootIdentity) })
    }
}

// MARK: An UpdateRequest whose `candidates` is a COMPUTED property — mints fresh tokens.

struct ComputedCandidatesBody: ServerRequestBody, ValidatableModel {
    var number: Int

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

extension ComputedCandidatesBody: DataModelWriter {
    /// Deliberately computed (a `var`, not a stored `let`) — the token-stability lint rejects it.
    static var candidates: LoadRequirement<Berth> {
        .write(Berth.self, in: .parentRoot)
    }

    func apply(to berth: Berth) throws {
        berth.number = number
    }
}

final class ComputedCandidatesUpdateRequest: UpdateRequest, @unchecked Sendable {
    typealias Query = BerthTargetQuery
    typealias RequestBody = ComputedCandidatesBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = EmptyError
    typealias RefreshRequest = BerthListRequest
    typealias ResponseBody = BerthListVM

    let id: String
    var requestBody: ComputedCandidatesBody? {
        nil
    }

    let query: BerthTargetQuery?
    var responseBody: BerthListVM?

    init(query: BerthTargetQuery?, sort _: EmptySort?, fragment _: EmptyFragment?, requestBody _: ComputedCandidatesBody?, responseBody: BerthListVM?) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }

    func refreshRequest() -> BerthListRequest {
        BerthListRequest(query: query.map { DockRootQuery(rootIdentity: $0.rootIdentity) })
    }
}

// MARK: A read request whose `dataRequirements` is COMPUTED — the read-plan token lint rejects it.

struct ComputedReadVM: RequestableViewModel, ComposableFactory, VaporResponseBodyFactory {
    typealias Request = ComputedReadRequest

    /// Deliberately computed — mints fresh tokens on each access.
    static var dataRequirements: [any DataRequirement] {
        [LoadRequirement.read(Berth.self, in: .parentRoot)]
    }

    var vmId = ViewModelId()
    init() {}

    func propertyNames() -> [LocalizableId: String] {
        [:]
    }

    static func stub() -> Self {
        .init()
    }

    static func body(context _: ProjectionContext<ComputedReadRequest, Void>) throws -> Self {
        .init()
    }
}

final class ComputedReadRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = DockRootQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: DockRootQuery?
    var responseBody: ComputedReadVM?

    init(query: DockRootQuery? = nil, sort _: EmptySort? = nil, fragment _: EmptyFragment? = nil, requestBody _: EmptyBody? = nil, responseBody: ComputedReadVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

// MARK: A DeleteRequest whose candidates use the WRONG verb (.write at the delete door).

struct WrongVerbDeleteBody: ServerRequestBody {}

extension WrongVerbDeleteBody: WriteTargetProviding {
    static let candidates = LoadRequirement.write(Berth.self, in: .parentRoot)
}

final class WrongVerbDeleteRequest: DeleteRequest, @unchecked Sendable {
    typealias Query = BerthTargetQuery
    typealias RequestBody = WrongVerbDeleteBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = EmptyError
    typealias RefreshRequest = BerthListRequest
    typealias ResponseBody = BerthListVM

    let id: String
    let query: BerthTargetQuery?
    var requestBody: WrongVerbDeleteBody? {
        nil
    }

    var responseBody: BerthListVM?

    init(query: BerthTargetQuery?, sort _: EmptySort?, fragment _: EmptyFragment?, requestBody _: WrongVerbDeleteBody?, responseBody: BerthListVM?) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }

    func refreshRequest() -> BerthListRequest {
        BerthListRequest(query: query.map { DockRootQuery(rootIdentity: $0.rootIdentity) })
    }
}

// MARK: An UpdateRequest whose candidates carry `.refinedByRequest` — a windowed candidate set.

struct RefinedCandidatesBody: ServerRequestBody, ValidatableModel {
    var number: Int

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

extension RefinedCandidatesBody: DataModelWriter {
    static let candidates = LoadRequirement.write(Berth.self, in: .parentRoot).refinedByRequest

    func apply(to berth: Berth) throws {
        berth.number = number
    }
}

final class RefinedCandidatesUpdateRequest: UpdateRequest, @unchecked Sendable {
    typealias Query = BerthTargetQuery
    typealias RequestBody = RefinedCandidatesBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = EmptyError
    typealias RefreshRequest = BerthListRequest
    typealias ResponseBody = BerthListVM

    let id: String
    let query: BerthTargetQuery?
    var requestBody: RefinedCandidatesBody? {
        nil
    }

    var responseBody: BerthListVM?

    init(query: BerthTargetQuery?, sort _: EmptySort?, fragment _: EmptyFragment?, requestBody _: RefinedCandidatesBody?, responseBody: BerthListVM?) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }

    func refreshRequest() -> BerthListRequest {
        BerthListRequest(query: query.map { DockRootQuery(rootIdentity: $0.rootIdentity) })
    }
}

// MARK: A DestroyRequest — a not-yet-supported write protocol, reaches the read door.

struct DestroyEchoBody: ServerRequestBody, VaporResponseBodyFactory {
    typealias Request = EchoDestroyRequest
    static func body(context _: ProjectionContext<EchoDestroyRequest, Void>) throws -> Self {
        .init()
    }
}

final class EchoDestroyRequest: DestroyRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias RequestBody = EmptyBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = EmptyError
    typealias ResponseBody = DestroyEchoBody

    let id: String
    var responseBody: DestroyEchoBody?

    init(query _: EmptyQuery?, sort _: EmptySort?, fragment _: EmptyFragment?, requestBody _: EmptyBody?, responseBody: DestroyEchoBody?) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }
}
