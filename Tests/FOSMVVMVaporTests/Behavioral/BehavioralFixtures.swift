// BehavioralFixtures.swift
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

// Fixtures for the behavioral (second-channel) suites. Projected from the ratified design only:
// every observation goes through public API — an event box in `Application.storage` for hook
// order and reach, sentinel titles to steer a hook's answer, and the thrown error for a refusal.

import Fluent
import FluentKit
import FOSFoundation
import FOSMVVM
import FOSMVVMVapor
import Foundation
import NIOConcurrencyHelpers
import Vapor

// MARK: - The event box (the only public signal for "which hooks ran, in what order")

final class BehavioralEventBox: @unchecked Sendable {
    private let lock = NIOLock()
    private var entries: [String] = []

    func record(_ entry: String) {
        lock.withLock { entries.append(entry) }
    }

    var all: [String] {
        lock.withLock { entries }
    }

    /// The hook events of one model type, in order, with the type prefix stripped.
    func events(of type: Any.Type) -> [String] {
        let prefix = "\(type)."
        return all.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    func count(of event: String, of type: Any.Type) -> Int {
        events(of: type).count(where: { $0 == event })
    }
}

struct BehavioralEventBoxKey: StorageKey {
    typealias Value = BehavioralEventBox
}

extension Application {
    var behavioralEvents: BehavioralEventBox? {
        get { storage[BehavioralEventBoxKey.self] }
        set { storage[BehavioralEventBoxKey.self] = newValue }
    }
}

extension DataModelWriteContext {
    func record(_ hook: String, _ type: Any.Type) {
        application.behavioralEvents?.record("\(type).\(hook)(\(action))")
    }
}

extension DataModelCommitContext {
    func record(_ hook: String, _ type: Any.Type) {
        application.behavioralEvents?.record("\(type).\(hook)(\(action))")
    }
}

/// Installs a fresh event box on the application under test.
func behavioralBox(on app: Application) -> BehavioralEventBox {
    let box = BehavioralEventBox()
    app.behavioralEvents = box
    return box
}

// MARK: - Sentinels (a title steers a hook's answer; nothing else does)

enum BehavioralTitle {
    static let ok = "Bedrock"
    static let fieldInvalid = "INVALID"
    static let fieldWarning = "FIELD-WARN"
    static let modelError = "MODEL-ERROR"
    static let modelWarning = "MODEL-WARN"
    static let modelMany = "MODEL-MANY"
    static let modelMixed = "MODEL-MIXED"
    static let modelThrow = "MODEL-THROW"
    static let willWriteThrow = "WILLWRITE-THROW"
    static let didWriteThrow = "DIDWRITE-THROW"
    static let didWriteWrites = "DIDWRITE-WRITES"
}

struct BehavioralHookFailure: Error, Equatable {
    let hook: String
}

// MARK: - Messages

@FieldValidationModel
struct BehavioralProbeMessages {
    @LocalizedString("title", messageGroup: "validationMessages", messageKey: "required") var titleRequired
    @LocalizedString("title", messageGroup: "validationMessages", messageKey: "invalid") var titleInvalid
    @LocalizedString("title", messageGroup: "validationMessages", messageKey: "unusual") var titleUnusual
    @LocalizedString("model", messageGroup: "validationMessages", messageKey: "full") var modelFull
    @LocalizedString("model", messageGroup: "validationMessages", messageKey: "odd") var modelOdd
    @LocalizedString("model", messageGroup: "validationMessages", messageKey: "second") var modelSecond
    @LocalizedString("model", messageGroup: "validationMessages", messageKey: "third") var modelThird
    @LocalizedString("model", messageGroup: "validationMessages", messageKey: "claimed") var modelClaimed
    @LocalizedString("model", messageGroup: "validationMessages", messageKey: "taken") var modelTaken

    init() {}
}

/// The mints every fixture uses, the way a `Fields` protocol mints its own.
enum BehavioralMessages {
    static var required: LocalizableString {
        .localized(for: BehavioralProbeMessages.self, propertyName: "title", messageGroup: "validationMessages", messageKey: "required")
    }

    static var invalid: LocalizableString {
        .localized(for: BehavioralProbeMessages.self, propertyName: "title", messageGroup: "validationMessages", messageKey: "invalid")
    }

    static var unusual: LocalizableString {
        .localized(for: BehavioralProbeMessages.self, propertyName: "title", messageGroup: "validationMessages", messageKey: "unusual")
    }

    static var full: LocalizableString {
        .localized(for: BehavioralProbeMessages.self, propertyName: "model", messageGroup: "validationMessages", messageKey: "full")
    }

    static var odd: LocalizableString {
        .localized(for: BehavioralProbeMessages.self, propertyName: "model", messageGroup: "validationMessages", messageKey: "odd")
    }

    static var second: LocalizableString {
        .localized(for: BehavioralProbeMessages.self, propertyName: "model", messageGroup: "validationMessages", messageKey: "second")
    }

    static var third: LocalizableString {
        .localized(for: BehavioralProbeMessages.self, propertyName: "model", messageGroup: "validationMessages", messageKey: "third")
    }

    static var claimed: LocalizableString {
        .localized(for: BehavioralProbeMessages.self, propertyName: "model", messageGroup: "validationMessages", messageKey: "claimed")
    }

    static var taken: LocalizableString {
        .localized(for: BehavioralProbeMessages.self, propertyName: "model", messageGroup: "validationMessages", messageKey: "taken")
    }
}

// MARK: - Hook recording, shared by the fixtures that only need to be seen

protocol BehavioralRecording: DataModelLifecycle {}

extension BehavioralRecording {
    func willWrite(in context: DataModelWriteContext) async throws {
        context.record("willWrite", Self.self)
    }

    func validateModel(in context: DataModelWriteContext) async throws -> [FOSMVVM.ValidationResult] {
        context.record("validateModel", Self.self)
        return []
    }

    func didWrite(in context: DataModelWriteContext) async throws {
        context.record("didWrite", Self.self)
    }

    func didCommit(in context: DataModelCommitContext) async {
        context.record("didCommit", Self.self)
    }
}

// MARK: - The ordering / reach probe (soft-deletable)

final class BehavioralProbe: DataModel, @unchecked Sendable {
    static let schema = "behavioral_probes"

    @ID(key: .id) var id: UUID?
    @Field(key: "title") var title: String
    @Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?

    init() {}
    init(title: String) {
        self.title = title
    }

    func validate(fields _: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        if title.isEmpty {
            validations.append(.init(status: .error, fieldId: #fieldId(\BehavioralProbe.title), message: BehavioralMessages.required))
        }
        if title == BehavioralTitle.fieldInvalid {
            validations.append(.init(status: .error, fieldId: #fieldId(\BehavioralProbe.title), message: BehavioralMessages.invalid))
        }
        if title == BehavioralTitle.fieldWarning {
            validations.append(.init(status: .warning, fieldId: #fieldId(\BehavioralProbe.title), message: BehavioralMessages.unusual))
        }
        return validations.status
    }

    func willWrite(in context: DataModelWriteContext) async throws {
        context.record("willWrite", Self.self)
        title = title.trimmingCharacters(in: .whitespaces)
        if title == BehavioralTitle.willWriteThrow {
            throw BehavioralHookFailure(hook: "willWrite")
        }
    }

    func validateModel(in context: DataModelWriteContext) async throws -> [FOSMVVM.ValidationResult] {
        context.record("validateModel", Self.self)
        switch title {
        case BehavioralTitle.modelError:
            return [.init(status: .error, message: BehavioralMessages.full)]
        case BehavioralTitle.modelWarning:
            return [.init(status: .warning, message: BehavioralMessages.odd)]
        case BehavioralTitle.modelMany:
            return [
                .init(status: .error, message: BehavioralMessages.full),
                .init(status: .error, message: BehavioralMessages.second),
                .init(status: .error, message: BehavioralMessages.third)
            ]
        case BehavioralTitle.modelMixed:
            return [
                .init(status: .warning, message: BehavioralMessages.odd),
                .init(status: .error, message: BehavioralMessages.full)
            ]
        case BehavioralTitle.modelThrow:
            throw BehavioralHookFailure(hook: "validateModel")
        default:
            return []
        }
    }

    func didWrite(in context: DataModelWriteContext) async throws {
        context.record("didWrite", Self.self)
        if title == BehavioralTitle.didWriteWrites {
            try await BehavioralOrphan(name: "from-didWrite").save(on: context.database)
        }
        if title == BehavioralTitle.didWriteThrow {
            throw BehavioralHookFailure(hook: "didWrite")
        }
    }

    func didCommit(in context: DataModelCommitContext) async {
        context.record("didCommit", Self.self)
    }
}

struct CreateBehavioralProbe: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(BehavioralProbe.schema).id()
            .field("title", .string, .required)
            .field("deleted_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(BehavioralProbe.schema).delete()
    }
}

// MARK: - A model with no delete timestamp (a plain delete destroys it)

final class BehavioralPlain: DataModel, BehavioralRecording, @unchecked Sendable {
    static let schema = "behavioral_plains"
    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    init() {}
    init(name: String) {
        self.name = name
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

struct CreateBehavioralPlain: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(BehavioralPlain.schema).id().field("name", .string, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(BehavioralPlain.schema).delete()
    }
}

// MARK: - Warning policy

final class BehavioralBlocker: DataModel, @unchecked Sendable {
    static let schema = "behavioral_blockers"
    static var warningPolicy: ValidationWarningPolicy {
        .blocking
    }

    @ID(key: .id) var id: UUID?
    @Field(key: "title") var title: String
    init() {}
    init(title: String) {
        self.title = title
    }

    func validate(fields _: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        if title == BehavioralTitle.fieldWarning {
            validations.append(.init(status: .warning, fieldId: #fieldId(\BehavioralBlocker.title), message: BehavioralMessages.unusual))
        }
        return validations.status
    }

    func validateModel(in context: DataModelWriteContext) async throws -> [FOSMVVM.ValidationResult] {
        context.record("validateModel", Self.self)
        switch title {
        case BehavioralTitle.modelWarning:
            return [.init(status: .warning, message: BehavioralMessages.odd)]
        case BehavioralTitle.modelMixed:
            return [
                .init(status: .warning, message: BehavioralMessages.odd),
                .init(status: .error, message: BehavioralMessages.full)
            ]
        default:
            return []
        }
    }

    func didWrite(in context: DataModelWriteContext) async throws {
        context.record("didWrite", Self.self)
    }
}

struct CreateBehavioralBlocker: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(BehavioralBlocker.schema).id().field("title", .string, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(BehavioralBlocker.schema).delete()
    }
}

// MARK: - Constraint claim

/// Counts the offers a claim hook received. `validationResult(for:)` receives no context, so the
/// counter lives in `Application.storage` like the event box and the fixture is handed it at
/// construction — the instance the test saves is the instance the middleware offers the failure to.
final class BehavioralClaimCounter: @unchecked Sendable {
    private let lock = NIOLock()
    private var counts: [String: Int] = [:]

    func offered(_ key: String) {
        lock.withLock { counts[key, default: 0] += 1 }
    }

    func count(_ key: String) -> Int {
        lock.withLock { counts[key] ?? 0 }
    }
}

struct BehavioralClaimCounterKey: StorageKey {
    typealias Value = BehavioralClaimCounter
}

extension Application {
    /// The application's claim counter, minted on first touch.
    var behavioralClaims: BehavioralClaimCounter {
        if let counter = storage[BehavioralClaimCounterKey.self] {
            return counter
        }
        let counter = BehavioralClaimCounter()
        storage[BehavioralClaimCounterKey.self] = counter
        return counter
    }
}

final class BehavioralClaimant: DataModel, @unchecked Sendable {
    static let schema = "behavioral_claimants"

    @ID(key: .id) var id: UUID?
    @Field(key: "title") var title: String
    /// Not persisted: the counter the claim hook records into, handed over by the test.
    var claims: BehavioralClaimCounter?
    init() {}
    init(title: String, claims: BehavioralClaimCounter? = nil) {
        self.title = title
        self.claims = claims
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }

    func validationResult(for violation: ConstraintViolation) -> FOSMVVM.ValidationResult? {
        claims?.offered("claimant")
        return .init(status: .error, message: BehavioralMessages.claimed)
    }
}

/// Claims with a WARNING result — the write has already failed at the driver, so the policy has
/// nothing to let through.
final class BehavioralWarningClaimant: DataModel, @unchecked Sendable {
    static let schema = "behavioral_warning_claimants"

    @ID(key: .id) var id: UUID?
    @Field(key: "title") var title: String
    init() {}
    init(title: String) {
        self.title = title
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }

    func validationResult(for _: ConstraintViolation) -> FOSMVVM.ValidationResult? {
        .init(status: .warning, message: BehavioralMessages.odd)
    }
}

final class BehavioralDecliner: DataModel, @unchecked Sendable {
    static let schema = "behavioral_decliners"

    @ID(key: .id) var id: UUID?
    @Field(key: "title") var title: String
    /// Not persisted: the counter the claim hook records into, handed over by the test.
    var claims: BehavioralClaimCounter?
    init() {}
    init(title: String, claims: BehavioralClaimCounter? = nil) {
        self.title = title
        self.claims = claims
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }

    func validationResult(for _: ConstraintViolation) -> FOSMVVM.ValidationResult? {
        claims?.offered("decliner")
        return nil
    }
}

struct CreateBehavioralClaimant: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(BehavioralClaimant.schema).id()
            .field("title", .string, .required)
            .unique(on: "title")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(BehavioralClaimant.schema).delete()
    }
}

struct CreateBehavioralWarningClaimant: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(BehavioralWarningClaimant.schema).id()
            .field("title", .string, .required)
            .unique(on: "title")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(BehavioralWarningClaimant.schema).delete()
    }
}

struct CreateBehavioralDecliner: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(BehavioralDecliner.schema).id()
            .field("title", .string, .required)
            .unique(on: "title")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(BehavioralDecliner.schema).delete()
    }
}

/// Carries BOTH a unique index and a foreign key; the model tells them apart by inspecting the
/// underlying error, the only discriminator the design offers.
final class BehavioralDualConstraint: DataModel, @unchecked Sendable {
    static let schema = "behavioral_dual_constraints"

    @ID(key: .id) var id: UUID?
    @Field(key: "title") var title: String
    @Parent(key: "box_id") var box: BehavioralBox
    /// Not persisted: the counter the claim hook records into, handed over by the test.
    var claims: BehavioralClaimCounter?
    init() {}
    init(title: String, boxId: ModelIdType, claims: BehavioralClaimCounter? = nil) {
        self.title = title
        $box.id = boxId
        self.claims = claims
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }

    func validationResult(for violation: ConstraintViolation) -> FOSMVVM.ValidationResult? {
        claims?.offered("dual")
        let text = String(describing: violation.underlyingError).uppercased()
        guard text.contains("UNIQUE") else { return nil }
        return .init(status: .error, message: BehavioralMessages.claimed)
    }
}

struct CreateBehavioralDualConstraint: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(BehavioralDualConstraint.schema).id()
            .field("title", .string, .required)
            .field("box_id", .uuid, .required, .references(BehavioralBox.schema, "id"))
            .unique(on: "title")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(BehavioralDualConstraint.schema).delete()
    }
}

// MARK: - Containment (registration reach: container, contained, pivot, double-reached)

final class BehavioralBox: ContainerDataModel, BehavioralRecording, @unchecked Sendable {
    static let schema = "behavioral_boxes"
    static var containedRecordTypes: [any FOSMVVM.Model.Type] {
        [BehavioralItem.self, BehavioralTag.self]
    }

    static var containment: [ContainmentRelation] {
        [.children(\BehavioralBox.$items), .siblings(\BehavioralBox.$tags)]
    }

    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Children(for: \.$box) var items: [BehavioralItem]
    @Siblings(through: BehavioralBoxTag.self, from: \.$box, to: \.$tag) var tags: [BehavioralTag]
    init() {}
    init(name: String) {
        self.name = name
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

/// A SECOND container that also declares `BehavioralItem` — the double-reached case.
final class BehavioralCrate: ContainerDataModel, BehavioralRecording, @unchecked Sendable {
    static let schema = "behavioral_crates"
    static var containedRecordTypes: [any FOSMVVM.Model.Type] {
        [BehavioralItem.self]
    }

    static var containment: [ContainmentRelation] {
        [.parent(\BehavioralCrate.$item)]
    }

    @ID(key: .id) var id: UUID?
    @Parent(key: "item_id") var item: BehavioralItem
    init() {}
    init(itemId: ModelIdType) {
        $item.id = itemId
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

final class BehavioralItem: DataModel, @unchecked Sendable {
    static let schema = "behavioral_items"

    @ID(key: .id) var id: UUID?
    @Field(key: "title") var title: String
    @Parent(key: "box_id") var box: BehavioralBox
    init() {}
    init(title: String, boxId: ModelIdType) {
        self.title = title
        $box.id = boxId
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }

    func willWrite(in context: DataModelWriteContext) async throws {
        context.record("willWrite", Self.self)
    }

    /// The title is unique WITHIN its box, and a model never collides with itself.
    func validateModel(in context: DataModelWriteContext) async throws -> [FOSMVVM.ValidationResult] {
        context.record("validateModel", Self.self)
        guard context.action == .create || context.action == .update else { return [] }
        var query = BehavioralItem.query(on: context.database)
            .filter(\.$box.$id == $box.id)
            .filter(\.$title == title)
        if let id {
            query = query.filter(\.$id != id)
        }
        let taken = try await query.first() != nil
        return taken ? [.init(status: .error, fieldId: #fieldId(\BehavioralItem.title), message: BehavioralMessages.taken)] : []
    }

    func didWrite(in context: DataModelWriteContext) async throws {
        context.record("didWrite", Self.self)
    }

    func didCommit(in context: DataModelCommitContext) async {
        context.record("didCommit", Self.self)
    }
}

final class BehavioralTag: DataModel, BehavioralRecording, @unchecked Sendable {
    static let schema = "behavioral_tags"
    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Siblings(through: BehavioralBoxTag.self, from: \.$tag, to: \.$box) var boxes: [BehavioralBox]
    init() {}
    init(name: String) {
        self.name = name
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

final class BehavioralBoxTag: DataModel, BehavioralRecording, @unchecked Sendable {
    static let schema = "behavioral_box_tags"
    @ID(key: .id) var id: UUID?
    @Parent(key: "box_id") var box: BehavioralBox
    @Parent(key: "tag_id") var tag: BehavioralTag
    init() {}
    init(boxId: ModelIdType, tagId: ModelIdType) {
        $box.id = boxId
        $tag.id = tagId
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

/// A `DataModel` no container declares — the registration overload's reason to exist.
final class BehavioralOrphan: DataModel, BehavioralRecording, @unchecked Sendable {
    static let schema = "behavioral_orphans"
    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    init() {}
    init(name: String) {
        self.name = name
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

/// Reaches the database through `app.migrations.add` alone — the bypass the design names.
final class BehavioralStray: DataModel, BehavioralRecording, @unchecked Sendable {
    static let schema = "behavioral_strays"
    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    init() {}
    init(name: String) {
        self.name = name
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

struct CreateBehavioralBox: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(BehavioralBox.schema).id().field("name", .string, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(BehavioralBox.schema).delete()
    }
}

struct CreateBehavioralItem: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(BehavioralItem.schema).id()
            .field("title", .string, .required)
            .field("box_id", .uuid, .required, .references(BehavioralBox.schema, "id"))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(BehavioralItem.schema).delete()
    }
}

struct CreateBehavioralCrate: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(BehavioralCrate.schema).id()
            .field("item_id", .uuid, .required, .references(BehavioralItem.schema, "id"))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(BehavioralCrate.schema).delete()
    }
}

struct CreateBehavioralTag: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(BehavioralTag.schema).id().field("name", .string, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(BehavioralTag.schema).delete()
    }
}

struct CreateBehavioralBoxTag: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(BehavioralBoxTag.schema).id()
            .field("box_id", .uuid, .required, .references(BehavioralBox.schema, "id"))
            .field("tag_id", .uuid, .required, .references(BehavioralTag.schema, "id"))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(BehavioralBoxTag.schema).delete()
    }
}

struct CreateBehavioralOrphan: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(BehavioralOrphan.schema).id().field("name", .string, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(BehavioralOrphan.schema).delete()
    }
}

struct CreateBehavioralStray: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(BehavioralStray.schema).id().field("name", .string, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(BehavioralStray.schema).delete()
    }
}

// MARK: - Registration helpers

/// The single-model door: the probe and the orphan, each registered with its migration.
func registerBehavioralProbes(_ app: Application) throws {
    try app.register(BehavioralProbe.self, migration: CreateBehavioralProbe())
    try app.register(BehavioralPlain.self, migration: CreateBehavioralPlain())
    try app.register(BehavioralOrphan.self, migration: CreateBehavioralOrphan())
}

/// The container graph: one call per container, the contained types and the pivot ride along.
func registerBehavioralContainment(_ app: Application) throws {
    try app.register(BehavioralBox.self, migration: CreateBehavioralBox())
    app.migrations.add(CreateBehavioralItem())
    app.migrations.add(CreateBehavioralTag())
    app.migrations.add(CreateBehavioralBoxTag())
}
