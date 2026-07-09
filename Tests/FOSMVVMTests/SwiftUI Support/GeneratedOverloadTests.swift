// GeneratedOverloadTests.swift
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
import FOSFoundation
import FOSMVVM
import FOSTesting
import Foundation
import SwiftUI
import Testing

/// Behavioral contract tests for the generated `Localizable` overload surface
/// (`SwiftUI Support/Generated/`) plus the hand-written survivors in
/// `LocalizableViews.swift`.
///
/// These assert the *contract* the overloads promise — never the generated
/// text. `Text` is `Equatable`, so the delegate policies are checked by
/// value-equality where the result type permits, and by compile-exercise
/// where SwiftUI's result views are not `Equatable`.
///
/// Value-equality assertions land on the `Text`-returning paths (the
/// hand-written survivors and `Text`-returning generated members);
/// `View`-returning generated members are compile-exercised because SwiftUI
/// views aren't `Equatable` — all paths share `defaultedLocalizedString`.
@Suite("Generated Overload Contract Tests")
struct GeneratedOverloadTests: LocalizableTestCase {
    let locStore: LocalizationStore
    init() throws {
        self.locStore = try Self.loadLocalizationStore(
            bundle: Bundle.module,
            resourceDirectoryName: "TestYAML"
        )
    }

    // MARK: Policy path 1 — direct (delegates to Apple's String-taking sibling)

    /// A *localized* `Localizable` rendered through the `Text` overload equals
    /// `Text(verbatim:)` of its resolved value: the direct policy forwards the
    /// localized string to Apple's non-localizing `Text(_:)` sibling.
    @Test func directOverloadRendersLocalizedValue() throws {
        let localized: LocalizableString = try LocalizableString
            .localized(key: "test")
            .toJSON(encoder: encoder())
            .fromJSON()

        #expect(localized.localizationStatus == .localized)
        #expect(try Text(localized) == Text(verbatim: localized.localizedString))
    }

    // MARK: defaultValue contract

    /// A *pending* (never-encoded) `Localizable` routed through an overload
    /// with `defaultValue:` renders the fallback — the value cannot resolve,
    /// so `defaultValue` is what reaches the delegate.
    @Test func pendingOverloadFallsBackToDefaultValue() {
        let pending = LocalizableString.localized(key: "test") // never encoded

        #expect(pending.localizationStatus == .localizationPending)
        #expect(Text(pending, defaultValue: "fallback") == Text(verbatim: "fallback"))
    }

    /// A GENERATED direct overload pinned by value:
    /// `Text.accessibilityLabel(_ localizable:defaultValue:)` returns `Text`
    /// (`Generated/Text+Localizable.swift`), so the delegation contract is
    /// asserted directly — our overload's result equals Apple's String-taking
    /// sibling applied to an identical base `Text` with the resolved string.
    /// Both branches: localized value, and pending + `defaultValue`.
    @Test func generatedTextAccessibilityLabelDelegates() throws {
        let base = Text(verbatim: "base")

        // Localized branch: resolves to the localized value
        let localized: LocalizableString = try LocalizableString
            .localized(key: "test")
            .toJSON(encoder: encoder())
            .fromJSON()
        let expectedLocalized = try base.accessibilityLabel(localized.localizedString)
        #expect(base.accessibilityLabel(localized) == expectedLocalized)

        // Pending branch: falls back to defaultValue.
        // The expected value's argument must be a String *value*, not a bare
        // literal — a literal would resolve to Apple's LocalizedStringKey
        // overload (different Text storage), not the String sibling our
        // overload delegates to.
        let pending = LocalizableString.localized(key: "test") // never encoded
        let fallback = "fallback"
        let expectedFallback = base.accessibilityLabel(fallback)
        #expect(base.accessibilityLabel(pending, defaultValue: fallback) == expectedFallback)
    }

    // MARK: Policy path 2 — text-verbatim (wraps in Text(verbatim:))

    /// A text-verbatim overload (`View.accessibilityCustomContent(_:_:importance:)`
    /// wraps the resolved value in `Text(verbatim:)`) compiles and yields
    /// `some View`. SwiftUI's result view is not `Equatable`, so this is a
    /// type-level / compile-exercise of the policy-2 path.
    @Test @MainActor func textVerbatimOverloadBuilds() throws {
        let localized: LocalizableString = try LocalizableString
            .localized(key: "test")
            .toJSON(encoder: encoder())
            .fromJSON()

        let view = EmptyView()
            .accessibilityCustomContent(localized, Text(verbatim: "value"))
        expectSomeView(view)
    }

    // MARK: Modifier path — direct, method-shaped

    /// A direct method-shaped modifier (`View.navigationTitle(_:)`) compiles
    /// and returns `some View`. Marked `@MainActor` to exercise the overload
    /// from the isolation a SwiftUI `body` actually calls it in.
    @Test @MainActor func navigationTitleModifierBuilds() throws {
        let localized: LocalizableString = try LocalizableString
            .localized(key: "test")
            .toJSON(encoder: encoder())
            .fromJSON()

        expectSomeView(EmptyView().navigationTitle(localized))
    }

    // MARK: Survivor contract — optional Text init nil-cascade

    /// The hand-written optional `Text(_:defaultValue:)` survivor cascades a
    /// `nil` localizable to `defaultValue`, and a `nil` `defaultValue` to the
    /// empty string.
    @Test func optionalTextInitNilCascade() {
        let none: LocalizableString? = nil

        #expect(Text(none, defaultValue: "d") == Text(verbatim: "d"))
        #expect(Text(none, defaultValue: nil) == Text(verbatim: ""))
    }

    /// Type-level assertion that a value is `some View` (SwiftUI result views
    /// are not `Equatable`, so behavior is checked by successful construction).
    @MainActor
    private func expectSomeView(_: some View) {}
}
#endif
