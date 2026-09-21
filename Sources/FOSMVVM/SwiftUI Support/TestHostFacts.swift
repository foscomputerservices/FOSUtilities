// TestHostFacts.swift
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

#if canImport(SwiftUI)
import Foundation

// What `testHost()` publishes about the view it resolved, for a failing test to read back.
//
// `package`, never `public`. Accessibility identifiers are transport infrastructure: the
// framework provides API built on them and does not hand them to the app. A consumer never
// types this string, never queries this element, and must not learn it exists — publishing
// it would make an implementation detail into a contract that could never change.
//
// Why-required for `package`: FOSTestingUI runs in a different PROCESS and cannot read
// FOSMVVM's registry, so the only route is the accessibility tree; it is a separate target
// of the same package, and no consumer of either module needs this. See the repo's
// access-minimalism rule — `package` is earned by a definite requirement, not a hedge.

package enum TestHostFacts {
    package static let accessibilityIdentifier = "__testing_host_facts__"

    // The value is `ProductionParents.rawValue` rendered as a decimal string, reconstituted
    // test-side through `ProductionParents(rawValue:)`. No new serialization and no second
    // format: the option set already round-trips through the initializer it must expose.
    package static func value(for parents: ProductionParents) -> String {
        String(parents.rawValue)
    }

    package static func parents(from value: String) -> ProductionParents? {
        guard let rawValue = Int(value) else { return nil }

        return ProductionParents(rawValue: rawValue)
    }
}
#endif
