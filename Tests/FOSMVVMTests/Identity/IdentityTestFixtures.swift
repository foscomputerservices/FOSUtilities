// IdentityTestFixtures.swift
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

import FOSFoundation
import FOSMVVM
import Foundation

/// Stable marker — its reflection token must not churn; used for persisted/golden namespace tests.
enum TestWidgetIdentity {}

/// A Model that takes the zero-config reflection default for its namespace.
struct TestGadget: Model {
    var id: ModelIdType?
    init(id: ModelIdType? = UUID()) {
        self.id = id
    }
}

/// A Model that overrides its namespace by anchoring to a stable marker type.
struct TestWidget: Model {
    var id: ModelIdType?
    init(id: ModelIdType? = UUID()) {
        self.id = id
    }

    static var modelIdentityNamespace: ModelNamespace {
        .init(for: TestWidgetIdentity.self)
    }
}
