// URLSession.swift
//
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

#if os(WASI)
import Foundation
import JavaScriptKit

/// Logging helper that outputs to browser console
private func log(_ message: String) {
    JSObject.global.console.log(message)
}

/// Minimal URLSessionDataTask implementation for WASI using JavaScriptKit fetch
public class URLSessionDataTask {
    private let task: () -> Void

    internal init(task: @escaping () -> Void) {
        self.task = task
    }

    public func resume() {
        task()
    }
}

/// Minimal URLSession implementation for WASI using JavaScriptKit fetch
public final class URLSession: URLSessionProtocol {
    public static let shared = URLSession()

    private init() {}

    public func dataTask(
        with url: URL,
        completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {
        let request = URLRequest(url: url)
        return dataTask(with: request, completionHandler: completionHandler)
    }

    public func dataTask(
        with request: URLRequest,
        completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {
        URLSessionDataTask {
            log("[WASM URLSession] dataTask called for URL: \(request.url.absoluteString)")

            // Build fetch options
            let options = JSObject.global.Object.function!.new()
            if let method = request.httpMethod {
                options["method"] = .string(method)
            }

            // Add headers
            if !request.headers.isEmpty {
                let headersObj = JSObject.global.Object.function!.new()
                for (key, value) in request.headers {
                    headersObj[key] = .string(value)
                }
                options["headers"] = .object(headersObj)
            }

            // Add body (but not for GET/HEAD requests)
            let method = request.httpMethod?.uppercased() ?? "GET"
            if let body = request.httpBody, method != "GET" && method != "HEAD" {
                let uint8Array = JSObject.global.Uint8Array.function!
                let jsArray = uint8Array.new(body.count)
                for (index, byte) in body.enumerated() {
                    jsArray[index] = .number(Double(byte))
                }
                options["body"] = .object(jsArray)
            }

            // Make fetch call - use wasmFetch wrapper (defined in HTML) to preserve 'this' context
            log("[WASM URLSession] Making fetch call...")
            let wasmFetch = JSObject.global.wasmFetch.function!
            let responsePromise = JSPromise(
                wasmFetch(request.url.absoluteString, options).object!
            )!

            // Handle fetch response
            responsePromise.then { responseValue in
                log("[WASM URLSession] Fetch response received")
                let response = responseValue.object!

                // Extract status and mime type
                let statusCode = Int(response.status.number!)
                let headersObj = response.headers.object!
                let contentType = JSObject.global.wasmHeadersGet.function!(headersObj, "content-type").string
                log("[WASM URLSession] Status: \(statusCode), Content-Type: \(contentType ?? "none")")

                // Extract headers from fetch response
                var headerFields: [String: String] = [:]
                let headersEntries = JSObject.global.wasmHeadersEntries.function!(headersObj).object!

                // Iterate through headers using JavaScript iterator protocol
                while true {
                    let next = JSObject.global.wasmIteratorNext.function!(headersEntries).object!
                    if next.done.boolean! {
                        break
                    }
                    let entry = next.value.object!
                    if let key = entry[0].string, let value = entry[1].string {
                        headerFields[key] = value
                    }
                }

                // Get response body as ArrayBuffer
                let arrayBufferPromise = JSPromise(JSObject.global.wasmArrayBuffer.function!(response).object!)!

                // Handle arrayBuffer response
                arrayBufferPromise.then { arrayBufferValue in
                    log("[WASM URLSession] ArrayBuffer received, converting to Data...")
                    let arrayBuffer = arrayBufferValue.object!

                    // Convert ArrayBuffer to Data
                    let uint8Array = JSObject.global.Uint8Array.function!.new(arrayBuffer)
                    let length = Int(uint8Array.length.number!)
                    var data = Data(count: length)
                    for i in 0..<length {
                        data[i] = UInt8(uint8Array[i].number!)
                    }

                    log("[WASM URLSession] Data converted, \(length) bytes")

                    let httpResponse = HTTPURLResponse(
                        statusCode: statusCode,
                        mimeType: contentType,
                        headerFields: headerFields
                    )

                    log("[WASM URLSession] Calling completion handler with success")
                    completionHandler(data, httpResponse, nil)

                    return .undefined
                }.catch { error in
                    log("[WASM URLSession] ArrayBuffer error: \(error.string ?? "Unknown")")
                    completionHandler(nil, nil, NSError(domain: "URLSession", code: -1, userInfo: [NSLocalizedDescriptionKey: error.string ?? "Unknown error"]))
                    return .undefined
                }

                return .undefined
            }.catch { error in
                let errorMessage = error.string ?? "Unknown"
                let errorObj = error.object
                log("[WASM URLSession] Fetch error: \(errorMessage)")
                if let errorObj = errorObj {
                    log("[WASM URLSession] Error object: \(errorObj)")
                    if let message = errorObj.message.string {
                        log("[WASM URLSession] Error message: \(message)")
                    }
                    if let stack = errorObj.stack.string {
                        log("[WASM URLSession] Error stack: \(stack)")
                    }
                }
                completionHandler(nil, nil, NSError(domain: "URLSession", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMessage]))
                return .undefined
            }
        }
    }

    public static func session(config: URLSessionConfiguration) -> Self {
        // For WASI, we ignore config and return shared
        return shared as! Self
    }
}
#endif // os(WASI)
