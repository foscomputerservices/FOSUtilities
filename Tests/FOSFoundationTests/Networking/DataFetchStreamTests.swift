// DataFetchStreamTests.swift
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

#if !os(WASI)
import FOSFoundation
import Foundation
import Testing

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite(.tags(.networking))
struct DataFetchStreamTests {
    @Test func bodyArrivesInOrder() async throws {
        let server = StreamScript(chunks: ["data: one\n\n", "data: two\n\n"])

        let chunks = try await server.dataFetch().openStream(from: server.url, headers: eventStream, locale: nil)
        let received = try await withTimeout(.seconds(10)) { try await collect(chunks) }

        #expect(received.joined() == "data: one\n\ndata: two\n\n")
    }

    @Test func requestCarriesTheHeadersSendSends() async throws {
        let server = StreamScript(chunks: [])

        let chunks = try await server.dataFetch().openStream(
            from: server.url,
            headers: [
                (field: "Accept", value: "text/event-stream"),
                (field: "Authorization", value: "Bearer token")
            ],
            locale: Locale(identifier: "fr")
        )
        _ = try await withTimeout(.seconds(10)) { try await collect(chunks) }

        let request = try #require(server.receivedRequest)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        #expect(request.value(forHTTPHeaderField: "Accept-Language") == "fr")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json;charset=utf-8")
        #expect(request.value(forHTTPHeaderField: "Accept-Encoding") == "deflate, gzip, *")
    }

    @Test func nonSuccessStatusThrowsBadStatus() async {
        let server = StreamScript(statusCode: 401, chunks: [])

        let error = await thrownError {
            _ = try await server.dataFetch().openStream(from: server.url, headers: nil, locale: nil)
        }

        guard case .badStatus(httpStatusCode: 401)? = error as? DataFetchError else {
            Issue.record("Expected badStatus(401), got \(String(describing: error))")
            return
        }
    }

    @Test func failedCheckEndsTheRequest() async throws {
        let server = StreamScript(statusCode: 503, chunks: ["data: one\n\n"], staysOpen: true)

        let error = await thrownError {
            _ = try await server.dataFetch().openStream(from: server.url, headers: eventStream, locale: nil)
        }

        guard case .badStatus(httpStatusCode: 503)? = error as? DataFetchError else {
            Issue.record("Expected badStatus(503), got \(String(describing: error))")
            return
        }
        try await withTimeout(.seconds(10)) { try await server.waitUntilStopped() }
    }

    @Test func retryAfterAnswerThrowsRetryAfter() async {
        let server = StreamScript(statusCode: 503, retryAfter: "120", chunks: [])

        let error = await thrownError {
            _ = try await server.dataFetch().openStream(from: server.url, headers: eventStream, locale: nil)
        }

        guard case .retryAfter(let wait)? = error as? DataFetchError else {
            Issue.record("Expected retryAfter, got \(String(describing: error))")
            return
        }
        #expect(wait == .seconds(120))
    }

    @Test func answerOfAnotherMediaTypeThrows() async {
        let server = StreamScript(contentType: "text/html", chunks: ["<html>"])

        let error = await thrownError {
            _ = try await server.dataFetch().openStream(
                from: server.url,
                headers: [(field: "Accept", value: "text/event-stream")],
                locale: nil
            )
        }

        guard case .badResponseMimeType? = error as? DataFetchError else {
            Issue.record("Expected badResponseMimeType, got \(String(describing: error))")
            return
        }
    }

    @Test func unreachableServerThrowsTheTransportError() async {
        let server = StreamScript(answers: false, chunks: [])

        let error = await thrownError {
            _ = try await server.dataFetch().openStream(from: server.url, headers: eventStream, locale: nil)
        }

        #expect((error as? URLError)?.code == .cannotConnectToHost)
    }

    @Test func connectionLostMidBodyThrowsFromTheStream() async throws {
        let server = StreamScript(chunks: ["data: one\n\n"], failsAfterChunks: URLError(.networkConnectionLost))
        let chunks = try await server.dataFetch().openStream(from: server.url, headers: eventStream, locale: nil)

        let error = await thrownError { _ = try await collect(chunks) }

        #expect((error as? URLError)?.code == .networkConnectionLost)
    }

    @Test func cancellingTheReaderEndsTheRequest() async throws {
        let server = StreamScript(chunks: ["data: one\n\n"], staysOpen: true)
        let chunks = try await server.dataFetch().openStream(from: server.url, headers: eventStream, locale: nil)

        let reader = Task {
            for try await _ in chunks {}
        }
        try await withTimeout(.seconds(10)) { try await server.waitUntilFirstChunkSent() }
        reader.cancel()

        try await withTimeout(.seconds(10)) { try await server.waitUntilStopped() }
    }

    @Test func cancellingTheOpenerThrowsCancellationError() async throws {
        let server = StreamScript(withholdsResponse: true, chunks: [])
        let dataFetch = server.dataFetch()
        let url = server.url

        let opener = Task {
            try await dataFetch.openStream(from: url, headers: eventStream, locale: nil)
        }
        try await withTimeout(.seconds(10)) { try await server.waitUntilRequested() }
        opener.cancel()

        let result = await opener.result
        #expect(throws: CancellationError.self) { try result.get() }
        try await withTimeout(.seconds(10)) { try await server.waitUntilStopped() }
    }

    @Test func callerSessionDelegateAnswersChallenges() async {
        let server = StreamScript(chunks: ["data: one\n\n"], challenge: NSURLAuthenticationMethodHTTPBasic)
        let delegate = RefusingDelegate()
        let session = URLSession(configuration: server.configuration, delegate: delegate, delegateQueue: nil)

        let error = await thrownError {
            _ = try await DataFetch(urlSession: session).openStream(from: server.url, headers: eventStream, locale: nil)
        }

        #expect(error != nil)
        #expect(!(error is CancellationError))
        #expect(delegate.challengeMethods == [NSURLAuthenticationMethodHTTPBasic])
    }

    // Server trust (and so pinning) exists only where the Security framework does.
    #if canImport(Security)
    @Test func callerSessionDelegateAnswersServerTrust() async {
        let server = StreamScript(chunks: ["data: one\n\n"], challenge: NSURLAuthenticationMethodServerTrust)
        let delegate = RefusingDelegate()
        let session = URLSession(configuration: server.configuration, delegate: delegate, delegateQueue: nil)

        let error = await thrownError {
            _ = try await DataFetch(urlSession: session).openStream(from: server.url, headers: eventStream, locale: nil)
        }

        #expect(error != nil)
        #expect(delegate.challengeMethods == [NSURLAuthenticationMethodServerTrust])
    }
    #endif

    @Test func callerTaskDelegateAnswersChallenges() async {
        let server = StreamScript(chunks: ["data: one\n\n"], challenge: NSURLAuthenticationMethodHTTPBasic)
        let delegate = TaskLevelRefusingDelegate()
        let session = URLSession(configuration: server.configuration, delegate: delegate, delegateQueue: nil)

        let error = await thrownError {
            _ = try await DataFetch(urlSession: session).openStream(from: server.url, headers: eventStream, locale: nil)
        }

        #expect(error != nil)
        #expect(delegate.taskLevelCount == 1)
        #expect(delegate.sessionLevelCount == 0)
    }

    // These two need the stub to proceed past its challenge. FoundationNetworking only honours a
    // refusal of a URLProtocol-raised challenge: given a credential it re-sends the request over
    // the network, and given default handling it ends the task with no response.
    #if !canImport(FoundationNetworking)
    @Test func sessionWithoutDelegateGetsDefaultHandling() async throws {
        let server = StreamScript(chunks: ["data: one\n\n"], challenge: NSURLAuthenticationMethodHTTPBasic)

        let chunks = try await server.dataFetch().openStream(from: server.url, headers: eventStream, locale: nil)
        let received = try await withTimeout(.seconds(10)) { try await collect(chunks) }

        #expect(received.joined() == "data: one\n\n")
    }

    @Test func invalidatedSessionThatHadADelegateRefusesChallenges() async throws {
        let server = StreamScript(chunks: ["data: one\n\n"], challenge: NSURLAuthenticationMethodHTTPBasic)
        let session = URLSession(configuration: server.configuration, delegate: AcceptingDelegate(), delegateQueue: nil)
        let dataFetch = DataFetch(urlSession: session)

        let first = try await dataFetch.openStream(from: server.url, headers: eventStream, locale: nil)
        _ = try await withTimeout(.seconds(10)) { try await collect(first) }
        session.invalidateAndCancel()

        let error = await thrownError {
            _ = try await dataFetch.openStream(from: server.url, headers: eventStream, locale: nil)
        }

        #expect(error != nil)
    }
    #endif
}

@Suite(.tags(.networking))
struct DataFetchSendRequestTests {
    @Test func sendCarriesItsBody() async throws {
        let server = StreamScript(contentType: "application/json", chunks: ["{}"])
        let body = Data(#"{"name":"Board"}"#.utf8)

        let _: [String: String] = try await server.dataFetch().send(
            data: body,
            to: server.url,
            httpMethod: "POST",
            headers: nil,
            locale: nil
        )

        #expect(server.receivedRequest?.httpMethod == "POST")
        #expect(server.receivedBody == body)
    }
}

// MARK: - Scripted streaming server

/// One scripted answer, keyed by a host unique to the test so concurrent tests never share state.
private final class StreamScript: Sendable {
    let url: URL
    private let host: String

    init(
        statusCode: Int = 200,
        contentType: String = "text/event-stream",
        retryAfter: String? = nil,
        answers: Bool = true,
        withholdsResponse: Bool = false,
        chunks: [String],
        staysOpen: Bool = false,
        failsAfterChunks: URLError? = nil,
        challenge: String? = nil
    ) {
        let host = "stream-\(UUID().uuidString.lowercased()).invalid"
        self.host = host
        self.url = URL(string: "https://\(host)/invalidations")!
        guard answers else {
            return
        }
        StreamingURLProtocol.setAnswer(
            .init(
                statusCode: statusCode,
                contentType: contentType,
                retryAfter: retryAfter,
                withholdsResponse: withholdsResponse,
                chunks: chunks.map { Data($0.utf8) },
                staysOpen: staysOpen,
                failsAfterChunks: failsAfterChunks,
                challenge: challenge
            ),
            for: host
        )
    }

    var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamingURLProtocol.self]
        return configuration
    }

    func dataFetch() -> DataFetch<URLSession> {
        DataFetch(urlSession: URLSession(configuration: configuration))
    }

    var receivedRequest: URLRequest? {
        StreamingURLProtocol.state(for: host).request
    }

    var receivedBody: Data? {
        StreamingURLProtocol.state(for: host).body
    }

    func waitUntilRequested() async throws {
        while StreamingURLProtocol.state(for: host).request == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func waitUntilFirstChunkSent() async throws {
        while !StreamingURLProtocol.state(for: host).sentChunk {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func waitUntilStopped() async throws {
        while !StreamingURLProtocol.state(for: host).stopped {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private final class StreamingURLProtocol: URLProtocol {
    struct Answer {
        let statusCode: Int
        let contentType: String
        let retryAfter: String?
        let withholdsResponse: Bool
        let chunks: [Data]
        let staysOpen: Bool
        let failsAfterChunks: URLError?
        let challenge: String?
    }

    struct State {
        var request: URLRequest?
        var body: Data?
        var sentChunk = false
        var stopped = false
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var answers: [String: Answer] = [:]
    private nonisolated(unsafe) static var states: [String: State] = [:]

    static func setAnswer(_ answer: Answer, for host: String) {
        lock.withLock { answers[host] = answer }
    }

    static func state(for host: String) -> State {
        lock.withLock { states[host] ?? State() }
    }

    private static func update(_ host: String, _ change: (inout State) -> Void) {
        lock.withLock { change(&states[host, default: State()]) }
    }

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    private var host: String {
        request.url?.host ?? ""
    }

    override func startLoading() {
        let host = host
        let body = request.httpBody ?? request.httpBodyStream.map(Self.readAll)
        Self.update(host) {
            $0.request = request
            $0.body = body
        }
        guard let answer = Self.lock.withLock({ Self.answers[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }

        if let method = answer.challenge {
            let space = URLProtectionSpace(
                host: host,
                port: 443,
                protocol: "https",
                realm: "stream",
                authenticationMethod: method
            )
            let challenge = URLAuthenticationChallenge(
                protectionSpace: space,
                proposedCredential: nil,
                previousFailureCount: 0,
                failureResponse: nil,
                error: nil,
                sender: ChallengeSender(answering: self)
            )
            client?.urlProtocol(self, didReceive: challenge)
            return
        }
        answerRequest(answer)
    }

    override func stopLoading() {
        Self.update(host) { $0.stopped = true }
    }

    private func answerRequest(_ answer: Answer) {
        guard !answer.withholdsResponse else {
            return
        }
        guard let url = request.url, let response = HTTPURLResponse(
            url: url,
            statusCode: answer.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": answer.contentType].merging(
                answer.retryAfter.map { ["Retry-After": $0] } ?? [:]
            ) { current, _ in current }
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotParseResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in answer.chunks {
            client?.urlProtocol(self, didLoad: chunk)
            Self.update(host) { $0.sentChunk = true }
        }
        if let failure = answer.failsAfterChunks {
            client?.urlProtocol(self, didFailWithError: failure)
        } else if !answer.staysOpen {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    func proceedAfterChallenge() {
        if let answer = Self.lock.withLock({ Self.answers[host] }) {
            answerRequest(answer)
        }
    }

    func failAfterChallenge(_ error: URLError) {
        client?.urlProtocol(self, didFailWithError: error)
    }

    private static func readAll(_ stream: InputStream) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        stream.open()
        defer { stream.close() }
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// Carries the caller's answer to a challenge back to the scripted server. Default handling
/// proceeds, as default trust would for a server with a valid certificate.
private final class ChallengeSender: NSObject, URLAuthenticationChallengeSender, @unchecked Sendable {
    private let server: StreamingURLProtocol

    init(answering server: StreamingURLProtocol) {
        self.server = server
    }

    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {
        server.proceedAfterChallenge()
    }

    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {
        server.failAfterChallenge(URLError(.userAuthenticationRequired))
    }

    func cancel(_ challenge: URLAuthenticationChallenge) {
        server.failAfterChallenge(URLError(.userCancelledAuthentication))
    }

    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {
        server.proceedAfterChallenge()
    }

    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {
        continueWithoutCredential(for: challenge)
    }
}

/// A caller's session delegate that refuses every challenge and records each one's method.
private final class RefusingDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var methods = [String]()

    var challengeMethods: [String] {
        lock.withLock { methods }
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        lock.withLock { methods.append(challenge.protectionSpace.authenticationMethod) }
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}

/// A caller's delegate with both challenge handlers, refusing each and counting which one ran.
private final class TaskLevelRefusingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var taskLevel = 0
    private var sessionLevel = 0

    var taskLevelCount: Int {
        lock.withLock { taskLevel }
    }

    var sessionLevelCount: Int {
        lock.withLock { sessionLevel }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        lock.withLock { taskLevel += 1 }
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        lock.withLock { sessionLevel += 1 }
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}

/// A caller's session delegate that accepts every challenge, standing in for a pinning delegate
/// whose pin matches.
private final class AcceptingDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(.useCredential, URLCredential(user: "stream", password: "stream", persistence: .none))
    }
}

// MARK: - Helpers

private let eventStream = [(field: "Accept", value: "text/event-stream")]

private func collect(_ chunks: AsyncThrowingStream<Data, any Error>) async throws -> [String] {
    var received = [String]()
    for try await chunk in chunks {
        // swiftlint:disable:next optional_data_string_conversion
        received.append(String(decoding: chunk, as: UTF8.self))
    }
    return received
}

private func thrownError(_ operation: @escaping @Sendable () async throws -> Void) async -> (any Error)? {
    do {
        try await withTimeout(.seconds(10), operation)
        return nil
    } catch {
        return error
    }
}

private struct TimeoutError: Error {}

/// Races `operation` against a deadline so no stream read can hang the suite.
private func withTimeout<T: Sendable>(
    _ duration: Duration,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw TimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
#endif
