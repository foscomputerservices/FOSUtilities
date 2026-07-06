// WriteRoute.swift
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
import FOSMVVM
import Foundation
import Vapor

// The write path (C8 T6): apply + fall-through. A write loads its auth-scoped candidate set,
// resolves the submitted target against it, mutates, commits, invalidates the mutated containers'
// cached records (never the per-Request grant memo), then re-serves ITSELF through the genuine read
// pipeline — building its own ResponseBody from the refreshed records. The whole flow runs
// sequentially in the one handler task (the C6 cache's single-writer contract).

extension Request {
    /// PATCH: validate → load candidates → resolve target → `apply` → save → invalidate → refresh.
    func serveUpdate<SR: UpdateRequest>(_ boundRequest: SR, body: SR.RequestBody) async throws -> SR.ResponseBody
        where SR.RequestBody: DataModelWriter,
        SR.Query: TargetedQuery,
        SR.ResponseBody: VaporResponseBodyFactory {
        let context = try await commitUpdate(boundRequest, body: body)
        invalidateWrittenContainers(context)
        return try await serve(boundRequest)
    }

    /// POST: validate → load candidate scope → fresh `Target()` → `apply` → create into scope →
    /// invalidate → refresh. No target resolution — the candidate scope is the destination.
    func serveCreate<SR: CreateRequest>(_ boundRequest: SR, body: SR.RequestBody) async throws -> SR.ResponseBody
        where SR.RequestBody: DataModelWriter,
        SR.ResponseBody: VaporResponseBodyFactory {
        let context = try await commitCreate(boundRequest, body: body)
        invalidateWrittenContainers(context)
        return try await serve(boundRequest)
    }

    /// DELETE: load candidates → resolve target → framework delete → invalidate → refresh. No body
    /// to validate, nothing to apply — deletion is framework-owned.
    func serveDelete<SR: DeleteRequest>(_ boundRequest: SR) async throws -> SR.ResponseBody
        where SR.RequestBody: WriteTargetProviding,
        SR.Query: TargetedQuery,
        SR.ResponseBody: VaporResponseBodyFactory {
        let context = try await commitDelete(boundRequest)
        invalidateWrittenContainers(context)
        return try await serve(boundRequest)
    }
}

// MARK: - Commit (steps 1–6; invalidation + the refresh are the serve tail above)

extension Request {
    /// Split from serveUpdate — and deliberately NOT invalidating — so the commit half is observable
    /// in tests: candidates only, the page read plan never loaded, before the refresh runs.
    @discardableResult
    func commitUpdate<SR: UpdateRequest>(_ boundRequest: SR, body: SR.RequestBody) async throws -> WriteCandidateContext
        where SR.RequestBody: DataModelWriter, SR.Query: TargetedQuery {
        // 2. Structural gate: a failing validation never reaches apply.
        if let error = body.validate() {
            throw error
        }
        // 3. Load the writer's candidate set (write-verb grants), candidates only.
        let context = try await loadCandidates(for: boundRequest)
        // 4. Resolve the submitted target against the candidate set (not-yours == not-found).
        guard let selector = boundRequest.query?.target else {
            throw Abort(.badRequest, reason: "\(String(describing: SR.self)) requires a target identity")
        }
        let target: SR.RequestBody.Target = try resolveWriteTarget(selector: selector, context: context)
        // 5. Authored apply. 6. Save (the caller invalidates).
        try body.apply(to: target)
        try await target.save(on: db)
        return context
    }

    @discardableResult
    func commitCreate<SR: CreateRequest>(_ boundRequest: SR, body: SR.RequestBody) async throws -> WriteCandidateContext
        where SR.RequestBody: DataModelWriter {
        if let error = body.validate() {
            throw error
        }
        let context = try await loadCandidates(for: boundRequest)
        guard let tuple = context.plan.tuples.first,
              let container = context.resolved.rootIdentities[tuple.root] else {
            throw ContainmentError.invalidLoadPlan(
                request: String(describing: SR.self),
                reason: "the create candidate scope did not resolve to a container — the writer's candidate set is missing"
            )
        }
        // The create door's step-4 twin: update/delete gate on target membership; create has no
        // target, so it gates on the grant verdict itself. A denial is not-found — the same shape
        // a create into a missing container produces (no authorization oracle).
        guard try await holdsAuthorization(tuple.operation, ofType: SR.RequestBody.Target.self, in: container) else {
            throw Abort(.notFound)
        }
        let fresh = SR.RequestBody.Target()
        try body.apply(to: fresh)
        // The framework sets the container FK from the candidate scope — apply never names a parent.
        try await createMember(fresh, in: container, on: db)
        return context
    }

    @discardableResult
    func commitDelete<SR: DeleteRequest>(_ boundRequest: SR) async throws -> WriteCandidateContext
        where SR.RequestBody: WriteTargetProviding, SR.Query: TargetedQuery {
        let context = try await loadCandidates(for: boundRequest)
        guard let selector = boundRequest.query?.target else {
            throw Abort(.badRequest, reason: "\(String(describing: SR.self)) requires a target identity")
        }
        let target: SR.RequestBody.Target = try resolveWriteTarget(selector: selector, context: context)
        try await target.delete(on: db)
        return context
    }
}

// MARK: - Shared write steps

/// The resolved candidate plan for one write request, bound to its query root(s) and executed —
/// its records live in the request's container-record cache, keyed by the tuple.
struct WriteCandidateContext {
    let plan: RecordLoadPlan
    let resolved: ResolvedRecordLoadPlan
}

extension Request {
    /// Runs the write request's candidate plan through the SAME executor path a read plan uses —
    /// its records land in the cache under the write verb's operation. The page's read plan is not
    /// loaded here; only the candidates are.
    func loadCandidates<SR: ServerRequest>(for boundRequest: SR) async throws -> WriteCandidateContext {
        guard let plan = application.candidatePlan(for: SR.self) else {
            throw ContainmentError.invalidLoadPlan(
                request: String(describing: SR.self),
                reason: "no candidate plan was derived — register the request as a write via try app.register(request:), which derives and validates the candidate plan at boot"
            )
        }
        let resolved = try await resolveRecordLoadPlan(plan, for: boundRequest)
        try await resolved.execute(on: self)
        return WriteCandidateContext(plan: plan, resolved: resolved)
    }

    /// Resolves the submitted opaque identity against the loaded candidate records by identity
    /// equality. A miss throws `Abort(.notFound)` — the same shape a missing row produces, so
    /// not-yours is indistinguishable from not-found (no authorization oracle).
    func resolveWriteTarget<Target: DataModel>(
        selector: ModelIdentity,
        context: WriteCandidateContext
    ) throws -> Target {
        guard let tuple = context.plan.tuples.first else {
            throw ContainmentError.invalidLoadPlan(
                request: context.resolved.requestName,
                reason: "the candidate plan has no tuple — the writer's candidate set is missing; there is nothing to resolve the target against"
            )
        }
        let records = (tupleCacheKeys[tuple] ?? []).flatMap { containerRecordCache[$0] ?? [] }
        guard let match = records.first(where: { record in
            (try? record.modelIdentity).map { $0 == selector } ?? false
        }) else {
            throw Abort(.notFound)
        }
        guard let typed = match as? Target else {
            throw ContainmentError.invalidLoadPlan(
                request: context.resolved.requestName,
                reason: "a candidate record is not \(String(describing: Target.self)) — framework-invariant breakage; file an issue"
            )
        }
        return typed
    }

    /// Invalidates the cached records of every container the candidate load touched (its roots and
    /// each branch container) — the C6 pass-#2 contract, so the refresh re-serves fresh. Touches
    /// records only; the per-Request grant memo stands.
    func invalidateWrittenContainers(_ context: WriteCandidateContext) {
        var touched = Set(context.resolved.rootIdentities.values)
        for tuple in context.plan.tuples {
            for key in tupleCacheKeys[tuple] ?? [] {
                touched.insert(key.container)
            }
        }
        for container in touched {
            invalidateContainerRecords(of: container)
        }
    }
}
