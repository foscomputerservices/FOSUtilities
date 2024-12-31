// Expectations.swift
//
// Created by David Hunt on 9/4/24
// Copyright 2024 FOS Services, LLC
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
import Foundation
import Testing

/// Performs tests to ensure that the **Codable**s implementation can encode and decode properly
///
/// ## Example
///
/// ```swift
/// try expectCodable(MyViewModel.self)
/// ```
///
/// - Parameter codableType: A `System.Type` of a type that conforms to **Codable** and **Stubbable**
/// - Parameter message: An optional message that will be added to any error messages
/// - Parameter encoder: An optional *JSONEncoder* to use to encode the data (default: **JSONEncoder()**)
/// - Parameter decoder: n optional *JSONDecoder* to use to decode the data (default: **JSONDecoder()**)
public func expectCodable<C>(_ codableType: C.Type, encoder: JSONEncoder? = nil, decoder: JSONDecoder? = nil, _ message: @autoclosure () -> String = "") throws where C: Codable, C: Stubbable {
    let instance = codableType.stub()
    let message = message() + ": "

    let encodedData: Data
    do {
        let encoder = encoder ?? JSONEncoder()
        encodedData = try encoder.encode(instance)

        if encodedData.count == 0 {
            throw FOSCodableError.error(message + "Encoded 0 bytes")
        }
    } catch let e {
        throw FOSCodableError.error(message + "Exception encoding \(C.self): \(e.localizedDescription)")
    }

    do {
        let decoder = decoder ?? JSONDecoder()
        _ = try decoder.decode(codableType, from: encodedData)
    } catch let e {
        // swiftlint:disable:next optional_data_string_conversion
        throw FOSCodableError.error(message + "Exception decoding \(C.self): \(e.localizedDescription) from json \(String(decoding: encodedData, as: UTF8.self))")
    }
}

/// Performs tests to ensure that the **ViewModel**s versions is complete and stable
///
/// ## Example
///
/// ```swift
/// try expectVersionedViewModel(MyViewModel.self)
/// ```
///
/// - Parameters:
///     - viewModelType: A *System.Type* of a type that conforms to **ViewModel**
///     - version: The version of *viewModelType* (default: *SystemVersion.current*)
///     - encoder: An optional *JSONEncoder* to use to encode the data (default: **JSONEncoder()**)
///     - decoder: n optional *JSONDecoder* to use to decode the data (default: **JSONDecoder()**)
///     - message: An optional message that will be added to any error messages
///     - fixedTestFilePath: An optional fully qualified path of a directory in which to store the versioned json files (default: .VersionedTestJSON)
///     - file: The optional file path of the source file calling this method
///     - line: The optional line number of the test function calling this method
public func expectVersionedViewModel<VM>(_ viewModelType: VM.Type, version: SystemVersion = .current, encoder: JSONEncoder? = nil, decoder: JSONDecoder? = nil, _ message: @autoclosure () -> String = "", fixedTestFilePath: URL? = nil, file: String = #filePath, line: Int = #line) throws where VM: ViewModel {

    let fileMgr = FileManager.default

    let message = message() + ": "
    let testFileDirectory = fixedTestFilePath ?? fileMgr.testFileDirectory(basePath: file)
    let testFilePath = version.testFilePath(for: viewModelType, testFileDirectory: testFileDirectory)

    try fileMgr.ensureDirectoryExists(at: testFileDirectory)

    // If we've not already stored this version, store it now
    if !fileMgr.fileExists(atPath: testFilePath.path) {
        let instance = viewModelType.self.stub()
        let encoder = encoder ?? JSONEncoder()
        let encodedData = try encoder.encode(instance)

        guard encodedData.count > 0 else {
            throw FOSCodableError.error(message + "Encoded 0 bytes")
        }

        try encodedData.write(to: testFilePath)
    }

    // Test that every version can be loaded
    for testFile in try fileMgr.testFiles(for: viewModelType, testFileDirectory: testFileDirectory) {
        let decoder = decoder ?? JSONDecoder()

        do {
            let data = try Data(contentsOf: testFile)
            _ = try decoder.decode(VM.self, from: data)
        } catch let e {
            let message = message + "Decoding of file \(testFile) failed: \(e)"
            throw FOSCodableError.error(message)
        }
    }
}

private extension FileManager {
    func testFileDirectory(basePath: String) -> URL {
        URL(fileURLWithPath: basePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".VersionedTestJSON")
    }

    func testFiles<VM>(for type: VM.Type, testFileDirectory: URL) throws -> [URL] {
        try contentsOfDirectory(atPath: testFileDirectory.path())
            .filter { $0.hasSuffix(".json") }
            .filter { $0.hasPrefix("\(type)_") }
            .map { testFileDirectory.appending(path: $0) }
    }

    func ensureDirectoryExists(at path: URL) throws {
        guard !fileExists(atPath: path.path) else { return }
        try createDirectory(at: path, withIntermediateDirectories: true)
    }
}

private extension SystemVersion {
    func testFilePath<VM>(for type: VM.Type, testFileDirectory: URL) -> URL {
        testFileDirectory
            .appendingPathComponent("\(type)_\(self).json")
    }
}

public enum FOSCodableError: Error {
    case error(_ message: String)

    public var localizedDescription: String {
        switch self {
        case .error(let message): message
        }
    }
}
