// ReplaceRequestTests.swift
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

import FOSFoundation
import FOSMVVM
import Foundation
import Testing

/// A minimal concrete `ReplaceRequest` (PUT). Its existence proves the protocol
/// carries the mirror of `UpdateRequest`'s constraints — `RequestBody:
/// ValidatableModel`, `ResponseBody: ReplaceResponseBody` — and its `action`
/// resolves to `.replace`, which the action enum already maps to PUT.
final class TestReplaceRequest: ReplaceRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias Fragment = EmptyFragment
    typealias RequestBody = EmptyBody
    typealias ResponseBody = EmptyBody
    typealias ResponseError = EmptyError

    required init(
        query: EmptyQuery? = nil,
        sort: EmptySort? = nil,
        fragment: EmptyFragment? = nil,
        requestBody: EmptyBody? = nil,
        responseBody: EmptyBody? = nil
    ) {}

    static func stub() -> Self {
        .init()
    }
}

@Suite("ReplaceRequest")
struct ReplaceRequestTests {
    @Test func actionIsReplace() {
        #expect(TestReplaceRequest().action == .replace)
    }

    @Test func baseTypeNameIsReplaceRequest() {
        #expect(TestReplaceRequest.baseTypeName == "ReplaceRequest")
    }
}
