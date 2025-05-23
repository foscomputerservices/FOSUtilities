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

    let locStore: LocalizationStore
    init() async throws {
        self.locStore = try await Self.loadLocalizationStore(
            bundle: Bundle.module,
            resourceDirectoryName: "TestYAML"
        )
    }
}
