// DataFetchResponseErrorTests.swift
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
import FOSTesting
import Foundation
import Testing

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite(.tags(.networking))
struct DataFetchResponseErrorTests {
    // MARK: The standard: Retry-After on 429 and 503

    @Test(arguments: [429, 503])
    func secondsFormThrowsRetryAfter(statusCode: Int) async throws {
        let dataFetch = try DataFetch(urlSession: session(statusCode: statusCode, retryAfter: "120"))

        let error = await thrownError { let _: Board = try await dataFetch.fetch(boardURL) }

        #expect(wait(in: error) == .seconds(120))
    }

    @Test(arguments: [
        "EEE, dd MMM yyyy HH:mm:ss 'GMT'", // IMF-fixdate
        "EEEE, dd-MMM-yy HH:mm:ss 'GMT'", // rfc850-date (obsolete)
        "EEE MMM d HH:mm:ss yyyy" // asctime-date (obsolete)
    ])
    func httpDateFormThrowsWaitFromNow(dateFormat: String) async throws {
        let retryAfter = httpDate(Date().addingTimeInterval(120), format: dateFormat)
        let dataFetch = try DataFetch(urlSession: session(statusCode: 503, retryAfter: retryAfter))

        let error = await thrownError { let _: Board = try await dataFetch.fetch(boardURL) }

        let delay = try #require(wait(in: error))
        #expect(delay > .seconds(100) && delay <= .seconds(121))
    }

    @Test(arguments: ["soon", "-5", "+5", "1.5", "Someday, 99 Nov 9999"])
    func malformedHeaderTakesTodaysPath(retryAfter: String) async throws {
        let dataFetch = try DataFetch(urlSession: session(statusCode: 429, retryAfter: retryAfter))

        let error = await thrownError { let _: Board = try await dataFetch.fetch(boardURL) }

        #expect(status(in: error) == 429)
    }

    @Test func pastDateTakesTodaysPath() async throws {
        let retryAfter = httpDate(Date().addingTimeInterval(-120), format: "EEE, dd MMM yyyy HH:mm:ss 'GMT'")
        let dataFetch = try DataFetch(urlSession: session(statusCode: 503, retryAfter: retryAfter))

        let error = await thrownError { let _: Board = try await dataFetch.fetch(boardURL) }

        #expect(status(in: error) == 503)
    }

    @Test func tooManyRequestsWithoutHeaderTakesTodaysPath() async throws {
        let dataFetch = try DataFetch(urlSession: session(statusCode: 429))

        let error = await thrownError { let _: Board = try await dataFetch.fetch(boardURL) }

        #expect(status(in: error) == 429)
    }

    @Test func tooManyRequestsWithoutHeaderStillDecodesErrorType() async throws {
        let dataFetch = try DataFetch(urlSession: session(statusCode: 429, body: ServiceError.stub()))

        let error = await thrownError {
            let _: Board = try await dataFetch.fetch(boardURL, errorType: ServiceError.self)
        }

        #expect(error is ServiceError)
    }

    @Test func retryAfterOnOtherStatusesIsIgnored() async throws {
        let dataFetch = try DataFetch(urlSession: session(statusCode: 500, retryAfter: "120"))

        let error = await thrownError { let _: Board = try await dataFetch.fetch(boardURL) }

        #expect(status(in: error) == 500)
    }

    @Test func retryAfterIsThrownAheadOfTheErrorType() async throws {
        let dataFetch = try DataFetch(urlSession: session(
            statusCode: 503,
            retryAfter: "30",
            body: ServiceError.stub()
        ))

        let error = await thrownError {
            let _: Board = try await dataFetch.fetch(boardURL, errorType: ServiceError.self)
        }

        #expect(wait(in: error) == .seconds(30))
    }

    // MARK: The caller's hook

    @Test func hooksErrorWinsOverTheStandard() async throws {
        let dataFetch = try DataFetch(urlSession: session(statusCode: 429, retryAfter: "120")) { _, _ in
            BoardLocked()
        }

        let error = await thrownError { let _: Board = try await dataFetch.fetch(boardURL) }

        #expect(error is BoardLocked)
    }

    @Test func hooksErrorWinsOverTheErrorType() async throws {
        let dataFetch = try DataFetch(urlSession: session(statusCode: 400, body: ServiceError.stub())) { _, _ in
            BoardLocked()
        }

        let error = await thrownError {
            let _: Board = try await dataFetch.fetch(boardURL, errorType: ServiceError.self)
        }

        #expect(error is BoardLocked)
    }

    @Test func hookReturningNilFallsThroughToTheStandard() async throws {
        let dataFetch = try DataFetch(urlSession: session(statusCode: 429, retryAfter: "120")) { _, _ in nil }

        let error = await thrownError { let _: Board = try await dataFetch.fetch(boardURL) }

        #expect(wait(in: error) == .seconds(120))
    }

    @Test func hookReturningNilFallsThroughToTheErrorType() async throws {
        let dataFetch = try DataFetch(urlSession: session(statusCode: 400, body: ServiceError.stub())) { _, _ in nil }

        let error = await thrownError {
            let _: Board = try await dataFetch.fetch(boardURL, errorType: ServiceError.self)
        }

        #expect(error is ServiceError)
    }

    @Test func hookReturningNilLeavesSuccessAlone() async throws {
        let board = Board.stub()
        let dataFetch = try DataFetch(urlSession: session(statusCode: 200, body: board)) { _, _ in nil }

        let fetched: Board = try await dataFetch.fetch(boardURL)

        #expect(fetched == board)
    }

    @Test func hookCombinesJSONErrorAndRetryAfterIntoOneError() async throws {
        let dataFetch = try DataFetch(urlSession: session(
            statusCode: 429,
            retryAfter: "7",
            body: ServiceError(message: "Too many requests for this workspace")
        )) { response, data in
            guard response.statusCode == 429,
                  let data, let body: ServiceError = try? data.fromJSON(),
                  let seconds = response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            else {
                return nil
            }
            return RateLimited(message: body.message, wait: .seconds(seconds))
        }

        let error = await thrownError { let _: Board = try await dataFetch.fetch(boardURL) }

        let rateLimited = try #require(error as? RateLimited)
        #expect(rateLimited.message == "Too many requests for this workspace")
        #expect(rateLimited.wait == .seconds(7))
    }

    @Test(arguments: SendPath.allCases)
    func hookIsAskedOnEverySendPath(path: SendPath) async throws {
        let dataFetch = try DataFetch(urlSession: session(statusCode: 409, body: ServiceError.stub())) { _, _ in
            BoardLocked()
        }

        let error = await thrownError { try await path.send(through: dataFetch, to: boardURL) }

        #expect(error is BoardLocked)
    }

    @Test(arguments: SendPath.allCases)
    func standardAppliesOnEverySendPath(path: SendPath) async throws {
        let dataFetch = try DataFetch(urlSession: session(statusCode: 503, retryAfter: "15", body: ServiceError.stub()))

        let error = await thrownError { try await path.send(through: dataFetch, to: boardURL) }

        #expect(wait(in: error) == .seconds(15))
    }

    // MARK: Without a hook, nothing else changes

    @Test func withoutHookSuccessDecodes() async throws {
        let board = Board.stub()
        let dataFetch = try DataFetch(urlSession: session(statusCode: 200, retryAfter: "120", body: board))

        let fetched: Board = try await dataFetch.fetch(boardURL)

        #expect(fetched == board)
    }

    @Test func withoutHookErrorTypeStillDecodes() async throws {
        let dataFetch = try DataFetch(urlSession: session(statusCode: 500, body: ServiceError.stub()))

        let error = await thrownError {
            let _: Board = try await dataFetch.fetch(boardURL, errorType: ServiceError.self)
        }

        #expect(error is ServiceError)
    }

    @Test func withoutHookBadStatusStillThrown() async throws {
        let dataFetch = try DataFetch(urlSession: session(statusCode: 500, body: ServiceError.stub()))

        let error = await thrownError { let _: Board = try await dataFetch.fetch(boardURL) }

        #expect(status(in: error) == 500)
    }

    private let boardURL = URL(string: "https://boards.example.invalid/workspace/board")!
}

// MARK: - Support

extension DataFetchResponseErrorTests {
    struct Board: Codable, Equatable, Stubbable {
        let title: String

        static func stub() -> Self {
            .init(title: "Release planning")
        }
    }

    struct ServiceError: Codable, Error, Stubbable {
        let message: String

        static func stub() -> Self {
            .init(message: "The board could not be updated")
        }
    }

    struct BoardLocked: Error {}

    struct RateLimited: Error {
        let message: String
        let wait: Duration
    }

    enum SendPath: CaseIterable, Sendable {
        case fetch
        case fetchWithErrorType
        case post
        case postWithErrorType
        case delete
        case deleteWithErrorType

        func send(through dataFetch: DataFetch<MockURLSession>, to url: URL) async throws {
            let board = Board.stub()
            let _: Board = switch self {
            case .fetch: try await dataFetch.fetch(url)
            case .fetchWithErrorType: try await dataFetch.fetch(url, errorType: ServiceError.self)
            case .post: try await dataFetch.post(data: board, to: url)
            case .postWithErrorType: try await dataFetch.post(data: board, to: url, errorType: ServiceError.self)
            case .delete: try await dataFetch.delete(data: board, at: url)
            case .deleteWithErrorType: try await dataFetch.delete(data: board, at: url, errorType: ServiceError.self)
            }
        }
    }

    private func session(statusCode: Int, retryAfter: String? = nil, body: (some Encodable)? = Board?.none) throws -> MockURLSession {
        var headers = ["Content-Type": "application/json;charset=utf-8"]
        headers["Retry-After"] = retryAfter

        return try MockURLSession(
            data: body?.toJSONData() ?? Data(),
            error: nil,
            response: HTTPURLResponse(url: boardURL, statusCode: statusCode, httpVersion: nil, headerFields: headers)
        )
    }

    private func thrownError(_ body: () async throws -> Void) async -> (any Error)? {
        do {
            try await body()
            return nil
        } catch {
            return error
        }
    }

    private func wait(in error: (any Error)?) -> Duration? {
        guard case .retryAfter(let wait) = error as? DataFetchError else { return nil }
        return wait
    }

    private func status(in error: (any Error)?) -> Int? {
        guard case .badStatus(let code) = error as? DataFetchError else { return nil }
        return code
    }

    private func httpDate(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
