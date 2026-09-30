// FormValidationsView.swift
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
import SwiftUI

/// ``FormValidationsView`` wraps another view with the model-level validation messages
///
/// ``FormValidationsView`` monitors ``Validations`` in the SwiftUI environment and displays
/// every message that names no field above the wrapped view.  ``FieldValidationsView``
/// displays the messages that do name a field.
struct FormValidationsView<Wrapped: View>: View {
    let wrappedView: Wrapped

    @Environment(Validations.self) private var installedValidations: Validations?

    private var validations: Validations {
        MissingEnvironmentDiagnostic.require(
            installedValidations,
            orStop: MissingEnvironmentDiagnostic.missingFormValidations()
        )
    }

    var body: some View {
        if modelMessages.isEmpty {
            wrappedView
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(modelMessages, id: \.self) { message in
                    Text(message.message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.leading)
                }
                wrappedView
            }
        }
    }

    private var modelMessages: [ValidationResult.Message] {
        validations.modelMessages.filter { !$0.message.isEmpty }
    }
}

public extension View {
    /// Shows the form's model-level validation messages above this view
    ///
    /// Apply it to the form or to the view where the summary belongs; it adds nothing when there
    /// are none:
    ///
    /// ```swift
    /// Form {
    ///     FormFieldView(fieldModel: title, focusField: $focus)
    /// }
    /// .withFormValidations()
    /// .environment(validations)
    /// ```
    ///
    /// Requires `Validations` in the environment, like the field views.
    func withFormValidations() -> some View {
        FormValidationsView(wrappedView: self)
    }
}
#endif
