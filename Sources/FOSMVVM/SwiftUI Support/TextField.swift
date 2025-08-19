// TextField.swift
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

import FOSFoundation
#if canImport(SwiftUI)
import SwiftUI

public extension TextField where Label == Text {
    //    nonisolated init(
    //        _ localizableTitle: any Localizable,
    //        defaultTitle: String? = nil,
    //        text: Binding<String>,
    //        prompt: Text?
    //    ) {
    //        self.init(
    //            localizableTitle.defaultedLocalizedString(defaultValue: defaultTitle),
    //            text: text,
    //            prompt: prompt
    //        )
    //    }

    nonisolated init<F>(
        _ localizableTitle: any Localizable,
        defaultTitle: String? = nil,
        value: Binding<F.FormatInput?>,
        format: F,
        prompt: Text? = nil
    ) where F: ParseableFormatStyle, F.FormatOutput == String {
        self.init(
            localizableTitle.defaultedLocalizedString(defaultValue: defaultTitle),
            value: value,
            format: format,
            prompt: prompt
        )
    }

    nonisolated init<F>(
        _ localizableTitle: any Localizable,
        defaultTitle: String? = nil,
        value: Binding<F.FormatInput>,
        format: F,
        prompt: Text? = nil
    ) where F: ParseableFormatStyle, F.FormatOutput == String {
        self.init(
            localizableTitle.defaultedLocalizedString(defaultValue: defaultTitle),
            value: value,
            format: format,
            prompt: prompt
        )
    }

    nonisolated init(
        _ localizableTitle: any Localizable,
        defaultTitle: String? = nil,
        value: Binding<some Any>,
        formatter: Formatter,
        prompt: Text?
    ) {
        self.init(
            localizableTitle.defaultedLocalizedString(
                defaultValue: defaultTitle
            ),
            value: value,
            formatter: formatter,
            prompt: prompt
        )
    }

    nonisolated init(
        _ localizableTitle: any Localizable,
        defaultTitle: String? = nil,
        value: Binding<some Any>,
        formatter: Formatter
    ) {
        self.init(
            localizableTitle.defaultedLocalizedString(
                defaultValue: defaultTitle
            ),
            value: value,
            formatter: formatter
        )
    }

    nonisolated init(
        _ localizableTitle: any Localizable,
        defaultTitle: String? = nil,
        text: Binding<String>,
        prompt: Text? = nil,
        axis: Axis
    ) {
        self.init(
            localizableTitle.defaultedLocalizedString(
                defaultValue: defaultTitle
            ),
            text: text,
            prompt: prompt,
            axis: axis
        )
    }

    nonisolated init(
        _ localizableTitle: any Localizable,
        defaultTitle: String? = nil,
        text: Binding<String>,
        prompt: Text? = nil
    ) {
        self.init(
            localizableTitle.defaultedLocalizedString(
                defaultValue: defaultTitle
            ),
            text: text,
            prompt: prompt
        )
    }
}

@available(iOS 18.0, macOS 15.0, visionOS 2.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public extension TextField where Label == Text {
    nonisolated init(
        _ localizableTitle: any Localizable,
        defaultTitle: String? = nil,
        text: Binding<String>,
        selection: Binding<TextSelection?>,
        prompt: Text? = nil,
        axis: Axis? = nil
    ) {
        self.init(
            localizableTitle.defaultedLocalizedString(
                defaultValue: defaultTitle
            ),
            text: text,
            selection: selection,
            prompt: prompt,
            axis: axis
        )
    }
}
#endif
