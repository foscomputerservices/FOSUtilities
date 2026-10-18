// StreamingSession.swift
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

#if !os(WASI)
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// A body only arrives chunk by chunk through a *session* data delegate: swift-corelibs
// FoundationNetworking has no `bytes(for:)`, never hands body data to a per-task delegate of a
// plain data task, and `data(for:delegate:)` buffers the whole body. So each caller session gets
// one streaming session built from its configuration, on every platform, whose delegate forwards
// authentication challenges to the caller session's delegate (keeping
// `URLSession.session(config:mutualTLS:)` pinning in force).
//
// Streaming sessions, and the caller sessions they forward to, are never released: freeing a
// `URLSession` can abort under FoundationNetworking (see `SharedURLSession`). Checked 2026-10-17
// with Swift 6.4.0 on Linux (arm64): freeing a session after an HTTPS request to google.com,
// github.com, apple.com or swift.org aborts within ten sessions ("_MultiHandle deallocated with
// non-zero retain count"), even after `finishTasksAndInvalidate()` or `invalidateAndCancel()`.

/// The session that carries `DataFetch.openStream` requests for one caller session. Get it with
/// ``shared(forwardingTo:)``, which returns the same instance for every call with the same caller session.
final class StreamingSession: Sendable {
    private let session: URLSession
    private let delegate: StreamingDelegate

    private static let lock = NSLock()
    private nonisolated(unsafe) static var sessions: [ObjectIdentifier: StreamingSession] = [:]

    static func shared(forwardingTo callerSession: URLSession) -> StreamingSession {
        lock.withLock {
            let key = ObjectIdentifier(callerSession)
            if let existing = sessions[key] {
                return existing
            }
            let streaming = StreamingSession(callerSession: callerSession)
            sessions[key] = streaming
            return streaming
        }
    }

    private init(callerSession: URLSession) {
        let delegate = StreamingDelegate(callerSession: callerSession)
        self.delegate = delegate
        self.session = URLSession(
            configuration: callerSession.configuration,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    /// Starts `request` and returns once the response arrives and passes `check`, with the body
    /// still to come. A failed check, cancelling the calling task, or ending iteration of the
    /// returned stream cancels the request.
    func open(
        _ request: URLRequest,
        check: (URLResponse) throws -> Void
    ) async throws -> AsyncThrowingStream<Data, any Error> {
        let task = session.dataTask(with: request)
        let (chunks, chunkContinuation) = AsyncThrowingStream<Data, any Error>.makeStream()

        do {
            let response = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (responseContinuation: CheckedContinuation<URLResponse, any Error>) in
                    delegate.register(task, responseContinuation: responseContinuation, chunkContinuation: chunkContinuation)
                    task.resume()
                }
            } onCancel: {
                task.cancel()
            }
            do {
                try check(response)
            } catch {
                task.cancel()
                throw error
            }
            chunkContinuation.onTermination = { _ in task.cancel() }
            return chunks
        } catch {
            // Only the caller's own cancellation is a CancellationError; a refused challenge also
            // ends the task as NSURLErrorCancelled and must stay a failure.
            if Task.isCancelled {
                throw CancellationError()
            }
            throw error
        }
    }
}

/// Routes each task's response and chunks to its waiter and stream, and forwards its challenges to
/// the caller session's delegate.
private final class StreamingDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct Continuations {
        var responseContinuation: CheckedContinuation<URLResponse, any Error>?
        let chunkContinuation: AsyncThrowingStream<Data, any Error>.Continuation
    }

    private let callerSession: URLSession
    private let callerHadDelegate: Bool
    private let lock = NSLock()
    private var continuations: [Int: Continuations] = [:]

    init(callerSession: URLSession) {
        self.callerSession = callerSession
        self.callerHadDelegate = callerSession.delegate != nil
    }

    func register(
        _ task: URLSessionTask,
        responseContinuation: CheckedContinuation<URLResponse, any Error>,
        chunkContinuation: AsyncThrowingStream<Data, any Error>.Continuation
    ) {
        lock.withLock {
            continuations[task.taskIdentifier] = Continuations(responseContinuation: responseContinuation, chunkContinuation: chunkContinuation)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        let responseContinuation = lock.withLock {
            let continuation = continuations[dataTask.taskIdentifier]?.responseContinuation
            continuations[dataTask.taskIdentifier]?.responseContinuation = nil
            return continuation
        }
        responseContinuation?.resume(returning: response)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let chunkContinuation = lock.withLock { continuations[dataTask.taskIdentifier]?.chunkContinuation }
        chunkContinuation?.yield(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let finished = lock.withLock({ continuations.removeValue(forKey: task.taskIdentifier) }) else {
            return
        }
        if let responseContinuation = finished.responseContinuation {
            responseContinuation.resume(throwing: error ?? URLError(.badServerResponse))
        }
        if let error {
            finished.chunkContinuation.finish(throwing: error)
        } else {
            finished.chunkContinuation.finish()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let callerSession = callerSession
        guard let callerDelegate = callerSession.delegate else {
            // An invalidated session releases its delegate. Its pinning went with it, so fail
            // closed rather than fall back to default trust.
            completionHandler(callerHadDelegate ? .cancelAuthenticationChallenge : .performDefaultHandling, nil)
            return
        }

        // Answer as the caller session would for its own task: its task-level handler when it has
        // one, otherwise its session-level handler.
        #if canImport(FoundationNetworking)
        if let taskDelegate = callerDelegate as? URLSessionTaskDelegate {
            taskDelegate.urlSession(callerSession, task: task, didReceive: challenge, completionHandler: completionHandler)
        } else {
            callerDelegate.urlSession(callerSession, didReceive: challenge, completionHandler: completionHandler)
        }
        #else
        if let taskDelegate = callerDelegate as? URLSessionTaskDelegate,
           taskDelegate.responds(to: #selector(URLSessionTaskDelegate.urlSession(_:task:didReceive:completionHandler:))) {
            taskDelegate.urlSession?(callerSession, task: task, didReceive: challenge, completionHandler: completionHandler)
        } else if callerDelegate.responds(to: #selector(URLSessionDelegate.urlSession(_:didReceive:completionHandler:))) {
            callerDelegate.urlSession?(callerSession, didReceive: challenge, completionHandler: completionHandler)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
        #endif
    }
}
#endif
