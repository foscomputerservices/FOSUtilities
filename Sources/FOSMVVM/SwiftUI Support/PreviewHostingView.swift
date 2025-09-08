// PreviewHostingView.swift
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
    /// struct MyView: ViewModelView {
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
    /// ## Example - Setting States
    ///
    /// At times it is advantageous to be able to set the @State variables of a view that is being previewed.
    /// The *setStates:* function provides for this option.
    ///
    /// ```swift
    /// public struct MyViewModel: ViewModel {
    ///     @LocalizedString public var title
    /// }
    ///
    /// struct MyView: ViewModelView {
    ///     @State private isTitleShowing = true
    ///
    ///     let viewModel: MyViewModel
    ///
    ///     var body: some View {
    ///         if isTitleShowing {
    ///             Text(viewModel.title)
    ///         }
    ///     }
    /// }
    ///
    /// private extension MyView {
    ///     mutating func setStates(
    ///         isTitleShowing: Bool
    ///     ) {
    ///         _isTitleShowing = State(initialValue: isTitleShowing)
    ///     }
    /// }
    ///
    /// #Preview("Hidden Title") {
    ///     MyView.previewHost(
    ///         setStates: { view in
    ///             view.setStates(
    ///                 isTitleShowing: false
    ///             )
    ///         }
    ///    )
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - bundle: The Bundle that contains the resources of the YAML files (default: Bundle.main)
    ///   - resourceDirectoryName: The directory name within the app bundle that contains localization resources (e.g., YAML files) (default: "")
    ///   - locale: The locale to lookup the YAML bindings for (default: Locale.current)
    ///   - viewModel: A ViewModel that will be provided to the ViewModelView (default: .stub())
    ///   - setStates: A function that can modify the ViewModelView instance (default: nil)
    static func previewHost(
        bundle: Bundle = .main,
        resourceDirectoryName: String = "",
        locale: Locale = .current,
        viewModel: VM = .stub(),
        setStates: ((inout Self) -> Void)? = nil
    ) -> some View {
        PreviewHostingView(
            inner: Self.self,
            bundle: bundle,
            resourceDirectoryName: resourceDirectoryName,
            locale: locale,
            viewModel: viewModel,
            setStates: setStates
        )
    }
}

private extension ViewModelView {
    func setStates(modifier: (inout Self) -> Void) -> Self {
        var modified = self
        modifier(&modified)
        return modified
    }
}

private struct PreviewHostingView<Inner: ViewModelView>: View {
    @State private var loadingText = "Loading Localization for Preview..."
    @State private var localizationStore: LocalizationStore?

    let inner: Inner.Type
    let bundle: Bundle
    let resourceDirectoryName: String
    let locale: Locale
    let viewModel: Inner.VM
    let setStates: ((inout Inner) -> Void)?

    var body: some View {
        if let localizationStore {
            Inner(viewModel: viewModel(
                localizationStore: localizationStore,
                viewModel: viewModel
            ))
            .setStates(modifier: setStates ?? { _ in () })
            .environment(mmEnv(localizationStore: localizationStore))
        } else {
            Text(loadingText)
                .task {
                    do {
                        localizationStore = try await bundle.yamlLocalization(
                            resourceDirectoryName: resourceDirectoryName
                        )
                    } catch {
                        loadingText = """
                            Unable to initialize the localization store: \(error)

                              - Bundle: \(bundle.bundlePath)
                              - resourceDirectoryName: \(resourceDirectoryName.isEmpty ? "<Empty>" : resourceDirectoryName)
                        """
                    }
                }
        }
    }

    private func mmEnv(localizationStore: LocalizationStore) -> MVVMEnvironment {
        MVVMEnvironment(
            localizationStore: localizationStore,
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
