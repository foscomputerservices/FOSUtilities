// Localizer.swift
//
// Created by David Hunt on 9/4/24
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

import Foundation

public enum LocalizerError: Error {
    case unknownLocalizationType(_ type: String)
    case localizationStoreMissing

    /// Localization occurs during encode/init(from:).  If encoding/decoding has not taken place, then this error will result.
    case localizationUnbound

    static func processUnknown(error: any Error) -> any Error {
        if let localizerError = error as? Self {
            localizerError
        } else {
            error
        }
    }
}

extension Locale {
    func localize(_ localizable: some Localizable, localizationStore: LocalizationStore) throws -> String? {
        if let string = localizable as? LocalizableString {
            return localize(string, localizationStore: localizationStore)
        } else if let compound = localizable as? LocalizableCompoundValue<LocalizableString> {
            return try localize(compound, localizationStore: localizationStore)
        } else if let subs = localizable as? LocalizableSubstitutions {
            return try localize(subs, localizationStore: localizationStore)
        } else if let int = localizable as? LocalizableInt {
            return localize(int)
        } /* else if let double = localizable as? LocalizableDouble {
         return try localize(double)
         } else if let date = localizable as? LocalizableDate {
         return try localize(date)
         } */ else {
            throw LocalizerError.unknownLocalizationType(
                String(describing: localizable.self)
            )
        }
    }

    func array<Element: Localizable>(_ array: LocalizableArray<Element>, localizationStore: LocalizationStore) -> [Element]? {
        switch array {
        case .empty:
            return [Element]()
        case .constant(let elements):
            return elements
        case .localized(let ref):
            switch ref {
            case .value(let key):
                if let value = localizationStore.v(key, locale: self) {
                    if Element.self is any LocalizableValue.Type {
                        fatalError("NYI!")
                    } else if Element.self is LocalizableString.Type {
                        if let value = value as? String {
                            // Reviewed - dgh - The type has already been established
                            //    in the 'if' case above
                            // swiftlint:disable:next force_cast
                            return [LocalizableString.constant(value) as! Element]
                        } else if let array = value as? [String] {
                            // Reviewed - dgh - The type has already been established
                            //    in the 'if' case above
                            // swiftlint:disable:next force_cast
                            return array.map { LocalizableString.constant($0) as! Element }
                        } else {
                            return [Element]()
                        }
                    }
                }
            case .arrayValue(let key, let index):
                if let value = localizationStore.v(key, locale: self, index: index) as? Element {
                    return [value]
                }
            }
        }

        return [Element]()
    }
}

private extension Locale {
    private func localize(_ locStr: LocalizableString, localizationStore: LocalizationStore) -> String? {
        switch locStr {
        case .constant(let string):
            string

        case .empty:
            ""

        case .localized(let ref):
            switch ref {
            case .value(let key):
                localizationStore.t(key, locale: self)
            case .arrayValue(let key, let index):
                localizationStore.t(key, locale: self, index: index)
            }
        }
    }

    private func localize(_ locComp: LocalizableCompoundValue<LocalizableString>, localizationStore: LocalizationStore) throws -> String? {
        let strings = try locComp.pieces.localizedArray
        let separator = localize(locComp.separator ?? .empty, localizationStore: localizationStore)

        return strings.joined(separator: separator ?? "")
    }

    private func localize(_ locSubs: LocalizableSubstitutions, localizationStore: LocalizationStore) throws -> String? {
        guard let baseStr = localize(locSubs.baseString, localizationStore: localizationStore) else {
            return nil
        }

        do {
            return try locSubs.substitutions.reduce(baseStr) { result, tuple in
                let sub = try localize(
                    tuple.value,
                    localizationStore: localizationStore
                ) ?? ""
                return result.replacingOccurrences(
                    of: "%{\(tuple.key)}",
                    with: sub
                )
            }
        } catch let e {
            throw LocalizerError.processUnknown(error: e)
        }
    }

    private func localize(_ locInt: LocalizableInt) -> String? {
        let intFormatter = intFormatter(
            showGroupingSeparator: locInt.showGroupingSeparator,
            groupingSize: locInt.groupingSize
        )
        return intFormatter.string(from: NSNumber(value: locInt.value))
    }

    #if later
    private func localize(_ locDouble: LocalizableDouble) -> String? {
        let numFmt = doubleFormatter(
            minimumFractionDigits: locDouble.minimumFractionDigits,
            maximumFractionDigits: locDouble.maximumFractionDigits
        )

        return numFmt.string(from: NSNumber(value: locDouble.value))
    }

    private func localize(_ locCurrency: LocalizableCurrency) -> String? {
        let numFmt = currencyFormatter(
            minimumFractionDigits: locCurrency.minimumFractionDigits,
            maximumFractionDigits: locCurrency.maximumFractionDigits
        )

        return numFmt.string(from: NSNumber(value: locCurrency.value))
    }

    private func localize(_ locDate: LocalizableDate) -> String? {
        let dateFmt = dateFormatter(
            dateStyle: locDate.dateStyle,
            timeStyle: locDate.timeStyle,
            dateFormat: locDate.dateFormat
        )

        return dateFmt.string(from: locDate.date)
    }
    #endif

    func intFormatter(showGroupingSeparator: Bool, groupingSize: Int) -> NumberFormatter {
        let numFmt = NumberFormatter()
        numFmt.allowsFloats = false
        numFmt.alwaysShowsDecimalSeparator = false
        if let groupingSeparator {
            numFmt.groupingSeparator = groupingSeparator
        }
        numFmt.usesGroupingSeparator = showGroupingSeparator
        numFmt.groupingSize = groupingSize

        return numFmt
    }

    func doubleFormatter(showGroupingSeparator: Bool, groupingSize: Int, minimumFractionDigits: Int, maximumFractionDigits: Int) -> NumberFormatter {
        let numFmt = NumberFormatter()
        numFmt.allowsFloats = true
        numFmt.alwaysShowsDecimalSeparator = minimumFractionDigits > 0
        if let groupingSeparator {
            numFmt.groupingSeparator = groupingSeparator
        }

        #if os(macOS) || os(Linux)
        numFmt.hasThousandSeparators = true
        if let decimalSeparator {
            numFmt.thousandSeparator = decimalSeparator
        }
        #endif
        numFmt.minimumFractionDigits = minimumFractionDigits
        numFmt.maximumFractionDigits = maximumFractionDigits

        return numFmt
    }

    func currencyFormatter(showGroupingSeparator: Bool, groupingSize: Int, minimumFractionDigits: Int, maximumFractionDigits: Int) -> NumberFormatter {
        let numFmt = doubleFormatter(
            showGroupingSeparator: showGroupingSeparator,
            groupingSize: groupingSize,
            minimumFractionDigits: minimumFractionDigits,
            maximumFractionDigits: maximumFractionDigits
        )
        if let currencySymbol {
            numFmt.currencySymbol = currencySymbol
        }

        return numFmt
    }

    func dateFormatter(dateStyle: DateFormatter.Style?, timeStyle: DateFormatter.Style?, dateFormat: String?) -> DateFormatter {
        let dateFmt = DateFormatter()
        dateFmt.locale = self
        dateFmt.timeZone = calendar.timeZone
        if let dateFormat {
            dateFmt.dateFormat = dateFormat
        } else {
            if let dateStyle {
                dateFmt.dateStyle = dateStyle
            }
            if let timeStyle {
                dateFmt.timeStyle = timeStyle
            }
        }

        return dateFmt
    }
}
