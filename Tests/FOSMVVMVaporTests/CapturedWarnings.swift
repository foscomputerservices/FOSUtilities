// CapturedWarnings.swift
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

import Foundation
import NIOConcurrencyHelpers
import Vapor

/// Lock-guarded warning sink shared between the handler (inside the app) and the assertion.
final class CapturedWarnings: @unchecked Sendable {
    private let lock = NIOLock()
    private var messages: [String] = []

    func append(_ message: String) {
        lock.withLock { messages.append(message) }
    }

    var all: [String] {
        lock.withLock { messages }
    }

    func contains(allOf fragments: String...) -> Bool {
        all.contains { message in fragments.allSatisfy { message.contains($0) } }
    }
}

/// Captures `.warning`+ messages; forwards nothing (tests stay quiet).
struct CapturingLogHandler: LogHandler {
    let captured: CapturedWarnings

    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .warning

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    // swiftlint:disable:next function_parameter_count
    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        guard level >= .warning else {
            return
        }
        captured.append(message.description)
    }
}

/// Rebinds the app's logger to the capturing sink. Whatever logs through `Application.logger` lands
/// in `captured`: boot checks, Fluent's database logger, and the HTTP server, whose configuration
/// takes the application's logger when it is first read.
func captureWarnings(of app: Application, into captured: CapturedWarnings) {
    app.logger = Logger(label: "captured-warnings") { _ in
        CapturingLogHandler(captured: captured)
    }
}
