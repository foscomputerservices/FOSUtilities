// ValidationsTests.swift
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

@Suite("Validations")
struct ValidationsTests {
    private static let failing = FormFieldIdentifier(id: "failing")
    private static let passing = FormFieldIdentifier(id: "passing")

    @Test("A field named by a failing result has an error")
    func failingFieldHasError() {
        let validations = Validations([
            .init(status: .error, fieldId: Self.failing, message: .constant("too large"))
        ])

        #expect(validations.hasError(for: Self.failing))
    }

    @Test("A field no failing result names does not have an error")
    func unnamedFieldHasNoError() {
        let validations = Validations([
            .init(status: .error, fieldId: Self.failing, message: .constant("too large"))
        ])

        #expect(!validations.hasError(for: Self.passing))
    }

    @Test("A warning is not an error, even for the field it names")
    func warningIsNotAnError() {
        let validations = Validations([
            .init(status: .warning, fieldId: Self.failing, message: .constant("unusual"))
        ])

        #expect(!validations.hasError(for: Self.failing))
    }

    @Test("An empty set has no error for any field")
    func emptyHasNoError() {
        #expect(!Validations().hasError(for: Self.failing))
    }
}
