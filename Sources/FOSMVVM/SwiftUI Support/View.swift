// View.swift
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

extension View {
    /// Wraps the given view with a `FieldValidationsView`
    func withValidations(for fieldModel: FormFieldModel<some Codable>) -> some View {
        FieldValidationsView(wrappedView: self, fieldId: fieldModel.formField.fieldId)
    }

    /// Wraps the given view with a `FieldValidationsView`
    func withValidations(for formField: FormFieldBase) -> some View {
        FieldValidationsView(wrappedView: self, fieldId: formField.fieldId)
    }

    /// Wraps the given view with a `FieldValidationsView`
    func withValidations(for fieldName: String) -> some View {
        FieldValidationsView(wrappedView: self, fieldId: .init(id: fieldName))
    }
}

public extension View {
    /// Indicates when a ``ViewModel`` binding might be out of date
    ///
    /// To invalidate a bound ``ViewModel``, provide a Binding<Bool> that returns
    /// **true** when the ``ViewModel`` should be re-pulled from the server.
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct MyView: ViewModelView {
    ///    @State private var vmOutOfDate = false
    ///
    ///    var body: some View {
    ///      VStack {
    ///        MySubView
    ///            .bind()
    ///            .invalidateBinding($vmOutOfDate)
    ///
    ///        Button("Invalidate") { vmOutOfDate = true }
    ///      }
    ///    }
    /// }
    /// ```
    ///
    /// - Parameter binding: A *Binding<Bool>* that is **true** when the ``ViewModel``
    ///     should be refreshed
    func invalidateBinding(_ binding: Binding<Bool>) -> some View {
        environment(\.viewModelInvalidated, binding)
    }

    /// - Parameter binding: A *Binding<VM>* that is **true** when the ``ViewModel``
    ///     should be refreshed with the provided value.
    func refreshedViewModel<VM: ViewModel>(_ binding: Binding<VM>) -> some View {
        environment(\.viewModelRefreshed, .init(
            // fosmvvm-review:disable:begin no-silent-failure -- TODO: Add error logging
            get: { (try? binding.wrappedValue.toJSON()) ?? "" },
            set: { newVMStr in
                if let newVM: VM = try? newVMStr.fromJSON() {
                    binding.wrappedValue = newVM
                }
            }
            // fosmvvm-review:disable:end no-silent-failure
        ))
    }
}

extension EnvironmentValues {
    @Entry var viewModelInvalidated: Binding<Bool> = .init(
        get: { false },
        set: { _ in }
    )

    @Entry var viewModelRefreshed: Binding<String> = .init(
        get: { "" },
        set: { _ in }
    )
}
#endif
