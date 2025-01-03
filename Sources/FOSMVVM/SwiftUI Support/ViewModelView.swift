// ViewModelView.swift
//
// Created by David Hunt on 1/1/25
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
/// ``ViewModelView/bind(viewModel:query:fragment:)`` that allows the
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
    ///   @State var viewModel: MyViewModel?
    ///
    ///   var body: some View {
    ///     MyView.bind(
    ///        viewModel: $viewModel,
    ///        query: .init( ... )
    ///     )
    ///   }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - viewModel: A [Binding](https://developer.apple.com/documentation/swiftui/binding)
    ///     used to store the retrieved ``ViewModel``
    ///   - query: A *SystemQuery* to be sent to the server to indicate how to compose the ``ViewModel``
    ///   - fragment: *Future*
    ///
    /// - Returns: A *Loading View* while retrieving the ``ViewModel`` or an instance of
    ///   *Self* if the ``ViewModel`` has been successfully retrieved
    ///
    /// - See Also: ``MVVMEnvironment/loadingView``
    @ViewBuilder static func bind(viewModel: @Sendable @autoclosure @escaping () -> Binding<VM.Request.ResponseBody?>, query: VM.Request.Query, fragment: VM.Request.Fragment? = nil) -> some View where VM.Request.ResponseBody == Self.VM {
        if let viewModel = viewModel().wrappedValue {
            Self(viewModel: viewModel)
        } else {
            MVVMEnvironmentView { mvvmEnv, locale in
                mvvmEnv.loadingView()
                    .task {
                        do {
                            viewModel().wrappedValue =
                                try await mvvmEnv.serverBaseURL
                                    .appending(serverRequest: VM.Request(
                                        query: query,
                                        fragment: fragment,
                                        requestBody: nil,
                                        responseBody: nil
                                    ))?.fetch(locale: locale)
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
    ///   @State var viewModel: MyViewModel?
    ///
    ///   var body: some View {
    ///     MyView.bind(
    ///        viewModel: $viewModel
    ///     )
    ///   }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - viewModel: A [Binding](https://developer.apple.com/documentation/swiftui/binding)
    ///     used to store the retrieved ``ViewModel``
    ///
    /// - Returns: A *Loading View* while retrieving the ``ViewModel`` or an instance of
    ///   *Self* if the ``ViewModel`` has been successfully retrieved
    ///
    /// - See Also: ``MVVMEnvironment/loadingView``
    @ViewBuilder static func bind(viewModel: @Sendable @autoclosure @escaping () -> Binding<VM.Request.ResponseBody?>) -> some View where VM.Request.ResponseBody == Self.VM, VM.Request.Query == EmptyQuery {
        if let viewModel = viewModel().wrappedValue {
            Self(viewModel: viewModel)
        } else {
            MVVMEnvironmentView { mvvmEnv, locale in
                mvvmEnv.loadingView()
                    .task {
                        do {
                            viewModel().wrappedValue =
                                try await mvvmEnv.serverBaseURL
                                    .appending(serverRequest: VM.Request(
                                        query: nil,
                                        fragment: nil,
                                        requestBody: nil,
                                        responseBody: nil
                                    ))?.fetch(locale: locale)
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
