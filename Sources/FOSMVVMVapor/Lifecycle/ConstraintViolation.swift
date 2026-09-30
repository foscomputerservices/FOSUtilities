// ConstraintViolation.swift
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

/// A database constraint the write ran into, offered to ``DataModelLifecycle/validationResult(for:)``
///
/// Look at `action` to know which write failed. Inspect `underlyingError` only when your model
/// has more than one constraint and needs to tell them apart:
///
/// ```swift
/// public func validationResult(for violation: ConstraintViolation) -> ValidationResult? {
///     guard violation.action == .create else { return nil }
///     return .init(status: .error, message: validationMessages.alreadyClaimed)
/// }
/// ```
public struct ConstraintViolation: Sendable {
    public let action: DataModelAction
    public let underlyingError: any Error & Sendable
}
