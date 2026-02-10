// LabeledContent.swift
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

public extension LabeledContent where Label == Text, Content == Text {
    /// Creates a labeled content component with a title generated from a Localizable
    /// and a string value.
    ///
    /// - Parameters:
    ///    - localizable: A Localizable used as the label.
    ///    - defaultValue: An optional default string if the localization fails.
    ///    - value: The string value to display.
    nonisolated init(
        _ localizable: some Localizable,
        defaultValue: String? = nil,
        value: String
    ) {
        self.init {
            Text(value)
        } label: {
            Text(localizable.defaultedLocalizedString(defaultValue: defaultValue))
        }
    }
}

public extension LabeledContent where Label == Text, Content: View {
    /// Creates a labeled content component with a title generated from a Localizable
    /// and a custom content view.
    ///
    /// - Parameters:
    ///    - localizable: A Localizable used as the label.
    ///    - defaultValue: An optional default string if the localization fails.
    ///    - content: A view builder that creates the content.
    nonisolated init(
        _ localizable: some Localizable,
        defaultValue: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init {
            content()
        } label: {
            Text(localizable.defaultedLocalizedString(defaultValue: defaultValue))
        }
    }
}
#endif
