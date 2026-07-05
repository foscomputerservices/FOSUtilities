// ContainerTests.swift
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
import Testing

@Suite("Container")
struct ContainerTests {
    /// A container that owns Berths.
    struct Dock: Container {
        var id: ModelIdType?
        static var containedRecordTypes: [any Model.Type] {
            [Berth.self]
        }

        init(id: ModelIdType? = nil) {
            self.id = id
        }
    }

    /// A leaf model that owns nothing — inherits the empty default.
    struct Berth: Container {
        var id: ModelIdType?
        init(id: ModelIdType? = nil) {
            self.id = id
        }
    }

    @Test("Override returns declared contained types (dispatched through Container.self)")
    func override() {
        func containedTypes(of type: (some Container).Type) -> [any Model.Type] {
            type.containedRecordTypes
        }
        #expect(containedTypes(of: Dock.self).count == 1)
        #expect(containedTypes(of: Dock.self).first is Berth.Type)
    }

    @Test("A model that owns nothing inherits the empty default")
    func emptyDefault() {
        #expect(Berth.containedRecordTypes.isEmpty)
    }
}
