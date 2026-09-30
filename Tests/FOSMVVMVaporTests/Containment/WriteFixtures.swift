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

/// Roots a request at a Board (the cards' container).
struct BoardRootQuery: ScopedQuery {
    let scopeIdentity: ModelIdentity
}

/// Names both the scope root (ScopedQuery) and the targeted card (TargetedQuery). The target is
/// an opaque identity echoed from the ViewModel — never a raw id in the body.
struct CardTargetQuery: TargetedQuery, ScopedQuery {
    let scopeIdentity: ModelIdentity
    let target: ModelIdentity
}

// MARK: - Refresh read screen (the write's fall-through body)

/// A read screen that surfaces its board's cards — the body every write request refreshes to.
/// It reflects post-write state because it re-reads through the genuine load pipeline.
struct CardListVM: RequestableViewModel, ComposableFactory, VaporResponseBodyFactory {
    typealias Request = CardListRequest

    static let cards = Card.loadingPlan(.read, within: .parent)
    static var loadingPlans: LoadingPlans {
        cards
    }

    var vmId = ViewModelId()
    var cardNumbers: [Int] = []
    var cardNames: [String] = []

    init() {}
    init(cardNumbers: [Int], cardNames: [String]) {
        self.cardNumbers = cardNumbers
        self.cardNames = cardNames
    }

    func propertyNames() -> [LocalizableId: String] {
        [:]
    }

    static func stub() -> Self {
        .init()
    }

    static func body<R: ServerRequest>(context: ProjectionContext<R, Void>) throws -> Self where R.ResponseBody == Self {
        let cards = try context.records(Self.cards)
        return .init(
            cardNumbers: cards.map(\.number).sorted(),
            cardNames: cards.map(\.boardName)
        )
    }
}

/// The refresh body doubles as the write requests' ResponseBody — it adopts the write markers.
extension CardListVM: UpdateResponseBody, CreateResponseBody, ArchiveResponseBody {}

final class CardListRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = BoardRootQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: BoardRootQuery?
    var responseBody: CardListVM?

    init(query: BoardRootQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: CardListVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

// MARK: - Update

/// A bespoke per-request body — validated (number must be non-negative), never EmptyBody.
struct UpdateCardBody: ServerRequestBody, ValidatableModel {
    var number: Int
    var boardName: String

    func validate(fields _: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        guard number >= 0 else {
            validations.append(
                .init(status: .error, fieldId: #fieldId(\Self.number), message: .constant("number must be non-negative"))
            )
            return .error
        }
        return nil
    }
}

/// SERVER target: one conformance carries candidates + sync apply (no Database).
extension UpdateCardBody: DataModelWriter {
    static let candidates = Card.loadingPlan(.write, within: .parent)

    func apply(to card: Card) throws {
        card.number = number
        card.boardName = boardName
    }
}

final class UpdateCardRequest: UpdateRequest, @unchecked Sendable {
    typealias Query = CardTargetQuery
    typealias RequestBody = UpdateCardBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = ValidationError
    typealias ResponseBody = CardListVM

    let id: String
    let query: CardTargetQuery?
    let requestBody: UpdateCardBody?
    var responseBody: CardListVM?

    init(query: CardTargetQuery?, sort: EmptySort?, fragment: EmptyFragment?, requestBody: UpdateCardBody?, responseBody: CardListVM?) {
        self.id = .random(length: 10)
        self.query = query
        self.requestBody = requestBody
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }
}

// MARK: - Create

struct CreateCardBody: ServerRequestBody, ValidatableModel {
    var number: Int
    var boardName: String

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

extension CreateCardBody: DataModelWriter {
    static let candidates = Card.creationPlan(within: .parent)

    func apply(to card: Card) throws {
        card.number = number
        card.boardName = boardName
    }
}

final class CreateCardRequest: CreateRequest, @unchecked Sendable {
    typealias Query = BoardRootQuery
    typealias RequestBody = CreateCardBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = ValidationError
    typealias ResponseBody = CardListVM

    let id: String
    let query: BoardRootQuery?
    let requestBody: CreateCardBody?
    var responseBody: CardListVM?

    init(query: BoardRootQuery?, sort: EmptySort?, fragment: EmptyFragment?, requestBody: CreateCardBody?, responseBody: CardListVM?) {
        self.id = .random(length: 10)
        self.query = query
        self.requestBody = requestBody
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }
}

// MARK: - Archive Body

/// A bespoke empty body — conforming a shared empty-body type to WriteTargetProviding would be one
/// global retroactive conformance colliding across every delete request.
struct ArchiveCardBody: ServerRequestBody {}

extension ArchiveCardBody: WriteTargetProviding {
    static let candidates = Card.loadingPlan(.archive, within: .parent)
}

final class ArchiveCardRequest: ArchiveRequest, @unchecked Sendable {
    typealias Query = CardTargetQuery
    typealias RequestBody = ArchiveCardBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = ValidationError
    typealias ResponseBody = CardListVM

    let id: String
    let query: CardTargetQuery?
    let requestBody: ArchiveCardBody?
    var responseBody: CardListVM?

    init(query: CardTargetQuery?, sort: EmptySort?, fragment: EmptyFragment?, requestBody: ArchiveCardBody?, responseBody: CardListVM?) {
        self.id = .random(length: 10)
        self.query = query
        self.requestBody = requestBody
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// MARK: - Boot fail-fast fixtures (group 15)

// These are deliberately misconfigured; each exists to prove one boot-time rejection.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

// MARK: A ReplaceRequest — a not-yet-supported write protocol, reaches the read door.

struct ReplaceEchoBody: ServerRequestBody, VaporResponseBodyFactory, ReplaceResponseBody {
    typealias Request = EchoReplaceRequest
    static func body<R: ServerRequest>(context _: ProjectionContext<R, Void>) throws -> Self where R.ResponseBody == Self {
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
    typealias ResponseError = ValidationError
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

// MARK: An UpdateRequest whose RequestBody is NOT a DataModelWriter — so it misses the write door

// and binds the base read door instead of failing to compile.

struct SelfEchoBody: ServerRequestBody, VaporResponseBodyFactory, UpdateResponseBody {
    typealias Request = SelfRefreshUpdateRequest
    static func body<R: ServerRequest>(context _: ProjectionContext<R, Void>) throws -> Self where R.ResponseBody == Self {
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
    typealias ResponseError = ValidationError
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
}

// MARK: An UpdateRequest whose candidate roots at `.query` but whose query is not ScopedQuery.

struct TargetOnlyQuery: TargetedQuery {
    let target: ModelIdentity
}

final class NoRootUpdateRequest: UpdateRequest, @unchecked Sendable {
    typealias Query = TargetOnlyQuery
    typealias RequestBody = UpdateCardBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = ValidationError
    typealias ResponseBody = CardListVM

    let id: String
    var requestBody: UpdateCardBody? {
        nil
    }

    let query: TargetOnlyQuery?
    var responseBody: CardListVM?

    init(query: TargetOnlyQuery?, sort _: EmptySort?, fragment _: EmptyFragment?, requestBody _: UpdateCardBody?, responseBody: CardListVM?) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }
}

// MARK: An UpdateRequest whose candidate is within `.application` with none registered.

struct ApplicationUpdateBody: ServerRequestBody, ValidatableModel {
    var number: Int

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

extension ApplicationUpdateBody: DataModelWriter {
    static let candidates = Card.loadingPlan(.write, within: .application, via: Board.self)

    func apply(to card: Card) throws {
        card.number = number
    }
}

final class ApplicationUpdateRequest: UpdateRequest, @unchecked Sendable {
    typealias Query = CardTargetQuery
    typealias RequestBody = ApplicationUpdateBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = ValidationError
    typealias ResponseBody = CardListVM

    let id: String
    var requestBody: ApplicationUpdateBody? {
        nil
    }

    let query: CardTargetQuery?
    var responseBody: CardListVM?

    init(query: CardTargetQuery?, sort _: EmptySort?, fragment _: EmptyFragment?, requestBody _: ApplicationUpdateBody?, responseBody: CardListVM?) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
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
    static var candidates: LoadingPlan<Card> {
        Card.loadingPlan(.write, within: .parent)
    }

    func apply(to card: Card) throws {
        card.number = number
    }
}

final class ComputedCandidatesUpdateRequest: UpdateRequest, @unchecked Sendable {
    typealias Query = CardTargetQuery
    typealias RequestBody = ComputedCandidatesBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = ValidationError
    typealias ResponseBody = CardListVM

    let id: String
    var requestBody: ComputedCandidatesBody? {
        nil
    }

    let query: CardTargetQuery?
    var responseBody: CardListVM?

    init(query: CardTargetQuery?, sort _: EmptySort?, fragment _: EmptyFragment?, requestBody _: ComputedCandidatesBody?, responseBody: CardListVM?) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }
}

// MARK: A read request whose `loadingPlans` mints inline — the read-plan token lint rejects it.

struct ComputedReadVM: RequestableViewModel, ComposableFactory, VaporResponseBodyFactory {
    typealias Request = ComputedReadRequest

    /// Deliberately computed — mints fresh tokens on each access.
    static var loadingPlans: LoadingPlans {
        Card.loadingPlan(.read, within: .parent)
    }

    var vmId = ViewModelId()
    init() {}

    func propertyNames() -> [LocalizableId: String] {
        [:]
    }

    static func stub() -> Self {
        .init()
    }

    static func body<R: ServerRequest>(context _: ProjectionContext<R, Void>) throws -> Self where R.ResponseBody == Self {
        .init()
    }
}

final class ComputedReadRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = BoardRootQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: BoardRootQuery?
    var responseBody: ComputedReadVM?

    init(query: BoardRootQuery? = nil, sort _: EmptySort? = nil, fragment _: EmptyFragment? = nil, requestBody _: EmptyBody? = nil, responseBody: ComputedReadVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

// MARK: An ArchiveRequest whose candidates use the WRONG verb (.write at the archive door).

struct WrongVerbArchiveBody: ServerRequestBody {}

extension WrongVerbArchiveBody: WriteTargetProviding {
    static let candidates = Card.loadingPlan(.write, within: .parent)
}

final class WrongVerbArchiveRequest: ArchiveRequest, @unchecked Sendable {
    typealias Query = CardTargetQuery
    typealias RequestBody = WrongVerbArchiveBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = ValidationError
    typealias ResponseBody = CardListVM

    let id: String
    let query: CardTargetQuery?
    var requestBody: WrongVerbArchiveBody? {
        nil
    }

    var responseBody: CardListVM?

    init(query: CardTargetQuery?, sort _: EmptySort?, fragment _: EmptyFragment?, requestBody _: WrongVerbArchiveBody?, responseBody: CardListVM?) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
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
    static let candidates = Card.loadingPlan(.write, within: .parent).refinedByRequest

    func apply(to card: Card) throws {
        card.number = number
    }
}

final class RefinedCandidatesUpdateRequest: UpdateRequest, @unchecked Sendable {
    typealias Query = CardTargetQuery
    typealias RequestBody = RefinedCandidatesBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = ValidationError
    typealias ResponseBody = CardListVM

    let id: String
    let query: CardTargetQuery?
    var requestBody: RefinedCandidatesBody? {
        nil
    }

    var responseBody: CardListVM?

    init(query: CardTargetQuery?, sort _: EmptySort?, fragment _: EmptyFragment?, requestBody _: RefinedCandidatesBody?, responseBody: CardListVM?) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }
}

// MARK: A DestroyRequest — a not-yet-supported write protocol, reaches the read door.

struct DestroyEchoBody: ServerRequestBody, VaporResponseBodyFactory, DestroyResponseBody {
    typealias Request = EchoDestroyRequest
    static func body<R: ServerRequest>(context _: ProjectionContext<R, Void>) throws -> Self where R.ResponseBody == Self {
        .init()
    }
}

final class EchoDestroyRequest: DestroyRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias RequestBody = EmptyBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = ValidationError
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

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// MARK: - The archivable container: a Quay of Moorings

// Mooring declares a delete timestamp, so `delete(on:)` marks its row and `delete(force:on:)`
// removes it. Card deliberately declares none — it is the model an archive registration refuses.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

final class Quay: ContainerDataModel, @unchecked Sendable {
    static let schema = "quays"
    static var containedRecordTypes: [any FOSMVVM.Model.Type] {
        [Mooring.self]
    }

    static var containment: [ContainmentRelation] {
        [.children(\Quay.$moorings)]
    }

    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Children(for: \.$quay) var moorings: [Mooring]
    init() {}
    init(name: String) {
        self.name = name
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

final class Mooring: DataModel, @unchecked Sendable {
    static let schema = "moorings"
    @ID(key: .id) var id: UUID?
    @Field(key: "tag") var tag: String
    @Parent(key: "quay_id") var quay: Quay
    @Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?
    /// A mooring carrying this tag is one the model's own rules refuse to remove.
    static let refusedTag = "REFUSED"

    init() {}
    init(tag: String, quayId: ModelIdType) {
        self.tag = tag
        $quay.id = quayId
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }

    func validateModel(in context: DataModelWriteContext) async throws -> [FOSMVVM.ValidationResult] {
        guard tag == Self.refusedTag, context.action == .archive || context.action == .destroy else {
            return []
        }
        return [.init(status: .error, message: .constant("that mooring is still in use"))]
    }
}

struct CreateQuay: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Quay.schema).id().field("name", .string, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Quay.schema).delete()
    }
}

struct CreateMooring: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Mooring.schema).id()
            .field("tag", .string, .required)
            .field("quay_id", .uuid, .required, .references(Quay.schema, "id"))
            .field("deleted_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Mooring.schema).delete()
    }
}

/// Roots a request at a Quay and names the targeted mooring.
struct MooringTargetQuery: TargetedQuery, ScopedQuery {
    let scopeIdentity: ModelIdentity
    let target: ModelIdentity
}

/// Roots a request at a Quay.
struct QuayRootQuery: ScopedQuery {
    let scopeIdentity: ModelIdentity
}

/// The refresh body both deletion verbs fall through to — a live mooring is one Fluent excludes
/// once its delete timestamp is set, so an archived mooring drops out of `tags` too.
struct MooringListVM: RequestableViewModel, ComposableFactory, VaporResponseBodyFactory {
    typealias Request = MooringListRequest

    static let moorings = Mooring.loadingPlan(.read, within: .parent)
    static var loadingPlans: LoadingPlans {
        moorings
    }

    var vmId = ViewModelId()
    var tags: [String] = []

    init() {}
    init(tags: [String]) {
        self.tags = tags
    }

    func propertyNames() -> [LocalizableId: String] {
        [:]
    }

    static func stub() -> Self {
        .init()
    }

    static func body<R: ServerRequest>(context: ProjectionContext<R, Void>) throws -> Self where R.ResponseBody == Self {
        let moorings = try context.records(Self.moorings)
        return .init(tags: moorings.map(\.tag).sorted())
    }
}

extension MooringListVM: ArchiveResponseBody, DestroyResponseBody {}

final class MooringListRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = QuayRootQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: QuayRootQuery?
    var responseBody: MooringListVM?

    init(query: QuayRootQuery? = nil, sort _: EmptySort? = nil, fragment _: EmptyFragment? = nil, requestBody _: EmptyBody? = nil, responseBody: MooringListVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

struct ArchiveMooringBody: ServerRequestBody {}

extension ArchiveMooringBody: WriteTargetProviding {
    static let candidates = Mooring.loadingPlan(.archive, within: .parent)
}

final class ArchiveMooringRequest: ArchiveRequest, @unchecked Sendable {
    typealias Query = MooringTargetQuery
    typealias RequestBody = ArchiveMooringBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = ValidationError
    typealias ResponseBody = MooringListVM

    let id: String
    let query: MooringTargetQuery?
    var requestBody: ArchiveMooringBody? {
        nil
    }

    var responseBody: MooringListVM?

    init(query: MooringTargetQuery?, sort _: EmptySort?, fragment _: EmptyFragment?, requestBody _: ArchiveMooringBody?, responseBody: MooringListVM?) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }
}

struct DestroyMooringBody: ServerRequestBody {}

extension DestroyMooringBody: WriteTargetProviding {
    static let candidates = Mooring.loadingPlan(.destroy, within: .parent)
}

final class DestroyMooringRequest: DestroyRequest, @unchecked Sendable {
    typealias Query = MooringTargetQuery
    typealias RequestBody = DestroyMooringBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = ValidationError
    typealias ResponseBody = MooringListVM

    let id: String
    let query: MooringTargetQuery?
    var requestBody: DestroyMooringBody? {
        nil
    }

    var responseBody: MooringListVM?

    init(query: MooringTargetQuery?, sort _: EmptySort?, fragment _: EmptyFragment?, requestBody _: DestroyMooringBody?, responseBody: MooringListVM?) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// MARK: - Writes within the subject scope

// The candidate set is whatever the subject's grants reach — a Mooring a grant names with the
// verb's model operation, or a Mooring inside a Quay whose grant extends the verb to Moorings —
// so the query names only the target. The refresh body lists the subject's Moorings the same way.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

struct SubjectMooringListVM: RequestableViewModel, ComposableFactory, VaporResponseBodyFactory {
    typealias Request = SubjectMooringListRequest

    static let moorings = Mooring.loadingPlan(.read, within: .subject)
    static var loadingPlans: LoadingPlans {
        moorings
    }

    var vmId = ViewModelId()
    var tags: [String] = []

    init() {}
    init(tags: [String]) {
        self.tags = tags
    }

    func propertyNames() -> [LocalizableId: String] {
        [:]
    }

    static func stub() -> Self {
        .init()
    }

    static func body<R: ServerRequest>(context: ProjectionContext<R, Void>) throws -> Self where R.ResponseBody == Self {
        let moorings = try context.records(Self.moorings)
        return .init(tags: moorings.map(\.tag).sorted())
    }
}

extension SubjectMooringListVM: UpdateResponseBody, ArchiveResponseBody, DestroyResponseBody {}

final class SubjectMooringListRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias ResponseError = EmptyError

    let id: String
    var responseBody: SubjectMooringListVM?

    init(query _: EmptyQuery? = nil, sort _: EmptySort? = nil, fragment _: EmptyFragment? = nil, requestBody _: EmptyBody? = nil, responseBody: SubjectMooringListVM? = nil) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }
}

struct UpdateMooringBody: ServerRequestBody, ValidatableModel {
    var tag: String

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

extension UpdateMooringBody: DataModelWriter {
    static let candidates = Mooring.loadingPlan(.write, within: .subject)

    func apply(to mooring: Mooring) throws {
        mooring.tag = tag
    }
}

final class SubjectUpdateMooringRequest: UpdateRequest, @unchecked Sendable {
    typealias Query = TargetOnlyQuery
    typealias RequestBody = UpdateMooringBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = ValidationError
    typealias ResponseBody = SubjectMooringListVM

    let id: String
    let query: TargetOnlyQuery?
    let requestBody: UpdateMooringBody?
    var responseBody: SubjectMooringListVM?

    init(query: TargetOnlyQuery?, sort _: EmptySort?, fragment _: EmptyFragment?, requestBody: UpdateMooringBody?, responseBody: SubjectMooringListVM?) {
        self.id = .random(length: 10)
        self.query = query
        self.requestBody = requestBody
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }
}

struct SubjectArchiveMooringBody: ServerRequestBody {}

extension SubjectArchiveMooringBody: WriteTargetProviding {
    static let candidates = Mooring.loadingPlan(.archive, within: .subject)
}

final class SubjectArchiveMooringRequest: ArchiveRequest, @unchecked Sendable {
    typealias Query = TargetOnlyQuery
    typealias RequestBody = SubjectArchiveMooringBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = ValidationError
    typealias ResponseBody = SubjectMooringListVM

    let id: String
    let query: TargetOnlyQuery?
    var requestBody: SubjectArchiveMooringBody? {
        nil
    }

    var responseBody: SubjectMooringListVM?

    init(query: TargetOnlyQuery?, sort _: EmptySort?, fragment _: EmptyFragment?, requestBody _: SubjectArchiveMooringBody?, responseBody: SubjectMooringListVM?) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }
}

struct SubjectDestroyMooringBody: ServerRequestBody {}

extension SubjectDestroyMooringBody: WriteTargetProviding {
    static let candidates = Mooring.loadingPlan(.destroy, within: .subject)
}

final class SubjectDestroyMooringRequest: DestroyRequest, @unchecked Sendable {
    typealias Query = TargetOnlyQuery
    typealias RequestBody = SubjectDestroyMooringBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = ValidationError
    typealias ResponseBody = SubjectMooringListVM

    let id: String
    let query: TargetOnlyQuery?
    var requestBody: SubjectDestroyMooringBody? {
        nil
    }

    var responseBody: SubjectMooringListVM?

    init(query: TargetOnlyQuery?, sort _: EmptySort?, fragment _: EmptyFragment?, requestBody _: SubjectDestroyMooringBody?, responseBody: SubjectMooringListVM?) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }
}

/// A create declared within the subject scope — refused at registration: a create names the
/// container it creates into.
struct SubjectCreateCardBody: ServerRequestBody, ValidatableModel {
    var number: Int

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

extension SubjectCreateCardBody: DataModelWriter {
    static let candidates = Card.creationPlan(within: .subject)

    func apply(to card: Card) throws {
        card.number = number
    }
}

final class SubjectCreateCardRequest: CreateRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias RequestBody = SubjectCreateCardBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = ValidationError
    typealias ResponseBody = CardListVM

    let id: String
    let requestBody: SubjectCreateCardBody?
    var responseBody: CardListVM?

    init(query _: EmptyQuery?, sort _: EmptySort?, fragment _: EmptyFragment?, requestBody: SubjectCreateCardBody?, responseBody: CardListVM?) {
        self.id = .random(length: 10)
        self.requestBody = requestBody
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }
}

/// The mixed shape: candidates within the request's container, the refresh body within the
/// subject scope.
final class MixedArchiveMooringRequest: ArchiveRequest, @unchecked Sendable {
    typealias Query = MooringTargetQuery
    typealias RequestBody = ArchiveMooringBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = ValidationError
    typealias ResponseBody = SubjectMooringListVM

    let id: String
    let query: MooringTargetQuery?
    var requestBody: ArchiveMooringBody? {
        nil
    }

    var responseBody: SubjectMooringListVM?

    init(query: MooringTargetQuery?, sort _: EmptySort?, fragment _: EmptyFragment?, requestBody _: ArchiveMooringBody?, responseBody: SubjectMooringListVM?) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// MARK: - A write request carrying its own ValidatableViewModelRequestError

// The typed-error path: whatever the route refuses with, the client decodes as THIS type.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

struct CardWriteRefusal: ValidatableViewModelRequestError {
    let validations: [FOSMVVM.ValidationResult]
}

/// Carries the same non-negative rule as `UpdateCardBody`, so one request proves both refusal
/// paths: the body's own rules, and a `ValidationError` raised during the save.
struct TypedErrorUpdateBody: ServerRequestBody, ValidatableModel {
    var number: Int
    var boardName: String

    func validate(fields _: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        guard number >= 0 else {
            validations.append(
                .init(status: .error, fieldId: #fieldId(\TypedErrorUpdateBody.number), message: .constant("number must be non-negative"))
            )
            return .error
        }
        return nil
    }
}

extension TypedErrorUpdateBody: DataModelWriter {
    static let candidates = Card.loadingPlan(.write, within: .parent)

    func apply(to card: Card) throws {
        card.number = number
        card.boardName = boardName
    }
}

final class TypedErrorUpdateRequest: UpdateRequest, @unchecked Sendable {
    typealias Query = CardTargetQuery
    typealias RequestBody = TypedErrorUpdateBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = CardWriteRefusal
    typealias ResponseBody = CardListVM

    let id: String
    let query: CardTargetQuery?
    let requestBody: TypedErrorUpdateBody?
    var responseBody: CardListVM?

    init(query: CardTargetQuery?, sort _: EmptySort?, fragment _: EmptyFragment?, requestBody: TypedErrorUpdateBody?, responseBody: CardListVM?) {
        self.id = .random(length: 10)
        self.query = query
        self.requestBody = requestBody
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// MARK: - Archive and destroy requests carrying their own ValidatableViewModelRequestError

// A refusal the model raises during the deletion must reach the client as THESE types.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

struct MooringWriteRefusal: ValidatableViewModelRequestError {
    let validations: [FOSMVVM.ValidationResult]
}

struct TypedErrorArchiveMooringBody: ServerRequestBody {}

extension TypedErrorArchiveMooringBody: WriteTargetProviding {
    static let candidates = Mooring.loadingPlan(.archive, within: .parent)
}

final class TypedErrorArchiveMooringRequest: ArchiveRequest, @unchecked Sendable {
    typealias Query = MooringTargetQuery
    typealias RequestBody = TypedErrorArchiveMooringBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = MooringWriteRefusal
    typealias ResponseBody = MooringListVM

    let id: String
    let query: MooringTargetQuery?
    var requestBody: TypedErrorArchiveMooringBody? {
        nil
    }

    var responseBody: MooringListVM?

    init(query: MooringTargetQuery?, sort _: EmptySort?, fragment _: EmptyFragment?, requestBody _: TypedErrorArchiveMooringBody?, responseBody: MooringListVM?) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }
}

struct TypedErrorDestroyMooringBody: ServerRequestBody {}

extension TypedErrorDestroyMooringBody: WriteTargetProviding {
    static let candidates = Mooring.loadingPlan(.destroy, within: .parent)
}

final class TypedErrorDestroyMooringRequest: DestroyRequest, @unchecked Sendable {
    typealias Query = MooringTargetQuery
    typealias RequestBody = TypedErrorDestroyMooringBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = MooringWriteRefusal
    typealias ResponseBody = MooringListVM

    let id: String
    let query: MooringTargetQuery?
    var requestBody: TypedErrorDestroyMooringBody? {
        nil
    }

    var responseBody: MooringListVM?

    init(query: MooringTargetQuery?, sort _: EmptySort?, fragment _: EmptyFragment?, requestBody _: TypedErrorDestroyMooringBody?, responseBody: MooringListVM?) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }
}
