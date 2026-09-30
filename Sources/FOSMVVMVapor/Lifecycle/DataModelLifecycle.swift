// DataModelLifecycle.swift
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

import FOSMVVM
import Foundation

/// The hooks FOSMVVM runs around every write of a `DataModel`
///
/// Every `DataModel` already conforms. Every hook has a default that does nothing, so declare
/// only the ones your model needs:
///
/// ```swift
/// public final class Card: DataModel, CardFields, @unchecked Sendable {
///     // fields …
///
///     public func willWrite(in context: DataModelWriteContext) async throws {
///         title = title.trimmingCharacters(in: .whitespaces)
///     }
///
///     public func validateModel(in context: DataModelWriteContext) async throws -> [ValidationResult] {
///         let taken = try await Card.query(on: context.database)
///             .filter(\.$board.$id == $board.id).filter(\.$title == title).filter(\.$id != id)
///             .first() != nil
///         return taken
///             ? [.init(status: .error, fieldId: #fieldId(\CardFields.title), message: validationMessages.titleTaken)]
///             : []
///     }
/// }
/// ```
///
/// The order for one write: `willWrite`; the field validation your `Fields` protocol defines
/// (`validate(fields:validations:)`, on create and update); `validateModel`; the write;
/// `didWrite` in the same transaction; `didCommit` once it commits. A failed validation stops
/// the write and reaches the client as the request's `ResponseError`; a throw from a hook is an
/// error, not a validation.
///
/// Register the model with its migration, `app.register(Card.self, migration: Card.Initial())`,
/// and the hooks run. A batch write (`[Card].create(on:)`, `[Card].delete(on:)`) issues its one
/// statement only after every model has been through the middleware, so it runs `willWrite`, the
/// `Fields` rules and `validateModel` — a refusal from any of them still stops the whole batch —
/// and runs neither `didWrite` nor `didCommit`, there being no row yet to hand them. A constraint
/// failure is for the same reason never offered to `validationResult(for:)`, and a batch delete is
/// always `.destroy`.
public protocol DataModelLifecycle {
    /// Change the model before it is validated and written
    ///
    /// Derive, trim, and stamp here; validation runs after this:
    ///
    /// ```swift
    /// public func willWrite(in context: DataModelWriteContext) async throws {
    ///     slug = title.slugified()
    /// }
    /// ```
    ///
    /// Throw only for an error the user cannot fix; a value the user must correct belongs in
    /// ``validateModel(in:)``.
    func willWrite(in context: DataModelWriteContext) async throws

    /// Judge this model against other rows and return every problem found
    ///
    /// Runs for every action after field validation passed. Query through `context.database`
    /// and return one `ValidationResult` per rule that fails; FOSMVVM stops the write when any
    /// is an error:
    ///
    /// ```swift
    /// public func validateModel(in context: DataModelWriteContext) async throws -> [ValidationResult] {
    ///     guard context.action == .destroy else { return [] }
    ///     let hasCards = try await Card.query(on: context.database).filter(\.$board.$id == id).count() > 0
    ///     return hasCards ? [.init(status: .error, message: validationMessages.boardHasCards)] : []
    /// }
    /// ```
    ///
    /// Return every failure, not the first. A result with no field is about the model as a
    /// whole. Throw only for a failure of the query itself.
    func validateModel(in context: DataModelWriteContext) async throws -> [ValidationResult]

    /// Turn a database constraint failure into a validation result the user can act on
    ///
    /// When the database rejects the write on a constraint your migration declared, FOSMVVM asks
    /// your model what it means. Return a result and the client receives it as a validation
    /// failure; return `nil` and the original error is thrown unchanged:
    ///
    /// ```swift
    /// public func validationResult(for violation: ConstraintViolation) -> ValidationResult? {
    ///     guard violation.action == .create else { return nil }
    ///     return .init(status: .error, message: validationMessages.alreadyClaimed)
    /// }
    /// ```
    ///
    /// Reach for this when two writers race on a unique index and the loser should see a
    /// message, not a database error.
    func validationResult(for violation: ConstraintViolation) -> ValidationResult?

    /// Do more work in the same transaction after the row was written
    ///
    /// Write related rows here, through `context.database` so they join the same transaction:
    ///
    /// ```swift
    /// public func didWrite(in context: DataModelWriteContext) async throws {
    ///     guard context.action == .create else { return }
    ///     try await CardHistory(cardId: try requireID(), event: .created).save(on: context.database)
    /// }
    /// ```
    ///
    /// > Note: A throw rolls the row back with the rest of the transaction only when the write is
    /// > in one. On an auto-commit write the row is already durable, and the throw reaches the
    /// > caller with the row in place; write inside `liveTransaction { }` when the two must stand
    /// > or fall together.
    func didWrite(in context: DataModelWriteContext) async throws

    /// Run a side effect once the write is durable
    ///
    /// Send the email, call the exchange, notify the other system. This runs after the
    /// transaction commits, so nothing here can be rolled back and nothing here can fail the
    /// request. Handle your own failures:
    ///
    /// ```swift
    /// public func didCommit(in context: DataModelCommitContext) async {
    ///     guard context.action == .create else { return }
    ///     await context.application.notifier.cardCreated(id: id)
    /// }
    /// ```
    ///
    /// Inside `liveTransaction { }` this runs when the transaction commits. Inside a bare
    /// `database.transaction { }` it does not run; use `liveTransaction` for any write whose
    /// commit a hook must see.
    func didCommit(in context: DataModelCommitContext) async

    /// Whether a validation warning stops the write
    ///
    /// The default, `.advisory`, lets the write proceed. Declare `.blocking` on a model whose
    /// warnings the user must see before the row is saved:
    ///
    /// ```swift
    /// public static var warningPolicy: ValidationWarningPolicy { .blocking }
    /// ```
    static var warningPolicy: ValidationWarningPolicy { get }
}

public extension DataModelLifecycle {
    func willWrite(in context: DataModelWriteContext) async throws {}

    func validateModel(in context: DataModelWriteContext) async throws -> [ValidationResult] {
        []
    }

    func validationResult(for violation: ConstraintViolation) -> ValidationResult? {
        nil
    }

    func didWrite(in context: DataModelWriteContext) async throws {}

    func didCommit(in context: DataModelCommitContext) async {}

    static var warningPolicy: ValidationWarningPolicy {
        .advisory
    }
}
