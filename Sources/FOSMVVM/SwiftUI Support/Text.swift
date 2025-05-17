// Text.swift
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

public extension Text {
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
    init(_ localizable: some Localizable) {
        self.init((try? localizable.localizedString) ?? "")
    }
}

public extension Localizable {
    var text: some View {
        LocalizableResolverView(localizable: self)
    }
}

private struct LocalizableResolverView<L: Localizable>: View {
    let localizable: L

    @State private var value: String? = nil
    @Environment(\.locale) private var locale
    @Environment(MVVMEnvironment.self) private var mvvmEnv

    var body: some View {
        if let value = localizedString {
            Text(value)
        } else {
            Text("")
                .task {
                    if let store = try? await mvvmEnv.clientLocalizationStore {
                        resolve(locale: locale, store: store)
                    } else {
                        // TODO: Error handling
                        fatalError("Why no store???")
                    }
                }
        }
    }

    private var localizedString: String? {
        if localizable.localizationStatus == .localized {
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
            value = (try? resolved.localizedString) ?? "Missing"
        }
    }
}

#endif
