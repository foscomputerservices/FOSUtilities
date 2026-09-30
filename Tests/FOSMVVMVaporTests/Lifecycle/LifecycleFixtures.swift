// LifecycleFixtures.swift
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
import FOSMVVMVapor
import Foundation
import NIOConcurrencyHelpers
import Vapor

// Fluent fixtures follow Vapor's template idiom (final class + @unchecked Sendable).

// MARK: - The ordered hook log

/// Lock-guarded ordered log. One lives in `Application.storage` for the whole suite; each ``Entry``
/// carries one of its own, because field validation is the single hook with no context to reach the
/// application through.
final class LifecycleEventBox: @unchecked Sendable {
    private let lock = NIOLock()
    private var entries: [String] = []

    func append(_ entry: String) {
        lock.withLock { entries.append(entry) }
    }

    var all: [String] {
        lock.withLock { entries }
    }

    func count(of entry: String) -> Int {
        lock.withLock { entries.count { $0 == entry } }
    }
}

struct LifecycleEventBoxKey: StorageKey {
    typealias Value = LifecycleEventBox
}

extension Application {
    /// The suite's hook log. Touch it once from `configure` so every hook appends to one box.
    var lifecycleEvents: LifecycleEventBox {
        if let box = storage[LifecycleEventBoxKey.self] {
            return box
        }
        let box = LifecycleEventBox()
        storage[LifecycleEventBoxKey.self] = box
        return box
    }
}

enum LifecycleFailure: Error, Equatable {
    case willWrite
    case didWrite
}

// MARK: - The form contract shared by the probe

/// Localized validation messages for ``EntryFields``, keyed in `TestYAML/EntryFieldsMessages.yml`.
@FieldValidationModel
struct EntryFieldsMessages {
    @LocalizedString(parentKeys: "label", "validationMessages") var required
    @LocalizedString(parentKeys: "label", "validationMessages") var taken

    init() {}
}

/// The user-editable contract ``Entry`` and any body writing one both answer to.
protocol EntryFields: ValidatableModel {
    var label: String { get set }
}

extension EntryFields {
    /// Minted the way a FormField's title is: a @LocalizedString property binds its key only while
    /// its own model is being encoded, so a message pulled out of one would encode empty.
    static var labelRequiredMessage: LocalizableString {
        .localized(for: EntryFieldsMessages.self, propertyName: "label", messageGroup: "validationMessages", messageKey: "required")
    }

    static var labelTakenMessage: LocalizableString {
        .localized(for: EntryFieldsMessages.self, propertyName: "label", messageGroup: "validationMessages", messageKey: "taken")
    }

    static var labelFieldId: FormFieldIdentifier {
        #fieldId(\Self.label)
    }

    /// The one rule: a label is required.
    func entryFieldsValidate(validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        guard label.isEmpty else { return nil }
        validations.append(
            .init(status: .error, fieldId: Self.labelFieldId, message: Self.labelRequiredMessage)
        )
        return .error
    }
}

// MARK: - The containers

final class Ledger: ContainerDataModel, @unchecked Sendable {
    static let schema = "ledgers"
    static var containedRecordTypes: [any FOSMVVM.Model.Type] {
        [Entry.self, Auditor.self]
    }

    static var containment: [ContainmentRelation] {
        [.children(\Ledger.$entries), .siblings(\Ledger.$auditors)]
    }

    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Children(for: \.$ledger) var entries: [Entry]
    @Siblings(through: LedgerAuditor.self, from: \.$ledger, to: \.$auditor) var auditors: [Auditor]
    init() {}
    init(name: String) {
        self.name = name
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

/// A second container declaring ``Entry`` too — the double-reached child fixture.
final class Vault: ContainerDataModel, @unchecked Sendable {
    static let schema = "vaults"
    static var containedRecordTypes: [any FOSMVVM.Model.Type] {
        [Entry.self]
    }

    static var containment: [ContainmentRelation] {
        [.children(\Vault.$entries)]
    }

    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Children(for: \.$vault) var entries: [Entry]
    init() {}
    init(name: String) {
        self.name = name
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

// MARK: - The probe

/// Declares all five hooks and notes each one it runs, in order. Two containers declare it, it
/// carries a delete timestamp, and its label is unique within its ledger.
final class Entry: DataModel, EntryFields, @unchecked Sendable {
    static let schema = "entries"

    @ID(key: .id) var id: UUID?
    @Field(key: "label") var label: String
    @Parent(key: "ledger_id") var ledger: Ledger
    @Parent(key: "vault_id") var vault: Vault
    @Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?

    private let hookLog = LifecycleEventBox()

    /// This instance's hooks, in the order they ran.
    var trace: [String] {
        hookLog.all
    }

    init() {}
    init(label: String, ledgerId: ModelIdType, vaultId: ModelIdType) {
        self.label = label
        $ledger.id = ledgerId
        $vault.id = vaultId
    }

    // MARK: ValidatableModel Protocol

    func validate(fields _: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        hookLog.append("fieldValidation")
        return entryFieldsValidate(validations: validations)
    }

    // MARK: DataModelLifecycle Protocol

    func willWrite(in context: DataModelWriteContext) async throws {
        note("willWrite", context.action, in: context.application)
        if label == "unwritable" {
            throw LifecycleFailure.willWrite
        }
        label = label.trimmingCharacters(in: .whitespaces)
    }

    func validateModel(in context: DataModelWriteContext) async throws -> [FOSMVVM.ValidationResult] {
        note("validateModel", context.action, in: context.application)
        guard context.action == .create || context.action == .update else { return [] }

        let taken = try await Entry.query(on: context.database)
            .filter(\.$ledger.$id == $ledger.id)
            .filter(\.$label == label)
            .filter(\.$id != (id ?? ModelIdType()))
            .first() != nil
        return taken
            ? [.init(status: .error, message: Self.labelTakenMessage)]
            : []
    }

    func didWrite(in context: DataModelWriteContext) async throws {
        note("didWrite", context.action, in: context.application)
        if label == "rollback" {
            throw LifecycleFailure.didWrite
        }
    }

    func didCommit(in context: DataModelCommitContext) async {
        note("didCommit", context.action, in: context.application)
    }

    private func note(_ hook: String, _ action: DataModelAction, in application: Application) {
        hookLog.append(hook)
        application.lifecycleEvents.append("Entry.\(hook):\(action)")
    }
}

// MARK: - The pivot and its far end

final class Auditor: DataModel, @unchecked Sendable {
    static let schema = "auditors"
    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Siblings(through: LedgerAuditor.self, from: \.$auditor, to: \.$ledger) var ledgers: [Ledger]
    init() {}
    init(name: String) {
        self.name = name
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

/// A pivot that declares hooks — membership changes run the lifecycle too.
final class LedgerAuditor: DataModel, @unchecked Sendable {
    static let schema = "ledger_auditors"
    @ID(key: .id) var id: UUID?
    @Parent(key: "ledger_id") var ledger: Ledger
    @Parent(key: "auditor_id") var auditor: Auditor
    init() {}
    init(ledgerId: ModelIdType, auditorId: ModelIdType) {
        $ledger.id = ledgerId
        $auditor.id = auditorId
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }

    func willWrite(in context: DataModelWriteContext) async throws {
        context.application.lifecycleEvents.append("LedgerAuditor.willWrite:\(context.action)")
    }
}

// MARK: - Registered with no container

/// Registered through the `DataModel` overload — no container declares it.
final class Beacon: DataModel, @unchecked Sendable {
    static let schema = "beacons"
    @ID(key: .id) var id: UUID?
    @Field(key: "note") var note: String
    init() {}
    init(note: String) {
        self.note = note
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }

    func willWrite(in context: DataModelWriteContext) async throws {
        context.application.lifecycleEvents.append("Beacon.willWrite:\(context.action)")
    }

    func didCommit(in context: DataModelCommitContext) async {
        context.application.lifecycleEvents.append("Beacon.didCommit:\(context.action)")
    }
}

/// Registered, declares no hook at all — saves exactly as it did before the lifecycle shipped.
final class Plain: DataModel, @unchecked Sendable {
    static let schema = "plains"
    @ID(key: .id) var id: UUID?
    @Field(key: "note") var note: String
    init() {}
    init(note: String) {
        self.note = note
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

/// Declares hooks but is never registered — its migration is added directly.
final class Stray: DataModel, @unchecked Sendable {
    static let schema = "strays"
    @ID(key: .id) var id: UUID?
    @Field(key: "note") var note: String
    init() {}
    init(note: String) {
        self.note = note
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }

    func willWrite(in context: DataModelWriteContext) async throws {
        context.application.lifecycleEvents.append("Stray.willWrite:\(context.action)")
    }
}

// MARK: - Warning policy

/// Takes the default policy: a warning never stops its write. A negative value also fails.
final class Gauge: DataModel, @unchecked Sendable {
    static let schema = "gauges"
    @ID(key: .id) var id: UUID?
    @Field(key: "value") var value: Int
    init() {}
    init(value: Int) {
        self.value = value
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }

    func validateModel(in _: DataModelWriteContext) async throws -> [FOSMVVM.ValidationResult] {
        gaugeResults(for: value)
    }
}

/// The same rules under `.blocking`: the warning alone stops the write.
final class Quota: DataModel, @unchecked Sendable {
    static let schema = "quotas"
    static var warningPolicy: ValidationWarningPolicy {
        .blocking
    }

    @ID(key: .id) var id: UUID?
    @Field(key: "value") var value: Int
    init() {}
    init(value: Int) {
        self.value = value
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }

    func validateModel(in _: DataModelWriteContext) async throws -> [FOSMVVM.ValidationResult] {
        gaugeResults(for: value)
    }
}

/// One warning always; an error as well when the value is negative.
func gaugeResults(for value: Int) -> [FOSMVVM.ValidationResult] {
    var results: [FOSMVVM.ValidationResult] = [
        .init(status: .warning, message: .constant("value is unusual"))
    ]
    if value < 0 {
        results.append(.init(status: .error, message: .constant("value must not be negative")))
    }
    return results
}

// MARK: - Constraint violations

/// Claims the unique-index failure on `code` and answers it as a validation refusal.
final class Stamp: DataModel, @unchecked Sendable {
    static let schema = "stamps"
    @ID(key: .id) var id: UUID?
    @Field(key: "code") var code: String
    init() {}
    init(code: String) {
        self.code = code
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }

    func validationResult(for violation: ConstraintViolation) -> FOSMVVM.ValidationResult? {
        guard violation.action == .create else { return nil }
        return .init(status: .error, message: .constant("that code is already claimed"))
    }
}

/// Declines the same failure — the driver's error is thrown unchanged.
final class Coupon: DataModel, @unchecked Sendable {
    static let schema = "coupons"
    @ID(key: .id) var id: UUID?
    @Field(key: "code") var code: String
    init() {}
    init(code: String) {
        self.code = code
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

// MARK: - Migrations (parents first — FK order)

struct CreateLedger: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Ledger.schema).id().field("name", .string, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Ledger.schema).delete()
    }
}

struct CreateVault: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Vault.schema).id().field("name", .string, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Vault.schema).delete()
    }
}

struct CreateEntry: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Entry.schema).id()
            .field("label", .string, .required)
            .field("ledger_id", .uuid, .required, .references(Ledger.schema, "id"))
            .field("vault_id", .uuid, .required, .references(Vault.schema, "id"))
            .field("deleted_at", .datetime)
            .unique(on: "ledger_id", "label")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Entry.schema).delete()
    }
}

struct CreateAuditor: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Auditor.schema).id().field("name", .string, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Auditor.schema).delete()
    }
}

struct CreateLedgerAuditor: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(LedgerAuditor.schema).id()
            .field("ledger_id", .uuid, .required, .references(Ledger.schema, "id"))
            .field("auditor_id", .uuid, .required, .references(Auditor.schema, "id"))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(LedgerAuditor.schema).delete()
    }
}

struct CreateBeacon: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Beacon.schema).id().field("note", .string, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Beacon.schema).delete()
    }
}

struct CreatePlain: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Plain.schema).id().field("note", .string, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Plain.schema).delete()
    }
}

struct CreateStray: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Stray.schema).id().field("note", .string, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Stray.schema).delete()
    }
}

struct CreateGauge: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Gauge.schema).id().field("value", .int, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Gauge.schema).delete()
    }
}

struct CreateQuota: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Quota.schema).id().field("value", .int, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Quota.schema).delete()
    }
}

struct CreateStamp: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Stamp.schema).id()
            .field("code", .string, .required)
            .unique(on: "code")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Stamp.schema).delete()
    }
}

struct CreateCoupon: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Coupon.schema).id()
            .field("code", .string, .required)
            .unique(on: "code")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Coupon.schema).delete()
    }
}

// MARK: - Registration and seed

/// Registers the whole lifecycle graph. ``Stray`` is deliberately left out of the registry; live
/// invalidation is left off — the hooks do not depend on it.
func registerLifecycleGraph(_ app: Application) throws {
    _ = app.lifecycleEvents
    try app.register(Ledger.self, migration: CreateLedger())
    try app.register(Vault.self, migration: CreateVault())
    try app.register(Beacon.self, migration: CreateBeacon())
    try app.register(Plain.self, migration: CreatePlain())
    try app.register(Gauge.self, migration: CreateGauge())
    try app.register(Quota.self, migration: CreateQuota())
    try app.register(Stamp.self, migration: CreateStamp())
    try app.register(Coupon.self, migration: CreateCoupon())
    app.migrations.add(CreateEntry())
    app.migrations.add(CreateAuditor())
    app.migrations.add(CreateLedgerAuditor())
    app.migrations.add(CreateStray())
}

/// One ledger and one vault, so an ``Entry`` has both of its owners.
func seedLedger(on db: any Database, name: String = "Main") async throws -> (ledger: Ledger, vault: Vault) {
    let ledger = Ledger(name: name)
    try await ledger.save(on: db)
    let vault = Vault(name: name)
    try await vault.save(on: db)
    return (ledger, vault)
}
