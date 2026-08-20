// AsyncButtonActivity.swift
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

/// The in-flight state of an async button — declare one as `@State` and hand it to the button
///
/// ```swift
/// @State private var activity = AsyncButtonActivity()
/// @State private var error: Error?
///
/// var body: some View {
///     Button(viewModel.uploadTitle, cancelTitle: viewModel.cancelTitle,
///            activity: $activity, error: $error) {
///         try await viewModel.operations.upload()
///     }
///     .disabled(activity.phase == .cancelling)
/// }
/// ```
///
/// While the button's work runs, ``phase`` is `.running`; a cancel-capable button that has
/// been asked to stop is `.cancelling` until its work unwinds. Use ``phase`` (or
/// ``isRunning``) to drive `disabled(_:)`, progress indicators, and phase-aware labels.
///
/// Share one activity between several buttons to make them mutually exclusive — while any
/// of them is running, the others refuse to start, and (for cancel-capable buttons) any of
/// their faces can stop the running operation.
///
/// Call ``cancel()`` to stop the running operation from outside the button — a toolbar ✕,
/// or `.onDisappear { activity.cancel() }`.
public struct AsyncButtonActivity: Sendable {
    /// The lifecycle position of the button's current invocation
    ///
    /// `idle` — no work in flight; a tap starts the action. `running` — the action is in
    /// flight. `cancelling` — cancellation was requested and the action is unwinding; the
    /// button refuses taps until it returns to `idle`.
    public enum Phase: Equatable, Sendable {
        case idle
        case running
        case cancelling
    }

    /// The current lifecycle position — drive `disabled(_:)`, progress indicators, and
    /// phase-aware labels from it
    public private(set) var phase: Phase = .idle

    /// **true** while the button should not accept new work (`phase` is `.running` or
    /// `.cancelling`)
    ///
    /// ```swift
    /// ProgressView()
    ///     .opacity(activity.isRunning ? 1 : 0)
    /// ```
    public var isRunning: Bool {
        phase != .idle
    }

    /// Requests cancellation of the running operation
    ///
    /// ```swift
    /// .onDisappear { activity.cancel() }
    /// ```
    ///
    /// The phase moves to `.cancelling` until the operation's task unwinds, then returns to
    /// `.idle`. Does nothing unless the phase is `.running`.
    ///
    /// > Important: Cancellation is cooperative — the button's action must run
    /// > cancellation-aware work (any `URLSession`-backed request is) for the request to
    /// > take effect.
    public mutating func cancel() {
        guard phase == .running else { return }

        phase = .cancelling
        task?.cancel()
    }

    /// Creates an idle activity — the only constructible state
    public init() {}

    // Sealed engine state: reachable only through the AsyncButtonEngine tap flow (and the
    // engine's tests). Internal, never public — a forgeable `running` state or an exposed
    // task handle would break every invariant the phases guarantee.
    private var task: Task<Void, Never>?
    var lastIdleFlip: ContinuousClock.Instant?

    mutating func beginRun(_ task: Task<Void, Never>) {
        phase = .running
        self.task = task
    }

    mutating func finishRun(recordFlip: Bool) {
        phase = .idle
        task = nil
        if recordFlip {
            lastIdleFlip = ContinuousClock().now
        }
    }

    func isInRefractoryWindow(now: ContinuousClock.Instant) -> Bool {
        guard let lastIdleFlip else { return false }

        return now < lastIdleFlip + AsyncButtonEngine.refractoryWindow
    }
}

/// The single home of the async-button tap semantics — every async `Button` init forwards
/// here, so a semantic change lands once and is never re-stamped.
enum AsyncButtonEngine {
    enum Mode {
        /// No cancel face: a tap while running has no observable effect
        case refuse
        /// Cancel face provided: a tap while running cancels the operation
        case toggle
    }

    /// The window after a toggle button's running→idle flip during which taps are presumed
    /// aimed at the old (Cancel) face and discarded. Pinned by AsyncButtonActivityTests;
    /// deliberately not part of the public contract.
    static let refractoryWindow: Duration = .milliseconds(500)

    static func tapAction(
        mode: Mode,
        activity: Binding<AsyncButtonActivity>?,
        error: Binding<Error?>,
        action: @escaping @Sendable () async throws -> Void
    ) -> @MainActor () -> Void {
        { @MainActor in
            handleTap(mode: mode, activity: activity, error: error, action: action)
        }
    }

    /// `now` is an internal determinism seam for the refractory tests; production taps use
    /// the default.
    @MainActor static func handleTap(
        mode: Mode,
        activity: Binding<AsyncButtonActivity>?,
        error: Binding<Error?>,
        now: ContinuousClock.Instant = ContinuousClock().now,
        action: @escaping @Sendable () async throws -> Void
    ) {
        if let activity {
            switch activity.wrappedValue.phase {
            case .cancelling:
                return

            case .running:
                if mode == .toggle {
                    activity.wrappedValue.cancel()
                }
                return

            case .idle:
                if mode == .toggle, activity.wrappedValue.isInRefractoryWindow(now: now) {
                    return
                }
            }
        }

        error.wrappedValue = nil

        let task = Task { @MainActor in
            var failure: (any Error)?
            do {
                try await action()
            } catch let actionError {
                failure = actionError
            }

            if !Task.isCancelled, let failure {
                error.wrappedValue = failure
            }
            activity?.wrappedValue.finishRun(recordFlip: mode == .toggle)
        }

        activity?.wrappedValue.beginRun(task)
    }
}

public extension Button {
    /// Async form of SwiftUI's `Button.init(action:label:)` — runs a throwing async action
    /// and routes its error to a binding
    ///
    /// ```swift
    /// @State private var error: Error?
    ///
    /// Button(error: $error) {
    ///     try await viewModel.operations.save()
    /// } label: {
    ///     Text(viewModel.saveTitle)
    /// }
    /// .alert(error: $error,
    ///        title: viewModel.errorTitle,
    ///        dismissButtonLabel: viewModel.dismissTitle)
    /// ```
    ///
    /// Tapping starts the action; a thrown error lands in `error`. Starting a new
    /// invocation clears `error` first — the binding always holds the outcome of the most
    /// recent invocation.
    ///
    /// Pass `activity:` to prevent re-entry: while a run is in flight, further taps are
    /// ignored, and `activity` reports the running state for `disabled(_:)` or a progress
    /// indicator. Without `activity:`, every tap starts a new concurrent invocation.
    ///
    /// The action runs in a task that is not cancelled by the view disappearing; it runs to
    /// completion. For user-cancellable work, use the initializers that take a phase-aware
    /// label (or a `cancelTitle:`). For long-running *server* work, model the operation as
    /// a server-tracked resource and cancel it with another request — client-side
    /// cancellation only abandons the response.
    nonisolated init(
        activity: Binding<AsyncButtonActivity>? = nil,
        error: Binding<Error?>,
        action: @escaping @Sendable () async throws -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.init(
            action: AsyncButtonEngine.tapAction(
                mode: .refuse,
                activity: activity,
                error: error,
                action: action
            ),
            label: label
        )
    }

    /// Async form of SwiftUI's `Button.init(role:action:label:)` — runs a throwing async
    /// action and routes its error to a binding
    ///
    /// See ``SwiftUI/Button/init(activity:error:action:label:)-swift.init`` for the
    /// behavior contract; `role` is passed through to SwiftUI unchanged.
    nonisolated init(
        role: ButtonRole?,
        activity: Binding<AsyncButtonActivity>? = nil,
        error: Binding<Error?>,
        action: @escaping @Sendable () async throws -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.init(
            role: role,
            action: AsyncButtonEngine.tapAction(
                mode: .refuse,
                activity: activity,
                error: error,
                action: action
            ),
            label: label
        )
    }

    /// A two-faced async button: tap to start the operation, tap again to cancel it
    ///
    /// Providing the phase-aware label is what enables cancellation — you have taken
    /// responsibility for rendering both faces:
    ///
    /// ```swift
    /// @State private var activity = AsyncButtonActivity()
    /// @State private var error: Error?
    ///
    /// Button(activity: $activity, error: $error) {
    ///     try await viewModel.operations.upload()
    /// } label: { phase in
    ///     phase == .idle
    ///         ? Label(viewModel.uploadTitle, systemImage: "arrow.up")
    ///         : Label(viewModel.cancelTitle, systemImage: "xmark")
    /// }
    /// ```
    ///
    /// While idle the button starts the action when tapped. While running, a tap cancels
    /// the operation; the button then refuses taps until the work unwinds
    /// (`activity.phase == .cancelling`). A cancelled invocation writes nothing to `error`.
    /// A tap arriving in the instant after the button changes faces is ignored rather than
    /// misread against the old face.
    ///
    /// > Important: Cancellation is cooperative. Your action must run cancellation-aware
    /// > work (any `URLSession`-backed `ServerRequest` is) for the cancel face to take
    /// > effect.
    nonisolated init(
        activity: Binding<AsyncButtonActivity>,
        error: Binding<Error?>,
        action: @escaping @Sendable () async throws -> Void,
        @ViewBuilder label: (AsyncButtonActivity.Phase) -> Label
    ) {
        self.init(
            action: AsyncButtonEngine.tapAction(
                mode: .toggle,
                activity: activity,
                error: error,
                action: action
            ),
            label: { label(activity.wrappedValue.phase) }
        )
    }

    /// A two-faced async button with a role: tap to start the operation, tap again to
    /// cancel it
    ///
    /// See ``SwiftUI/Button/init(activity:error:action:label:)-swift.init`` (the phase-aware
    /// label form) for the behavior contract; `role` is passed through to SwiftUI
    /// unchanged.
    nonisolated init(
        role: ButtonRole?,
        activity: Binding<AsyncButtonActivity>,
        error: Binding<Error?>,
        action: @escaping @Sendable () async throws -> Void,
        @ViewBuilder label: (AsyncButtonActivity.Phase) -> Label
    ) {
        self.init(
            role: role,
            action: AsyncButtonEngine.tapAction(
                mode: .toggle,
                activity: activity,
                error: error,
                action: action
            ),
            label: { label(activity.wrappedValue.phase) }
        )
    }
}
#endif
