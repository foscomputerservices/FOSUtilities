// Label.swift
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

import SwiftUI

public extension Label where Title == Text, Icon == Image {
    /// Creates a label with an icon image and a title generated from a Localizable.
    ///
    /// - Parameters:
    ///    - title: A Localizable used as the label's title.
    ///    - image: The name of the image resource to lookup.
    nonisolated init(
        _ localizable: some Localizable,
        defaultValue: String? = nil,
        image name: String
    ) {
        self.init(localizable.defaultedLocalizedString(defaultValue: defaultValue), image: name)
    }

    /// Creates a label with a system icon image and a title generated from a
    /// Localizable.
    ///
    /// - Parameters:
    ///    - title: A Localizable used as the label's title.
    ///    - systemImage: The name of the image resource to lookup.
    nonisolated init(
        _ localizable: some Localizable,
        defaultValue: String? = nil,
        systemImage name: String
    ) {
        self.init(localizable.defaultedLocalizedString(defaultValue: defaultValue), systemImage: name)
    }
}
