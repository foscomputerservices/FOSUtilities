// DataModelCommitContext.swift
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
import Vapor

/// What ``DataModelLifecycle/didCommit(in:)`` receives after the transaction has committed
///
/// There is no database here: the transaction is over. Use `application` for the side effect the
/// commit unlocks:
///
/// ```swift
/// public func didCommit(in context: DataModelCommitContext) async {
///     guard context.action == .create else { return }
///     await context.application.mailer.sendWelcome(to: email)
/// }
/// ```
public struct DataModelCommitContext: Sendable {
    public let action: DataModelAction
    public let application: Vapor.Application
}
