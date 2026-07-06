// ServerRequestSortURLTests.swift
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
import FOSMVVMVapor
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import Vapor

/// Spec test group 9: sort rides the request URL as a reserved item; pre-C6 URLs
/// round-trip byte-identically. These tests (not DocC) pin the reserved `sort=`
/// item name and the raw-`&` split rule — the representation stays unpublished.
@Suite("ServerRequestSortURL")
struct ServerRequestSortURLTests {
    enum TestSortKey: String, SortKey { case number, dockName }

    struct TestQuery: ServerRequestQuery {
        let modelId: Int
    }

    /// A query whose string field carries hostile wire characters (`&`, `=`, and a
    /// literal `sort=` substring) so the multiplexing split rule is pinned under fire.
    struct HostileQuery: ServerRequestQuery {
        let note: String
    }

    /// Mirrors `ServerRequestSortTests.SortedRequest` (other test target) with a
    /// real `Query` so the query blob and the sort item coexist on one URL.
    final class SortedRequest: ServerRequest, @unchecked Sendable {
        typealias Fragment = EmptyFragment
        typealias RequestBody = EmptyBody
        typealias ResponseBody = EmptyBody
        typealias ResponseError = EmptyError
        typealias Sort = SortCriteria<TestSortKey>

        var action: ServerRequestAction {
            .show
        }

        let query: TestQuery?
        let sort: SortCriteria<TestSortKey>?

        init(query: TestQuery?, sort: SortCriteria<TestSortKey>?, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: EmptyBody? = nil) {
            self.query = query
            self.sort = sort
        }
    }

    /// `SortedRequest` with a ``HostileQuery`` payload.
    final class HostileSortedRequest: ServerRequest, @unchecked Sendable {
        typealias Fragment = EmptyFragment
        typealias RequestBody = EmptyBody
        typealias ResponseBody = EmptyBody
        typealias ResponseError = EmptyError
        typealias Sort = SortCriteria<TestSortKey>

        var action: ServerRequestAction {
            .show
        }

        let query: HostileQuery?
        let sort: SortCriteria<TestSortKey>?

        init(query: HostileQuery?, sort: SortCriteria<TestSortKey>?, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: EmptyBody? = nil) {
            self.query = query
            self.sort = sort
        }
    }

    /// An `EmptySort` conformer — `sort` is nil via the constrained extension.
    final class UnsortedRequest: ServerRequest, @unchecked Sendable {
        typealias Fragment = EmptyFragment
        typealias RequestBody = EmptyBody
        typealias ResponseBody = EmptyBody
        typealias ResponseError = EmptyError

        var action: ServerRequestAction {
            .show
        }

        let query: TestQuery?

        init(query: TestQuery?, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: EmptyBody? = nil) {
            self.query = query
        }
    }

    @Test("Query and sort round-trip together through the URL")
    func queryAndSortRoundTrip() async throws {
        let query = TestQuery(modelId: 42)
        let sort = SortCriteria<TestSortKey>([
            .init(key: .dockName, direction: .ascending),
            .init(key: .number, direction: .descending)
        ])
        let request = SortedRequest(query: query, sort: sort)
        let url = try requestURL(for: request)

        try await withVaporRequest(url: url) { req in
            let recoveredSort = try req.serverRequestSort(ofType: SortCriteria<TestSortKey>.self)
            let recoveredQuery = try req.serverRequestQuery(ofType: TestQuery.self)
            #expect(recoveredSort == sort)
            #expect(recoveredQuery == query)
        }
    }

    /// Pins the split-safety rule the parser relies on: URLQueryItem percent-encodes
    /// '&' and '=' inside names/values, so hostile characters in payloads can never
    /// masquerade as item separators or as the reserved "sort=" item. Fails loudly
    /// if Foundation (incl. swift-corelibs-foundation on Linux) ever drifts.
    @Test("Hostile wire characters in the query round-trip alongside the sort item")
    func hostilePayloadRoundTrip() async throws {
        let query = HostileQuery(note: "a&sort=1&b=2")
        let sort = SortCriteria<TestSortKey>([
            .init(key: .number, direction: .descending)
        ])
        let request = HostileSortedRequest(query: query, sort: sort)
        let url = try requestURL(for: request)

        try await withVaporRequest(url: url) { req in
            let recoveredQuery = try req.serverRequestQuery(ofType: HostileQuery.self)
            let recoveredSort = try req.serverRequestSort(ofType: SortCriteria<TestSortKey>.self)
            #expect(recoveredQuery == query)
            #expect(recoveredSort == sort)
        }
    }

    @Test("Sort-only request: sort recovers, query is nil")
    func sortOnlyRequest() async throws {
        let sort = SortCriteria<TestSortKey>([
            .init(key: .number, direction: .ascending)
        ])
        let request = SortedRequest(query: nil, sort: sort)
        let url = try requestURL(for: request)

        try await withVaporRequest(url: url) { req in
            let recoveredSort = try req.serverRequestSort(ofType: SortCriteria<TestSortKey>.self)
            let recoveredQuery = try req.serverRequestQuery(ofType: TestQuery.self)
            #expect(recoveredSort == sort)
            #expect(recoveredQuery == nil)
        }
    }

    @Test("Nil-sort request URL is byte-identical to the pre-C6 encoding")
    func nilSortCompatibility() throws {
        let query = TestQuery(modelId: 7)
        let request = SortedRequest(query: query, sort: nil)
        let url = try requestURL(for: request)

        #expect(url.query?.contains("sort=") != true)

        // The shipped (pre-C6) rule: ONE item whose NAME is the query JSON, nil value.
        let legacy = try legacyURL(path: SortedRequest.path, query: query)
        #expect(url == legacy)
    }

    @Test("Legacy URL (query blob only) parses: query decodes, sort is nil")
    func legacyURLParses() async throws {
        let query = TestQuery(modelId: 99)
        let url = try legacyURL(path: SortedRequest.path, query: query)

        try await withVaporRequest(url: url) { req in
            let recoveredQuery = try req.serverRequestQuery(ofType: TestQuery.self)
            let recoveredSort = try req.serverRequestSort(ofType: SortCriteria<TestSortKey>.self)
            #expect(recoveredQuery == query)
            #expect(recoveredSort == nil)
        }
    }

    @Test("EmptySort conformer produces no sort item")
    func emptySortConformer() throws {
        let query = TestQuery(modelId: 1)
        let request = UnsortedRequest(query: query)
        let url = try requestURL(for: request)

        #expect(url.query?.contains("sort=") != true)
        let legacy = try legacyURL(path: UnsortedRequest.path, query: query)
        #expect(url == legacy)
    }

    // MARK: Test Support

    /// Encodes `request` onto the base URL via the production encoder.
    private func requestURL(for request: some ServerRequest) throws -> URL {
        let base = try #require(URL(string: "http://localhost"))
        let url = try base.appending(serverRequest: request)
        return try #require(url)
    }

    /// Builds a URL exactly as the shipped, pre-C6 encoder did: the percent-encoded
    /// path plus a single URLQueryItem whose name is the query JSON with a nil value.
    private func legacyURL(path: String, query: some ServerRequestQuery) throws -> URL {
        let extraPath = try #require(path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed))
        let base = try #require(URL(string: "http://localhost"))
        return try base
            .appendingPathComponent(extraPath)
            .appending(queryItems: [.init(name: query.toJSON(), value: nil)])
    }

    /// Mints a real Vapor `Request` for `url`. A plain `Application.make(.testing)`
    /// suffices — no database is involved in URL parsing.
    private func withVaporRequest(url: URL, _ body: (Vapor.Request) throws -> Void) async throws {
        let app = try await Application.make(.testing)
        do {
            let req = Vapor.Request(
                application: app,
                method: .GET,
                url: URI(string: url.absoluteString),
                on: app.eventLoopGroup.next()
            )
            try body(req)
            try await app.asyncShutdown()
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
    }
}
