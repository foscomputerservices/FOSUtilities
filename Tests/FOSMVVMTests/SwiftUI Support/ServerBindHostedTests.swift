// ServerBindHostedTests.swift
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

#if os(macOS)
import AppKit
import FOSFoundation
@testable import FOSMVVM
import Foundation
import Observation
import SwiftUI
import Testing

// The server resolver's wiring, driven by hosting a bound view in a window. Every fetch is answered
// by `FailingRequestCounter`, which fails it and counts it per test.
//
// Not reachable here: the client-hosted stop (`reportAndStop` traps), and a successful fetch,
// which would need a version-stamped ViewModel response.

@MainActor
@Suite(.systemVersionAccess)
struct ServerBindHostedTests {
    @Test func bindLoadingView_takesPrecedenceOverTheEnvironments() async throws {
        let harness = try Harness()
        defer { harness.close() }

        try await harness.host { model in
            ProbeView.bind(error: model.binding) { error in
                harness.bindLoadingView.record(error)
                return Text("bind")
            }
        }

        await harness.waitUntil { harness.bindLoadingView.sawError }
        #expect(harness.environmentLoadingView.values.isEmpty)
    }

    @Test func environmentLoadingView_isShown_andReceivesTheFailure() async throws {
        let harness = try Harness()
        defer { harness.close() }

        try await harness.host { model in
            ProbeView.bind(error: model.binding)
        }

        await harness.waitUntil { harness.environmentLoadingView.sawError }
    }

    @Test func failure_reachesTheCallerBinding() async throws {
        let harness = try Harness()
        defer { harness.close() }

        try await harness.host { model in
            ProbeView.bind(error: model.binding)
        }

        await harness.waitUntil { harness.model.error != nil }
    }

    @Test func failedFirstLoad_fetchesOnce() async throws {
        let harness = try Harness()
        defer { harness.close() }

        try await harness.host { model in
            ProbeView.bind(error: model.binding)
        }

        await harness.waitUntil { harness.model.error != nil }
        await harness.settle()
        #expect(harness.requestCount == 1)
    }

    @Test func clearingTheFailure_fetchesExactlyOnceMore() async throws {
        let harness = try Harness()
        defer { harness.close() }

        try await harness.host { model in
            ProbeView.bind(error: model.binding)
        }
        await harness.waitUntil { harness.model.error != nil }

        harness.model.error = nil

        await harness.waitUntil { harness.requestCount == 2 && harness.model.error != nil }
        await harness.settle()
        #expect(harness.requestCount == 2)
    }

    @Test func withAnErrorBinding_theScreenOwnsATypedServerError() async throws {
        let handled = LockedRecorder<Error>()
        let harness = try Harness(answersWithServerError: true, requestErrorHandler: handled)
        defer { harness.close() }

        try await harness.host { model in
            ProbeView.bind(error: model.binding)
        }

        await harness.waitUntil { harness.model.error is EmptyError }
        await harness.settle()
        #expect(handled.values.count == 0)
    }

    @Test func withoutAnErrorBinding_theRequestErrorHandlerHearsIt() async throws {
        let handled = LockedRecorder<Error>()
        let harness = try Harness(answersWithServerError: true, requestErrorHandler: handled)
        defer { harness.close() }

        try await harness.host { _ in
            ProbeView.bind()
        }

        await harness.waitUntil { handled.values.count == 1 }
        // The loading view still gets the failure
        await harness.waitUntil { harness.environmentLoadingView.sawError }
    }

    @Test func bindingThatDropsWrites_doesNotRetryInALoop() async throws {
        let harness = try Harness()
        defer { harness.close() }

        try await harness.host { _ in
            ProbeView.bind(error: .constant(nil)) { error in
                harness.bindLoadingView.record(error)
                return Text("bind")
            }
        }

        await harness.waitUntil { harness.bindLoadingView.sawError }
        await harness.settle()
        #expect(harness.requestCount == 1)
    }
}

// MARK: - Test Support

private struct ProbeView: ViewModelView {
    let viewModel: TestVersionedViewModel
    var body: some View {
        EmptyView()
    }
}

@MainActor @Observable
private final class HarnessModel {
    var error: Error?

    var binding: Binding<Error?> {
        Binding(get: { self.error }, set: { self.error = $0 })
    }
}

@MainActor
private final class Harness {
    let model = HarnessModel()
    let bindLoadingView = LockedRecorder<Error?>()
    let environmentLoadingView = LockedRecorder<Error?>()

    private let host: String
    private let env: MVVMEnvironment
    private var window: NSWindow?
    private var hostingView: NSView?

    var requestCount: Int {
        FailingRequestCounter.count(for: host)
    }

    init(answersWithServerError: Bool = false, requestErrorHandler: LockedRecorder<Error>? = nil) throws {
        let prefix = answersWithServerError ? FailingRequestCounter.serverErrorPrefix : "bind-"
        let host = "\(prefix)\(UUID().uuidString.lowercased()).invalid"
        self.host = host

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FailingRequestCounter.self]

        let environmentLoadingView = environmentLoadingView
        var handler: (@Sendable (any ServerRequest, any ServerRequestError) -> Void)?
        if let requestErrorHandler {
            handler = { _, error in requestErrorHandler.record(error) }
        }
        // The public SwiftUI initializers check the app bundle's version, which a test bundle lacks;
        // the preview initializer stores `loadingView` the same way.
        self.env = try MVVMEnvironment(
            localizationStore: Bundle.module.yamlLocalization(resourceDirectoryName: "TestYAML"),
            deploymentURLs: [
                .debug: .init(serverBaseURL: #require(URL(string: "http://\(host)")))
            ],
            requestErrorHandler: handler,
            session: URLSession(configuration: configuration),
            loadingView: { error in
                environmentLoadingView.record(error)
                return Text("environment")
            }
        )
    }

    func host(_ content: @escaping (HarnessModel) -> some View) async throws {
        let model = model
        let rootView = HarnessRoot(model: model, content: content)
            .environment(env)
        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.orderFrontRegardless()
        self.window = window
        self.hostingView = hostingView
    }

    func waitUntil(_ condition: @MainActor () -> Bool) async {
        var spins = 0
        while !condition(), spins < 500 {
            hostingView?.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(10))
            spins += 1
        }
        #expect(condition(), "condition not reached after \(spins) spins")
    }

    /// Lets any extra fetch that would wrongly follow get the chance to happen.
    func settle() async {
        for _ in 0..<30 {
            hostingView?.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func close() {
        window?.close()
        window = nil
        hostingView = nil
    }
}

private struct HarnessRoot<Content: View>: View {
    @Bindable var model: HarnessModel
    let content: (HarnessModel) -> Content

    var body: some View {
        content(model)
    }
}

/// Fails every request it sees and counts them by host, so concurrent tests count independently.
/// A host starting with `serverErrorPrefix` is answered with the request's own typed server error
/// instead of a connection failure.
private final class FailingRequestCounter: URLProtocol {
    static let serverErrorPrefix = "typed-"
    private static let lock = NSLock()
    private nonisolated(unsafe) static var counts: [String: Int] = [:]

    static func count(for host: String) -> Int {
        lock.withLock { counts[host] ?? 0 }
    }

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if let host = request.url?.host {
            Self.lock.withLock { Self.counts[host, default: 0] += 1 }

            if host.hasPrefix(Self.serverErrorPrefix), let url = request.url {
                answerWithServerError(url: url)
                return
            }
        }
        client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
    }

    override func stopLoading() {}

    private func answerWithServerError(url: URL) {
        guard
            let body = try? WireError<EmptyError>.response(EmptyError()).toJSONData(),
            let response = HTTPURLResponse(
                url: url,
                statusCode: 400,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotParseResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

#endif
