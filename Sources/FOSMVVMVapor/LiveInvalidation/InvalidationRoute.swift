// InvalidationRoute.swift
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
import NIOCore
import Vapor

extension Vapor.Application {
    /// Mounts the SSE endpoint on the passed group (spec §3.2/§6): `GET <group>/invalidations`,
    /// `text/event-stream`, one `data:` event per hub emission, comment-line heartbeats between
    /// events. No auth here — the group carries whatever middleware the app hung it on.
    func mountInvalidationStream(on routes: any RoutesBuilder, hub: InvalidationHub) {
        routes.get(InvalidationRoute.pathComponent) { req -> Response in
            let subscription = await hub.subscribe()
            let heartbeat = req.application.invalidationHeartbeatInterval

            var headers = HTTPHeaders()
            headers.contentType = HTTPMediaType(type: "text", subType: "event-stream")
            headers.replaceOrAdd(name: .cacheControl, value: "no-cache")

            let logger = req.logger
            let body = Response.Body(asyncStream: { writer in
                await InvalidationRoute.pump(
                    subscription,
                    heartbeat: heartbeat,
                    to: writer,
                    logger: logger
                )
            })
            return Response(status: .ok, headers: headers, body: body)
        }
    }

    /// The SSE heartbeat interval — comment lines emitted on an idle stream so intermediaries don't
    /// cut it (spec §3.2). Internal-only override: tests shorten it; no public surface.
    var invalidationHeartbeatInterval: Duration {
        get { storage[InvalidationHeartbeatIntervalKey.self] ?? InvalidationRoute.defaultHeartbeatInterval }
        set { storage[InvalidationHeartbeatIntervalKey.self] = newValue }
    }
}

private struct InvalidationHeartbeatIntervalKey: StorageKey {
    typealias Value = Duration
}

/// The wire-framing and pump for one connected SSE client (spec §6, frozen): `data:`-only events
/// carrying a JSON array of ``ModelIdentity`` via `JSONEncoder.defaultEncoder`, comment-line
/// heartbeats, no `id:`/`event:` fields.
private enum InvalidationRoute {
    static let pathComponent: PathComponent = "invalidations"
    static let defaultHeartbeatInterval: Duration = .seconds(15)

    /// One connected client's feed: a single consumer serializes every write, selecting between the
    /// next hub emission and a heartbeat deadline (merged into one stream so the two producers never
    /// race on the writer). Ends the client stream cleanly when the hub terminates the subscription
    /// (overflow) or a write fails (client disconnect).
    static func pump(
        _ subscription: AsyncStream<Set<ModelIdentity>>,
        heartbeat: Duration,
        to writer: any AsyncBodyStreamWriter,
        logger: Logger
    ) async {
        // Unbounded by design: heartbeat ticks can accumulate here on a wedged, emission-less
        // connection until the next blocked write throws (bounded in practice by the write failing).
        let merged = AsyncStream<Tick> { continuation in
            let hubTask = Task {
                for await identities in subscription {
                    continuation.yield(.event(identities))
                }
                continuation.yield(.hubEnded)
                continuation.finish()
            }
            let heartbeatTask = Task {
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: heartbeat)
                    } catch {
                        break
                    }
                    continuation.yield(.heartbeat)
                }
            }
            // The SOLE reaper of both producer tasks — fires when the consumer drops the stream
            // (client gone, pump returned) or the stream finishes. Without it a heartbeat task
            // would outlive its connection.
            continuation.onTermination = { _ in
                hubTask.cancel()
                heartbeatTask.cancel()
            }
        }

        do {
            // Open the stream immediately so the client receives response headers without waiting
            // for the first event or heartbeat (the server flushes the head with the first body
            // byte). A comment line is inert to SSE consumers.
            try await writer.write(.buffer(ByteBuffer(string: ": open\n\n")))

            consume: for await tick in merged {
                switch tick {
                case .event(let identities):
                    let frame: ByteBuffer
                    do {
                        frame = try dataFrame(identities)
                    } catch {
                        // A frame that cannot encode is a bug, not a disconnect — surface it, then
                        // end the stream so the client's reconnect sweep covers the missed nudge.
                        logger.error("Live invalidation: failed to encode an identity set — ending this client's stream. \(String(reflecting: error))")
                        break consume
                    }
                    try await writer.write(.buffer(frame))
                case .heartbeat:
                    try await writer.write(.buffer(ByteBuffer(string: ": keep-alive\n\n")))
                case .hubEnded:
                    break consume
                }
            }
            try await writer.write(.end)
        } catch {
            // Client disconnected mid-write: end the stream.
            try? await writer.write(.end)
        }
    }

    /// `data: <JSON array of ModelIdentity>\n\n` — the frozen §6 frame.
    static func dataFrame(_ identities: Set<ModelIdentity>) throws -> ByteBuffer {
        let json = try JSONEncoder.defaultEncoder.encode(Array(identities))
        var buffer = ByteBuffer(string: "data: ")
        buffer.writeBytes(json)
        buffer.writeString("\n\n")
        return buffer
    }

    private enum Tick: Sendable {
        case event(Set<ModelIdentity>)
        case heartbeat
        case hubEnded
    }
}
