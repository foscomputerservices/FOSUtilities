// PaginationTests.swift
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

@Suite("Pagination")
struct PaginationTests {
    struct PagedQuery: PaginatedQuery {
        var pagination: Pagination {
            .init(startIndex: 0, maxResults: 25)
        }
    }

    struct PlainQuery: ServerRequestQuery {}

    @Test("A conforming query exposes its window")
    func exposes() {
        #expect(PagedQuery().pagination.startIndex == 0)
        #expect(PagedQuery().pagination.maxResults == 25)
    }

    @Test("Pagination on a query is opt-in — a plain query is not a PaginatedQuery")
    func optIn() {
        let paged: any ServerRequestQuery = PagedQuery()
        let plain: any ServerRequestQuery = PlainQuery()
        #expect((paged as? any PaginatedQuery) != nil)
        #expect((plain as? any PaginatedQuery) == nil)
    }

    @Test("Pagination round-trips, value-preserving")
    func roundTrip() throws {
        let page = Pagination(startIndex: 50, maxResults: 25)
        let back: Pagination = try page.toJSON().fromJSON()
        #expect(back == page)
    }
}
