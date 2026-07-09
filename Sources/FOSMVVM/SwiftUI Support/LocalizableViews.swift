// LocalizableViews.swift
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

public extension Text {
    // Hand-written, not swept: Apple's LocalizedStringKey `Text` init is
    // `init(_:tableName:bundle:comment:)` — its bundle-lookup parameters have no
    // meaning for pre-localized strings, so the sweep honestly rejects it
    // (no-delegate-target). This init is FOSMVVM's own contract, not a mechanical
    // mirror of an Apple overload.

    /// Displays ``Localizable`` text in the UI
    ///
    /// - Parameter localizable: The ``Localizable`` text to be presented
    ///
    /// ## Example
    ///
    /// ```swift
    /// public struct MyViewModel: ViewModel {
    ///   @LocalizedString public var pageTitle
    /// }
    ///
    /// struct LandingPageView: ViewModelView {
    ///   let viewModel: LandingPageViewModel
    ///
    ///   var body: some View {
    ///     Text(viewModel.pageTitle)
    ///   }
    /// }
    /// ```
    init(_ localizable: some Localizable, defaultValue: String? = nil) {
        self.init(localizable.defaultedLocalizedString(defaultValue: defaultValue))
    }

    /// Displays optional ``Localizable`` text in the UI
    ///
    /// When *localizable* is `nil`, *defaultValue* is rendered instead;
    /// when that is also `nil`, an empty string is rendered.
    ///
    /// ## Example
    ///
    /// ```swift
    /// public struct MyViewModel: ViewModel {
    ///   public var subtitle: LocalizableString?
    /// }
    ///
    /// struct LandingPageView: ViewModelView {
    ///   let viewModel: LandingPageViewModel
    ///
    ///   var body: some View {
    ///     Text(viewModel.subtitle, defaultValue: "—")
    ///   }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - localizable: The ``Localizable`` text to be presented, if any
    ///   - defaultValue: Fallback text used when *localizable* is `nil`
    ///     or its localization did not complete
    init(_ localizable: (some Localizable)?, defaultValue: String? = nil) {
        self.init(localizable?.defaultedLocalizedString(defaultValue: defaultValue) ?? defaultValue ?? "")
    }
}

public extension LabeledContent where Label == Text, Content == Text {
    // Hand-written, not swept: Apple's LocalizedStringKey `LabeledContent.init(_:value:)`
    // has no mechanically-matchable String/Text sibling — the sweep honestly rejects it
    // (no-delegate-target). This overload is FOSMVVM's own contract, preserved by hand.

    /// Creates a labeled content component with a title generated from a Localizable
    /// and a string value.
    ///
    /// ## Example
    ///
    /// ```swift
    /// LabeledContent(viewModel.balanceLabel, value: account.balance)
    /// ```
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

public extension Localizable {
    /// A view that resolves and displays this ``Localizable`` on the client
    ///
    /// Reach for `text` when the value's localization is still pending
    /// (`localizationStatus == .localizationPending`) — for example, a stubbed
    /// or locally-constructed value that never round-tripped through the
    /// server. The view resolves the value on the client via
    /// ``MVVMEnvironment``'s localization store. For values already localized
    /// by the server, use `Text(localizable)` instead.
    ///
    /// ## Example
    ///
    /// ```swift
    /// viewModel.pageTitle.text
    /// ```
    var text: some View {
        LocalizableResolverView(localizable: self)
    }
}

private struct LocalizableResolverView<L: Localizable>: View {
    let localizable: L

    @State private var value: String?
    @Environment(\.locale) private var locale
    @Environment(MVVMEnvironment.self) private var mvvmEnv

    var body: some View {
        if let value = localizedString {
            Text(value)
        } else {
            Text("")
                .onAppear {
                    // fosmvvm-review:disable:begin no-silent-failure -- Error handling is TBD
                    if let store = try? mvvmEnv.clientLocalizationStore {
                        resolve(locale: locale, store: store)
                    } else {
                        // TODO: Error handling
                        fatalError("Why no store???")
                    }
                    // fosmvvm-review:disable:end no-silent-failure
                }
        }
    }

    private var localizedString: String? {
        if localizable.localizationStatus == .localized {
            // fosmvvm-review:disable:next no-silent-failure -- Error handling is TBD
            return try? localizable.localizedString
        }

        return value
    }

    private func resolve(locale: Locale, store: any LocalizationStore) {
        guard value == nil else {
            return
        }

        let encoder = JSONEncoder.localizingEncoder(locale: locale, localizationStore: store)
        if let resolved: L = try? localizable
            .toJSON(encoder: encoder)
            .fromJSON() {
            // TODO: Add error logging in the future
            // fosmvvm-review:disable:next no-silent-failure -- "<Missing>" is the failure handler
            value = (try? resolved.localizedString) ?? "<Missing>"
        }
    }
}

#endif
