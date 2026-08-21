# Async Action Lifecycle and Cancellation

Watch what the `error` binding and ``AsyncButtonActivity/phase`` hold at each moment of an async action's life — nine situations, traced one at a time against a single screen.

## Overview

Every async surface in FOSMVVM — the async `Button` forms and the error-routing `task(error:)` modifiers — reports its outcome through a screen-level `error` binding. Buttons that take an ``AsyncButtonActivity`` also report where their work is in its lifecycle, through ``AsyncButtonActivity/phase``.

This article declares one screen and then walks it through nine situations: what the user does, what runs, what each binding holds, and what appears on screen. Each walkthrough ends with the one-sentence rule it just demonstrated, and the final section collects those sentences into the full contract.

For the wiring itself — which forms exist and how to declare them — see <doc:AsyncActionsAndErrors>.

## One Screen, Every Situation

Here is the screen every walkthrough uses — a document view whose content loads for the lifetime of the view, plus two buttons:

```swift
struct DocumentView: ViewModelView {
    let viewModel: DocumentViewModel

    @State private var error: Error?
    @State private var activity = AsyncButtonActivity()

    var body: some View {
        VStack {
            // ... the document content ...

            Button(viewModel.saveTitle, activity: $activity, error: $error) {
                try await viewModel.operations.save()
            }

            Button(viewModel.uploadTitle, cancelTitle: viewModel.cancelTitle,
                   activity: $activity, error: $error) {
                try await viewModel.operations.upload()
            }
        }
        .task(id: viewModel.selectedDocumentId, error: $error) {
            try await viewModel.operations.loadDocument()
        }
        .alert(error: $error,
               title: viewModel.errorTitle,
               dismissButtonLabel: viewModel.dismissTitle)
    }
}
```

- The **save** button has no cancellation support — it appears in the saving, retrying, and tapping-while-running walkthroughs.
- The **upload** button's `cancelTitle:` gives it a cancellation support — it appears in the cancellation walkthroughs.
- The **`task(id:error:)`** load appears in the navigating-away and switching-documents walkthroughs.
- All three deposit into the same `error` binding, presented by the one alert, and the two buttons share one `activity`.

The localization YAML and the rest of the wiring for a screen like this are shown in <doc:AsyncActionsAndErrors>.

## Who Writes `error`, and When

`error` is your `@State`, and it has exactly three writers:

1. **The async surface** (a button or the `task` modifier) writes at most twice per invocation: `nil` at the moment the invocation starts, and the thrown error at the moment the invocation fails.
2. **The alert** writes `nil` when the user dismisses it.
3. **Your own code** can write it, since you own the state — the walkthroughs assume you don't.

`activity.phase` has one writer — the framework — and it only ever moves the value along one path: `idle` to `running` when an invocation starts, `running` to `cancelling` when cancellation is requested, and back to `idle` when the work has unwound.

Everything in the rest of this article is these writers acting at their moments. When a walkthrough surprises you, come back to this list and find which writer acted — or held back.

## Saving Succeeds

You tap Save. The button writes `nil` into `error`, moves `activity.phase` to `running`, and starts the action. `try await viewModel.operations.save()` runs and returns. The button writes nothing more to `error`, and the phase returns to `idle`. `error` is `nil`, and no alert appears.

```
User          Button          activity.phase    error
 │             │               │ idle            │ nil
 │  tap        │               │                 │
 │────────────▶│  clear        │                 │
 │             │───────────────┼────────────────▶│ nil
 │             │──────────────▶│ running         │
 │             │  run action   │                 │
 │             │  …succeeds…   │                 │
 │             │ (writes       │                 │
 │             │  nothing)     │                 │
 │             │──────────────▶│ idle            │ nil — no alert
```

The document's saved state reaches the screen the way all state does in FOSMVVM — through the ViewModel — so the error channel had nothing to say here.

**The rule this trace shows:** a successful invocation leaves `error` at `nil`.

## Saving Fails

You tap Save. The button writes `nil` into `error`, moves `activity.phase` to `running`, and starts the action. This time `save()` throws. The button writes the thrown error into `error`, and the phase returns to `idle` — failure ends an invocation the same way success does. The alert — which presents whenever `error` is non-`nil` — appears with the localized message. You tap OK; the alert writes `nil`; the screen is back where it started.

```
User          Button          activity.phase    error
 │  tap        │               │ idle            │
 │────────────▶│  clear        │                 │
 │             │───────────────┼────────────────▶│ nil
 │             │──────────────▶│ running         │
 │             │  run action   │                 │
 │             │  …throws e…   │                 │
 │             │  deposit      │                 │
 │             │───────────────┼────────────────▶│ e — alert
 │             │──────────────▶│ idle            │    presents
 │  dismiss    │               │                 │
 │─────────────┼───────────────┼────────────────▶│ nil
```

Notice that the upload button and the `task` load deposit into this same binding — whichever surface fails, this same alert presents it. One binding and one alert per screen is the intended shape.

**The rule this trace shows:** a thrown error lands in `error`, and dismissing the alert clears it.

## Retrying After a Failure

Suppose this screen presented its errors inline — a text row reading from `error` — instead of an alert, so a failure message can still be on screen when you tap Save again.

The failure `e₁` sits in `error`; the row shows its message. You tap Save. The button's first write is `nil` — the stale message leaves the screen at the tap, before the new attempt has done any work. The retry then fails with `e₂`, and `e₂` is deposited. `activity.phase` makes its usual round trip, `idle` to `running` and back.

```
User          Button          activity.phase    error
 │             │               │ idle            │ e₁ (previous failure)
 │  tap (retry)│               │                 │
 │────────────▶│  clear        │                 │
 │             │───────────────┼────────────────▶│ nil
 │             │──────────────▶│ running         │
 │             │  run action   │                 │
 │             │  …throws e₂…  │                 │
 │             │───────────────┼────────────────▶│ e₂
 │             │──────────────▶│ idle            │
```

At no point could the screen show `e₁` next to the retry's outcome — the binding held one invocation's outcome at a time. This also means `error` is not a history; if your screen needs earlier failures preserved, copy them into your own state before retrying.

**The rule this trace shows:** starting an invocation clears `error` first, so the binding always holds the outcome of the most recent invocation.

## Cancelling the Upload

You tap Upload. The button writes `nil` into `error`, starts the action, and moves `activity.phase` to `running` — and because `running` is the phase the upload button renders its `cancelTitle:` face from, the button now reads Cancel.

You tap Cancel. The phase moves to `cancelling`, and cancellation is requested of the running work. The work unwinds — usually by throwing `CancellationError`, sometimes with a genuine failure that raced your cancel. Either way, the surface's second writer holds back: the invocation was cancelled, so nothing is deposited — a failure you cancelled into is one you'll meet again if you retry, and the discarded outcome is recorded in the debug log. When the unwind completes, the phase returns to `idle` and the button reads Upload again. `error` was `nil` throughout; no alert appeared.

```
User          Button          activity.phase    error
 │  tap        │               │ idle            │ nil
 │────────────▶│  start        │                 │
 │             │──────────────▶│ running         │
 │  tap (✕)    │               │                 │
 │────────────▶│  cancel       │                 │
 │             │──────────────▶│ cancelling      │
 │             │  …unwinds…    │                 │
 │             │──────────────▶│ idle            │ nil — nothing
 │             │               │                 │       written
```

If the screen should confirm the cancellation, the phase is where that lives. `cancelling` means "stopping was requested"; the return to `idle` means "the work has stopped." The screen can watch that transition:

```swift
.onChange(of: activity.phase) { previous, current in
    if previous == .cancelling, current == .idle {
        showCancelledConfirmation = true
    }
}
```

The two bindings divide the work: `error` answers "did the outcome I wanted happen?", and `activity.phase` answers "where is the work right now?". A cancellation is the second kind of fact.

> Important: Cancellation is cooperative — the action must run cancellation-aware work (any `URLSession`-backed ``ServerRequest`` is) for the request to take effect.

**The rule this trace shows:** a cancelled invocation writes nothing to `error`; its story is told by `activity.phase`.

## Tapping Save While It Runs

You tap Save; the phase moves to `running`. You tap Save again before it finishes. Nothing happens: no second invocation starts, no write to `error`, no phase change. A third tap — the same. When the first invocation completes, the phase returns to `idle` and taps work again.

```
User          Button          activity.phase
 │  tap        │               │ idle
 │────────────▶│  start        │
 │             │──────────────▶│ running
 │  tap        │               │
 │────────────▶│  refused      │ running (unchanged)
 │  tap        │               │
 │────────────▶│  refused      │ running (unchanged)
 │             │  …completes…  │
 │             │──────────────▶│ idle
```

On the rooted screen, Save and Upload share the one `activity` — so while the save runs, a tap on Upload is refused the same way. Sharing an activity is how you declare "these buttons are one operation slot."

The refusal comes from the `activity:` parameter. A button *without* one has no way to know work is in flight: every tap starts a new concurrent invocation, each following the traces above independently.

**The rule this trace shows:** while an activity's work is in flight, its buttons refuse to start new work.

## Tapping Cancel as the Upload Finishes

The upload is running; the button reads Cancel; your finger is already descending. The upload completes first: the phase returns to `idle` and the face flips back to Upload. Your tap — aimed at Cancel — lands on Upload.

The button ignores it. No invocation starts. A tap arriving in the instant after the faces change is treated as aimed at the old face and discarded; a deliberate tap a moment later starts normally.

```
User          Button          activity.phase
 │             │               │ running — shows ✕
 │             │  …completes…  │
 │             │──────────────▶│ idle — shows Start
 │  tap (aimed │               │
 │   at ✕)     │               │
 │────────────▶│  absorbed     │ idle (no new invocation)
 │             │               │
 │  tap (later)│               │
 │────────────▶│  start        │ running
```

**The rule this trace shows:** a tap in the instant after a face change is ignored rather than misread against the old face.

## Navigating Away While the Document Loads

The screen appears; `task(id:error:)` writes `nil` into `error` and starts `loadDocument()`. Before it finishes, you navigate deeper into the app. SwiftUI cancels the task — that is `task`'s standing behavior, twin or not — and the load unwinds, typically throwing `CancellationError`. The invocation was cancelled, so nothing is deposited.

You navigate back. The screen's `@State` — including `error`, still `nil` — survived in the `NavigationStack` while you were away, and on appearance `task` starts a fresh invocation. If the load's problem was momentary, this one succeeds. If the server is genuinely unreachable, this invocation fails *on the screen you are looking at*, deposits its error, and the alert presents it.

```
SwiftUI         task invocation      error
 │  appear         │                   │
 │────────────────▶│  clear            │
 │                 │──────────────────▶│ nil
 │                 │  …loading…        │
 │  disappear      │                   │
 │  (cancels)      │                   │
 │────────────────▶│  …unwinds,        │
 │                 │   throws          │
 │                 │   Cancellation-   │
 │                 │   Error…          │
 │                 │  (suppressed)     │ nil — nothing
 │                 │                   │       written
 │  appear (back)  │                   │
 │────────────────▶│  runs again       │
```

Trace the alternative for one step to see what the held-back write protects: had the cancelled invocation deposited its `CancellationError`, that error would have sat in the surviving `@State` while you were away — and greeted your return with an alert about a load that was, at that same moment, already re-running.

**The rule this trace shows:** teardown deposits nothing, and no durable failure is lost — a real problem recurs and presents on the next appearance.

## Selecting a Different Document

`loadDocument()` for document A is in flight when `viewModel.selectedDocumentId` changes to B. `task(id:error:)` responds the way `task(id:)` always does: it cancels invocation A and starts invocation B. B's first act is the `nil` write. A unwinds late — its task was cancelled, so however it finishes, it deposits nothing. B fails against the server; B's error is deposited; the alert presents it.

```
SwiftUI         invocation A    invocation B    error
 │  appear         │                │             │
 │────────────────▶│ clear, run     │             │ nil
 │                 │ …loading…      │             │
 │  id changes     │                │             │
 │  (cancels A)    │                │             │
 │────────────────────────────────▶│ clear, run  │ nil
 │                 │ …unwinds       │ …loading…   │
 │                 │  late…         │             │
 │                 │ (suppressed)   │             │
 │                 │                │ …throws e…  │
 │                 │                │────────────▶│ e — B's
 │                 │                │             │     outcome
```

The order on the right edge is the point of the trace: A's unwind finished *after* B started, and `error` still holds only B's outcome. A cancelled invocation cannot write, so a superseded load can never speak over the current one — not with a `CancellationError`, and not with a stale failure about a document you are no longer viewing.

**The rule this trace shows:** an `id` change starts a fresh invocation, and the superseded one contributes nothing.

## When the Action Itself Throws `CancellationError`

One last trace, to close the contract.

Save is running. Nobody taps Cancel, nothing navigates away — the invocation's task is never cancelled. But inside the action, a child task the operation spawned gets cancelled, and its `CancellationError` escapes the action. The surface recognizes the language's cancellation sentinel and holds back: nothing is deposited, the phase returns to `idle`, and the discard is recorded in the debug log. The tap ends with no alert.

```
User          Button          activity.phase    error
 │  tap        │               │ idle            │
 │────────────▶│  clear        │                 │
 │             │───────────────┼────────────────▶│ nil
 │             │──────────────▶│ running         │
 │             │  child task   │                 │
 │             │  cancelled    │                 │
 │             │  inside the   │                 │
 │             │  action;      │                 │
 │             │  Cancellation-│                 │
 │             │  Error escapes│                 │
 │             │  (discarded,  │                 │
 │             │   logged)     │                 │
 │             │──────────────▶│ idle            │ nil — no alert
```

This makes the quiet exit an idiom you can use on purpose: an action that decides mid-flight to end with nothing presented — the user declined a confirmation step, say — throws `CancellationError`, and the invocation finishes silently.

The filter recognizes exactly one type: the language's own `CancellationError`. Errors that merely *describe* a cancellation in some domain's vocabulary — `URLError.cancelled`, for instance — deposit and present like any other failure. The framework recognizes the language's sentinel; it does not interpret your domain's error semantics.

**The rule this trace shows:** a `CancellationError` never reaches `error` — cancellation, whatever its source, is not a fact the error channel carries.

## The Contract, Collected

The nine traces above demonstrate the full contract:

- Starting an invocation writes `nil` into `error`.
- A thrown error lands in `error`; dismissing the alert clears it.
- Cancellation never reaches `error`: a cancelled invocation deposits nothing, and a `CancellationError` — the exact language type — is never deposited even when the invocation itself wasn't cancelled.
- Every discarded outcome is recorded in the debug log.
- Together: `error` always holds the outcome of the most recent invocation.
- `activity.phase` reports the work's lifecycle — `idle`, `running`, `cancelling` — and its `cancelling`-to-`idle` transition means the cancelled work has actually stopped.
- With an `activity:`, taps while work is in flight are refused, as is a tap in the instant after a two-faced button changes faces.

## Topics

- ``AsyncButtonActivity``
- ``AsyncButtonActivity/Phase``
- ``LocalizableError``
- ``ViewModelOperations``
