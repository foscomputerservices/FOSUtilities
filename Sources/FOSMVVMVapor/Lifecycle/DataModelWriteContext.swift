// DataModelWriteContext.swift
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
import Foundation
import Vapor

/// What ``DataModelLifecycle/willWrite(in:)``, ``DataModelLifecycle/validateModel(in:)`` and
/// ``DataModelLifecycle/didWrite(in:)`` receive
///
/// Read `action` to decide what applies, query through `database` so you see the same
/// transaction as the write, and reach configuration through `application`:
///
/// ```swift
/// public func validateModel(in context: DataModelWriteContext) async throws -> [ValidationResult] {
///     guard context.action == .create else { return [] }
///     let limit = context.application.cardLimits.perBoard
///     let count = try await Card.query(on: context.database).filter(\.$board.$id == $board.id).count()
///     return count >= limit ? [.init(status: .error, message: validationMessages.boardFull)] : []
/// }
/// ```
///
/// When the write came through a FOSMVVM write request, `database` is that request's transaction,
/// so a query you make here and the row about to be written are one state.
public struct DataModelWriteContext: Sendable {
    public let action: DataModelAction
    public let database: any Database
    public let application: Vapor.Application
}
