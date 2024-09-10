// Text.swift
//
// Created by David Hunt on 9/6/24
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
#endif
