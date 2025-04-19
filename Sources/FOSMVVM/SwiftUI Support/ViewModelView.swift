// ViewModelView.swift
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

#if canImport(SwiftUI)
import FOSFoundation
import Foundation
import SwiftUI

public enum ViewModelViewError: Error, CustomDebugStringConvertible {
    case badServerRequestAction
    case badClientRequestAction
    case missingRequestBody
    case missingLocalizationStore

    public var debugDescription: String {
        switch self {
        case .badServerRequestAction:
            "ViewModelViewError: Only show (GET) and create (POST) actions are supported for Server ViewModel requests"
        case .badClientRequestAction:
            "ViewModelViewError: Only show (GET) actions are supported for Client ViewModel requests"
        case .missingRequestBody:
            "ViewModelViewError: Create (POST) actions must include a request body"
        case .missingLocalizationStore:
            "ViewModelViewError: Missing Client Localization Store in MVVMEnvironment"
        }
    }

    public var localizedDescription: String {
        debugDescription
    }
}

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
    /// @ViewModelImpl
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
    ///     let viewModel = $viewModel
    ///     MyView.bind(
    ///        viewModel: viewModel,
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
    @ViewBuilder static func bind(viewModel: @Sendable @autoclosure @escaping () -> Binding<VM.Request.ResponseBody?>, query: VM.Request.Query, fragment: VM.Request.Fragment? = nil, body: VM.Request.RequestBody? = nil) -> some View where VM.Request.ResponseBody == VM {
        if let viewModel = viewModel().wrappedValue {
            Self(viewModel: viewModel)
        } else {
            MVVMEnvironmentView { mvvmEnv, locale in
                mvvmEnv.loadingView()
                    .task {
                        do {
                            viewModel().wrappedValue = try await resolveServerHostedRequest(
                                mvvmEnv: mvvmEnv,
                                query: query,
                                fragment: fragment,
                                body: body,
                                locale: locale
                            )
                        } catch {
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

    /// Retrieves a ``RequestableViewModel`` locally and binds it to the
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
    ///     let viewModel = $viewModel
    ///     MyView.bind(
    ///        viewModel: viewModel,
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
    @ViewBuilder static func bind(viewModel: @Sendable @autoclosure @escaping () -> Binding<VM.Request.ResponseBody?>, query: VM.Request.Query, fragment: VM.Request.Fragment? = nil) -> some View where VM.Request.ResponseBody == VM, VM: ClientHostedViewModelFactory, VM == VM.Request.ResponseBody {
        if let viewModel = viewModel().wrappedValue {
            Self(viewModel: viewModel)
        } else {
            MVVMEnvironmentView { mvvmEnv, locale in
                mvvmEnv.loadingView()
                    .task {
                        do {
                            viewModel().wrappedValue = try await resolveClientHostedRequest(
                                mvvmEnv: mvvmEnv,
                                query: query,
                                fragment: fragment,
                                locale: locale
                            )
                        } catch {
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
    ///     let viewModel = $viewModel
    ///     MyView.bind(
    ///        viewModel: viewModel
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
    @ViewBuilder static func bind(viewModel: @Sendable @autoclosure @escaping () -> Binding<VM.Request.ResponseBody?>) -> some View where VM.Request.ResponseBody == VM, VM.Request.Query == EmptyQuery, VM.Request.Fragment == EmptyFragment, VM.Request.RequestBody == EmptyBody {
        if let viewModel = viewModel().wrappedValue {
            Self(viewModel: viewModel)
        } else {
            MVVMEnvironmentView { mvvmEnv, locale in
                mvvmEnv.loadingView()
                    .task {
                        do {
                            viewModel().wrappedValue = try await resolveServerHostedRequest(
                                mvvmEnv: mvvmEnv,
                                query: nil,
                                fragment: nil,
                                body: nil,
                                locale: locale
                            )
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

    /// Retrieves a ``RequestableViewModel`` locally and binds it to the
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
    ///     let viewModel = $viewModel
    ///     MyView.bind(
    ///        viewModel: viewModel
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
    @ViewBuilder static func bind(viewModel: @Sendable @autoclosure @escaping () -> Binding<VM.Request.ResponseBody?>) -> some View where VM.Request.ResponseBody == VM, VM.Request.Query == EmptyQuery, VM.Request.Fragment == EmptyFragment, VM.Request.RequestBody == EmptyBody, VM: ClientHostedViewModelFactory, VM == VM.Request.ResponseBody {
        if let viewModel = viewModel().wrappedValue {
            Self(viewModel: viewModel)
        } else {
            MVVMEnvironmentView { mvvmEnv, locale in
                mvvmEnv.loadingView()
                    .task {
                        do {
                            viewModel().wrappedValue = try await resolveClientHostedRequest(
                                mvvmEnv: mvvmEnv,
                                query: nil,
                                fragment: nil,
                                locale: locale
                            )
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

    /// Resolves a ViewModelRequest from an external Web Service
    private static func resolveServerHostedRequest(mvvmEnv: MVVMEnvironment, query: VM.Request.Query?, fragment: VM.Request.Fragment?, body: VM.Request.RequestBody?, locale: Locale) async throws -> VM? {
        let request = VM.Request(
            query: query,
            fragment: fragment,
            requestBody: body,
            responseBody: nil
        )

        guard let url = try await mvvmEnv.serverBaseURL.appending(serverRequest: request) else {
            return nil
        }

        switch request.action {
        case .show:
            return try await url.fetch(locale: locale)
        case .create:
            guard let requestBody = request.requestBody else {
                throw ViewModelViewError.missingRequestBody
            }

            return try await url.send(
                data: requestBody
            )
        default:
            throw ViewModelViewError.badServerRequestAction
        }
    }

    /// Resolves a ViewModelRequest locally to the client application
    private static func resolveClientHostedRequest(mvvmEnv: MVVMEnvironment, query: VM.Request.Query?, fragment: VM.Request.Fragment?, locale: Locale) async throws -> VM? where VM: ClientHostedViewModelFactory, VM == VM.Request.ResponseBody {
        guard let localizationStore = try await mvvmEnv.clientLocalizationStore else {
            throw ViewModelViewError.missingLocalizationStore
        }

        let request = VM.Request(
            query: query,
            fragment: fragment,
            requestBody: nil,
            responseBody: nil
        )

        guard request.action == .show else {
            throw ViewModelViewError.badClientRequestAction
        }

        let context = ClientHostedModelFactoryContext(
            locale: locale,
            localizationStore: localizationStore,
            vmRequest: request
        )
        return try await VM.model(context: context, vmRequest: request)
    }
}
#endif
