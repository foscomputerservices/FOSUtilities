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
// test group 6). The subject types are Darwin-only (FoundationNetworking lacks
// `URLSession.bytes`), so the suite carries the same guard.
#if canImport(Darwin)
import FOSFoundation
@testable import FOSMVVM
import Foundation
import Testing

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

    /// `.connected` is (re)emitted on every successful open — the dispatcher's sweep trigger.
    @Test func connectedReemittedOnEachReopen() async {
        let connects = await collectConnects(count: 3)
        #expect(connects == 3)
    }
}

// MARK: - Reconnect harness

/// Scripts per-iteration open success for `runReconnectLoop`.
private actor CallScript {
    private let opens: [Bool]
    private var index = 0
    init(_ opens: [Bool]) {
        self.opens = opens
    }

    func nextShouldOpen() -> Bool {
        defer { index += 1 }
        return index < opens.count ? opens[index] : false
    }
}

private struct DropError: Error {}

/// Drives `runReconnectLoop` with a scripted `streamOnce` and a no-sleep clock that records the
/// requested back-off durations, returning the first `count` of them.
private func collectSleeps(
    count: Int,
    opens: [Bool],
    initialBackoff: Duration,
    maxBackoff: Duration
) async -> [Duration] {
    let script = CallScript(opens)
    let (durations, durationsCont) = AsyncStream.makeStream(of: Duration.self)
    let (_, eventsCont) = AsyncStream.makeStream(of: InvalidationEvent.self)

    let loop = Task {
        await SSEInvalidationChannel.runReconnectLoop(
            yielding: eventsCont,
            sleep: { durationsCont.yield($0) },
            initialBackoff: initialBackoff,
            maxBackoff: maxBackoff
        ) { _, onOpen in
            if await script.nextShouldOpen() { onOpen() }
            throw DropError()
        }
    }

    var collected: [Duration] = []
    for await duration in durations {
        collected.append(duration)
        if collected.count == count { break }
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
            sleep: { _ in },
            initialBackoff: .milliseconds(1),
            maxBackoff: .milliseconds(8)
        ) { _, onOpen in
            onOpen()
            throw DropError()
        }
    }

    var connects = 0
    for await event in events {
        if case .connected = event { connects += 1 }
        if connects == count { break }
    }
    loop.cancel()
    eventsCont.finish()
    return connects
}
#endif
