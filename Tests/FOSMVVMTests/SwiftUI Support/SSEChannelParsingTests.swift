// SSEChannelParsingTests.swift
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

// @testable coverage of the internal default-channel parser and reconnect loop (spec §3.2/§6,
// test group 6). The subject types are not built on WASI, so the suite carries the same guard.
#if !os(WASI)
import FOSFoundation
@testable import FOSMVVM
import Foundation
import Testing

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("SSE default channel — parsing & reconnect (spec §3.2/§6, group 6)")
struct SSEChannelParsingTests {
    // MARK: - Parser

    /// A single `data:` line + blank terminator yields exactly that data payload, which decodes
    /// back to the emitted identity set.
    @Test func dataLineEventRoundTrips() throws {
        let identity = try TestGadget().modelIdentity
        let json = try String(decoding: JSONEncoder.defaultEncoder.encode([identity]), as: UTF8.self)

        var parser = SSEEventParser()
        #expect(parser.consume("data: \(json)") == nil)
        let terminated = parser.consume("")
        let payload = try #require(terminated)
        #expect(payload == json)

        let decoded = try #require(SSEInvalidationChannel.decode(payload))
        #expect(decoded == Set([identity]))
    }

    /// Multiple `data:` lines in one event are joined with `\n` per the SSE grammar.
    @Test func multiDataLineEventJoinsWithNewline() {
        var parser = SSEEventParser()
        #expect(parser.consume("data: line-1") == nil)
        #expect(parser.consume("data: line-2") == nil)
        #expect(parser.consume("") == "line-1\nline-2")
    }

    /// Comment lines (`:`-prefixed heartbeats / the open preamble) are consumed and ignored; only
    /// the real data event surfaces.
    @Test func commentLinesAreIgnored() {
        var parser = SSEEventParser()
        #expect(parser.consume(": open") == nil)
        #expect(parser.consume(": keep-alive") == nil)
        #expect(parser.consume("data: payload") == nil)
        #expect(parser.consume("") == "payload")
    }

    /// A blank line with no accumulated data lines produces nothing (no spurious empty event).
    @Test func blankLineWithoutDataProducesNothing() {
        var parser = SSEEventParser()
        #expect(parser.consume("") == nil)
        #expect(parser.consume("") == nil)
    }

    /// Trailing CR on `data:` and terminator lines is tolerated (CRLF framing).
    @Test func crlfIsTolerated() {
        var parser = SSEEventParser()
        #expect(parser.consume("data: payload\r") == nil)
        #expect(parser.consume("\r") == "payload")
    }

    /// `id:`/`event:` fields are skipped defensively (§6: v1 events are data-only) — never an error.
    @Test func idAndEventFieldsAreSkipped() {
        var parser = SSEEventParser()
        #expect(parser.consume("id: 42") == nil)
        #expect(parser.consume("event: nudge") == nil)
        #expect(parser.consume("data: payload") == nil)
        #expect(parser.consume("") == "payload")
    }

    /// A malformed JSON body decodes to `nil` — the channel skips that event and keeps the stream
    /// alive (it must never kill the channel).
    @Test func malformedJSONIsSkipped() {
        #expect(SSEInvalidationChannel.decode("not-json") == nil)
        #expect(SSEInvalidationChannel.decode("") == nil)
    }

    // MARK: - Reconnect back-off

    /// Failed opens back off exponentially and hold at the cap (no `onOpen` ⇒ no reset).
    @Test func backoffGrowsExponentiallyToCap() async {
        let sleeps = await collectSleeps(
            count: 6,
            opens: Array(repeating: false, count: 8),
            initialBackoff: .milliseconds(1),
            maxBackoff: .milliseconds(8)
        )
        #expect(sleeps == [
            .milliseconds(1), .milliseconds(2), .milliseconds(4),
            .milliseconds(8), .milliseconds(8), .milliseconds(8)
        ])
    }

    /// A successful open resets the back-off: growth resumes from the floor after a live connection
    /// drops.
    @Test func backoffResetsAfterSuccessfulOpen() async {
        // fail, fail, succeed-then-drop, fail, fail
        let sleeps = await collectSleeps(
            count: 5,
            opens: [false, false, true, false, false],
            initialBackoff: .milliseconds(1),
            maxBackoff: .milliseconds(8)
        )
        #expect(sleeps == [
            .milliseconds(1), .milliseconds(2), // growth
            .milliseconds(1), // reset after the successful open
            .milliseconds(2), .milliseconds(4) // growth resumes
        ])
    }

    /// A Retry-After answer holds the reconnect off for at least the server's wait.
    @Test func retryAfterWaitHoldsOffTheReconnect() async {
        let sleeps = await collectSleeps(
            count: 2,
            opens: [false, false],
            retryAfter: [.seconds(120)],
            initialBackoff: .milliseconds(1),
            maxBackoff: .milliseconds(8)
        )
        #expect(sleeps == [.seconds(120), .milliseconds(2)])
    }

    /// A Retry-After wait shorter than the back-off still gets the back-off.
    @Test func retryAfterWaitNeverShortensTheBackoff() async {
        let sleeps = await collectSleeps(
            count: 3,
            opens: [false, false, false],
            retryAfter: [nil, nil, .milliseconds(1)],
            initialBackoff: .milliseconds(1),
            maxBackoff: .milliseconds(8)
        )
        #expect(sleeps == [.milliseconds(1), .milliseconds(2), .milliseconds(4)])
    }

    /// `.connected` is (re)emitted on every successful open — the dispatcher's sweep trigger.
    @Test func connectedReemittedOnEachReopen() async {
        let connects = await collectConnects(count: 3)
        #expect(connects == 3)
    }

    // MARK: - Chunk reassembly

    /// An event split across several body chunks still decodes: a line carries over from one
    /// chunk to the next.
    @Test func eventSplitAcrossChunksIsReassembled() async throws {
        let identity = try TestGadget().modelIdentity
        // swiftlint:disable:next optional_data_string_conversion
        let json = try String(decoding: JSONEncoder.defaultEncoder.encode([identity]), as: UTF8.self)
        let half = json.index(json.startIndex, offsetBy: json.count / 2)
        let host = SplitChunkURLProtocol.serve(chunks: ["data: \(json[..<half])", "\(json[half...])\n", "\n"])

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SplitChunkURLProtocol.self]
        let channel = SSEInvalidationChannel(
            baseURL: { URL(string: "https://\(host)")! },
            credentialProvider: nil,
            session: URLSession(configuration: configuration)
        )

        let invalidated = try await withTimeout(.seconds(10)) {
            for await event in channel.events() {
                if case .invalidated(let identities) = event {
                    return identities
                }
            }
            return Set<ModelIdentity>()
        }

        #expect(invalidated == Set([identity]))
    }
}

// MARK: - Split-chunk server

/// Answers an event stream whose body arrives in separate chunks, a beat apart so the session
/// cannot merge them. Keyed by a host unique to the test so concurrent tests never share state.
private final class SplitChunkURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var bodies: [String: [Data]] = [:]

    static func serve(chunks: [String]) -> String {
        let host = "split-\(UUID().uuidString.lowercased()).invalid"
        lock.withLock { bodies[host] = chunks.map { Data($0.utf8) } }
        return host
    }

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let chunks = Self.lock.withLock({ Self.bodies[url.host ?? ""] }),
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "text/event-stream"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        send(chunks[...])
    }

    /// The response stays open after the last chunk, so the channel never reconnects mid-test.
    fileprivate func send(_ chunks: ArraySlice<Data>) {
        guard let chunk = chunks.first else {
            return
        }
        client?.urlProtocol(self, didLoad: chunk)
        let rest = RemainingChunks(server: self, chunks: chunks.dropFirst())
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(50)) {
            rest.send()
        }
    }

    override func stopLoading() {}
}

/// Carries the chunks still to send to the delayed send; a URLProtocol is not Sendable on Linux.
private final class RemainingChunks: @unchecked Sendable {
    private let server: SplitChunkURLProtocol
    private let chunks: ArraySlice<Data>

    init(server: SplitChunkURLProtocol, chunks: ArraySlice<Data>) {
        self.server = server
        self.chunks = chunks
    }

    func send() {
        server.send(chunks)
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

// MARK: - Reconnect harness

/// Scripts each `runReconnectLoop` attempt: whether it opens, and the Retry-After wait (if any) it
/// then fails with.
private actor CallScript {
    private let opens: [Bool]
    private let retryAfter: [Duration?]
    private var index = 0
    init(_ opens: [Bool], retryAfter: [Duration?]) {
        self.opens = opens
        self.retryAfter = retryAfter
    }

    func next() -> (opens: Bool, retryAfter: Duration?) {
        defer { index += 1 }
        return (
            index < opens.count ? opens[index] : false,
            index < retryAfter.count ? retryAfter[index] : nil
        )
    }
}

private struct DropError: Error {}

/// Drives `runReconnectLoop` with a scripted `streamOnce` and a no-sleep clock that records the
/// requested back-off durations, returning the first `count` of them.
private func collectSleeps(
    count: Int,
    opens: [Bool],
    retryAfter: [Duration?] = [],
    initialBackoff: Duration,
    maxBackoff: Duration
) async -> [Duration] {
    let script = CallScript(opens, retryAfter: retryAfter)
    let (durations, durationsCont) = AsyncStream.makeStream(of: Duration.self)
    let (_, eventsCont) = AsyncStream.makeStream(of: InvalidationEvent.self)

    let loop = Task {
        await SSEInvalidationChannel.runReconnectLoop(
            yielding: eventsCont,
            sleep: {
                durationsCont.yield($0)
                await Task.yield()
            },
            initialBackoff: initialBackoff,
            maxBackoff: maxBackoff
        ) { _, onOpen in
            let attempt = await script.next()
            if attempt.opens {
                onOpen()
            }
            if let wait = attempt.retryAfter {
                throw DataFetchError.retryAfter(wait)
            }
            throw DropError()
        }
    }

    var collected: [Duration] = []
    for await duration in durations {
        collected.append(duration)
        if collected.count == count {
            break
        }
    }
    loop.cancel()
    durationsCont.finish()
    eventsCont.finish()
    return collected
}

/// Drives `runReconnectLoop` with always-succeeding opens, counting the first `count` `.connected`
/// events.
private func collectConnects(count: Int) async -> Int {
    let (events, eventsCont) = AsyncStream.makeStream(of: InvalidationEvent.self)

    let loop = Task {
        await SSEInvalidationChannel.runReconnectLoop(
            yielding: eventsCont,
            sleep: { _ in await Task.yield() },
            initialBackoff: .milliseconds(1),
            maxBackoff: .milliseconds(8)
        ) { _, onOpen in
            onOpen()
            throw DropError()
        }
    }

    var connects = 0
    for await event in events {
        if case .connected = event {
            connects += 1
        }
        if connects == count {
            break
        }
    }
    loop.cancel()
    eventsCont.finish()
    return connects
}
#endif
