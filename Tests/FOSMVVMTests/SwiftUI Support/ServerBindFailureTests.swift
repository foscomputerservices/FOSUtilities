// ServerBindFailureTests.swift
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

#if canImport(SwiftUI)
@testable import FOSMVVM
import Foundation
import SwiftUI
import Testing

// Each `bind(error:)` ruling gets a test, driven through the seams the server resolver forwards to:
// `ServerBindFailure` (failure routing + retry decision), `AsyncTaskEngine` (the `task(error:)`
// rules), `MVVMEnvironment`'s loading-view storage and `ServerBindDiagnostic`. The resolver's
// wiring is tested hosted, in `ServerBindHostedTests`.

@MainActor
struct ServerBindFailureTests {
    // MARK: Failure routing

    @Test func failure_landsInStateAndCallerBinding() async {
        let failure = ValueBox<Error?>(nil)
        let delivered = ValueBox<Bool>(false)
        let caller = ValueBox<Error?>(nil)

        await AsyncTaskEngine.run(
            error: ServerBindFailure.binding(failure: failure.binding, delivered: delivered.binding, caller: caller.binding)
        ) { throw TestLoadError.unreachable }

        #expect(failure.value as? TestLoadError == .unreachable)
        #expect(caller.value as? TestLoadError == .unreachable)
    }

    @Test func failure_withoutCallerBinding_stillReachesTheLoadingView() async {
        let failure = ValueBox<Error?>(nil)
        let delivered = ValueBox<Bool>(false)

        await AsyncTaskEngine.run(
            error: ServerBindFailure.binding(failure: failure.binding, delivered: delivered.binding, caller: nil)
        ) { throw TestLoadError.unreachable }

        #expect(failure.value as? TestLoadError == .unreachable)
    }

    @Test func launch_clearsBoth() async {
        let failure = ValueBox<Error?>(TestLoadError.previous)
        let delivered = ValueBox<Bool>(false)
        let caller = ValueBox<Error?>(TestLoadError.previous)

        await AsyncTaskEngine.run(
            error: ServerBindFailure.binding(failure: failure.binding, delivered: delivered.binding, caller: caller.binding)
        ) {}

        #expect(failure.value == nil)
        #expect(caller.value == nil)
    }

    @Test func cancelledLoad_writesNeither() async {
        let failure = ValueBox<Error?>(nil)
        let delivered = ValueBox<Bool>(false)
        let caller = ValueBox<Error?>(nil)
        let started = Gate()

        let load = Task { @MainActor in
            await AsyncTaskEngine.run(
                error: ServerBindFailure.binding(failure: failure.binding, delivered: delivered.binding, caller: caller.binding)
            ) {
                await started.open()
                try await Task.sleep(for: .seconds(600))
            }
        }

        await started.wait()
        load.cancel()
        await load.value

        #expect(failure.value == nil)
        #expect(caller.value == nil)
    }

    // MARK: Clear-to-re-fetch

    @Test func failure_isDelivered_whenTheCallerKeepsIt() async {
        let failure = ValueBox<Error?>(nil)
        let delivered = ValueBox<Bool>(false)
        let caller = ValueBox<Error?>(nil)

        await AsyncTaskEngine.run(
            error: ServerBindFailure.binding(failure: failure.binding, delivered: delivered.binding, caller: caller.binding)
        ) { throw TestLoadError.unreachable }

        #expect(delivered.value)
    }

    @Test func failure_isNotDelivered_toABindingThatDropsWrites() async {
        let failure = ValueBox<Error?>(nil)
        let delivered = ValueBox<Bool>(false)

        await AsyncTaskEngine.run(
            error: ServerBindFailure.binding(failure: failure.binding, delivered: delivered.binding, caller: .constant(nil))
        ) { throw TestLoadError.unreachable }

        #expect(failure.value as? TestLoadError == .unreachable)
        #expect(!delivered.value)
    }

    @Test func callerEmptyingADeliveredFailure_requestsARetry() {
        #expect(ServerBindFailure.retryRequested(
            delivered: true,
            callerError: nil,
            failure: TestLoadError.unreachable
        ))
    }

    @Test func failureStillInTheCallersBinding_isNoRetry() {
        #expect(!ServerBindFailure.retryRequested(
            delivered: true,
            callerError: TestLoadError.unreachable,
            failure: TestLoadError.unreachable
        ))
    }

    @Test func noFailureShowing_isNoRetry() {
        // Starting an attempt clears `failure`, which ends the request it answered
        #expect(!ServerBindFailure.retryRequested(delivered: false, callerError: nil, failure: nil))
    }

    @Test func undeliveredFailure_isNoRetry() {
        // No binding, or one that drops writes (`.constant(nil)`): retrying would loop
        #expect(!ServerBindFailure.retryRequested(
            delivered: false,
            callerError: nil,
            failure: TestLoadError.unreachable
        ))
    }

    // MARK: App-wide loading view

    @Test func appLoadingView_receivesTheError() {
        let received = LockedRecorder<Error?>()
        let stored = MVVMEnvironment.erasedLoadingView { error in
            received.record(error)
            return Text("Loading")
        }

        _ = stored(nil)
        _ = stored(TestLoadError.unreachable)

        #expect(received.values.count == 2)
        #expect(received.values[0] == nil)
        #expect(received.values[1] as? TestLoadError == .unreachable)
    }

    @Test func defaultLoadingView_acceptsAnError() {
        _ = MVVMEnvironment.defaultLoadingView(nil)
        _ = MVVMEnvironment.defaultLoadingView(TestLoadError.unreachable)
    }

    // MARK: Client-hosted ViewModel on the server path

    @Test func serverHostedViewModel_passes() {
        #expect(ServerBindDiagnostic.clientHostedBoundAsServer(
            TestViewModel.self,
            view: ServerProbeView.self
        ) == nil)
    }

    @Test func clientHostedViewModel_isStopped_namingTheFix() throws {
        let message = try #require(ServerBindDiagnostic.clientHostedBoundAsServer(
            TestClientHostedViewModel.self,
            view: ClientProbeView.self
        ))

        #expect(message.contains("TestClientHostedViewModel"))
        #expect(message.contains("ClientProbeView"))
        #expect(message.contains("appState:"))
        #expect(message.contains("error:"))
        #expect(message.contains("loadingView:"))
    }

    @Test func clientHostedViewModel_failsTheLoadWithTheSameMessage() throws {
        let failure = try #require(ServerBindDiagnostic.clientHostedFailure(
            TestClientHostedViewModel.self,
            view: ClientProbeView.self
        ))
        let message = try #require(ServerBindDiagnostic.clientHostedBoundAsServer(
            TestClientHostedViewModel.self,
            view: ClientProbeView.self
        ))

        #expect(failure.diagnostic == message)
        // What an alert shows a user is not the developer banner
        #expect(!failure.debugDescription.contains("FOSMVVM"))
    }

    @Test func clientHostedMisuse_isNeverRetried() throws {
        let failure = try #require(ServerBindDiagnostic.clientHostedFailure(
            TestClientHostedViewModel.self,
            view: ClientProbeView.self
        ))

        #expect(!ServerBindFailure.retryRequested(delivered: true, callerError: nil, failure: failure))
    }

    @Test func serverHostedViewModel_hasNoLoadFailure() {
        #expect(ServerBindDiagnostic.clientHostedFailure(TestViewModel.self, view: ServerProbeView.self) == nil)
    }

    // MARK: Public surface (compiles)

    @Test func overloads_construct() {
        let error = Binding<Error?>.constant(nil)

        _ = ServerProbeView.bind(query: .init(id: 1), error: error)
        _ = ServerProbeView.bind(query: .init(id: 1)) { _ in Text("Loading") }
        _ = ServerProbeView.bind(query: .init(id: 1), error: error) { _ in Text("Loading") }
        _ = EmptyQueryProbeView.bind(error: error)
        _ = EmptyQueryProbeView.bind { _ in Text("Loading") }
        _ = EmptyQueryProbeView.bind(error: error) { error in
            if error != nil {
                Text("Can't reach the server")
            } else {
                ProgressView()
            }
        }
    }
}

// MARK: - Test Support

private struct ServerProbeView: ViewModelView {
    let viewModel: TestViewModel
    var body: some View {
        EmptyView()
    }
}

private struct EmptyQueryProbeView: ViewModelView {
    let viewModel: TestVersionedViewModel
    var body: some View {
        EmptyView()
    }
}

private struct ClientProbeView: ViewModelView {
    let viewModel: TestClientHostedViewModel
    var body: some View {
        EmptyView()
    }
}

private enum TestLoadError: Error, Equatable {
    case previous
    case unreachable
}

@MainActor
private final class ValueBox<V> {
    var value: V

    var binding: Binding<V> {
        Binding(
            get: { self.value },
            set: { self.value = $0 }
        )
    }

    init(_ value: V) {
        self.value = value
    }
}

@MainActor
private final class Gate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func open() {
        isOpen = true
        continuations.forEach { $0.resume() }
        continuations.removeAll()
    }

    func wait() async {
        if isOpen {
            return
        }
        await withCheckedContinuation { continuations.append($0) }
    }
}
#endif
