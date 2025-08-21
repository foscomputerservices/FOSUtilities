// ErrorMiddleware.swift
//
// Copyright 2025 FOS Computer Services, LLC
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

import FOSMVVM
import Vapor

/// Captures all errors and transforms them into an internal server error HTTP response.
///
/// A version of Vapor's *ErrorMiddleware* that has specialized handling for Encodable errors.
/// This specialized handling allows client applications to receive rich error information back
/// from the server so that it can be presented to the user in context-specific ways (including
/// form validation, for example).
///
/// ``ErrorMiddleware`` aligns with FOSFoundation's *ServerRequest* and uses the
/// Vapor *Request*'s *localizingEncoder* to encode the Error and thus any *Localizable*
/// values will be localized before sending them  back to the client.  The client will then
/// convert the response back to the *ServerRequest*'s *ResponseError* type and
/// throw it for the client application to use.
public final class ErrorMiddleware: AsyncMiddleware {
    /// Error-handling closure.
    private let closure: @Sendable (Request, any Error) -> (Response)

    // MARK: Middleware Protocol

    public func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch {
            return closure(request, error)
        }
    }

    // MARK: Initialization Methods

    /// Create a new ``ErrorMiddleware``
    ///
    /// - Parameters:
    ///   - closure: Error-handling closure. Converts `Error` to `Response`.
    @preconcurrency public init(_ closure: @Sendable @escaping (Request, any Error) -> (Response)) {
        self.closure = closure
    }
}

public extension ErrorMiddleware {
    /// Create a default `ErrorMiddleware`. Logs errors to a `Logger` based on `Environment`
    /// and converts `Error` to `Response` based on conformance to `AbortError` and `Debuggable`.
    ///
    /// - parameters:
    ///     - environment: The environment to respect when presenting errors.
    static func `default`(environment: Environment) -> ErrorMiddleware {
        .init { req, error in
            let status: HTTPResponseStatus,
                reason: String,
                errorData: Data?,
                source: ErrorSource
            var headers: HTTPHeaders

            // Inspect the error type and extract what data we can.
            switch error {
            case let encodable as any Encodable:
                do {
                    let encoder = try req.localizingEncoder

                    (reason, errorData, status, headers, source) = try (
                        "",
                        encodable.toJSONData(encoder: encoder),
                        .badRequest,
                        [HTTPHeaders.Name.contentType.description: "application/json;charset=utf-8"],
                        .capture()
                    )
                } catch {
                    (reason, errorData, status, headers, source) = (
                        "Error serializing ViewModelRequestError to JSON: \(error)",
                        nil,
                        .badRequest,
                        [:],
                        .capture()
                    )
                }

            case let debugAbort as (any DebuggableError & AbortError):
                (reason, errorData, status, headers, source) = (
                    debugAbort.reason,
                    nil,
                    debugAbort.status,
                    debugAbort.headers,
                    debugAbort.source ?? .capture()
                )

            case let abort as any AbortError:
                (reason, errorData, status, headers, source) = (
                    abort.reason,
                    nil,
                    abort.status,
                    abort.headers,
                    .capture()
                )

            case let describableError as any CustomDebugStringConvertible:
                (reason, errorData, status, headers, source) = (
                    describableError.debugDescription,
                    nil,
                    .internalServerError,
                    [:],
                    .capture()
                )

            case let debugErr as any DebuggableError:
                (reason, errorData, status, headers, source) = (
                    debugErr.reason,
                    nil,
                    .internalServerError,
                    [:],
                    debugErr.source ?? .capture()
                )

            default:
                // In debug mode, provide the error description; otherwise hide it to avoid sensitive data disclosure.
                reason = environment.isRelease
                    ? "Something went wrong."
                    : String(describing: error)
                errorData = nil
                (status, headers, source) = (.internalServerError, [:], .capture())
            }

            // Report the error
            req.logger.report(error: error,
                              metadata: ["method": "\(req.method.rawValue)",
                                         "url": "\(req.url.string)",
                                         "userAgent": .array(req.headers["User-Agent"].map { "\($0)" })],
                              file: source.file,
                              function: source.function,
                              line: source.line)

            // attempt to serialize the error to json
            let body: Response.Body
            do {
                let encoder = try req.localizingEncoder
                var byteBuffer = req.byteBufferAllocator.buffer(capacity: 0)
                if let errorData {
                    byteBuffer.writeBytes(errorData)
                    headers.add(
                        name: HTTPHeaders.Name.contentType,
                        value: "application/json; charset=utf-8"
                    )
                } else {
                    try encoder.encode(
                        reason,
                        to: &byteBuffer,
                        headers: &headers
                    )
                }

                body = .init(
                    buffer: byteBuffer,
                    byteBufferAllocator: req.byteBufferAllocator
                )
            } catch {
                body = .init(
                    string: "Oops: \(String(describing: error))\nWhile encoding error: \(reason)",
                    byteBufferAllocator: req.byteBufferAllocator
                )
                headers.contentType = .plainText
            }

            // create a Response with appropriate status
            return Response(status: status, headers: headers, body: body)
        }
    }
}
