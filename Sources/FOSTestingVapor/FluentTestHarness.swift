// FluentTestHarness.swift
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
import Vapor

/// Runs `body` against a booted Vapor application backed by a fresh in-memory SQLite database.
///
/// Configure the application in `configure` — register containers, add migrations — then use the
/// application and database handed to `body`. The harness runs the migrations, boots, and always
/// shuts the application down:
///
/// ```swift
/// let berths = try await withFluentTestApp { app in
///     try app.register(Dock.self, migration: CreateDock())
///     app.migrations.add(CreateBerth())
/// } _: { app, db in
///     try await Dock(name: "5").save(on: db)
///     return try await Berth.query(on: db).all()
/// }
/// ```
///
/// Each call owns a private database and a full application lifecycle, so tests stay isolated and
/// run safely in parallel.
public func withFluentTestApp<R: Sendable>(
    configure: @Sendable (Application) async throws -> Void,
    _ body: @Sendable (Application, any Database) async throws -> R
) async throws -> R {
    let app = try await Application.make(.testing)
    do {
        app.databases.use(.sqlite(.memory), as: .sqlite)
        try await configure(app)
        try await app.autoMigrate()
        // asyncBoot, not startup()/boot(): async lifecycle handlers only run under async boot,
        // and startup()'s console parser chokes on test-runner arguments (see VaporServerTestCase).
        try await app.asyncBoot()
        let result = try await body(app, app.db)
        try await app.asyncShutdown()
        return result
    } catch {
        try? await app.asyncShutdown()
        throw error
    }
}
#endif
