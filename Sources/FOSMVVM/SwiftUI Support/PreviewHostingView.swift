// PreviewHostingView.swift
//
// Created by David Hunt on 3/12/25
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
import Foundation
import SwiftUI

public extension ViewModelView {
    /// Creates an instance of the ``ViewModelView`` and it's corresponding ``ViewModel`` that
    /// will be bound with stub data and with all ``LocalizedString`` values bound to their localized
    /// values
    ///
    /// ## Example:
    ///
    /// ```swift
    /// public struct MyViewModel: ViewModel {
    ///     @LocalizedString public var title
    /// }
    ///
    ///  struct MyView: ViewModelView {
    ///
    ///     let viewModel: MyViewModel
    ///
    ///     var body: some View {
    ///         Text(viewModel.title)
    ///     }
    /// }
    ///
    /// #Preview {
    ///     MyView.previewHost()
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - resourceDirectoryName: The directory name that contains the resources (default: "")
    ///   - locale: The locale to lookup the YAML bindings for (default: Locale.current)
    static func previewHost(resourceDirectoryName: String = "", locale: Locale = .current, viewModel: VM = .stub()) -> some View {
        PreviewHostingView(
            inner: Self.self,
            resourceDirectoryName: resourceDirectoryName,
            locale: locale,
            viewModel: viewModel
        )
    }
}

private struct PreviewHostingView<Inner: ViewModelView>: View {
    @State private var localizationStore: LocalizationStore?

    let inner: Inner.Type
    let resourceDirectoryName: String
    let locale: Locale
    let viewModel: Inner.VM

    var body: some View {
        if let localizationStore {
            Inner(viewModel: viewModel(
                localizationStore: localizationStore,
                viewModel: viewModel
            ))
            .preferredColorScheme(ColorScheme.light)
            .environment(mmEnv(resourceDirectoryName: resourceDirectoryName))
        } else {
            Text("Loading...")
                .task {
                    do {
                        localizationStore = try await Bundle.main.yamlLocalization(
                            resourceDirectoryName: resourceDirectoryName
                        )
                    } catch {
                        fatalError("Unable to initialize the localization store: \(error)")
                    }
                }
        }
    }

    private func mmEnv(resourceDirectoryName: String) -> MVVMEnvironment {
        MVVMEnvironment(
            appBundle: Bundle.main,
            resourceDirectoryName: resourceDirectoryName,
            deploymentURLs: [
                .debug: .init(serverBaseURL: URL(string: "https://localhost:8080")!)
            ]
        )
    }

    private func viewModel(localizationStore: LocalizationStore, viewModel: Inner.VM) -> Inner.VM {
        let encoder = JSONEncoder.localizingEncoder(
            locale: locale,
            localizationStore: localizationStore
        )
        do {
            return try viewModel.toJSON(encoder: encoder).fromJSON()
        } catch {
            print("Unable to localize ViewModel.  Most data will likely be blank.  Error: \(error)")
            return viewModel
        }
    }
}
#endif
