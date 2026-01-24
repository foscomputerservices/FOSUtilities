// LocalizableSubstitutionsTests.swift
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
import FOSMVVM
import FOSTesting
import Foundation
import Testing

@Suite("Localizable Substitutions Tests")
struct LocalizableSubstitutionsTests: LocalizableTestCase {
    // MARK: Initialization Methods

    @Test func testInit() {
        let base = LocalizableString.constant("%{foo}")
        let subVal = LocalizableInt(value: 42)
        let subs: [String: any Localizable] = ["foo": subVal]

        let locSub = LocalizableSubstitutions(baseString: base, substitutions: subs)

        #expect(locSub.baseString == base)
        #expect(locSub.substitutions.count == 1)
        #expect(locSub.substitutions["foo"] != nil)
    }

    // MARK: Localizable Protocol

    @Test func localizable_isEmpty_nonLocalized() {
        let base = LocalizableString.constant("%{foo}")
        let subVal = LocalizableInt(value: 42)
        let subs: [String: any Localizable] = ["foo": subVal]

        let locSub = LocalizableSubstitutions(baseString: base, substitutions: subs)

        #expect(locSub.isEmpty)
    }

    @Test func localizable_isEmpty_nonLocalized_butConstant() {
        let base = LocalizableString.constant("%{foo}")
        let subVal = LocalizableString.constant("foo")
        let subs: [String: any Localizable] = ["foo": subVal]

        let locSub = LocalizableSubstitutions(baseString: base, substitutions: subs)

        #expect(!locSub.isEmpty)
    }

    @Test func localizable_isEmpty_localized() throws {
        let base = LocalizableString.constant("%{foo}")
        let subVal = LocalizableInt(value: 42)
        let subs: [String: any Localizable] = ["foo": subVal]

        let locSub = LocalizableSubstitutions(baseString: base, substitutions: subs)

        let decodedLoc: LocalizableSubstitutions = try locSub.toJSON(encoder: encoder()).fromJSON()

        #expect(!decodedLoc.isEmpty)
    }

    @Test func localizable_localizationStatus_nonLocalized1() {
        let base = LocalizableString.constant("%{foo}")
        let subVal = LocalizableInt(value: 42)
        let subs: [String: any Localizable] = ["foo": subVal]

        let locSub = LocalizableSubstitutions(baseString: base, substitutions: subs)

        #expect(locSub.localizationStatus == .localizationPending)
    }

    @Test func localizable_localizationStatus_nonLocalized2() {
        let base = LocalizableString.localized(key: "foo")
        let subVal = LocalizableInt(value: 42)
        let subs: [String: any Localizable] = ["foo": subVal]

        let locSub = LocalizableSubstitutions(baseString: base, substitutions: subs)

        #expect(locSub.localizationStatus == .localizationPending)
    }

    @Test func localizable_localizationStatus_nonLocalized_butConstant() {
        let base = LocalizableString.constant("%{foo}")
        let subVal = LocalizableString.constant("foo")
        let subs: [String: any Localizable] = ["foo": subVal]

        let locSub = LocalizableSubstitutions(baseString: base, substitutions: subs)

        #expect(locSub.localizationStatus == .localized)
    }

    @Test func localizable_localizationStatus_localized() throws {
        let base = LocalizableString.constant("%{foo}")
        let subVal = LocalizableInt(value: 42)
        let subs: [String: any Localizable] = ["foo": subVal]

        let locSub = LocalizableSubstitutions(baseString: base, substitutions: subs)

        let decodedLoc: LocalizableSubstitutions = try locSub.toJSON(encoder: encoder()).fromJSON()

        #expect(decodedLoc.localizationStatus == .localized)
    }

    @Test func localizable_localizedString_nonLocalized_butConstant() throws {
        let base = LocalizableString.constant("_%{sub}_")
        let subVal = LocalizableString.constant("Foo")
        let subs: [String: any Localizable] = ["sub": subVal]

        let locSub = LocalizableSubstitutions(baseString: base, substitutions: subs)

        #expect(try locSub.localizedString == "_Foo_")
    }

    @Test func localizable_localizedString_localized() throws {
        let base = LocalizableString.localized(key: "subString")
        let subVal = LocalizableInt(value: 42)
        let subs: [String: any Localizable] = ["sub": subVal]

        let locSub = LocalizableSubstitutions(baseString: base, substitutions: subs)

        let decodedLoc: LocalizableSubstitutions = try locSub.toJSON(encoder: encoder()).fromJSON()

        #expect(try decodedLoc.localizedString == "->42<-")
    }

    // MARK: Codable Protocol

    @Test func codable() throws {
        let base = LocalizableString.localized(key: "subString")
        let subVal = LocalizableInt(value: 42)
        let subs: [String: any Localizable] = ["sub": subVal]

        let locSub = LocalizableSubstitutions(baseString: base, substitutions: subs)

        let decodedLoc: LocalizableSubstitutions = try locSub.toJSON(encoder: encoder()).fromJSON()

        #expect(try !(decodedLoc.baseString.localizedString.contains("%{sub}")))
        #expect(decodedLoc.substitutions.count == 0)
    }

    // MARK: LocalizableString.bind

    @Test func localizableString_bind() throws {
        let subVal = LocalizableInt(value: 42)
        let locSub = LocalizableString.localized(key: "subString")
            .bind(substitutions: ["sub": subVal])

        let decodedLoc: LocalizableSubstitutions = try locSub.toJSON(encoder: encoder()).fromJSON()

        #expect(try !(decodedLoc.baseString.localizedString.contains("%{sub}")))
        #expect(decodedLoc.substitutions.count == 0)
    }

    // MARK: - Edge Case Tests

    //
    // Note: When using constant base strings, substitution happens via localizedString
    // directly without encoding/decoding. Encoding only applies substitutions when
    // using localized (non-constant) base strings.

    @Test func substitution_emptyDictionary() throws {
        // When no substitutions are provided, the base string should be used as-is
        let base = LocalizableString.constant("No substitutions here")
        let subs: [String: any Localizable] = [:]

        let locSub = LocalizableSubstitutions(baseString: base, substitutions: subs)

        #expect(try locSub.localizedString == "No substitutions here")
    }

    @Test func substitution_multipleSubstitutions() throws {
        // Multiple substitutions should all be applied
        let base = LocalizableString.constant("Hello %{name}, you have %{count} messages")
        let subs: [String: any Localizable] = [
            "name": LocalizableString.constant("Alice"),
            "count": LocalizableString.constant("5")
        ]

        let locSub = LocalizableSubstitutions(baseString: base, substitutions: subs)

        #expect(try locSub.localizedString == "Hello Alice, you have 5 messages")
    }

    @Test func substitution_sameKeyMultipleTimes() throws {
        // Same substitution key used multiple times in template
        let base = LocalizableString.constant("%{word} %{word} %{word}")
        let subs: [String: any Localizable] = [
            "word": LocalizableString.constant("echo")
        ]

        let locSub = LocalizableSubstitutions(baseString: base, substitutions: subs)

        #expect(try locSub.localizedString == "echo echo echo")
    }

    @Test func substitution_unusedKey_passesThrough() throws {
        // If a substitution key is not used in the template, it should be ignored
        let base = LocalizableString.constant("Only %{used} here")
        let subs: [String: any Localizable] = [
            "used": LocalizableString.constant("this"),
            "unused": LocalizableString.constant("that")
        ]

        let locSub = LocalizableSubstitutions(baseString: base, substitutions: subs)

        #expect(try locSub.localizedString == "Only this here")
    }

    @Test func substitution_specialCharactersInValue() throws {
        // Substitution values with special characters should be preserved
        let base = LocalizableString.constant("Path: %{path}")
        let subs: [String: any Localizable] = [
            "path": LocalizableString.constant("/usr/local/bin")
        ]

        let locSub = LocalizableSubstitutions(baseString: base, substitutions: subs)

        #expect(try locSub.localizedString == "Path: /usr/local/bin")
    }

    @Test func substitution_emptyStringValue() throws {
        // Substituting with an empty string should work
        let base = LocalizableString.constant("Hello%{suffix}")
        let subs: [String: any Localizable] = [
            "suffix": LocalizableString.constant("")
        ]

        let locSub = LocalizableSubstitutions(baseString: base, substitutions: subs)

        #expect(try locSub.localizedString == "Hello")
    }

    @Test func substitution_missingKey_leftUnsubstituted() throws {
        // If a substitution key in the template is not provided, it remains as-is
        let base = LocalizableString.constant("Hello %{name}, you have %{missing} messages")
        let subs: [String: any Localizable] = [
            "name": LocalizableString.constant("Alice")
        ]

        let locSub = LocalizableSubstitutions(baseString: base, substitutions: subs)

        #expect(try locSub.localizedString == "Hello Alice, you have %{missing} messages")
    }

    @Test func substitution_numericSubstitution() throws {
        // Numeric values formatted as strings
        let base = LocalizableString.constant("Count: %{num}")
        let subs: [String: any Localizable] = [
            "num": LocalizableString.constant("42")
        ]

        let locSub = LocalizableSubstitutions(baseString: base, substitutions: subs)

        #expect(try locSub.localizedString == "Count: 42")
    }

    let locStore: LocalizationStore
    init() throws {
        self.locStore = try Self.loadLocalizationStore(
            bundle: Bundle.module,
            resourceDirectoryName: "TestYAML"
        )
    }
}
