// FieldValidationsView.swift
//
// Copyright 2025 FOS Computer Services, LLC
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
import SwiftUI

/// ``FieldValidationsView`` wraps another view with validation messages
///
/// ``FieldValidationsView`` monitors ``Validations`` in the SwiftUI environment
/// and searches for messages that match the corresponding ``FormField/fieldId``.
/// When a message is located, the first of the messages is displayed around the affected
/// field.
struct FieldValidationsView<Wrapped: View>: View {
    let wrappedView: Wrapped
    let fieldId: FormFieldIdentifier

    @Environment(\.colorScheme) private var colorScheme
    @Environment(Validations.self) private var validations

    var body: some View {
        if let message = validationErrorMessage, !message.message.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                wrappedView
                Text(message.message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.leading)
            }
        } else {
            wrappedView
        }
    }

    private var validationErrorMessage: ValidationResult.Message? {
        validations.validations.compactMap { validation in
            validation.messages.filter { message in
                message.fieldIds.contains(fieldId)
            }.first
        }.first
    }
}

#endif
