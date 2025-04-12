// URLSessionWebSocketTask.swift
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
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Errors resulting from calls to various **URLSessionWebSocketTask** APIs
public enum WebSocketError: Error, CustomDebugStringConvertible {
    /// The **URLSessionTask** is not currently running
    case notRunning

    /// An error was received while sending data to the web socket
    case sendError(any Error)

    public var debugDescription: String {
        switch self {
        case .notRunning:
            "WebSocketError: The URLSessionWebSocketTask is not currently running"
        case .sendError(let e):
            "WebSocketError: An error occurred while sending data to the web socket: \(e)"
        }
    }
}

public extension URLSessionWebSocketTask {
    /// A simplified API to send an **Encodable** over a web socket
    ///
    /// This API uses **Encodable.toJSON()** to encode the provided `data` and
    /// sends that JSON to the web socket.
    ///
    /// - Parameter data: The data to encode as JSON and send over the web socket
    func send(_ data: some Encodable) async throws {
        guard state == .running else {
            throw WebSocketError.notRunning
        }

        do {
            let json = try data.toJSON()

            try await send(.string(json))
        } catch let e {
            throw WebSocketError.sendError(e)
        }
    }
}
