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
    /// Configures the view's title for purposes of navigation,
    /// using a localized string.
    ///
    /// A view's navigation title is used to visually display
    /// the current navigation state of an interface.
    /// On iOS and watchOS, when a view is navigated to inside
    /// of a navigation view, that view's title is displayed
    /// in the navigation bar. On iPadOS, the primary destination's
    /// navigation title is reflected as the window's title in the
    /// App Switcher. Similarly on macOS, the primary destination's title
    /// is used as the window title in the titlebar, Windows menu
    /// and Mission Control.
    ///
    /// Refer to the <doc:Configure-Your-Apps-Navigation-Titles> article
    /// for more information on navigation title modifiers.
    ///
    /// - Parameter titleKey: The key to a localized string to display.
    func navigationTitle(_ localizable: some Localizable) -> some View {
        navigationTitle(localizable.defaultedLocalizedString())
    }
}
#endif
