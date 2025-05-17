// FoundationDataFetchTests.swift
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

import FOSFoundation
import FOSTesting
import Foundation
import Testing

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("Foundation Data Fetch Test", .tags(.networking, .json))
struct FoundationDataFetchTests {
    // MARK: Fetch

    @Test func fetchLive() async throws {
        let dataFetch = DataFetch<URLSession>.default
        let result: String = try #require(await dataFetch.fetch(
            URL(string: "https://google.com")!,
            headers: [("Accept", "text/html")]
        ))

        #expect(!result.isEmpty)
    }

    @Test func fetchSimple() async throws {
        let testData = TestModel.stub()
        let session = mockSession(testData)
        let dataFetch = DataFetch(urlSession: session)

        let result: TestModel = try #require(await dataFetch.fetch(
            dummyURL
        ))
        #expect(result == testData)

        let result2: TestModel = try #require(await dataFetch.fetch(
            dummyURL,
            errorType: TestError.self
        ))
        #expect(result2 == testData)
    }

    @Test func fetchCustomError() async throws {
        let session = mockSession(TestError.stub())
        let dataFetch = DataFetch(urlSession: session)

        await #expect(throws: TestError.self) {
            let _: TestModel = try await dataFetch.fetch(
                dummyURL,
                errorType: TestError.self
            )
        }
    }

    // MARK: Post

    @Test func postSimple() async throws {
        let testResponse = TestResponse.stub()
        let session = mockSession(testResponse)
        let dataFetch = DataFetch(urlSession: session)

        let result: TestResponse = try #require(await dataFetch.post(
            data: TestModel.stub(),
            to: dummyURL
        ))
        #expect(result == testResponse)

        let result2: TestResponse = try #require(await dataFetch.post(
            data: TestModel.stub(),
            to: dummyURL,
            errorType: TestError.self
        ))
        #expect(result2 == testResponse)
    }

    @Test func postCustomError() async throws {
        let session = mockSession(TestError.stub())
        let dataFetch = DataFetch(urlSession: session)

        await #expect(throws: TestError.self) {
            let _: TestModel = try await dataFetch.post(
                data: TestModel.stub(),
                to: dummyURL,
                errorType: TestError.self
            )
        }
    }

    // MARK: Delete

    @Test func deleteSimple() async throws {
        let testResponse = TestResponse.stub()
        let session = mockSession(testResponse)
        let dataFetch = DataFetch(urlSession: session)

        let result: TestResponse = try #require(await dataFetch.delete(
            data: TestModel.stub(),
            at: dummyURL
        ))
        #expect(result == testResponse)

        let result2: TestResponse = try #require(await dataFetch.delete(
            data: TestModel.stub(),
            at: dummyURL,
            errorType: TestError.self
        ))
        #expect(result2 == testResponse)
    }

    @Test func deleteCustomError() async throws {
        let session = mockSession(TestError.stub())
        let dataFetch = DataFetch(urlSession: session)

        await #expect(throws: TestError.self) {
            let _: TestModel = try await dataFetch.delete(
                data: TestModel.stub(),
                at: dummyURL,
                errorType: TestError.self
            )
        }
    }

    private let dummyURL = URL(string: "https://my.domain")!
}

extension FoundationDataFetchTests {
    struct TestModel: Codable, Equatable, Stubbable {
        let data: String

        static func stub() -> Self {
            .init(data: "Hello world!")
        }
    }

    struct TestResponse: Codable, Equatable, Stubbable {
        let response: String

        static func stub() -> Self {
            .init(response: "All is good!")
        }
    }

    struct TestError: Codable, Error, Stubbable {
        let message: String

        static func stub() -> Self {
            .init(message: "Bad request")
        }
    }

    private func mockSession(_ model: some Codable) -> MockURLSession {
        try! .init(model: model, url: dummyURL)
    }
}
