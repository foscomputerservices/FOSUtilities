// ErrorMiddlewareDressingTests.swift
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

// ErrorMiddleware transport-dressing contract: an error that is BOTH Encodable
// and AbortError is served with its typed body AND its own status/headers; a
// plain Encodable error keeps the typed body with 400 (unchanged).

import FOSFoundation
import FOSMVVM
import FOSMVVMVapor
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import Vapor

private struct DressedError: ServerRequestError, AbortError {
    let errorCode: Int
    var status: HTTPResponseStatus {
        .conflict
    } // 409 — distinctive
    var headers: HTTPHeaders {
        ["X-Dressed": "yes"]
    }

    var reason: String {
        "dressed"
    }
}

private struct PlainEncodableError: ServerRequestError {
    let errorCode: Int
}

@Suite("ErrorMiddleware dressing (running server)", .serialized)
struct ErrorMiddlewareDressingTests {
    @Test("Encodable & AbortError: typed body + its own status and headers")
    func dressedErrorKeepsStatusAndBody() async throws {
        try await withRunningServer { app in
            app.middleware = .init()
            app.middleware.use(FOSMVVMVapor.ErrorMiddleware.default(environment: app.environment))
            app.get("boom") { _ -> String in throw DressedError(errorCode: 7) }
        } _: { base in
            let (status, body, headers) = try await rawGet(
                base.appendingPathComponent("boom"),
                readHeaders: ["X-Dressed", "Content-Type"]
            )
            #expect(status == 409)
            #expect(headers["X-Dressed"] == "yes")
            // A single Content-Type on the wire — a duplicate would surface here
            // comma-joined by value(forHTTPHeaderField:)
            #expect(headers["Content-Type"] == "application/json; charset=utf-8")
            let decoded: DressedError = try body.fromJSON()
            #expect(decoded.errorCode == 7)
        }
    }

    @Test("Plain Encodable: typed body + 400 (existing contract unchanged)")
    func plainEncodableKeeps400() async throws {
        try await withRunningServer { app in
            app.middleware = .init()
            app.middleware.use(FOSMVVMVapor.ErrorMiddleware.default(environment: app.environment))
            app.get("boom") { _ -> String in throw PlainEncodableError(errorCode: 9) }
        } _: { base in
            let (status, body, headers) = try await rawGet(
                base.appendingPathComponent("boom"),
                readHeaders: ["Content-Type"]
            )
            #expect(status == 400)
            // A single Content-Type on the wire — a duplicate would surface here
            // comma-joined by value(forHTTPHeaderField:)
            #expect(headers["Content-Type"] == "application/json; charset=utf-8")
            let decoded: PlainEncodableError = try body.fromJSON()
            #expect(decoded.errorCode == 9)
        }
    }
}

/// Performs `GET <url>` and yields the raw status + body + the requested
/// response headers the server sent — no client-side error mapping in the way.
/// Each name in `readHeaders` is resolved via `http.value(forHTTPHeaderField:)`
/// (case-insensitive) rather than by indexing `allHeaderFields`, whose key
/// capitalization differs across Darwin / FoundationNetworking.
private func rawGet(
    _ url: URL,
    readHeaders: [String]
) async throws -> (status: Int, body: String, headers: [String: String]) {
    let urlRequest = URLRequest(url: url)

    return try await withCheckedThrowingContinuation { continuation in
        URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            if let error {
                continuation.resume(throwing: error)
                return
            }
            guard let http = response as? HTTPURLResponse else {
                continuation.resume(throwing: NonHTTPResponseFailure())
                return
            }

            var resolved: [String: String] = [:]
            for name in readHeaders {
                if let value = http.value(forHTTPHeaderField: name) {
                    resolved[name] = value
                }
            }

            continuation.resume(returning: (
                status: http.statusCode,
                body: String(data: data ?? Data(), encoding: .utf8) ?? "",
                headers: resolved
            ))
        }.resume()
    }
}

/// The server replied with something other than HTTP — never expected against the harness.
private struct NonHTTPResponseFailure: Error {}
