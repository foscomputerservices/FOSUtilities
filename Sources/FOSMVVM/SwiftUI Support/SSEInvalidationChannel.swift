// SSEInvalidationChannel.swift
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

// The default ``InvalidationChannel`` transport (spec §3.2/§6). Darwin-only: swift-corelibs
// FoundationNetworking has no async `URLSession.bytes(for:)`. On every other platform
// (Linux, WASI) `MVVMEnvironment.effectiveInvalidationChannel` degrades to `nil`
// (no channel ⇒ fetch-once semantics, the north-star promise); a custom
// ``InvalidationChannel`` remains the door for those clients.
#if canImport(Darwin)
import FOSFoundation
import Foundation

/// The default Server-Sent-Events transport for live invalidation.
///
/// Consumes `<invalidationBaseURL>/invalidations` as a `text/event-stream`, decoding each `data:`
/// event as a JSON array of ``ModelIdentity`` and yielding `.invalidated`. Emits `.connected` on
/// every (re)open so the dispatcher can sweep; reconnects with exponential back-off after any drop.
struct SSEInvalidationChannel: InvalidationChannel {
    /// Resolves the current-deployment base URL at each open (mirrors the async `serverBaseURL`
    /// resolution; picks up a deployment change without rebuilding the channel).
    private let baseURL: @Sendable () async throws -> URL
    private let credentialProvider: (any ClientCredentialProvider)?
    private let session: URLSession?

    // Reconnect seam — injectable so back-off is deterministically testable (no real sleeping).
    private let sleep: @Sendable (Duration) async -> Void
    private let initialBackoff: Duration
    private let maxBackoff: Duration

    init(
        baseURL: @escaping @Sendable () async throws -> URL,
        credentialProvider: (any ClientCredentialProvider)?,
        session: URLSession?,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        initialBackoff: Duration = .seconds(1),
        maxBackoff: Duration = .seconds(30)
    ) {
        self.baseURL = baseURL
        self.credentialProvider = credentialProvider
        self.session = session
        self.sleep = sleep
        self.initialBackoff = initialBackoff
        self.maxBackoff = maxBackoff
    }

    func events() -> AsyncStream<InvalidationEvent> {
        AsyncStream { continuation in
            // Structured under a single Task the stream owns: consumer cancellation (dispatcher
            // shutdown / last registration gone) fires onTermination, which cancels this task; the
            // in-flight `URLSession.bytes` read and the back-off sleep are both cancellation points,
            // so teardown is prompt.
            let task = Task {
                await Self.runReconnectLoop(
                    yielding: continuation,
                    sleep: sleep,
                    initialBackoff: initialBackoff,
                    maxBackoff: maxBackoff
                ) { continuation, onOpen in
                    try await openAndStream(yielding: continuation, onOpen: onOpen)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The reconnect cornerstone (spec §3.2), factored as the testable unit: it owns back-off and
    /// the `.connected` signal; `streamOnce` performs one open-and-stream and calls `onOpen` the
    /// moment the connection is live (resetting back-off and emitting `.connected`).
    static func runReconnectLoop(
        yielding continuation: AsyncStream<InvalidationEvent>.Continuation,
        sleep: @Sendable (Duration) async -> Void,
        initialBackoff: Duration,
        maxBackoff: Duration,
        streamOnce: (
            _ continuation: AsyncStream<InvalidationEvent>.Continuation,
            _ onOpen: () -> Void
        ) async throws -> Void
    ) async {
        var backoff = initialBackoff
        while !Task.isCancelled {
            do {
                try await streamOnce(continuation) {
                    backoff = initialBackoff
                    continuation.yield(.connected)
                }
            } catch is CancellationError {
                break
            } catch {
                // Any open/stream failure is a drop → reconnect after back-off.
            }
            if Task.isCancelled {
                break
            }
            await sleep(backoff)
            backoff = min(backoff * 2, maxBackoff)
        }
        continuation.finish()
    }

    /// Opens one authenticated stream and pumps parsed events until EOF or failure. Re-consults the
    /// credential provider on every call, so a rotated credential self-heals on reconnect (§3.2).
    private func openAndStream(
        yielding continuation: AsyncStream<InvalidationEvent>.Continuation,
        onOpen: () -> Void
    ) async throws {
        let credentialHeaders = try await credentialProvider?.credentialHeaders() ?? []
        let request = try await Self.makeRequest(baseURL: baseURL(), credentialHeaders: credentialHeaders)
        let session = session ?? .shared

        let (bytes, response) = try await session.bytes(for: request)

        // `bytes(for:)` throws only on transport failure — a 401/404/5xx arrives as a normal
        // response. Signaling open on one would emit a false `.connected` (spurious dispatcher
        // sweep) and reset back-off into a ~1 Hz hot spin against a misconfigured URL or expired
        // credential. Treat non-2xx as a drop: back-off grows, and the next open re-consults the
        // credential provider (rotation still self-heals).
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // A 401 is the credential being refused. Tell the provider so it can refresh and
            // persist; the return is discarded because the reconnect below re-consults
            // `credentialHeaders()` — the channel carries no credential state of its own.
            if http.statusCode == 401 {
                _ = await credentialProvider?.credentialHeaders(
                    afterRejection: CredentialRejectedError(code: .invalid)
                )
            }

            throw SSEStreamOpenError.badStatus(http.statusCode)
        }
        onOpen()

        // Split on `\n` by hand rather than `bytes.lines`: Foundation's `AsyncLineSequence` swallows
        // empty lines, and SSE's event terminator IS the blank line. The parser strips a trailing
        // `\r`, so CRLF framing round-trips.
        var parser = SSEEventParser()
        var lineBytes = [UInt8]()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard byte == UInt8(ascii: "\n") else {
                lineBytes.append(byte)
                continue
            }
            // swiftlint:disable:next optional_data_string_conversion
            let line = String(decoding: lineBytes, as: UTF8.self)
            lineBytes.removeAll(keepingCapacity: true)
            guard let payload = parser.consume(line) else { continue }
            guard let identities = Self.decode(payload) else { continue }
            continuation.yield(.invalidated(identities))
        }
    }

    /// The stream-open request: the frozen §6 `invalidations` path with `Accept: text/event-stream`
    /// and the provider's credential headers. Factored out so header attachment is unit-testable.
    static func makeRequest(baseURL: URL, credentialHeaders: [(field: String, value: String)]) -> URLRequest {
        // FROZEN §6 wire literal — the server keeps its own private copy in
        // FOSMVVMVapor/LiveInvalidation/InvalidationRoute.swift (`InvalidationRoute.pathComponent`).
        // Frozen contracts make this duplication safe; the FOSMVVMVaporTests round-trip locks it
        // end-to-end. Do NOT promote to shared public surface.
        var request = URLRequest(url: baseURL.appending(path: "invalidations"))
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for header in credentialHeaders {
            request.setValue(header.value, forHTTPHeaderField: header.field)
        }
        return request
    }

    /// Decodes one completed event's data payload. A malformed body is skipped (returns `nil`) so a
    /// single bad event never kills the channel — the reconnect sweep would otherwise be needed for
    /// a fault the stream itself survives.
    static func decode(_ payload: String) -> Set<ModelIdentity>? {
        // NEVER a raw JSONDecoder — PL-5; the server framed this with JSONEncoder.defaultEncoder.
        guard let array = try? JSONDecoder.defaultDecoder.decode([ModelIdentity].self, from: Data(payload.utf8)) else {
            return nil
        }
        return Set(array)
    }
}

/// A stream-open that answered non-2xx — treated as a drop by the reconnect loop.
enum SSEStreamOpenError: Error {
    case badStatus(Int)
}

/// Line-oriented Server-Sent-Events reassembly (spec §6, frozen): joins one event's `data:` lines,
/// dispatches on the blank-line terminator, and silently consumes comment lines (`:`-prefixed
/// heartbeats / the open preamble) and any non-`data` field (`id:`/`event:` are ignored defensively,
/// never an error). Tolerates CRLF.
struct SSEEventParser {
    private var dataLines: [String] = []

    /// Feeds one line (the `\n` already removed by the caller's byte splitter; a trailing `\r` may
    /// remain and is stripped here). Returns the completed event's joined data payload on a
    /// blank-line terminator, else `nil`.
    mutating func consume(_ rawLine: String) -> String? {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine

        if line.isEmpty {
            guard !dataLines.isEmpty else { return nil }
            let payload = dataLines.joined(separator: "\n")
            dataLines.removeAll(keepingCapacity: true)
            return payload
        }
        if line.hasPrefix(":") {
            return nil
        }

        let (field, value) = Self.splitField(line)
        if field == "data" {
            dataLines.append(value)
        }
        // id:/event:/retry:/unknown fields — defensively ignored (§6: v1 events are data-only).
        return nil
    }

    /// Splits a `field: value` line on the first colon; a single leading space after the colon is
    /// stripped per the SSE grammar. A colon-less line is a field with an empty value.
    static func splitField(_ line: String) -> (field: String, value: String) {
        guard let colon = line.firstIndex(of: ":") else {
            return (line, "")
        }
        let field = String(line[line.startIndex..<colon])
        var valueStart = line.index(after: colon)
        if valueStart < line.endIndex, line[valueStart] == " " {
            valueStart = line.index(after: valueStart)
        }
        return (field, String(line[valueStart..<line.endIndex]))
    }
}
#endif
