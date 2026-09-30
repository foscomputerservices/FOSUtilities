// OffLoopRequest.swift
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

import Fluent
import FOSMVVMVapor
import Foundation
import Vapor

/// A request on an event loop other than `database`'s, so a transaction on `req.db` and a
/// query on `database` never wait on one another.
///
/// SQLite holds ONE connection per event loop: FluentSQLiteDriver builds its pool at one and
/// ignores `maxConnectionsPerEventLoop` on purpose. A handle in a transaction holds its loop's
/// connection, so a second handle bound to the same loop waits until the pool times out.
/// `app.db` binds to a round-robin loop, so a request made on `eventLoopGroup.next()` shares
/// its loop by chance — the intermittent ten-second timeout seen on CI. Pinning the request off
/// the handle's loop makes the two independent by construction.
///
/// Nil on a one-loop group, which cannot host two independent SQLite handles at all.
func makeRequest(_ app: Application, offTheLoopOf database: any Database) -> Vapor.Request? {
    for loop in app.eventLoopGroup.makeIterator() where loop !== database.eventLoop {
        return Vapor.Request(application: app, on: loop)
    }
    return nil
}
