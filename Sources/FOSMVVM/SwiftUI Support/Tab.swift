// Tab.swift
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
#if canImport(SwiftUI)
import SwiftUI

@available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
public extension Tab where Value: Hashable, Content: View, Label: View {
    /// Creates a tab that the tab view presents when the tab view's selection
    /// matches the tab's value, with a string label.
    ///
    /// - Parameters:
    ///     - title: The ``Localizable`` label for the tab's tab item.
    ///     - image: The image for the tab's tab item.
    ///     - value: The `selection` value which selects this tab.
    ///     - content: The view content of the tab.
    init(
        _ localizable: some Localizable,
        image: String,
        value: Value,
        @ViewBuilder content: () -> Content
    ) where Label == DefaultTabLabel {
        self.init(
            localizable.defaultedLocalizedString(),
            image: image,
            value: value,
            content: content
        )
    }

    /// Creates a tab that the tab view presents when the tab view's selection
    /// matches the tab's value, with a string label.
    ///
    /// - Parameters:
    ///     - title: The ``Localizable`` label for the tab's tab item.
    ///     - image: The image for the tab's tab item.
    ///     - value: The `selection` value which selects this tab.
    ///     - role: The role defining the semantic purpose of the tab.
    ///     - content: The view content of the tab.
    init(
        _ localizable: some Localizable,
        image: String,
        value: Value,
        role: TabRole?,
        @ViewBuilder content: () -> Content
    ) where Label == DefaultTabLabel {
        self.init(
            localizable.defaultedLocalizedString(),
            image: image,
            value: value,
            role: role,
            content: content
        )
    }

    /// Creates a tab that the tab view presents when the tab view's selection
    /// matches the tab's value, with a string label.
    ///
    /// - Parameters:
    ///     - title: The ``Localizable`` label for the tab's tab item.
    ///     - image: The image for the tab's tab item.
    ///     - value: The `selection` value which selects this tab.
    ///     - content: The view content of the tab.
    init<T>(
        _ localizable: some Localizable,
        image: String,
        value: T,
        @ViewBuilder content: () -> Content
    ) where Value == T?, Label == DefaultTabLabel, T: Hashable {
        self.init(
            localizable.defaultedLocalizedString(),
            image: image,
            value: value,
            content: content
        )
    }

    /// Creates a tab that the tab view presents when the tab view's selection
    /// matches the tab's value, with a string label.
    ///
    /// - Parameters:
    ///     - title: The ``Localizable`` label for the tab's tab item.
    ///     - image: The image for the tab's tab item.
    ///     - value: The `selection` value which selects this tab.
    ///     - role: The role defining the semantic purpose of the tab.
    ///     - content: The view content of the tab.
    init<T>(
        _ localizable: some Localizable,
        image: String,
        value: T,
        role: TabRole?,
        @ViewBuilder content: () -> Content
    ) where Value == T?, Label == DefaultTabLabel, T: Hashable {
        self.init(
            localizable.defaultedLocalizedString(),
            image: image,
            value: value,
            role: role,
            content: content
        )
    }
}
#endif
