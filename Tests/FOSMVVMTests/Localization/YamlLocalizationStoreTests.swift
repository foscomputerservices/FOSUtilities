// YamlLocalizationStoreTests.swift
//
// Copyright 2024 FOS Computer Services, LLC
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
@testable import FOSMVVM
import FOSTesting
import Foundation
import Testing

struct YamlLocalizationStoreTests: LocalizableTestCase {
    #if !os(macOS)
    // TODO: This crashes the Swift compiler on GitHub 🤷‍♂️
    @Test func testKeyExists() {
        #expect(locStore.keyExists("test", locale: en))
        #expect(locStore.keyExists("test", locale: es))
    }
    #endif

    @Test func translate() {
        #expect(locStore.t("test", locale: en) == "Test")
        #expect(locStore.t("test", locale: es) == "Prueba")
        #expect(locStore.t("nested.inner", locale: en) == "inner")
        #expect(locStore.t("nested.inner", locale: es) == "interior")
    }

    @Test func translateArray() {
        #expect(locStore.t("stringArray", locale: en, index: 2) == "Three")
        #expect(locStore.t("stringArray", locale: es, index: 0) == "Uno")
    }

    @Test func testValue() {
        #expect(locStore.v("int", locale: en) as? Int == 42)
        #expect(locStore.v("int", locale: es) as? Int == 42)
        #expect(locStore.v("double", locale: en) as? Double == 42.2)
        #expect(locStore.v("boolTrue", locale: en) as? Bool == true)
        #expect(locStore.v("boolFalse", locale: en) as? Bool == false)
    }

    @Test func valueArray() {
        #expect(locStore.value("intArray", locale: en, default: nil, index: 1) as? Int == 2)
        #expect(locStore.value("intArray", locale: es, default: nil, index: 1) as? Int == 2)
        #expect(locStore.value("doubleArray", locale: en, default: nil, index: 1) as? Double == 2.2)
        #expect(locStore.value("boolArray", locale: en, default: nil, index: 1) as? Bool == false)
    }

    @Test func regionalTranslation() {
        #expect(locStore.t("carHood", locale: enUS) == "Hood")
        #expect(locStore.t("carHood", locale: enGB) == "Bonnet")
    }

    @Test func fallbackTranslation() {
        #expect(locStore.t("test", locale: enGB) == "Test")
        #expect(locStore.t("test", locale: Locale(identifier: "en_gb")) == "Test")
    }

    @Test func caseSensitiveKeyTranslation() {
        #expect(locStore.t("carHood", locale: enUS) == "Hood")
        #expect(locStore.t("carhood", locale: enUS) == nil)
    }

    @Test func defaultTranslation() {
        #expect(locStore.t("carhood", locale: enUS, default: "fred") == "fred")
        #expect(locStore.t("stringArray", locale: en, default: "wilma", index: 999) == "wilma")
    }

    @Test func defaultValue() {
        #expect(locStore.v("_number", locale: en, default: -41, index: 0) as? Int == -41)
        #expect(locStore.v("intArray", locale: en, default: -42, index: 99) as? Int == -42)
    }

    @Test func unknownLocale() {
        #expect(locStore.t("carHood", locale: Locale(identifier: "fred")) == nil)
        #expect(locStore.v("int", locale: Locale(identifier: "fred")) == nil)
    }

    /// When two bundles define the same key, the main app bundle's YAML must
    /// override an embedded Swift Package bundle's YAML, regardless of the
    /// order in which the bundles are passed.
    @Test func appBundleOverridesEmbeddedPackageBundle() throws {
        let fixture = try OverrideFixture()
        defer { fixture.cleanup() }

        for bundles in [
            [fixture.appBundle, fixture.packageBundle],
            [fixture.packageBundle, fixture.appBundle]
        ] {
            let store = try bundles.yamlLocalization(resourceDirectoryName: "Localizations")
            #expect(
                store.t("greeting", locale: Locale(identifier: "en")) == "main-app",
                "App bundle YAML must override embedded package YAML on duplicate keys."
            )
            #expect(
                store.t("packageOnly", locale: Locale(identifier: "en")) == "package-only",
                "Package-only keys remain available."
            )
        }
    }

    @Test func yamlSearchPathsDistinguishesEmbeddedBundlePaths() throws {
        let fixture = try OverrideFixture()
        defer { fixture.cleanup() }

        let appPaths = fixture.appBundle.yamlSearchPaths(resourceDirectoryName: "Localizations")
        let pkgPaths = fixture.packageBundle.yamlSearchPaths(resourceDirectoryName: "Localizations")

        #expect((appPaths + pkgPaths).allSatisfy { $0.hasDirectoryPath })
        #expect(pkgPaths.contains { $0.path.contains(".bundle/") })
        #expect(appPaths.allSatisfy { !$0.path.contains(".bundle/") })
    }

    let locStore: LocalizationStore
    init() throws {
        self.locStore = try Self.loadLocalizationStore(
            bundle: Bundle.module,
            resourceDirectoryName: "TestYAML"
        )
    }
}

private struct OverrideFixture {
    let root: URL
    let appBundle: Bundle
    let packageBundle: Bundle

    init() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("YamlOverrideTest-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        // Main app bundle — no ".bundle/" in its path.
        let appBundleDir = root.appendingPathComponent("MainApp.app", isDirectory: true)
        let appYamlDir = appBundleDir
            .appendingPathComponent("Contents/Resources/Localizations", isDirectory: true)
        try fm.createDirectory(at: appYamlDir, withIntermediateDirectories: true)
        try """
        en:
          greeting: "main-app"
        """.write(to: appYamlDir.appendingPathComponent("test.yml"), atomically: true, encoding: .utf8)

        // Embedded Swift Package resource bundle — ".bundle/" in its path.
        let pkgBundleDir = root.appendingPathComponent("EmbeddedPkg.bundle", isDirectory: true)
        let pkgYamlDir = pkgBundleDir
            .appendingPathComponent("Contents/Resources/Localizations", isDirectory: true)
        try fm.createDirectory(at: pkgYamlDir, withIntermediateDirectories: true)
        try """
        en:
          greeting: "package"
          packageOnly: "package-only"
        """.write(to: pkgYamlDir.appendingPathComponent("test.yml"), atomically: true, encoding: .utf8)

        guard let appBundle = Bundle(url: appBundleDir),
              let packageBundle = Bundle(url: pkgBundleDir) else {
            try? fm.removeItem(at: root)
            throw FixtureError.bundleInitFailed
        }

        self.root = root
        self.appBundle = appBundle
        self.packageBundle = packageBundle
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    enum FixtureError: Error { case bundleInitFailed }
}
