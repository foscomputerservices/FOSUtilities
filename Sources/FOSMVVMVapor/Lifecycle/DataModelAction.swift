// DataModelAction.swift
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

import Foundation

/// What is about to happen to your model's row, handed to every ``DataModelLifecycle`` hook
///
/// Read it from the context to make a hook act for some actions and not others:
///
/// ```swift
/// public func willWrite(in context: DataModelWriteContext) async throws {
///     if context.action == .create { createdAt = Date() }
/// }
/// ```
///
/// Your hook is told what will happen to the row, never which method was called: a model with a
/// `@Timestamp(on: .delete)` archives on a plain `delete(on:)` and destroys on
/// `delete(force: true, on:)`; a model without one destroys on either.
public enum DataModelAction: Sendable, Hashable {
    /// The row is being inserted
    case create
    /// The row is being changed in place; `save`, `update` and a replace request all arrive here
    case update
    /// The row stays, marked deleted through its delete timestamp
    case archive
    /// The row is being removed
    case destroy
    /// An archived row is coming back
    case restore
}
