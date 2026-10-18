// ServedFluentTestHarness.swift
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

#if canImport(FOSMVVMVapor)
import Fluent
import FluentKit
import FluentSQLiteDriver
import Foundation
import Vapor

/// Runs `body` against a booted Vapor application that is **listening on a real localhost port**,
/// backed by a fresh in-memory SQLite database.
///
/// Reach for this when a test must exercise a genuine HTTP connection — a streaming response, an
/// SSE feed — that `app.test(...)` cannot hold open. Configure the application in `configure`, then
/// use the application and the base `URL` handed to `body` to open a live socket to it:
///
/// ```swift
/// try await withServedFluentTestApp { app in
///     app.get("ticks") { _ in
///         Response(body: .init(asyncStream: { writer in
///             try await writer.write(.buffer(ByteBuffer(string: "tick\n")))
///             try await writer.write(.end)
///         }))
///     }
/// } _: { app, baseURL in
///     let url = baseURL.appending(path: "ticks")
///     let (bytes, _) = try await URLSession(configuration: .ephemeral).bytes(from: url)
///     for try await line in bytes.lines {
///         #expect(line == "tick")
///     }
/// }
/// ```
///
/// The harness binds the HTTP server to `127.0.0.1` on an ephemeral port (`port 0`) and hands
/// `body` `http://127.0.0.1:<bound-port>`. Each call owns a private database, a bound port, and a
/// full application lifecycle — server and application are always shut down — so tests stay isolated
/// and run safely in parallel.
///
/// Teardown runs in a served app's order: the application's lifecycle handlers shut down before the
/// server stops, so a handler that ends open streams (live invalidation does) keeps the stop prompt.
public func withServedFluentTestApp<R: Sendable>(
    configure: @Sendable (Application) async throws -> Void,
    _ body: @Sendable (Application, URL) async throws -> R
) async throws -> R {
    let app = try await Application.make(.testing)
    // Teardown discipline: the server is shut down only after a successful start, and each
    // shutdown runs at most once — a happy-path asyncShutdown() throw must not be retried by
    // the catch (Vapor asserts on double shutdown). The server is held here because
    // asyncShutdown() clears the storage `app.server` reads.
    var startedServer: (any Server)?
    var appShutDown = false
    do {
        app.databases.use(.sqlite(.memory), as: .sqlite)
        try await configure(app)
        try await app.autoMigrate()

        app.http.server.configuration.hostname = "127.0.0.1"
        app.http.server.configuration.port = 0

        // asyncBoot (not startup()): async lifecycle handlers only run under async boot, and
        // startup()'s console parser chokes on test-runner arguments (see FluentTestHarness).
        try await app.asyncBoot()
        let server = app.server
        try server.start()
        startedServer = server

        guard let port = app.http.server.shared.localAddress?.port,
              let baseURL = URL(string: "http://127.0.0.1:\(port)") else {
            throw ServedFluentTestHarnessError.noBoundPort
        }

        let result = try await body(app, baseURL)

        appShutDown = true
        let appShutdownError: (any Error)?
        do {
            try await app.asyncShutdown()
            appShutdownError = nil
        } catch {
            appShutdownError = error
        }
        await server.shutdown()
        startedServer = nil
        if let appShutdownError {
            throw appShutdownError
        }
        return result
    } catch {
        if !appShutDown {
            try? await app.asyncShutdown()
        }
        await startedServer?.shutdown()
        throw error
    }
}

enum ServedFluentTestHarnessError: Error, CustomDebugStringConvertible {
    case noBoundPort

    var debugDescription: String {
        switch self {
        case .noBoundPort:
            "withServedFluentTestApp: the HTTP server started but reported no bound local port."
        }
    }
}
#endif
