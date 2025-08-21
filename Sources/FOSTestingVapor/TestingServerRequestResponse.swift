// TestingServerRequestResponse.swift
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

import FOSFoundation
import FOSMVVM
import Vapor
import VaporTesting

/// The results of processing a *SystemRequest* by the web service
public struct TestingServerRequestResponse<R: ServerRequest> {
    /// The received *HTTPStatus*
    public let status: HTTPStatus

    /// The received *HTTPHeaders*
    public let headers: HTTPHeaders

    /// The received *ServerRequest/ResponseBody*, if any
    public let body: R.ResponseBody?

    /// The received *ServerRequest/ResponseError*, if any
    public let error: R.ResponseError?

    init(response: TestingHTTPResponse) throws {
        self.status = response.status
        self.headers = response.headers
        self.body = try? response.body.fromJSON()
        self.error = try? response.body.fromJSON()
    }
}

/// Extends *TestingApplicationTester* to include support for *ServerRequest*
public extension TestingApplicationTester {
    /// Sends the given *ServerRequest* to the web service for processing
    ///
    /// - Parameters:
    ///   - request: The *ServerRequest* to send
    ///   - locale: The *Locale* to use for encoding results passed back from the web service (default: "en")
    ///   - headers: Any additional headers to add to the HTTP request (default: [])
    ///   - fileID: The calling source file
    ///   - filePath: The calling source file path
    ///   - line: The calling source file line number
    ///   - column: The calling source file column number
    ///   - afterResponse: A callback that will provide the results of the web service in a ``TestingServerRequestResponse``
    @discardableResult func test<R: ServerRequest>(
        _ request: R,
        locale: Locale = Self.en,
        headers: HTTPHeaders = [:],
        fileID: String = #fileID,
        filePath: String = #filePath,
        line: Int = #line,
        column: Int = #column,
        afterResponse: (TestingServerRequestResponse<R>) async throws -> Void
    ) async throws -> any TestingApplicationTester {
        guard let requestBody = request.requestBody else {
            fatalError()
        }

        let version = try SystemVersion.current.toJSON()
        var headers = headers
        headers.add(name: SystemVersion.httpHeader, value: version)
        headers.add(name: HTTPHeaders.Name.accept.description, value: "application/json")
        headers.add(name: HTTPHeaders.Name.contentType.description, value: "application/json")
        headers.add(name: HTTPHeaders.Name.acceptLanguage.description, value: locale.identifier)

        return try await test(
            request.action.httpMethod,
            R.path,
            headers: headers,
            body: requestBody.toJSONByteBuffer(),
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        ) { _ in }
            afterResponse: { response in
                try await afterResponse(TestingServerRequestResponse<R>(
                    response: response
                ))
            }
    }

    static var en: Locale {
        Locale(identifier: "en")
    }

    var en: Locale {
        Self.en
    }

    static var enUS: Locale {
        Locale(identifier: "en-US")
    }

    var enUS: Locale {
        Self.enUS
    }

    static var enGB: Locale {
        Locale(identifier: "en-GB")
    }

    var enGB: Locale {
        Self.enGB
    }

    static var es: Locale {
        Locale(identifier: "es")
    }

    var es: Locale {
        Self.es
    }
}

private extension ServerRequestAction {
    var httpMethod: HTTPMethod {
        switch self {
        case .show: .GET
        case .create: .POST
        case .update: .PATCH
        case .replace: .PUT
        case .delete, .destroy: .DELETE
        }
    }
}

public extension Encodable {
    func toJSONByteBuffer(encoder: JSONEncoder? = nil) throws -> ByteBuffer {
        try ByteBufferAllocator().buffer(
            data: toJSONData(encoder: encoder)
        )
    }
}

public extension ByteBuffer {
    func fromJSON<T>(decoder: JSONDecoder? = nil) throws -> T where T: Decodable {
        let data: Data = withUnsafeReadableBytes {
            Data(UnsafeRawBufferPointer($0))
        }
        return try data.fromJSON(decoder: decoder)
    }
}
