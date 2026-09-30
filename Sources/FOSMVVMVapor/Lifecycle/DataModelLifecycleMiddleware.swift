// DataModelLifecycleMiddleware.swift
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

import FluentKit
import FOSMVVM
import Foundation
import Vapor

/// Runs ``DataModelLifecycle`` around every Fluent write of `M`, in the pinned order: `willWrite`;
/// the `Fields` rules (create and update only); `validateModel`; the write; the constraint claim;
/// `didWrite`; `didCommit`. One instance exists per model type in the registered graph
/// (`Application.registerLifecycleMiddleware(for:)`), installed BEFORE the emit middleware so the
/// validations run outside the emit's `next`.
struct DataModelLifecycleMiddleware<M: DataModel>: AsyncModelMiddleware {
    /// Weak-app closure: the middleware lives in the `Databases` configuration the `Application`
    /// owns, so a strong capture would cycle. After shutdown it answers nil, and the write is
    /// refused: a hook with no Application to run against is never silently skipped.
    let applicationReader: @Sendable () -> Vapor.Application?

    func create(model: M, on db: any Database, next: any AnyAsyncModelResponder) async throws {
        try await run(.create, model, on: db) { try await next.create(model, on: db) }
    }

    func update(model: M, on db: any Database, next: any AnyAsyncModelResponder) async throws {
        try await run(.update, model, on: db) { try await next.update(model, on: db) }
    }

    func delete(model: M, force: Bool, on db: any Database, next: any AnyAsyncModelResponder) async throws {
        // Fluent has already resolved the fate of the row: a forced delete, and an unforced one on
        // a model with no delete timestamp, both arrive here as the removal.
        try await run(.destroy, model, on: db) { try await next.delete(model, force: force, on: db) }
    }

    func softDelete(model: M, on db: any Database, next: any AnyAsyncModelResponder) async throws {
        try await run(.archive, model, on: db) { try await next.softDelete(model, on: db) }
    }

    func restore(model: M, on db: any Database, next: any AnyAsyncModelResponder) async throws {
        try await run(.restore, model, on: db) { try await next.restore(model, on: db) }
    }

    private func run(
        _ action: DataModelAction,
        _ model: M,
        on db: any Database,
        _ next: () async throws -> Void
    ) async throws {
        guard let application = applicationReader() else {
            throw DataModelLifecycleError.applicationShutDown(
                modelType: String(describing: M.self), action: action
            )
        }

        let context = DataModelWriteContext(action: action, database: db, application: application)
        try await model.willWrite(in: context)

        let validations = FOSMVVM.Validations()
        if action == .create || action == .update {
            _ = model.validate(fields: nil, validations: validations)
        }
        if let refusal = refusal(in: validations) {
            throw refusal
        }

        try await validations.append(contentsOf: model.validateModel(in: context))
        if let refusal = refusal(in: validations) {
            throw refusal
        }

        do {
            try await next()
        } catch {
            throw claimed(error, for: action, by: model, alongside: validations) ?? error
        }

        // The write stood, so nothing is left to refuse with; a warning the author asked to be
        // advisory is reported here and goes no further (the response is the refreshed ViewModel).
        if !validations.validations.isEmpty {
            db.logger.info(
                "\(String(describing: M.self)) was written with advisory validation results: \(validations.validations)"
            )
        }

        guard !isBatchWrite(action, model) else {
            return
        }

        try await model.didWrite(in: context)
        await runAfterCommit(action, model, on: db, application: application)
    }

    /// Whether `next` returned without a statement having run — FluentKit's batch paths
    /// (`[M].create(on:)`, `[M].delete(on:)`) hand every model to the middleware against a
    /// responder that does nothing and issue one statement afterwards
    /// (`Model+Concurrency.swift:143-185`), so the row's existence flag comes back exactly as it
    /// went in: a batch-created model still reads `_$idExists == false`, where a real insert's
    /// `output(from:)` has already set it true; a batch-destroyed one still reads `true`, where a
    /// real delete has already set it false. The batch clears both flags after its statement.
    /// FluentKit offers no batch update, soft delete or restore, so the other actions are always
    /// a real write.
    private func isBatchWrite(_ action: DataModelAction, _ model: M) -> Bool {
        switch action {
        case .create: !model._$idExists
        case .destroy: model._$idExists
        case .update, .archive, .restore: false
        }
    }

    /// The refusal both validation levels answer to: an error always refuses, a warning refuses only
    /// under `.blocking`. Everything collected so far rides in the refusal.
    private func refusal(in validations: FOSMVVM.Validations) -> ValidationError? {
        switch validations.status {
        case .error:
            ValidationError(validations: validations.validations)
        case .warning where M.warningPolicy == .blocking:
            ValidationError(validations: validations.validations)
        default:
            nil
        }
    }

    /// Offers a driver's constraint failure to the model and returns the refusal it claimed, or nil
    /// to leave the original error alone. Advisory results collected earlier ride along with it.
    private func claimed(
        _ error: any Error,
        for action: DataModelAction,
        by model: M,
        alongside validations: FOSMVVM.Validations
    ) -> ValidationError? {
        guard
            let databaseError = error as? any DatabaseError, databaseError.isConstraintFailure,
            let result = model.validationResult(
                for: ConstraintViolation(action: action, underlyingError: error)
            )
        else {
            return nil
        }

        return ValidationError(validations: validations.validations + [result])
    }

    /// The three after-commit routes: handed to the enclosing `liveTransaction` to run on its
    /// commit; suppressed inside a bare `database.transaction`, which exposes no commit to wait on;
    /// run immediately after an auto-commit write, whose middleware completion IS post-commit.
    private func runAfterCommit(
        _ action: DataModelAction,
        _ model: M,
        on db: any Database,
        application: Vapor.Application
    ) async {
        let commitContext = DataModelCommitContext(action: action, application: application)
        let deferred = await LiveTransactionState.deferUntilCommit(on: db) {
            await model.didCommit(in: commitContext)
        }
        guard !deferred else { return }

        guard db.inTransaction else {
            return await model.didCommit(in: commitContext)
        }

        let typeName = String(describing: M.self)
        if application.shouldWarnSuppressedAfterCommit(for: M.self) {
            db.logger.warning(
                "A \(typeName) write inside a bare database.transaction { } cannot run didCommit(in:) — FOSMVVM cannot see whether the transaction commits, so the after-commit work was suppressed. Use liveTransaction { } for a write whose commit a hook must see. (Warned once per model type.)"
            )
        }
    }
}
