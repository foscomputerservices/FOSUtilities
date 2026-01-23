// URLRequest.swift
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

/// Minimal URLRequest implementation for WASI using JavaScriptKit fetch
public struct URLRequest {
    public var url: URL
    public var httpMethod: String?
    public var httpBody: Data?

    internal var headers: [String: String] = [:]

    public init(url: URL) {
        self.url = url
    }

    public mutating func setValue(_ value: String?, forHTTPHeaderField field: String) {
        headers[field] = value
    }
}
#endif // os(WASI)
