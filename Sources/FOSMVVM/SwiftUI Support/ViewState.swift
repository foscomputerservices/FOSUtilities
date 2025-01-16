// ViewState.swift
//
// Created by David Hunt on 1/15/25
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

#if canImport(SwiftUI) && canImport(AppState)
import AppState
import FOSFoundation
import FOSMVVM
import SwiftUI

public struct ViewState: Sendable {
    public let viewStateKey: String
    public let requestData: Data?
    public let testUrl: URL?

    public static let testViewStateKey = "__test__"

    public init<R: ViewModelRequest>(type: R.Type, request: R? = nil) {
        self.viewStateKey = R.viewStateKey
        self.requestData = try? request?.toJSONData()
        self.testUrl = nil
    }

    public static var initial: Self {
        .init()
    }

    fileprivate init(testUrl: URL) {
        self.viewStateKey = Self.testViewStateKey
        self.requestData = nil
        self.testUrl = testUrl
    }

    private init() {
        self.viewStateKey = ""
        self.requestData = nil
        self.testUrl = nil
    }
}

public extension ViewModelRequest {
    static var viewStateKey: String {
        String(describing: Self.self)
    }
}

public extension ViewModelRequest {
    var viewState: ViewState {
        .init(type: Self.self, request: self)
    }
}

public extension Application {}

public struct ApplicationHostView<VM>: View where VM: ViewModelFactory, VM: ViewModelViewFactory, VM.Request.Fragment == EmptyFragment, VM.Request.Query == EmptyQuery, VM.Request.RequestBody == EmptyBody, VM.Request.ResponseBody == VM {
    private let viewState: Binding<ViewState>
    @State private var viewModel: VM?

    public var body: some View {
        let viewModel = $viewModel
        VM.ViewModelViewType
            .bind(viewModel: viewModel)
            .onOpenURL { url in
                processURLRequest(url, viewState: viewState)
            }
        #if DEBUG
            // Used by testing harness
            .onAppear {
                if
                    let arg = ProcessInfo.processInfo.arguments.first,
                    let url = URL(string: arg) {
                    processURLRequest(url, viewState: viewState)
                }
            }
        #endif
    }

    public init(viewState: Binding<ViewState>) {
        self.viewState = viewState
    }
}

public struct ApplicationClientHostedView<VM>: View where VM: ClientHostedViewModelFactory, VM: ViewModelViewFactory, VM.Request.Fragment == EmptyFragment, VM.Request.Query == EmptyQuery, VM.Request.RequestBody == EmptyBody, VM.Request.ResponseBody == VM {
    private let viewState: Binding<ViewState>
    @State private var viewModel: VM?

    public var body: some View {
        let viewModel = $viewModel
        VM.ViewModelViewType
            .bind(viewModel: viewModel)
            .onOpenURL { url in
                processURLRequest(url, viewState: viewState)
            }
        #if DEBUG
            // Used by testing harness
            .onAppear {
                print(ProcessInfo.processInfo.arguments.count)
                print(ProcessInfo.processInfo.arguments)
                if ProcessInfo.processInfo.arguments.count >= 2 {
                    let arg = ProcessInfo.processInfo.arguments[1]
                    print(arg)

                    if let url = URL(string: arg) {
                        processURLRequest(url, viewState: viewState)
                    }
                }
            }
        #endif
    }

    public init(viewState: Binding<ViewState>) {
        self.viewState = viewState
    }
}

public protocol ViewModelViewFactory: RequestableViewModel {
    associatedtype ViewModelViewType: ViewModelView where ViewModelViewType.VM == Self
}

private extension View {
    func processURLRequest(_ url: URL, viewState: Binding<ViewState>) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return
        }

        #if DEBUG
        if let action = comps.host, action == "test-view-request" {
            viewState.wrappedValue = ViewState(testUrl: url)
            return
        }
        #endif

        guard let requestStr = comps.queryItems?.first?.value else {
            return
        }
    }
}
#endif
