// StreamingSessionTests.swift
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

// @testable: StreamingSession is internal. Each caller session must map to one streaming session,
// or every reconnect would leak a URLSession that is never released.
#if !os(WASI)
@testable import FOSFoundation
import Foundation
import Testing

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite(.tags(.networking))
struct StreamingSessionTests {
    @Test func oneStreamingSessionPerCallerSession() {
        let caller = URLSession(configuration: .ephemeral)
        let other = URLSession(configuration: .ephemeral)

        #expect(StreamingSession.shared(forwardingTo: caller) === StreamingSession.shared(forwardingTo: caller))
        #expect(StreamingSession.shared(forwardingTo: caller) !== StreamingSession.shared(forwardingTo: other))
    }
}
#endif
