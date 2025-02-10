// ServerRequest.swift
//
// Created by David Hunt on 1/29/25
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

#if canImport(Vapor)
import FOSMVVM
import Foundation
import Vapor

public extension ServerRequestBody where Self: ServerRequestBody {
    // MARK: AsyncResponseEncodable Protocol

    // NOTE: It is intentional NOT to use Vapor's standard Content
    //   encoding as Vapor only allows setting the encoder
    //   globally (https://docs.vapor.codes/basics/content/#global).
    //   The encoder needs to take into account the request's
    //   locale to localize the model during encoding, which
    //   can only be done locally.
    //
    //   Also, Vapor's ContentEncoder protocol cannot be used
    //   as it doesn't provide access to Vapor.Request during
    //   encoding (https://docs.vapor.codes/basics/content/#content_1).
    //
    //   Additionally, the api version and other headers are
    //   added to the Response.  This is all done in vaporResponse().
    //
    //   Thus, we use the AsyncResponseEncodable protocol.

    func encodeResponse(for req: Request) async throws -> Response {
        var headers = HTTPHeaders()

        // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Type
        headers.replaceOrAdd(
            name: .contentType,
            value: "application/json; charset=utf-8"
        )

        // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Vary
        // https://www.smashingmagazine.com/2017/11/understanding-vary-header/
        headers.replaceOrAdd(name: .vary, value: "*")
        headers.replaceOrAdd(name: .cacheControl, value: "no-store")

        // try response.addApplicationVersion()

        // NOTE: Use the *viewModelEncoder* to localize the response
        return try .init(
            status: .ok,
            headers: headers,
            body: .init(data: toJSONData(encoder: req.viewModelEncoder))
        )
    }
}
#endif
