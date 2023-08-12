// FoundationDataFetchTests.swift
//
// Copyright © 2023 FOS Services, LLC. All rights reserved.
//

import FOSFoundation
import XCTest

final class FoundationDataFetchTests: XCTestCase {
    func testFetch() async throws {
        let url = URL(string: "https://google.com")!
        let dataFetch = FoundationDataFetch.default

        do {
            let result: String? = try await dataFetch.fetch(
                url,
                headers: [
                    ("Accept", "text/html")
                ]
            )

            XCTAssertNotNil(result)
            guard let result else { return }

            XCTAssertFalse(result.isEmpty)
        } catch let e {
            XCTFail("Failed with exception: \(e.localizedDescription)")
        }
    }
}
