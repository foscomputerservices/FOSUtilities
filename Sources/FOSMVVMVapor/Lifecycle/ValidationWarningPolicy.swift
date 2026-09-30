// ValidationWarningPolicy.swift
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

/// What a `DataModel` does with a validation warning at save time
///
/// Set it once per model through ``DataModelLifecycle/warningPolicy``:
///
/// ```swift
/// public static var warningPolicy: ValidationWarningPolicy { .blocking }
/// ```
public enum ValidationWarningPolicy: Sendable {
    /// The write proceeds. The default. Warnings collected alongside an error still reach the client with it.
    case advisory
    /// A warning stops the write and reaches the client like an error.
    case blocking
}
