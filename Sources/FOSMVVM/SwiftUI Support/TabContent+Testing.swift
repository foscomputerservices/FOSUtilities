// TabContent+Testing.swift
//
// Copyright 2026 FOS Computer Services, LLC
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

import SwiftUI

@available(iOS 18.0, macOS 15.0, *)
public extension TabContent {
    /// Adds an identifier that can be used to identify the element in an XCUITest
    ///
    /// ## Example
    ///
    /// ### View
    ///
    /// ```swift
    /// Tab("MyTab", image: "MyTabImage") { Text("Hello World") }
    ///   .uiTestingIdentifier("myTabButton")
    /// ```
    ///
    /// ### XCUITest
    ///
    /// ```swift
    /// private extension XCUIApplication {
    ///   var myTab: XCUIElement {
    ///       buttons.element(matching: .button, identifier: "myTabButton")
    ///
    ///       // Or possibly if button matching won't work -- breaks localization tests, however
    ///       buttons["MyTab"].firstMatch
    ///   }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - identifier: The accessibility identifier to apply.
    ///   - isEnabled: If true the accessibility identifier is applied;
    ///     otherwise the accessibility identifier is unchanged.
    func uiTestingIdentifier(_ string: String, isEnabled: Bool = true) -> some TabContent<Self.TabValue> {
        #if DEBUG
        accessibilityIdentifier(string, isEnabled: isEnabled)
        #else
        self
        #endif
    }
}
