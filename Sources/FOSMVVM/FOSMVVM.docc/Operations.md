# Getting Started With ViewModel Operations

Dispatch user-initiated actions from interactive Views to server-backed or client-hosted storage.

## Overview

A ``ViewModel`` is a snapshot of data for display. When the user *does* something — taps a button, submits a form, toggles a setting — that action dispatches through a separate protocol: ``ViewModelOperations``.

Operations is the seam between the View and whatever actually performs the work:

- On the **server-hosted** side, the work is a ``ServerRequest`` that reaches the database through the Vapor request context.
- On the **client-hosted** side, the work is generally a mutation of an [`@Observable`](https://developer.apple.com/documentation/observation/observable()) storage class held in the View's [SwiftUI Environment](https://developer.apple.com/documentation/swiftui/environment).

Both shapes conform to the same ``ViewModelOperations`` protocol. The public API they expose — the specific methods an interactive ``ViewModel`` offers — is the same across the wire. The *implementation* changes with the hosting mode, and the **method signatures** carry a small convention that reflects the asymmetry.

## When to Use Operations

Operations are a per-ViewModel, per-interaction-style decision:

| View behavior | ViewModel needs Operations? |
| :------------ | :-------------------------- |
| Renders data only (card, row, detail view) | No — **display-only** |
| Has buttons, forms, toggles, or any user-initiated action | Yes — **interactive** |

Display-only ViewModels have no Operations file at all. Do not create an empty ``ViewModelOperations`` protocol to satisfy a generic parameter; the test base class for display-only views is `ViewModelDisplayTestCase<VM>`, which takes no Operations type. See <doc:ViewTesting> for the two testing paths.

## The Operations Trio

Every interactive ``ViewModel`` has a companion file — `{Name}ViewModelOperations.swift` — containing three related declarations:

1. **Protocol** (`{Name}ViewModelOperations: ViewModelOperations`) — declares the actions the View can dispatch.
2. **Live implementation** (`{Name}Ops`, a `struct`) — does the real work.
3. **Stub implementation** (`{Name}StubOps`, a `final class`, `@unchecked Sendable`) — records which methods were called with what arguments, for UI tests.

The ``ViewModel`` itself wires to the trio via a private `isStub: Bool` flag and a computed `operations` property:

```swift
@ViewModel
public struct ButtonViewModel: RequestableViewModel {
    public typealias Request = ButtonRequest

    @LocalizedString public var buttonTitle

    private let isStub: Bool

    #if canImport(SwiftUI)
    public var operations: any ButtonViewModelOperations {
        isStub ? ButtonStubOps() : ButtonOps()
    }
    #endif

    public let vmId: ViewModelId

    public init() {
        self.init(isStub: false)
    }

    private init(isStub: Bool) {
        self.isStub = isStub
        self.vmId = .init(type: Self.self)
    }

    public static func stub() -> Self {
        .init(isStub: true)
    }
}
```

The public `init` forwards to a private `init(isStub:, …)` that accepts the stub flag. The `stub()` factory sets `isStub = true`; callers constructed by normal means get `isStub = false` and the live implementation. UI tests receive the `StubOps` instance through the [Test Data Transporter](<doc:ViewTesting>) and assert on what was called.

## Server-Backed Operations

Use server-backed operations when the ``ViewModel``'s hosting mode is server-hosted — i.e., the factory runs on the server and mutations go through a ``ServerRequest``. The server owns storage (the database, through the Vapor request context), so operations never need to carry a storage reference.

**Method signature:** scalar inputs only, typically `async throws`.

```swift
public protocol DeviceViewModelOperations: ViewModelOperations {
    func disconnect(deviceId: String) async throws
}
```

**Live implementation** — dispatches a ``ServerRequest``:

```swift
public struct DeviceOps: DeviceViewModelOperations {
    public init() {}

    public func disconnect(deviceId: String) async throws {
        let request = DisconnectDeviceRequest(query: .init(deviceId: deviceId))
        try await request.processRequest(mvvmEnv: .shared)
    }
}
```

**Stub implementation** — records inputs for tests:

```swift
#if canImport(SwiftUI)
public final class DeviceStubOps: DeviceViewModelOperations, @unchecked Sendable {
    public var disconnectCalled: Bool { disconnectCalledWith != nil }
    public private(set) var disconnectCalledWith: String?

    public init() {}

    public func disconnect(deviceId: String) async throws {
        disconnectCalledWith = deviceId
    }
}
#endif
```

**No `output:` parameter.** The server context already has everything it needs. The `async throws` is genuine — the body awaits network I/O and can fail.

**Call site in the View:**

```swift
Button(action: { Task { try await viewModel.operations.disconnect(deviceId: viewModel.deviceId) } }) {
    Text(viewModel.disconnectTitle)
}
```

See <doc:ServerOverview> for how the server publishes ``ViewModel``s that these operations can request, and <doc:ViewModelandViewModelRequest> for the ``ServerRequest`` pattern the live implementation dispatches.

## Client-Hosted Operations

Use client-hosted operations when the ``ViewModel``'s hosting mode is client-hosted — i.e., `@ViewModel(options: [.clientHostedFactory])` and the factory runs on the device. Here the View's [SwiftUI Environment](https://developer.apple.com/documentation/swiftui/environment) holds one or more [`@Observable`](https://developer.apple.com/documentation/observation/observable()) storage classes, and operations mutate that storage. No server context is implicit, so each mutating method takes the write target explicitly, conventionally labeled `output`, as its last parameter.

**Method signature:** scalar inputs first, `output storage:` last, typically synchronous.

```swift
public protocol PreferencesViewModelOperations: ViewModelOperations {
    func setTheme(_ theme: Theme, output storage: UserSettings)
    func setNotificationsEnabled(_ enabled: Bool, output storage: UserSettings)
}
```

**Live implementation** — mutates the `@Observable`:

```swift
public struct PreferencesOps: PreferencesViewModelOperations {
    public init() {}

    public func setTheme(_ theme: Theme, output storage: UserSettings) {
        storage.theme = theme
    }

    public func setNotificationsEnabled(_ enabled: Bool, output storage: UserSettings) {
        storage.notificationsEnabled = enabled
    }
}
```

**Stub implementation** — records that the operation fired, and **also mutates storage** so projection fires naturally in UI tests:

```swift
#if canImport(SwiftUI)
public final class PreferencesStubOps: PreferencesViewModelOperations, @unchecked Sendable {
    public private(set) var setThemeCalled: Bool = false
    public private(set) var setNotificationsEnabledCalled: Bool = false

    public init() {}

    public func setTheme(_ theme: Theme, output storage: UserSettings) {
        setThemeCalled = true
        storage.theme = theme
    }

    public func setNotificationsEnabled(_ enabled: Bool, output storage: UserSettings) {
        setNotificationsEnabledCalled = true
        storage.notificationsEnabled = enabled
    }
}
#endif
```

**`output storage:` is the last parameter.** Scalar inputs describe **what** changed; `output` describes **where to write**. The label `in storage:` is wrong because `in` reads like an input and conflates the write target with the inputs that describe the change.

**Why the client-hosted stub mirrors the live mutation (and the server-backed stub does not).** Client-hosted operations drive the projection loop: a tap mutates storage, `@Observable` fires, the resolver re-projects, and the View redraws. If the stub only recorded the call and skipped `storage.theme = theme`, UI tests would see the tap register in `setThemeCalled` but the UI would never update — masking real projection bugs. By performing the same write the live implementation would, the stub keeps the projection loop intact end-to-end in tests. Tests assert "was it called?" with `stubOps.setThemeCalled`, and "with what value?" by reading `storage.theme` directly — the storage itself holds the `CalledWith` equivalent, so no separate accessor is needed. Server-backed stubs don't follow this pattern because there is no local storage to mutate (the server doesn't exist in a UI test); they expose `Called` / `CalledWith` accessors instead.

**Call site in the View:** the View holds storage in `@Environment` and hands it to the operation:

```swift
public struct PreferencesView: ViewModelView {
    // The reference to the @Observable lives on the View, not the ViewModel.
    @Environment(UserSettings.self) private var settings

    private let viewModel: PreferencesViewModel
    private let operations: any PreferencesViewModelOperations

    public var body: some View {
        VStack {
            Toggle(
                viewModel.notificationsLabel,
                isOn: Binding(
                    get: { viewModel.notificationsEnabled },
                    set: { operations.setNotificationsEnabled($0, output: settings) }
                )
            )
        }
    }

    public init(viewModel: PreferencesViewModel) {
        self.viewModel = viewModel
        self.operations = viewModel.operations
    }
}
```

The ``ViewModel`` itself holds only **scalars** (`notificationsEnabled: Bool`, `theme: Theme`), projected from storage by the parent's `.bind(appState: .init(...))` call. The `UserSettings` reference never crosses the VM boundary — the View's mutation closure reads it from `@Environment` and hands it directly to the op.

See <doc:ApplicationState> for how AppState projects storage scalars into the ``ViewModel``, and for the `.bind(appState:)` call site pattern.

## Rules That Apply to Both Shapes

### `async` Only When the Body Awaits

Do not mark an operation `async` speculatively. An `async` operation's call site becomes `Task { try await op(...) }` in the View — each tap spawns an independent unstructured [Task](https://developer.apple.com/documentation/swift/task), and SwiftUI does not serialize them. For operations that just mutate state synchronously, multiple rapid taps can complete out of order, so the last write to storage may not reflect the last tap. The user sees a stepper "stick on the wrong number" after rapid taps.

Mark `async` only when the body genuinely awaits something — network I/O, device I/O, disk. If a lower layer is async, the operation that wraps it is correctly async; that's the rule's exception, not its default.

### Never Fail Silently

No `try?`, no empty `catch {}`. Every error must surface — to observable state, a logger, or a real error-handling path:

```swift
// ❌ Wrong — error vanishes
Task {
    try await operations.sendUpdate(update)
}

// ✅ Right — propagate or report
Task {
    do {
        try await operations.sendUpdate(update)
    } catch {
        settings.lastError = error
        logger.error("update failed: \(error)")
    }
}
```

Surfacing to observable state (`settings.lastError = error`) is the entry point into the standard error rendering pipeline — the `@Observable` write triggers re-projection, and the error scalar flows into a client-hosted error ``ViewModel`` for display.

## Testing Operations

Interactive Views subclass `ViewModelViewTestCase<VM, VMO>`; the `StubOps` is passed through to the app under test by the [Test Data Transporter](<doc:ViewTesting>), and tests retrieve it via `viewModelOperations()` to assert on what was called. Display-only Views subclass `ViewModelDisplayTestCase<VM>` and take no Operations type at all.

See <doc:ViewTesting> for the full testing setup on both paths.

## Topics

- <doc:ClientOverview>
- <doc:ServerOverview>
- <doc:ApplicationState>
- <doc:ViewModelandViewModelRequest>
- ``ViewModelOperations``
- ``ViewModel``
