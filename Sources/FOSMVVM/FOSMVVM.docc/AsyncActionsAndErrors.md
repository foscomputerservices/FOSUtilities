# Async Actions and Error Presentation

Run a throwing async operation from a Button, route its failure to one screen-level binding, and present it localized.

## Overview

Most user-initiated actions in an FOSMVVM application are asynchronous and can fail: the View dispatches through ``ViewModelOperations`` (see <doc:Operations>), the operation performs a ``ServerRequest``, and the server may answer with a typed error.

Four pieces carry that flow — from tap or view appearance to alert — and they are designed to be wired together:

- **Async `Button` forms** run a `@Sendable () async throws` action and deposit any thrown error into an `error:` binding.
- **`task(error:)` / `task(id:error:)`** run a view-lifetime (or value-keyed) load and route its error into the same binding.
- **`alert(error:title:message:dismissButtonLabel:)`** presents whatever lands in that binding, localized.
- **``LocalizableError``** gives your error types user-presentable, YAML-localized messages — composed exactly like a ``ViewModel``.

What the binding holds at every moment — success, failure, cancellation, restarts — is drawn situation-by-situation in <doc:AsyncLifecycle>.

## The Basic Wiring

One `@State` error per screen, fed by every async button on it, presented by one alert:

```swift
struct DocumentView: ViewModelView {
    let viewModel: DocumentViewModel

    @State private var error: Error?

    var body: some View {
        VStack {
            // ... the document form ...

            Button(viewModel.saveTitle, error: $error) {
                try await viewModel.operations.save()
            }
        }
        .alert(error: $error,
               title: viewModel.errorTitle,
               message: viewModel.errorMessage,
               dismissButtonLabel: viewModel.dismissTitle)
    }
}
```

```yaml
en:
  DocumentViewModel:
    saveTitle: "Save"
    errorTitle: "An Error Occurred"
    errorMessage: "The operation failed: %{error}"
    dismissTitle: "OK"
```

Tapping starts the action; a thrown error lands in `error` and the alert shows. Starting a new invocation clears the binding first — it always holds the outcome of the most recent invocation. Dismissing the alert clears it.

If `message` contains an `%{error}` substitution point, the presented error's localized message fills it. Omitting `message:` presents the error's message alone.

## Preventing Re-Entry

Every `Localizable` Button form has an async twin, and each accepts an optional ``AsyncButtonActivity``. Without one, every tap starts a new concurrent invocation. With one, taps are refused while a run is in flight, and the running state is available for `disabled(_:)` or a progress indicator:

```swift
@State private var activity = AsyncButtonActivity()

Button(viewModel.saveTitle, activity: $activity, error: $error) {
    try await viewModel.operations.save()
}
.disabled(activity.isRunning)
```

Share one activity between several buttons to make them mutually exclusive — while any of them runs, the others refuse to start.

## Cancellable Operations

Providing the cancel face turns a button two-faced: tap to start, tap again to cancel. On the titled forms that means `cancelTitle:` (optionally `cancelSystemImage:` or `cancelImage:`); on the ViewBuilder forms it means a phase-aware label closure. The `activity:` binding is required — cancellation needs state that survives view updates:

```swift
Button(viewModel.uploadTitle, cancelTitle: viewModel.cancelTitle,
       systemImage: "arrow.up", cancelSystemImage: "xmark",
       activity: $activity, error: $error) {
    try await viewModel.operations.upload()
}
```

While running, the button shows the cancel face and a tap cancels the operation; the phase is `.cancelling` until the work unwinds. A cancelled invocation writes nothing to `error`. Call ``AsyncButtonActivity/cancel()`` to cancel from outside the button — a toolbar ✕, or `.onDisappear { activity.cancel() }`.

> Important: Cancellation is cooperative — the action must run cancellation-aware work (any `URLSession`-backed ``ServerRequest`` is) for the cancel face to take effect.

For long-running *server* work, model the operation as a server-tracked resource and cancel it with another request — client-side cancellation only abandons the response.

## View-Lifetime Loads

The screen's initial load is not a tap — it belongs to the view's lifetime. The `task(error:)` twins of SwiftUI's `task` modifiers run a throwing load and feed the same binding:

```swift
.task(id: viewModel.selectedDocumentId, error: $error) {
    try await viewModel.operations.loadDocument()
}
```

The load starts on appearance — and restarts when `id` changes; a thrown error lands in `error` and the alert presents it. Cancellation — leaving the screen, an `id` restart, or the `CancellationError` sentinel — never deposits into the binding, so teardown and superseded loads stay silent. The full contract is in <doc:AsyncLifecycle>.

## Localizing Your Errors

Conform an error to ``LocalizableError`` and the alert presents it in the user's language; errors that do not conform are presented with their debug description. Compose the conformer exactly like a ``ViewModel`` — a `@LocalizedString` or `@LocalizedSubs` message property, plumbing from the `@LocalizableError` macro:

```swift
@LocalizableError
public struct QuotaError: ServerRequestError {
    public let requested: Int
    public let maximum: Int

    @LocalizedSubs(substitutions: \.subs) public var errorMessage

    public var localizedMessage: any Localizable { errorMessage }

    private var subs: [String: any Localizable] { [
        "requested": LocalizableInt(value: requested),
        "maximum": LocalizableInt(value: maximum)
    ] }

    public init(requested: Int, maximum: Int) {
        self.requested = requested
        self.maximum = maximum
    }
}
```

```yaml
en:
  QuotaError:
    errorMessage: "Requested %{requested} exceeds the maximum of %{maximum}"
```

Localization happens as it does for a ``ViewModel`` — during the localizing encode. The server throws the error, its middleware resolves the message as it encodes the response, and the client decodes a message that is *already localized*.

## One Localization Domain per Error Type

An error type belongs to exactly one localization domain: its YAML lives where the error is thrown.

- **Server-domain** errors (the canonical case, above) arrive at the client already resolved.
- **Client-domain** errors — created in an app that hosts its own localization YAML — declare `@LocalizableError(options: [.clientHosted])` and are resolved at presentation against ``MVVMEnvironment/resourceBundles``. The alert does this automatically; custom presentation surfaces call ``LocalizableError/localized(mvvmEnv:locale:)`` themselves.

The same type never straddles domains. An error reaching presentation unresolved surfaces as its debug description — the symptom of a domain violation.

## Topics

- ``AsyncButtonActivity``
- ``LocalizableError``
- ``ClientHostedLocalizableError``
- ``ViewModelOperations``
