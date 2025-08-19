// ControllerRouting.swift
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

import FluentKit
import FOSFoundation
import FOSMVVM
import Foundation
import Vapor

public protocol ControllerRouting {
    static var baseURL: String { get }

    static func path(
        for: ServerRequestAction,
        _ args: CustomStringConvertible...
    ) throws -> String

    static func path(
        for: ServerRequestAction,
        _ args: CustomStringConvertible...,
        query: some Encodable
    ) throws -> String
}

public extension ControllerRouting {
    static func path(
        for action: ServerRequestAction,
        _ args: CustomStringConvertible...
    ) throws -> String {
        try path(for: action, args: args)
    }

    static func path(
        for action: ServerRequestAction,
        args: [CustomStringConvertible]
    ) throws -> String {
        let fragment = args.map { String(describing: $0) }.joined(separator: "/")
        let path = fragment.isEmpty ? fragment : "/\(fragment)"

        switch action {
        case .show, .replace, .update:
            return baseURL + path

        case .create:
            return baseURL + "/create" + path

        case .delete:
            return baseURL + "/delete" + path

        case .destroy:
            return baseURL + "/destroy" + path
        }
    }

    static func path(
        for action: ServerRequestAction,
        _ args: CustomStringConvertible...,
        query: some Encodable
    ) throws -> String {
        let base = try path(for: action, args: args)

        let jsonData = try query.toJSONData()

        var queryStr = ""
        if let jsonDict = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
            var sepStr = "?"
            for tuple in jsonDict {
                queryStr += "\(sepStr)\(tuple.key)=\(tuple.value)"
                sepStr = "&"
            }
        }

        return base + queryStr
    }
}
