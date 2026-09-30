// DataModelLifecycleError.swift
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

/// Request-time framework failure in the lifecycle middleware; internal like `ContainmentError` —
/// apps never catch it, its value is the diagnostic message on the refused write. Coverage tests
/// assert the typed case via @testable.
enum DataModelLifecycleError: Error, CustomDebugStringConvertible {
    case applicationShutDown(modelType: String, action: DataModelAction)

    var debugDescription: String {
        switch self {
        case .applicationShutDown(let modelType, let action):
            "A \(modelType) \(action) reached DataModelLifecycle after the Application that registered it had shut down, so willWrite, the Fields rules, validateModel and the after-write hooks had no Application to run against. The write was refused rather than let through unvalidated. Writes must not outlive the Application that configured them: keep it alive for the duration of the work, or stop the work before shutdown."
        }
    }
}
