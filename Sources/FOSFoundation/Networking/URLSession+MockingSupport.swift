// URLSession+MockingSupport.swift
//
// Created by David Hunt on 8/22/24
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

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol URLSessionProtocol: Sendable {
    func dataTask(
        with url: URL,
        completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask

    func dataTask(
        with request: URLRequest,
        completionHandler: @escaping @Sendable (Data?, URLResponse?, (any Error)?) -> Void
    ) -> URLSessionDataTask

    static func session(config: URLSessionConfiguration) -> Self
}

extension URLSession: URLSessionProtocol, @unchecked Sendable {
    public static func session(config: URLSessionConfiguration) -> Self {
        // REVIEWED - dgh: This odd construction is due to the way that
        //   FoundationNetworking implements URLSession, which is different
        //   than Foundation.  FoundationNetworking implements URLSession
        //   via swift and the init() method is not marked as required.
        //   This leads to a compiler error if we use self.init() with
        //   a return type of Self saying that init() must be marked as
        //   required.  This is a workaround for that error.

        // swiftlint:disable:next force_cast
        URLSession.init(configuration: config) as! Self
    }
}
