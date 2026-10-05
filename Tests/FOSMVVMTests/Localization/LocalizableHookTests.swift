// LocalizableHookTests.swift
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

import FOSFoundation
import FOSMVVM
import FOSTesting
import Foundation
import Testing

/// A `Localizable` declared outside the library localizes through the same encoder as the
/// library's own types, by implementing `localized(in:store:)`.
@Suite("Localizable hook")
struct LocalizableHookTests: LocalizableTestCase {
    @Test func outsideConformer_localizesThroughTheEncoder() throws {
        let estimate = LocalizableEstimate(hours: 12345)
        #expect(estimate.localizationStatus == .localizationPending)

        let localized: LocalizableEstimate = try estimate
            .toJSON(encoder: JSONEncoder.localizingEncoder(in: Self.en, store: locStore))
            .fromJSON()

        #expect(localized.localizationStatus == .localized)
        #expect(localized.hours == 12345)
        #expect(try localized.localizedString == "12,345 hours")
    }

    @Test func outsideConformer_receivesTheEncodersLocale() throws {
        let localized: LocalizableEstimate = try LocalizableEstimate(hours: 12345)
            .toJSON(encoder: encoder(locale: Self.es))
            .fromJSON()

        #expect(try localized.localizedString == "12.345 horas")
    }

    @Test func outsideConformer_insideAViewModel() throws {
        let localized: EstimateViewModel = try EstimateViewModel.stub()
            .toJSON(encoder: encoder())
            .fromJSON()

        #expect(localized.estimate.localizationStatus == .localized)
        #expect(try localized.estimate.localizedString == "8 hours")
    }

    @Test func outsideConformer_missingText_failsAStrictEncode() {
        let estimate = LocalizableEstimate(hours: 1)
        let german = Locale(identifier: "de")

        #expect(throws: LocalizerError.self) {
            _ = try estimate.toJSON(encoder: encoder(locale: german))
        }

        let lenient = JSONEncoder.localizingEncoder(in: german, store: locStore)
        #expect(throws: Never.self) {
            _ = try estimate.toJSON(encoder: lenient)
        }
    }

    @Test func libraryTypes_resolveThroughTheDefault() throws {
        let localized = try LocalizableInt(value: 42000).localized(in: Self.en, store: locStore)
        #expect(localized == "42,000")
    }

    @Test func unknownType_withoutAnImplementation_throws() {
        #expect(throws: LocalizerError.self) {
            _ = try UnlocalizedValue().toJSON(encoder: encoder())
        }
    }

    let locStore: LocalizationStore
    init() throws {
        self.locStore = try Self.loadLocalizationStore(
            bundle: Bundle.module,
            resourceDirectoryName: "TestYAML"
        )
    }
}

private enum EstimateUnit: CaseIterable {
    case hours
}

private struct LocalizableEstimate: Localizable {
    let hours: Int
    private let text: String?

    init(hours: Int) {
        self.init(hours: hours, text: nil)
    }

    private init(hours: Int, text: String?) {
        self.hours = hours
        self.text = text
    }

    func localized(in locale: Locale, store: LocalizationStore) throws -> String? {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        guard let count = formatter.string(for: hours),
              let unit = try LocalizableString.localized(case: EstimateUnit.hours).localized(in: locale, store: store) else {
            return nil
        }
        return "\(count) \(unit)"
    }

    var isEmpty: Bool {
        text?.isEmpty ?? true
    }

    var localizationStatus: LocalizableStatus {
        text == nil ? .localizationPending : .localized
    }

    var id: LocalizableId {
        "\(hours)"
    }

    var localizedString: String {
        get throws {
            guard let text else { throw LocalizerError.localizationUnbound }
            return text
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.hours = try container.decode(Int.self, forKey: .hours)
        self.text = try container.decode(String.self, forKey: .text)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hours, forKey: .hours)
        try container.encode(text ?? encoder.localizeString(self) ?? "", forKey: .text)
    }

    static func stub(hours: Int = 8) -> Self {
        .init(hours: hours)
    }

    static func stub() -> Self {
        .stub(hours: 8)
    }

    private enum CodingKeys: String, CodingKey {
        case hours
        case text
    }
}

@ViewModel
private struct EstimateViewModel {
    let estimate: LocalizableEstimate
    var vmId: ViewModelId

    static func stub() -> Self {
        .init(estimate: .stub(), vmId: .init())
    }
}

private struct UnlocalizedValue: Localizable {
    var isEmpty: Bool {
        true
    }

    var localizationStatus: LocalizableStatus {
        .localizationPending
    }

    var id: LocalizableId {
        "unlocalized"
    }

    var localizedString: String {
        get throws { throw LocalizerError.localizationUnbound }
    }

    init() {}

    init(from decoder: Decoder) throws {}

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(encoder.localizeString(self) ?? "")
    }

    static func stub() -> Self {
        .init()
    }
}
