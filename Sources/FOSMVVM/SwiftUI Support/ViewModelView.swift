// ViewModelView.swift
//
// Created by David Hunt on 9/11/24
// Copyright 2024 FOS Services, LLC
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
import FOSFoundation
import Foundation
import SwiftUI

/// A standardized SwiftUI View pattern for using ``ViewModel``s
///
/// SwiftUI Views that bind to ``FOSMVVM`` ``ViewModel``s should
/// conform to ``ViewModelView`` as opposed to just SwiftUI's [View](https://developer.apple.com/documentation/swiftui/view)
/// protocol.  This will enable services to work with ``ViewModel``s.
///
/// Views that conform to ``ViewModelView`` have an extra static method
/// ``ViewModelView/bind(viewModel:using:)`` that allows the
/// parent view to retrieve the ``ViewModel`` from the web service and create an
/// instance of the view bound to the retrieved instance.
///
/// ## Example
///
/// ```swift
/// public struct MyViewModel: ViewModel {
///   @LocalizedString public var pageTitle
/// }
///
/// struct MyView: ViewModelView {
///   let viewModel: MyViewModel
///
///   var body: some View {
///     Text(viewModel.pageTitle)
///   }
/// }
/// ```
public protocol ViewModelView: View {
    associatedtype VM: ViewModel

    init(viewModel: VM)
}

public extension ViewModelView where VM: RequestableViewModel {
    /// Retrieves a ``RequestableViewModel`` from the web service and binds it to the
    /// [View](https://developer.apple.com/documentation/swiftui/view)
    ///
    /// ## Example
    ///
    /// ```swift
    /// public struct MyViewModel: RequestableViewModel {
    ///   @LocalizedString public var pageTitle
    /// }
    ///
    /// struct MyView: ViewModelView {
    ///   let viewModel: MyViewModel
    ///
    ///   var body: some View {
    ///     Text(viewModel.pageTitle)
    ///   }
    /// }
    ///
    /// struct ParentView: View {
    ///   @State var viewModel: MyViewModel
    ///
    ///   var body: some View {
    ///     MyView.bind(
    ///        viewModel: $viewModel,
    ///        using: MyViewModelRequest()
    ///     )
    ///   }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - viewModel: A [Binding](https://developer.apple.com/documentation/swiftui/binding)
    ///     used to store the retrieved ``ViewModel``
    ///   - request: A ``ViewModelRequest`` to specify information regarding the
    ///     required ``ViewModel`` instance
    ///
    /// - Returns: A *Loading View* while retrieving the ``ViewModel`` or an instance of
    ///   *Self* if the ``ViewModel`` has been successfully retrieved
    ///
    /// - See Also: ``MVVMEnvironment/loadingView``
    @ViewBuilder static func bind(viewModel: Binding<VM.Request.ResponseBody?>, using request: VM.Request) -> some View where VM.Request.ResponseBody == Self.VM {
        if let viewModel = viewModel.wrappedValue {
            Self(viewModel: viewModel)
        } else {
            MVVMEnvironmentView { mvvmEnv, locale in
                let serverBaseURL = mvvmEnv.serverBaseURL
                return mvvmEnv.loadingView()
                    .task {
                        do {
                            viewModel.wrappedValue =
                                try await serverBaseURL
                                    .appending(serverRequest: request)?
                                    .fetch(locale: locale)
                        } catch { // let e {
                            // TODO: Error handling
                            // Probably want to handle errors out-of-band.
                            // That is, no need to put an error view here,
                            // as that would yield tiny error views all
                            // over the UI.  But instead, some top-level
                            // way to display to the user that the app
                            // encountered an error.
                        }
                    }
            }
        }
    }
}
#endif
