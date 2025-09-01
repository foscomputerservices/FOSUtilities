// ViewModelView.swift
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
/// @ViewModel public struct MyViewModel {
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
    /// Retrieves a ``RequestableViewModel`` locally and binds it to the
    /// [View](https://developer.apple.com/documentation/swiftui/view)
    ///
    /// ## Example
    ///
    /// ```swift
    /// @ViewModel public struct MyViewModel: RequestableViewModel {
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
    ///
    ///   var body: some View {
    ///     MyView.bind(
    ///        query: .init( ... )
    ///     )
    ///   }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - query: A *SystemQuery* to be sent to the server to indicate how to compose the ``ViewModel``
    ///   - fragment: *Future*
    ///
    /// - Returns: A *Loading View* while retrieving the ``ViewModel`` or an instance of
    ///   *Self* if the ``ViewModel`` has been successfully retrieved
    ///
    /// - See Also: ``MVVMEnvironment/loadingView``
    @ViewBuilder @MainActor static func bind(
        query: VM.Request.Query,
        fragment: VM.Request.Fragment? = nil
    ) -> some View where
        VM.Request.RequestBody == EmptyBody,
        VM.Request.ResponseBody == VM,
        VM: ClientHostedViewModelFactory,
        VM.AppState == Void {
        VMClientResolverView<VM, Self>(
            query: query,
            fragment: fragment
        )
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
    ///
    ///   var body: some View {
    ///     MyView.bind(
    ///        query: .init( ... )
    ///     )
    ///   }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - query: A *SystemQuery* to be sent to the server to indicate how to compose the ``ViewModel``
    ///   - fragment: *Future*
    ///
    /// - Returns: A *Loading View* while retrieving the ``ViewModel`` or an instance of
    ///   *Self* if the ``ViewModel`` has been successfully retrieved
    ///
    /// - See Also: ``MVVMEnvironment/loadingView``
    @ViewBuilder @MainActor static func bind(
        query: VM.Request.Query,
        fragment: VM.Request.Fragment? = nil
    ) -> some View where
        VM.Request.RequestBody == EmptyBody,
        VM.Request.ResponseBody == VM {
        VMServerResolverView<VM, Self>(
            query: query,
            fragment: fragment
        )
    }

    /// Retrieves a ``RequestableViewModel`` locally and binds it to the
    /// [View](https://developer.apple.com/documentation/swiftui/view)
    ///
    /// ## Example
    ///
    /// ```swift
    /// public struct MyViewModel: RequestableViewModel {
    ///   @LocalizedString public var pageTitle
    ///   public let aState: Bool
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
    /// extension MyViewModel: ClientHostedViewModelFactory {
    ///     public struct AppState: Hashable, Sendable {
    ///         public let aState: Bool
    ///         public init(aState: Bool) {
    ///             self.aState = aState
    ///         }
    ///     }
    ///     public static func model(
    ///         context: ClientHostedModelFactoryContext<Request, AppState>
    ///     ) async throws -> Request.ResponseBody {
    ///         .init(
    ///             aState: context.appState.aState
    ///         )
    ///     }
    /// }
    ///
    /// struct ParentView: View {
    ///   @State var aState = false
    ///
    ///   var body: some View {
    ///     MyView.bind(
    ///        query: .init( ... ),
    ///        appState: .init(aState: aState)
    ///     )
    ///   }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - query: A *SystemQuery* to be sent to the server to indicate how to compose the ``ViewModel``
    ///   - fragment: *Future*
    ///   - appState: Context transferred from one view to another ``ViewModel``
    ///
    /// - Returns: A *Loading View* while retrieving the ``ViewModel`` or an instance of
    ///   *Self* if the ``ViewModel`` has been successfully retrieved
    ///
    /// - See Also: ``MVVMEnvironment/loadingView``
    @ViewBuilder @MainActor static func bind(
        query: VM.Request.Query,
        fragment: VM.Request.Fragment? = nil,
        appState: VM.AppState
    ) -> some View where
        VM.Request.RequestBody == EmptyBody,
        VM.Request.ResponseBody == VM,
        VM: ClientHostedViewModelFactory,
        VM.AppState: Hashable & Sendable {
        VMClientAppStateResolverView<VM, Self>(
            query: query,
            fragment: fragment,
            appState: appState
        )
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
    ///
    ///   var body: some View {
    ///     MyView.bind()
    ///   }
    /// }
    /// ```
    ///
    /// - Returns: A *Loading View* while retrieving the ``ViewModel`` or an instance of
    ///   *Self* if the ``ViewModel`` has been successfully retrieved
    ///
    /// - See Also: ``MVVMEnvironment/loadingView``
    @ViewBuilder @MainActor static func bind() -> some View where
        VM.Request.RequestBody == EmptyBody,
        VM.Request.ResponseBody == VM,
        VM.Request.Query == EmptyQuery,
        VM.Request.Fragment == EmptyFragment,
        VM.Request.RequestBody == EmptyBody,
        VM: ClientHostedViewModelFactory,
        VM.AppState == Void {
        VMClientResolverView<VM, Self>(query: nil, fragment: nil)
    }

    /// Retrieves a ``RequestableViewModel`` from the web service and binds it to the
    /// [View](https://developer.apple.com/documentation/swiftui/view)
    ///
    /// ## Example
    ///
    /// ```swift
    /// @ViewModel public struct MyViewModel: RequestableViewModel {
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
    ///
    ///   var body: some View {
    ///     MyView.bind()
    ///   }
    /// }
    /// ```
    ///
    /// - Returns: A *Loading View* while retrieving the ``ViewModel`` or an instance of
    ///   *Self* if the ``ViewModel`` has been successfully retrieved
    ///
    /// - See Also: ``MVVMEnvironment/loadingView``
    @ViewBuilder @MainActor static func bind() -> some View where
        VM.Request.RequestBody == EmptyBody,
        VM.Request.ResponseBody == VM,
        VM.Request.Query == EmptyQuery,
        VM.Request.Fragment == EmptyFragment,
        VM.Request.RequestBody == EmptyBody {
        VMServerResolverView<VM, Self>(query: nil, fragment: nil)
    }

    /// Retrieves a ``RequestableViewModel`` locally and binds it to the
    /// [View](https://developer.apple.com/documentation/swiftui/view)
    ///
    /// ## Example
    ///
    /// ```swift
    /// @ViewModel public struct MyViewModel: RequestableViewModel {
    ///   @LocalizedString public var pageTitle
    ///   public let aState: Bool
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
    /// extension MyViewModel: ClientHostedViewModelFactory {
    ///     public struct AppState: Hashable, Sendable {
    ///         public let aState: Bool
    ///         public init(aState: Bool) {
    ///             self.aState = aState
    ///         }
    ///     }
    ///     public static func model(
    ///         context: ClientHostedModelFactoryContext<Request, AppState>
    ///     ) async throws -> Request.ResponseBody {
    ///         .init(
    ///             aState: context.appState.aState
    ///         )
    ///     }
    /// }
    ///
    /// struct ParentView: View {
    ///   @State var aState = false
    ///
    ///   var body: some View {
    ///     MyView.bind(
    ///        appState: .init(aState: aState)
    ///     )
    ///   }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - appState: Context transferred from one view to another ``ViewModel``
    ///
    /// - Returns: A *Loading View* while retrieving the ``ViewModel`` or an instance of
    ///   *Self* if the ``ViewModel`` has been successfully retrieved
    ///
    /// - See Also: ``MVVMEnvironment/loadingView``
    @ViewBuilder @MainActor static func bind(appState: VM.AppState) -> some View where
        VM.Request.ResponseBody == VM,
        VM.Request.Query == EmptyQuery,
        VM.Request.Fragment == EmptyFragment,
        VM.Request.RequestBody == EmptyBody,
        VM: ClientHostedViewModelFactory,
        VM.AppState: Hashable & Sendable {
        VMClientAppStateResolverView<VM, Self>(
            query: nil,
            fragment: nil,
            appState: appState
        )
    }
}

private struct VMServerResolverView<VM, VMV>: View where
    VM: RequestableViewModel,
    VM.Request.RequestBody == EmptyBody,
    VM == VM.Request.ResponseBody,
    VMV: ViewModelView,
    VMV.VM == VM {
    @Environment(MVVMEnvironment.self) private var mvvmEnv
    @Environment(\.locale) private var locale
    @State private var viewModel: VM?

    private let query: VM.Request.Query?
    private let fragment: VM.Request.Fragment?

    var body: some View {
        ZStack {
            if let viewModel {
                VMV(viewModel: viewModel)
                    .onChange(of: query, initial: true) { Task {
                        self.viewModel = await resolveServerHostedRequest()
                    } }
                    .onChange(of: fragment, initial: true) {
                        guard fragment != nil else { return }
                        Task {
                            self.viewModel = await resolveServerHostedRequest()
                        }
                    }
            } else {
                ProgressView().task {
                    viewModel = await resolveServerHostedRequest()
                }
            }
        }
    }

    init(query: VM.Request.Query?, fragment: VM.Request.Fragment?) {
        self.query = query
        self.fragment = fragment
    }

    private func resolveServerHostedRequest() async -> VM? {
        do {
            let request = VM.Request(
                query: query,
                fragment: fragment,
                requestBody: nil,
                responseBody: nil
            )
            let errorType = VM.Request.ResponseError.self == EmptyError.self
                ? nil
                : VM.Request.ResponseError.self

            guard let url = try await mvvmEnv.serverBaseURL.appending(serverRequest: request) else {
                return nil
            }

            var httpHeaders = SystemVersion.current.versioningHeaders
            for (key, value) in mvvmEnv.requestHeaders {
                httpHeaders.append((field: key, value: value))
            }

            switch request.action {
            case .show:
                if let errorType {
                    return try await url.fetch(
                        headers: httpHeaders,
                        locale: locale,
                        errorType: errorType
                    )
                } else {
                    return try await url.fetch(
                        headers: httpHeaders,
                        locale: locale
                    )
                }
            case .create:
                guard let requestBody = request.requestBody else {
                    throw ViewModelViewError.missingRequestBody
                }

                if let errorType {
                    return try await url.send(
                        headers: httpHeaders,
                        data: requestBody,
                        errorType: errorType
                    )
                } else {
                    return try await url.send(
                        headers: httpHeaders,
                        data: requestBody
                    )
                }
            default:
                throw ViewModelViewError.badServerRequestAction
            }
        } catch {
            print("ViewModel Bind Error: \(error)")
            // TODO: Error handling
            // Probably want to handle errors out-of-band.
            // That is, no need to put an error view here,
            // as that would yield tiny error views all
            // over the UI.  But instead, some top-level
            // way to display to the user that the app
            // encountered an error.
            return nil
        }
    }
}

private struct VMClientAppStateResolverView<VM, VMV>: View where
    VM: RequestableViewModel,
    VM == VM.Request.ResponseBody,
    VM: ClientHostedViewModelFactory,
    VM.Context == ClientHostedModelFactoryContext<VM.Request, VM.AppState>,
    VM.AppState: Hashable & Sendable,
    VMV: ViewModelView,
    VMV.VM == VM {
    @Environment(MVVMEnvironment.self) private var mvvmEnv
    @Environment(\.locale) private var locale
    @State private var viewModel: VM?

    private let query: VM.Request.Query?
    private let fragment: VM.Request.Fragment?
    private let appState: VM.AppState

    var body: some View {
        ZStack {
            if let viewModel {
                VMV(viewModel: viewModel)
                    .onChange(of: query, initial: true) {
                        guard query != nil else { return }
                        Task {
                            self.viewModel = await resolveClientHostedRequest()
                        }
                    }
                    .onChange(of: fragment, initial: true) {
                        guard fragment != nil else { return }
                        Task {
                            self.viewModel = await resolveClientHostedRequest()
                        }
                    }
                    .onChange(of: appState, initial: true) { Task {
                        self.viewModel = await resolveClientHostedRequest()
                    } }
            } else {
                ProgressView().task {
                    viewModel = await resolveClientHostedRequest()
                }
            }
        }
    }

    init(query: VM.Request.Query?, fragment: VM.Request.Fragment?, appState: VM.AppState) {
        self.query = query
        self.fragment = fragment
        self.appState = appState
    }

    private func resolveClientHostedRequest() async -> VM? {
        do {
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
                vmRequest: request,
                appState: appState
            )

            return try await VM.model(context: context, vmRequest: request)
        } catch {
            print("ViewModel Bind Error: \(error)")
            // TODO: Error handling
            // Probably want to handle errors out-of-band.
            // That is, no need to put an error view here,
            // as that would yield tiny error views all
            // over the UI.  But instead, some top-level
            // way to display to the user that the app
            // encountered an error.
            return nil
        }
    }
}

private struct VMClientResolverView<VM, VMV>: View where
    VM: RequestableViewModel,
    VM == VM.Request.ResponseBody,
    VM: ClientHostedViewModelFactory,
    VM.Context == ClientHostedModelFactoryContext<VM.Request, VM.AppState>,
    VM.AppState == Void,
    VMV: ViewModelView,
    VMV.VM == VM {
    @Environment(MVVMEnvironment.self) private var mvvmEnv
    @Environment(\.locale) private var locale
    @State private var viewModel: VM?

    private let query: VM.Request.Query?
    private let fragment: VM.Request.Fragment?

    var body: some View {
        if let viewModel {
            VMV(viewModel: viewModel)
                .onChange(of: query, initial: true) { Task {
                    self.viewModel = await resolveClientHostedRequest()
                } }
                .onChange(of: fragment, initial: true) {
                    guard fragment != nil else { return }
                    Task {
                        self.viewModel = await resolveClientHostedRequest()
                    }
                }
        } else {
            ProgressView().task {
                viewModel = await resolveClientHostedRequest()
            }
        }
    }

    init(query: VM.Request.Query?, fragment: VM.Request.Fragment?) {
        self.query = query
        self.fragment = fragment
    }

    private func resolveClientHostedRequest() async -> VM? {
        do {
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
                vmRequest: request,
                appState: ()
            )

            return try await VM.model(context: context, vmRequest: request)
        } catch {
            print("ViewModel Bind Error: \(error)")
            // TODO: Error handling
            // Probably want to handle errors out-of-band.
            // That is, no need to put an error view here,
            // as that would yield tiny error views all
            // over the UI.  But instead, some top-level
            // way to display to the user that the app
            // encountered an error.
            return nil
        }
    }
}

#endif
