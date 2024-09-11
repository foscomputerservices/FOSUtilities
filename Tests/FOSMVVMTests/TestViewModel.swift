// TestViewModel.swift
//
// Created by David Hunt on 9/8/24
// Copyright 2024 FOS Services, LLC
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

struct TestViewModel: RequestableViewModel {
    typealias Request = TestViewModelRequest

    @LocalizedString var aLocalizedString
    @LocalizedString(parentKeys: "aField") var title
    @LocalizedString(parentKeys: "aField", propertyName: "title") var aFieldTitle
    @LocalizedString(parentKeys: "aField", "validationMessages") var error1
    @LocalizedString(parentKeys: "aField", "validationMessages") var error2
    @LocalizedString(propertyName: "pieces", index: 0) var firstPiece
    @LocalizeInt(value: 42) var aLocalizedInt
    @LocalizedStrings var pieces
    @LocalizedString var separator
    @LocalizeCompoundString(pieces: \._pieces) var aLocalizedCompoundNoSep
    @LocalizeCompoundString(pieces: \._pieces, separator: \Self._separator) var aLocalizedCompoundSep

    @LocalizeSubs(substitutions: \.substitutions) var aLocalizedSubstitution
    private let substitutions: [String: LocalizableInt]

    var vmId = ViewModelId()

    public var displayName: LocalizableString { .constant("TestVM") }

    init() {
        self.substitutions = [
            "aSub": .init(value: 42)
        ]
    }

    public static func stub() -> Self {
        fatalError()
    }
}

final class TestViewModelRequest: ViewModelRequest {
    typealias Query = EmptyQuery
    let responseBody: TestViewModel?

    let id: String

    init(query: FOSMVVM.EmptyQuery? = nil, fragment: FOSMVVM.EmptyFragment? = nil, requestBody: FOSMVVM.EmptyBody? = nil, responseBody: TestViewModel? = nil) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }
}

#if canImport(Vapor)
import Vapor

extension TestViewModel: ViewModelFactory {
    // MARK: ViewModelFactory Protocol

    static func model(_ req: Vapor.Request, vmRequest: TestViewModelRequest) async throws -> Self {
        .init()
    }
}
#endif