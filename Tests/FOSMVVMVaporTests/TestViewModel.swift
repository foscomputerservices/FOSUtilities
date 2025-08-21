// TestViewModel.swift
//
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
import FOSMVVM
import Foundation
import Testing

@ViewModel
struct TestViewModel: RequestableViewModel {
    typealias Request = TestViewModelRequest

    @LocalizedString var aLocalizedString
    @LocalizedString(parentKeys: "aField") var title
    @LocalizedString(parentKeys: "aField", propertyName: "title") var aFieldTitle
    @LocalizedString(parentKeys: "aField", "validationMessages") var error1
    @LocalizedString(parentKeys: "aField", "validationMessages") var error2
    @LocalizedString(propertyName: "pieces", index: 0) var firstPiece
    @LocalizedInt(value: 42) var aLocalizedInt
    @LocalizedStrings var pieces
    @LocalizedString var separator
    @LocalizedCompoundString(pieces: \._pieces) var aLocalizedCompoundNoSep
    @LocalizedCompoundString(pieces: \._pieces, separator: \Self._separator) var aLocalizedCompoundSep

    @LocalizedSubs(substitutions: \.substitutions) var aLocalizedSubstitution
    private let substitutions: [String: LocalizableInt]

    var vmId = ViewModelId()

    var displayName: LocalizableString { .constant("TestVM") }

    init() {
        self.substitutions = [
            "aSub": .init(value: 42)
        ]
    }

    static func stub() -> Self {
        fatalError()
    }
}

final class TestViewModelRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    var responseBody: TestViewModel?
    typealias ResponseError = EmptyError

    let id: String

    init(query: FOSMVVM.EmptyQuery? = nil, fragment: FOSMVVM.EmptyFragment? = nil, requestBody: FOSMVVM.EmptyBody? = nil, responseBody: TestViewModel? = nil) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }
}

extension TestViewModel: ViewModelFactory, ViewModelFactoryContext, Sendable {
    typealias Context = Self

    // MARK: ViewModelFactory Protocol

    var appVersion: SystemVersion { .init(major: 1, minor: 0) }

    static func model(context: Context) async throws -> Self {
        .init()
    }
}
