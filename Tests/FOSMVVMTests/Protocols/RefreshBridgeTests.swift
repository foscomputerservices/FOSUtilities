// RefreshBridgeTests.swift
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

/// The typed refresh bridge on the write CRUD protocols: a write request names
/// (`RefreshRequest`) and builds (`refreshRequest()`) the read request the server
/// re-serves after the write commits. This is the *typing half* — a pure value
/// mapping authored in the shared module; nothing round-trips through a server.
@Suite("RefreshBridge")
struct RefreshBridgeTests {
    // MARK: Fixtures (shared-module shape — public inits, no Fluent/Vapor)

    /// The read screen both write halves refresh to.
    struct FixturePageBody: ServerRequestBody {
        let title: String
    }

    struct FixtureQuery: ServerRequestQuery {
        let root: Int
    }

    struct FixtureWriteBody: ServerRequestBody, ValidatableModel {
        func validate(fields: [any FormFieldBase]?, validations: Validations) -> ValidationResult.Status? {
            nil
        }
    }

    /// The read request pass #2 re-serves — a plain `ShowRequest`.
    final class FixtureShowRequest: ShowRequest, @unchecked Sendable {
        typealias Query = FixtureQuery
        typealias Fragment = EmptyFragment
        typealias RequestBody = EmptyBody
        typealias ResponseBody = FixturePageBody
        typealias ResponseError = EmptyError

        let query: FixtureQuery?
        var responseBody: FixturePageBody?

        init(query: FixtureQuery?, sort: EmptySort?, fragment: EmptyFragment?, requestBody: EmptyBody?, responseBody: FixturePageBody?) {
            self.query = query
            self.responseBody = responseBody
        }
    }

    /// An `UpdateRequest` whose `RefreshRequest == FixtureShowRequest`; its
    /// `ResponseBody` is the show request's, by the protocol's new constraint.
    final class FixtureUpdateRequest: UpdateRequest, @unchecked Sendable {
        typealias Query = FixtureQuery
        typealias Fragment = EmptyFragment
        typealias RequestBody = FixtureWriteBody
        typealias ResponseBody = FixturePageBody
        typealias ResponseError = EmptyError
        typealias RefreshRequest = FixtureShowRequest

        let query: FixtureQuery?
        let requestBody: FixtureWriteBody?
        var responseBody: FixturePageBody?

        init(query: FixtureQuery?, sort: EmptySort?, fragment: EmptyFragment?, requestBody: FixtureWriteBody?, responseBody: FixturePageBody?) {
            self.query = query
            self.requestBody = requestBody
            self.responseBody = responseBody
        }

        func refreshRequest() -> FixtureShowRequest {
            .init(query: .init(root: query?.root ?? 0), fragment: nil, requestBody: nil, responseBody: nil)
        }

        static func stub() -> FixtureUpdateRequest {
            .init(query: .init(root: 0), fragment: nil, requestBody: .init(), responseBody: nil)
        }
    }

    /// A `CreateRequest` sharing the same refresh screen.
    final class FixtureCreateRequest: CreateRequest, @unchecked Sendable {
        typealias Query = FixtureQuery
        typealias Fragment = EmptyFragment
        typealias RequestBody = FixtureWriteBody
        typealias ResponseBody = FixturePageBody
        typealias ResponseError = EmptyError
        typealias RefreshRequest = FixtureShowRequest

        let query: FixtureQuery?
        let requestBody: FixtureWriteBody?
        var responseBody: FixturePageBody?

        init(query: FixtureQuery?, sort: EmptySort?, fragment: EmptyFragment?, requestBody: FixtureWriteBody?, responseBody: FixturePageBody?) {
            self.query = query
            self.requestBody = requestBody
            self.responseBody = responseBody
        }

        func refreshRequest() -> FixtureShowRequest {
            .init(query: .init(root: query?.root ?? 0), fragment: nil, requestBody: nil, responseBody: nil)
        }

        static func stub() -> FixtureCreateRequest {
            .init(query: .init(root: 0), fragment: nil, requestBody: .init(), responseBody: nil)
        }
    }

    /// A `DeleteRequest` sharing the same refresh screen (no `RequestBody`
    /// constraint, no `ResponseBody` marker — only the new bridge constraint).
    final class FixtureDeleteRequest: DeleteRequest, @unchecked Sendable {
        typealias Query = FixtureQuery
        typealias Fragment = EmptyFragment
        typealias RequestBody = EmptyBody
        typealias ResponseBody = FixturePageBody
        typealias ResponseError = EmptyError
        typealias RefreshRequest = FixtureShowRequest

        let query: FixtureQuery?
        var responseBody: FixturePageBody?

        init(query: FixtureQuery?, sort: EmptySort?, fragment: EmptyFragment?, requestBody: EmptyBody?, responseBody: FixturePageBody?) {
            self.query = query
            self.responseBody = responseBody
        }

        func refreshRequest() -> FixtureShowRequest {
            .init(query: .init(root: query?.root ?? 0), fragment: nil, requestBody: nil, responseBody: nil)
        }

        static func stub() -> FixtureDeleteRequest {
            .init(query: .init(root: 0), fragment: nil, requestBody: nil, responseBody: nil)
        }
    }

    // MARK: Tests

    // Route every assertion through the PROTOCOL requirement, not the concrete
    // fixture member: these generic accessors reference `X.RefreshRequest` and
    // `request.refreshRequest()` on the protocol itself, so they only compile
    // once the bridge is declared on Create/Update/DeleteRequest.

    private func refreshTarget(of request: some CreateRequest) -> some ServerRequest {
        request.refreshRequest()
    }

    private func refreshTarget(of request: some UpdateRequest) -> some ServerRequest {
        request.refreshRequest()
    }

    private func refreshTarget(of request: some DeleteRequest) -> some ServerRequest {
        request.refreshRequest()
    }

    @Test("Update's refresh request carries the write query's root — pure value mapping")
    func updateBridgeCarriesRoot() {
        let update = FixtureUpdateRequest(query: .init(root: 42), fragment: nil, requestBody: .init(), responseBody: nil)
        let refresh = refreshTarget(of: update) as? FixtureShowRequest
        #expect(refresh?.query?.root == 42)
    }

    @Test("Create's refresh request carries the write query's root")
    func createBridgeCarriesRoot() {
        let create = FixtureCreateRequest(query: .init(root: 7), fragment: nil, requestBody: .init(), responseBody: nil)
        let refresh = refreshTarget(of: create) as? FixtureShowRequest
        #expect(refresh?.query?.root == 7)
    }

    @Test("Delete's refresh request carries the write query's root")
    func deleteBridgeCarriesRoot() {
        let delete = FixtureDeleteRequest(query: .init(root: 99), fragment: nil, requestBody: nil, responseBody: nil)
        let refresh = refreshTarget(of: delete) as? FixtureShowRequest
        #expect(refresh?.query?.root == 99)
    }
}

// The refresh target's body adopts the shipped write markers so a write
// request's `ResponseBody` (constrained `: Create/UpdateResponseBody`) can
// equal it; delete imposes no such marker.
extension RefreshBridgeTests.FixturePageBody: CreateResponseBody {}
extension RefreshBridgeTests.FixturePageBody: UpdateResponseBody {}

// compile-audit: an `UpdateRequest` whose `ResponseBody` differs from its
// `RefreshRequest.ResponseBody` must fail to compile — the new
// `where ResponseBody == RefreshRequest.ResponseBody` constraint binds the
// caller to the fresh screen's body. `EmptyBody` already adopts
// `UpdateResponseBody`, so uncommenting the next declaration isolates the new
// constraint: it fails with a `ResponseBody` type-mismatch (EmptyBody vs
// FixturePageBody), never a missing-marker error.
// private final class MismatchedRefreshRequest: UpdateRequest, @unchecked Sendable {
//     typealias Query = RefreshBridgeTests.FixtureQuery
//     typealias Fragment = EmptyFragment
//     typealias RequestBody = RefreshBridgeTests.FixtureWriteBody
//     typealias ResponseBody = EmptyBody // ← differs from RefreshRequest.ResponseBody (FixturePageBody)
//     typealias ResponseError = EmptyError
//     typealias RefreshRequest = RefreshBridgeTests.FixtureShowRequest
//     let query: RefreshBridgeTests.FixtureQuery?
//     let requestBody: RefreshBridgeTests.FixtureWriteBody?
//     var responseBody: EmptyBody?
//     init(query: RefreshBridgeTests.FixtureQuery?, sort: EmptySort?, fragment: EmptyFragment?, requestBody: RefreshBridgeTests.FixtureWriteBody?, responseBody: EmptyBody?) {
//         self.query = query; self.requestBody = requestBody; self.responseBody = responseBody
//     }
//     func refreshRequest() -> RefreshBridgeTests.FixtureShowRequest { .stub() }
//     static func stub() -> MismatchedRefreshRequest { .init(query: .init(root: 0), fragment: nil, requestBody: .init(), responseBody: nil) }
// }
