// ProductionParents.swift
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

#if canImport(SwiftUI)
import Foundation

/// The production parents a *ViewModelView* is designed to live inside
///
/// Declare them where the view is registered, and `testHost()` presents the view under the
/// same parents production gives it:
///
/// ```swift
/// registerTestView(SettingsView.self, designedFor: .navigation)
/// registerTestView(DeviceCardView.self, designedFor: .scrolling)
/// registerTestView(DeviceDetailView.self, designedFor: [.navigation, .scrolling])
/// ```
///
/// A view that declares both is presented navigation-outermost —
/// `NavigationStack { ScrollView { view } }` — matching the way production nests them.
///
/// > Note: This states the view's *designed* environment, not a per-test preference. A view
/// > that declares nothing is presented bare.
public struct ProductionParents: OptionSet, Sendable {
    /// The view is designed to live inside a `NavigationStack`
    ///
    /// ```swift
    /// registerTestView(SettingsView.self, designedFor: .navigation)
    /// ```
    ///
    /// Declare it for any view that contributes to its navigation ancestor: `.toolbar`
    /// items, `navigationTitle`, `.searchable`, or `NavigationLink` destinations. All of
    /// those are preferences the *ancestor* renders, so presented with no navigation parent
    /// the view still appears — but everything it declared for the bar is absent from the
    /// accessibility tree, and a test looking for a toolbar button finds nothing.
    public static let navigation = ProductionParents(rawValue: 1 << 0)

    /// The view is designed to live inside a scrolling parent
    ///
    /// ```swift
    /// registerTestView(DeviceCardView.self, designedFor: .scrolling)
    /// ```
    ///
    /// Declare it for a view taller than a window in isolation — a form card inside a
    /// `ScrollView`, a section of a longer page. Presented bare, such a view compresses and
    /// overlaps, bottom controls sit beyond any tap's reach, keyboard avoidance displaces the
    /// whole content instead of scrolling, and XCUITest's scroll-to-visible has nothing to
    /// scroll.
    public static let scrolling = ProductionParents(rawValue: 1 << 1)

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}
#endif
