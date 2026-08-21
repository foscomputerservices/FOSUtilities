// View+AsyncTask.swift
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
import SwiftUI

public extension View {
    /// Async form of SwiftUI's `task(priority:_:)` — runs a throwing async action when the
    /// view appears and routes its error to a binding
    ///
    /// ```swift
    /// @State private var error: Error?
    ///
    /// var body: some View {
    ///     DocumentList(viewModel: viewModel)
    ///         .task(error: $error) {
    ///             try await viewModel.operations.loadDocuments()
    ///         }
    ///         .alert(error: $error,
    ///                title: viewModel.errorTitle,
    ///                dismissButtonLabel: viewModel.dismissTitle)
    /// }
    /// ```
    ///
    /// The action starts when the view appears; a thrown error lands in `error`. Starting an
    /// invocation clears `error` first — the binding always holds the outcome of the most
    /// recent invocation.
    ///
    /// When the view disappears the task is cancelled, and a cancelled invocation writes
    /// nothing to the binding — teardown never deposits a `CancellationError` into your
    /// alert.
    ///
    /// To restart the load when a value changes, use ``task(id:error:priority:_:)``. For
    /// work started by a tap, use the async `Button` forms — they pair with the same
    /// binding. The full lifecycle contract, drawn situation by situation, is in
    /// <doc:AsyncLifecycle>.
    nonisolated func task(
        error: Binding<Error?>,
        priority: TaskPriority = .userInitiated,
        _ action: @escaping @Sendable () async throws -> Void
    ) -> some View {
        task(priority: priority) {
            await AsyncTaskEngine.run(error: error, action: action)
        }
    }

    /// Async form of SwiftUI's `task(id:priority:_:)` — restarts a throwing async action
    /// whenever `id` changes and routes its error to a binding
    ///
    /// ```swift
    /// @State private var error: Error?
    ///
    /// var body: some View {
    ///     DocumentDetail(viewModel: viewModel)
    ///         .task(id: viewModel.selectedDocumentId, error: $error) {
    ///             try await viewModel.operations.loadDocument()
    ///         }
    ///         .alert(error: $error,
    ///                title: viewModel.errorTitle,
    ///                dismissButtonLabel: viewModel.dismissTitle)
    /// }
    /// ```
    ///
    /// The action starts when the view appears and restarts whenever `id` changes to a new
    /// value; each start clears `error` first — the binding always holds the outcome of the
    /// most recent invocation.
    ///
    /// A restart (or the view disappearing) cancels the in-flight invocation, and a
    /// cancelled invocation writes nothing to the binding — a superseded load can never
    /// overwrite the current invocation's outcome, and teardown never deposits a
    /// `CancellationError` into your alert.
    ///
    /// The full lifecycle contract, drawn situation by situation, is in
    /// <doc:AsyncLifecycle>.
    nonisolated func task(
        id: some Equatable,
        error: Binding<Error?>,
        priority: TaskPriority = .userInitiated,
        _ action: @escaping @Sendable () async throws -> Void
    ) -> some View {
        task(id: id, priority: priority) {
            await AsyncTaskEngine.run(error: error, action: action)
        }
    }
}

/// The single home of the `task(error:)` semantics — both overloads forward here, so a
/// semantic change lands once and is never re-stamped.
enum AsyncTaskEngine {
    /// @MainActor for the binding writes: unlike a body-site `.task` closure, the wrapper
    /// closure above is defined in a nonisolated extension and inherits no actor context.
    @MainActor static func run(
        error: Binding<Error?>,
        action: @Sendable () async throws -> Void
    ) async {
        error.wrappedValue = nil

        var failure: (any Error)?
        do {
            try await action()
        } catch let actionError {
            failure = actionError
        }

        if let failure {
            if Task.isCancelled {
                print("AsyncTask: discarding \(type(of: failure)) from a cancelled invocation")
            } else if failure is CancellationError {
                print("AsyncTask: discarding CancellationError from a non-cancelled invocation")
            } else {
                error.wrappedValue = failure
            }
        }
    }
}
#endif
