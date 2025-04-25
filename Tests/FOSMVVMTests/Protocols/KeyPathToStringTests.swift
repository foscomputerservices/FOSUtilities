// KeyPathToStringTests.swift
//
// Created by David Hunt on 9/4/24
// Copyright 2024 FOS Computer Services, LLC
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
@testable import FOSMVVM
import Testing

@Suite("KeyPath to String Tests")
struct KeyPathToStringTests {
    @Test func testSimple() throws {
        let model = Model()
        let map = model.propertyNames()
        #expect(map[model._propertyLocalizationId] == "property")
    }
}

@ViewModel
private struct Model {
    @LocalizedString var property
    let vmId: ViewModelId

    var _propertyLocalizationId: LocalizableId {
        _property.localizationId
    }

    init() {
        self.vmId = .init()
    }

    static func stub() -> Model { .init() }
}
