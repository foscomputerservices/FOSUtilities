// AsyncButtonGeneratedSurfaceTests.swift
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

/// Compile-exercise coverage of the generated async Button surface
/// (`Generated/Button+AsyncAction.swift`): every titled form constructs
/// through its public signature. `Button` is not `Equatable`, so — as with
/// the sibling generated surface — construction is the assertable contract;
/// the tap semantics all twelve forward to are covered behaviorally in
/// `AsyncButtonActivityTests`.
@Suite("Async Button Generated Surface")
@MainActor
struct AsyncButtonGeneratedSurfaceTests: LocalizableTestCase {
    let locStore: LocalizationStore
    init() throws {
        self.locStore = try Self.loadLocalizationStore(
            bundle: Bundle.module,
            resourceDirectoryName: "TestYAML"
        )
    }

    @Test func titledForms_construct() throws {
        let title: LocalizableString = try LocalizableString
            .localized(key: "test")
            .toJSON(encoder: encoder())
            .fromJSON()
        let cancel = LocalizableString.constant("Cancel")
        let requiredActivity = Binding.constant(AsyncButtonActivity())
        let optionalActivity: Binding<AsyncButtonActivity>? = requiredActivity
        let error = Binding<Error?>.constant(nil)
        let action: @Sendable () async throws -> Void = {}

        // Label == SwiftUI.Label<Text, Image> — systemImage decorations
        let _: Button<SwiftUI.Label<Text, Image>> = Button(
            title, systemImage: "tray", role: nil,
            activity: optionalActivity, error: error, action: action
        )
        let _: Button<SwiftUI.Label<Text, Image>> = Button(
            title, systemImage: "tray",
            activity: optionalActivity, error: error, action: action
        )
        let _: Button<SwiftUI.Label<Text, Image>> = Button(
            title, systemImage: "tray",
            cancelTitle: cancel, cancelSystemImage: "xmark", role: nil,
            activity: requiredActivity, error: error, action: action
        )
        let _: Button<SwiftUI.Label<Text, Image>> = Button(
            title, systemImage: "tray",
            cancelTitle: cancel,
            activity: requiredActivity, error: error, action: action
        )

        // Label == SwiftUI.Label<Text, Image> — ImageResource decorations
        let _: Button<SwiftUI.Label<Text, Image>> = Button(
            title, image: ImageResource(name: "test", bundle: .module), role: nil,
            activity: optionalActivity, error: error, action: action
        )
        let _: Button<SwiftUI.Label<Text, Image>> = Button(
            title, image: ImageResource(name: "test", bundle: .module),
            activity: optionalActivity, error: error, action: action
        )
        let _: Button<SwiftUI.Label<Text, Image>> = Button(
            title, image: ImageResource(name: "test", bundle: .module),
            cancelTitle: cancel, cancelImage: nil, role: nil,
            activity: requiredActivity, error: error, action: action
        )
        let _: Button<SwiftUI.Label<Text, Image>> = Button(
            title, image: ImageResource(name: "test", bundle: .module),
            cancelTitle: cancel,
            activity: requiredActivity, error: error, action: action
        )

        // Label == Text
        let _: Button<Text> = Button(
            title, role: nil,
            activity: optionalActivity, error: error, action: action
        )
        let _: Button<Text> = Button(
            title,
            activity: optionalActivity, error: error, action: action
        )
        let _: Button<Text> = Button(
            title,
            cancelTitle: cancel, role: nil,
            activity: requiredActivity, error: error, action: action
        )
        let _: Button<Text> = Button(
            title,
            cancelTitle: cancel,
            activity: requiredActivity, error: error, action: action
        )
    }
}
#endif
