// TestHost.swift
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
import SwiftUI

public extension View {
    /// Returns the view wrapped so that it can be tested with *ViewModelViewTestCase*
    ///
    /// The *decorator* *ViewBuilder* allows the hosting application to attach additional information to the
    /// view under test.  For example, this could be environment bindings that are substituted to allow the
    /// view under test to bind to test bindings.
    ///
    /// ## Example
    ///
    /// ```swift
    /// @main struct MyApp: App {
    ///
    ///    var body: some Scene {
    ///      WindowGroup {
    ///        MyMainView { ... }
    ///        #if DEBUG
    ///        .testHost { testView in
    ///          testView
    ///            .environment(\.binding, testValue)
    ///        }
    ///        #endif
    ///      }
    ///    }
    /// }
    /// ```
    ///
    /// - Parameter decorator: A *ViewBuilder* that can be used to attach additional test-only information to the view under test
    @ViewBuilder func testHost(@ViewBuilder decorator: (AnyView) -> some View) -> some View {
        #if DEBUG
        decorator(AnyView(TestingView(baseView: self)))
        #else
        self
        #endif
        // .onOpenURL { url in
        //     processURLRequest(url, viewState: viewState)
        // }
    }

    /// Returns the view wrapped so that it can be tested with *ViewModelViewTestCase*
    ///
    /// ## Example
    ///
    /// ```swift
    /// @main struct MyApp: App {
    ///
    ///    var body: some Scene {
    ///      WindowGroup {
    ///        MyMainView { ... }
    ///        #if DEBUG
    ///        .testHost()
    ///        #endif
    ///      }
    ///    }
    /// }
    /// ```
    func testHost() -> some View {
        testHost(decorator: { $0 })
    }
}

#if DEBUG
public extension URL {
    static let testHostRequest = "test-view-request"
}
#endif

private extension URL {
    var comps: URLComponents? {
        guard
            let comps = URLComponents(url: self, resolvingAgainstBaseURL: true),
            comps.host == "test-view-request"
        else {
            return nil
        }

        return comps
    }

    var viewModelType: String? {
        comps?.queryItems?.filter { $0.name == "viewModelType" }.first?.value
    }

    var viewModelData: Data? {
        guard
            let aStr = comps?.queryItems?.filter({ $0.name == "viewModel" }).first?.value,
            let str = aStr.reveal
        else {
            return nil
        }

        return str.data(using: .utf8)
    }

    func view(registeredTypes: [String: MVVMEnvironment.ViewFactory]) -> AnyView? {
        guard
            let vmTypeStr = viewModelType,
            let viewModelData
        else {
            return nil
        }

        guard let factory = registeredTypes[vmTypeStr] else {
            fatalError("Unknown testing view: \(vmTypeStr)")
        }

        return try? factory(viewModelData)
    }
}

extension ViewModelView {
    static var vmTypeStr: String {
        String(describing: type(of: self))
    }
}

#if DEBUG
private struct TestingView<BaseView: View>: View {
    let baseView: BaseView
    @State private var testView: AnyView? = nil
    @Environment(MVVMEnvironment.self) private var mvvmEnvironment

    var body: some View {
        if let testView {
            testView
        } else {
            baseView
                .onAppear { // Provided by the test harness
                    if ProcessInfo.processInfo.arguments.count > 1 {
                        let arg = ProcessInfo.processInfo.arguments[1]
                        if let url = URL(string: arg) {
                            testView = url.view(registeredTypes: mvvmEnvironment.registeredTestTypes)
                        }
                    }
                }
        }
    }
}
#endif
#endif
