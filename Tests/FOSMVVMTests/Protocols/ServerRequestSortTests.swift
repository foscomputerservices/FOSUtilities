// ServerRequestSortTests.swift
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

@Suite("ServerRequestSort")
struct ServerRequestSortTests {
    enum BerthSortKey: String, SortKey { case number, dockName, updatedAt }

    @Test("SortCriteria preserves term order")
    func order() {
        let sort = SortCriteria<BerthSortKey>([
            .init(key: .dockName, direction: .ascending),
            .init(key: .number, direction: .descending)
        ])
        #expect(sort.terms.map(\.key) == [.dockName, .number])
        #expect(sort.terms.map(\.direction) == [.ascending, .descending])
    }

    @Test("SortCriteria round-trips through JSON, value-preserving")
    func roundTrip() throws {
        let sort = SortCriteria<BerthSortKey>([
            .init(key: .number, direction: .ascending),
            .init(key: .updatedAt, direction: .descending)
        ])
        let back: SortCriteria<BerthSortKey> = try sort.toJSON().fromJSON()
        #expect(back == sort)
    }

    @Test("SortTerm & SortDirection equality")
    func terms() {
        #expect(SortTerm(key: BerthSortKey.number, direction: .ascending)
            == SortTerm(key: BerthSortKey.number, direction: .ascending))
        #expect(SortTerm(key: BerthSortKey.number, direction: .ascending)
            != SortTerm(key: BerthSortKey.number, direction: .descending))
    }

    /// A request with no sort — Sort defaults to EmptySort; `sort` comes from the convenience.
    /// `@unchecked Sendable` matches every real ServerRequest class conformer; `responseBody` and
    /// `id` are supplied by the existing `where ResponseBody == EmptyBody` + AnyObject defaults.
    final class UnsortedRequest: ServerRequest, @unchecked Sendable {
        typealias Query = EmptyQuery
        typealias Fragment = EmptyFragment
        typealias RequestBody = EmptyBody
        typealias ResponseBody = EmptyBody
        typealias ResponseError = EmptyError
        let action: ServerRequestAction = .show
        init(query: EmptyQuery?, sort: EmptySort?, fragment: EmptyFragment?, requestBody: EmptyBody?, responseBody: EmptyBody?) {}
    }

    /// A request that carries a real sort via its own stored property + init.
    final class SortedRequest: ServerRequest, @unchecked Sendable {
        typealias Query = EmptyQuery
        typealias Fragment = EmptyFragment
        typealias RequestBody = EmptyBody
        typealias ResponseBody = EmptyBody
        typealias ResponseError = EmptyError
        typealias Sort = SortCriteria<BerthSortKey>
        let action: ServerRequestAction = .show
        let sort: SortCriteria<BerthSortKey>?
        init(query: EmptyQuery?, sort: SortCriteria<BerthSortKey>?, fragment: EmptyFragment?, requestBody: EmptyBody?, responseBody: EmptyBody?) {
            self.sort = sort
        }
    }

    @Test("Unsorted request has nil sort via the EmptySort convenience")
    func unsortedDefault() {
        let req = UnsortedRequest(query: nil, fragment: nil, requestBody: nil, responseBody: nil)
        #expect(req.sort == nil)
    }

    @Test("Sorted request carries its sort")
    func sortedCarries() {
        let sort = SortCriteria<BerthSortKey>([.init(key: .number, direction: .ascending)])
        let req = SortedRequest(query: nil, sort: sort, fragment: nil, requestBody: nil, responseBody: nil)
        #expect(req.sort == sort)
    }

    @Test("Canonical init carries a real sort; the 4-param convenience yields nil")
    func canonicalInitRoundTrip() {
        let sort = SortCriteria<BerthSortKey>([.init(key: .dockName, direction: .descending)])
        let sorted = SortedRequest(query: nil, sort: sort, fragment: nil, requestBody: nil, responseBody: nil)
        #expect(sorted.sort == sort)

        let unsorted = SortedRequest(query: nil, fragment: nil, requestBody: nil, responseBody: nil)
        #expect(unsorted.sort == nil)
    }
}
