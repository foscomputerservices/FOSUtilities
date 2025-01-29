// YamlLocalizationStore.swift
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

import FOSFoundation
import Foundation
import Yams

public enum YamlStoreError: Error {
    case typeError(reason: String)
    case yamlError(error: YamlError)
    case fileError(path: URL, error: any Error)
    case fileDecodingError(path: URL)
    case noPaths
    case noLocalizationStore
    case noLocaleFound

    public var localizedDescription: String {
        switch self {
        case .typeError(let reason): reason
        case .yamlError(let error): error.localizedDescription
        case .fileError(let path, let error): "\(path) - \(error.localizedDescription)"
        case .fileDecodingError(let path): "\(path) -- Unable to decode contents of file to UTF-8"
        case .noPaths: "No YAML search paths were provided or the paths provided didn't match any real files or directories."
        case .noLocalizationStore: "The LocalizationStore is missing from the Application.  Generally this means that Application.initYamlLocalization() was not called during application startup."
        case .noLocaleFound: "No Locale could be inferred from the Request's acceptLanguage headers"
        }
    }
}

/// An extension on Bundle to allow initialization of the YamlStore
public extension Bundle {
    func yamlLocalization(resourceDirectoryName: String) async throws -> LocalizationStore {
        let config = try yamlStoreConfig(
            resourceDirectoryName: resourceDirectoryName
        )

        return try await YamlStore(config: config)
    }
}

package struct YamlStoreConfig: Sendable { // Internal for testing
    let searchPaths: [URL]

    fileprivate func localizationStore() async throws -> LocalizationStore {
        try await YamlStore(config: self)
    }

    init(searchPaths: some Collection<URL>) throws {
        guard !searchPaths.isEmpty else {
            throw YamlStoreError.noPaths
        }

        self.searchPaths = searchPaths.filter {
            $0.isFileURL && $0.hasDirectoryPath
        }

        guard !self.searchPaths.isEmpty else {
            throw YamlStoreError.noPaths
        }
    }
}

package extension Bundle {
    func yamlStoreConfig(resourceDirectoryName: String) throws -> YamlStoreConfig {
        try .init(
            searchPaths: yamlSearchPaths(
                resourceDirectoryName: resourceDirectoryName
            )
        )
    }

    func yamlSearchPaths(resourceDirectoryName: String) throws -> Set<URL> {
        let resourceURLs = [
            /* Packages */ bundleURL
                .appending(path: "Contents/Resources")
                .appending(path: resourceDirectoryName),
            /* xcodeproj */ bundleURL
                .appending(path: resourceDirectoryName)
        ]

        var result = Set<URL>()
        for resourceURL in resourceURLs {
            for file in resourceURL.findFiles(withExtension: "yml") {
                let url = file.deletingLastPathComponent()
                result.insert(url.absoluteURL)
            }
        }

        return result
    }
}

package struct YamlStore: LocalizationStore {
    let config: YamlStoreConfig

    private var yamlTree: [String: [String: YamlValue]]

    package func value(_ key: String, locale: Locale, default: Any? = nil, index: Int? = nil) -> Any? {
        guard let translation = translate(key, locale: locale) else {
            return `default`
        }

        if let index {
            return (translation as? [Any])?[safe: index] ?? `default`
        }

        return translation
    }

    package init(config: YamlStoreConfig) async throws {
        self.config = config
        self.yamlTree = try Self.loadFlattenedYAML(config: config)
    }
}

private struct YamlValue {
    // Why? We know the type, so possibly have stronger typing in the future
    let string: String?
    let int: Int?
    let double: Double?
    let bool: Bool?
    let stringArray: [String]?
    let intArray: [Int]?
    let doubleArray: [Double]?
    let boolArray: [Bool]?

    var value: Any? {
        if let string { return string }
        if let int { return int }
        if let double { return double }
        if let bool { return bool }
        if let stringArray { return stringArray }
        if let intArray { return intArray }
        if let doubleArray { return doubleArray }
        if let boolArray { return boolArray }

        return nil
    }

    init(string: String? = nil, int: Int? = nil, double: Double? = nil, bool: Bool? = nil, stringArray: [String]? = nil, intArray: [Int]? = nil, doubleArray: [Double]? = nil, boolArray: [Bool]? = nil) {
        self.string = string
        self.int = int
        self.double = double
        self.bool = bool
        self.stringArray = stringArray
        self.intArray = intArray
        self.doubleArray = doubleArray
        self.boolArray = boolArray
    }
}

private extension YamlStore {
    static func loadFlattenedYAML(config: YamlStoreConfig) throws -> [String: [String: YamlValue]] {
        var result: [String: [String: YamlValue]] = [:]

        guard !config.searchPaths.isEmpty else {
            throw YamlStoreError.noPaths
        }

        for searchPath in config.searchPaths {
            let filePaths = searchPath.findFiles(withExtension: "yml")

            for filePath in filePaths {
                do {
                    guard let fileData = try String(
                        data: Data(contentsOf: filePath),
                        encoding: .utf8
                    ) else {
                        throw YamlStoreError.fileDecodingError(
                            path: filePath
                        )
                    }

                    if let nextResult = try Yams.load(yaml: fileData) as? [String: Any] {
                        try nextResult.loadYaml(into: &result)
                    }
                } catch let e as YamlStoreError {
                    throw e
                } catch let e as YamlError {
                    throw YamlStoreError.yamlError(error: e)
                } catch let e {
                    throw YamlStoreError.fileError(path: filePath, error: e)
                }
            }
        }

        return result
    }

    func translate(_ key: String, locale: Locale) -> Any? {
        let locale = locale.identifier.lowercased()
        if let result = yamlTree[locale]?[key]?.value {
            return result
        }

        // Try a 'base' locale
        #if !os(Linux) && !os(Windows)
        if #available(macOS 15, iOS 16, tvOS 16, watchOS 9, visionOS 1, macCatalyst 16, *) {
            let localeComps = Locale.Language.Components(identifier: locale)
            let baseLocale = localeComps.languageCode?.identifier.lowercased() ?? "n/a"
            return yamlTree[baseLocale]?[key]?.value
        } else {
            return polyfillLanguage(key, locale: locale)
        }
        #else
        return polyfillLanguage(key, locale: locale)
        #endif
    }

    private func polyfillLanguage(_ key: String, locale: String) -> Any? {
        let locale = locale.replacingOccurrences(of: "_", with: "-")
        let localeComps = locale.split(separator: "-")
        let baseLocale = localeComps.first?.lowercased() ?? "n/a"
        return yamlTree[baseLocale]?[key]?.value
    }
}

private extension [String: Any] {
    func loadYaml(into result: inout [String: [String: YamlValue]]) throws {
        for locale in keys {
            if let languageYaml = self[locale] as? [String: Any] {
                // Store the locale keys lowercased
                let locale = locale.lowercased()
                var localeDict = result[locale] ?? [:]

                try languageYaml.flattenKeys(into: &localeDict)

                result[locale] = localeDict
            }
        }
    }

    /// Flatten the YAML hierarchy into [Key: YamlValue] (e.g. "a.b.c" : "String")
    func flattenKeys(into flattenedDict: inout [String: YamlValue], parentKey: String = "") throws {
        for nextKey in keys {
            let flattenedKey = parentKey + (parentKey.isEmpty ? "" : ".") + nextKey

            if let nextVal = self[nextKey], !(nextVal is NSNull) {
                if let nextVal = nextVal as? String {
                    flattenedDict[flattenedKey] = .init(
                        string: nextVal.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                } else if let nextVal = nextVal as? Int {
                    flattenedDict[flattenedKey] = .init(int: nextVal)
                } else if let nextVal = nextVal as? Double {
                    flattenedDict[flattenedKey] = .init(double: nextVal)
                } else if let nextVal = nextVal as? Bool {
                    flattenedDict[flattenedKey] = .init(bool: nextVal)
                } else if let nextYaml = nextVal as? [String: Any] {
                    try nextYaml.flattenKeys(into: &flattenedDict, parentKey: flattenedKey)
                } else if let nextArray = nextVal as? [Any], !nextArray.isEmpty {
                    let stringArray = nextArray.compactMap { $0 as? String }
                    if !stringArray.isEmpty {
                        flattenedDict[flattenedKey] = .init(stringArray: stringArray)
                        continue
                    }

                    let intArray = nextArray.compactMap { $0 as? Int }
                    if !intArray.isEmpty {
                        flattenedDict[flattenedKey] = .init(intArray: intArray)
                        continue
                    }

                    let doubleArray = nextArray.compactMap { $0 as? Double }
                    if !doubleArray.isEmpty {
                        flattenedDict[flattenedKey] = .init(doubleArray: doubleArray)
                        continue
                    }

                    let boolArray = nextArray.compactMap { $0 as? Bool }
                    if !boolArray.isEmpty {
                        flattenedDict[flattenedKey] = .init(boolArray: boolArray)
                        continue
                    }

                    throw YamlStoreError.typeError(
                        reason: "Invalid type \(type(of: nextVal)) found for key: \(flattenedKey)"
                    )
                }
            }
        }
    }
}
