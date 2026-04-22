# FOSMVVM Architecture Patterns

Mental models for working with FOSMVVM. Reference this when you find yourself creating abstractions or over-engineering.

---

## Trust the Type System

Swift's type system and FOSMVVM's macros handle the complexity. Your job is to use them, not rebuild them.

**Red flags - if you're thinking any of these, STOP:**

| Thought | Reality |
|---------|---------|
| "How do I detect if this is an error?" | You caught the concrete type. You already know. |
| "What if the localization isn't done?" | It is. The server/macro handled it. |
| "Should I create a protocol for...?" | No. Three similar lines of code beats a premature abstraction. |
| "How do I handle all error types uniformly?" | You don't. Each route catches its specific type. |
| "What format should error responses use?" | ViewModel → View. Same as everything else. |
| "Do I need to configure...?" | Probably not. The macro generates it. |

**The FOSMVVM contract:** If you use `@ViewModel`, `@ViewModel(options: [.clientHostedFactory])`, or `ServerRequest` correctly, they work. No defensive code needed. No edge cases to handle. The infrastructure is tested.

---

## Error UI Is Not Special

**Errors are just data to render.** The ViewModel → View pattern still applies.

When you display a user profile, you:
1. Get data (ViewModel)
2. Pass it to a template
3. Render

When you display an error, you:
1. Get data (ResponseError)
2. Wrap in a client-hosted ViewModel
3. Pass it to a template
4. Render

**Same pattern.** The only difference: error data already exists (from the caught `ResponseError`), so you use a **client-hosted ViewModel**.

Do NOT create:
- `ErrorDisplayable` protocol
- Generic error handling middleware
- Unified error architecture
- Runtime type discovery for errors

**The pattern:**
```swift
// Client-hosted ViewModel for THIS SPECIFIC error
@ViewModel(options: [.clientHostedFactory])
struct MoveIdeaErrorViewModel {
    let message: LocalizableString
    let errorCode: String

    public var vmId = ViewModelId()

    // Takes the specific ResponseError - tight coupling is good here
    init(responseError: MoveIdeaRequest.ResponseError) {
        self.message = responseError.message
        self.errorCode = responseError.code.rawValue
    }
}

// WebApp route - you KNOW the request type, so you KNOW the error type
catch let error as MoveIdeaRequest.ResponseError {
    let vm = MoveIdeaErrorViewModel(responseError: error)
    return try await req.view.render("Shared/ToastView", vm)
}
```

**Each error scenario gets its own ViewModel** - just like any other UI:
- `MoveIdeaErrorViewModel` for `MoveIdeaRequest.ResponseError`
- `CreateIdeaErrorViewModel` for `CreateIdeaRequest.ResponseError`
- `SettingsValidationErrorViewModel` for settings form errors

Don't create a generic "ToastViewModel" or "ErrorViewModel" - that's the unified architecture we're avoiding.

**Why client-hosted?** You already have the error data from `ResponseError`. No server fetch needed. The macro generates the factory from the init parameters.

**Note:** The `LocalizableString` properties in `ResponseError` are **already localized** - the server localized them when encoding the error response. The standard ViewModel → View encoding chain handles this correctly; already-localized strings pass through unchanged.

Each error scenario is a **UX design decision**, not a type system problem:
- What does the user need to understand?
- What action can they take?

---

## Type Safety Means You Already Know

In Swift, you know the types at compile time. Don't write code that "discovers" types at runtime.

**Wrong (JavaScript brain):**
```swift
catch let error as ServerRequestError {
    // "How do I get the message? What properties does it have?"
    // This thinking is wrong - you're not in a typeless world
}
```

**Right (Swift brain):**
```swift
catch let error as MoveIdeaRequest.ResponseError {
    // I KNOW this type. I KNOW its properties. No mystery.
    switch error.code {
    case .ideaNotFound: // I defined this
    case .invalidTransition: // I defined this
    }
}
```

---

## Views Render Data, They Don't Shape It

If a View/template is concatenating strings, formatting dates, or reordering text, the logic is in the wrong layer.

**Wrong:**
```html
#(user.firstName) #(user.lastName)  <!-- Hardcoded order, breaks RTL/locales -->
#date(content.createdAt, "MMM d, yyyy")  <!-- Hardcoded format -->
```

**Right:**
```html
#(user.fullName)  <!-- ViewModel composed it with locale awareness -->
#(content.createdDisplay)  <!-- ViewModel formatted it -->
```

The ViewModel shapes data for presentation. The View just renders what it receives.

(This doesn't prohibit nested ViewModels - `struct VM1 { let inner: VM2 }` is fine. The principle is about *data* shaping, not *structural* composition.)

---

## Don't Abstract One-Time Operations

If you're creating a helper, utility, or protocol for something that happens once, stop.

Three similar lines of code is better than a premature abstraction.

---

## ServerRequest Is THE Way

Every client-server communication uses ServerRequest. No exceptions.

**Wrong:**
```swift
let url = URL(string: "http://server/api/users/123")!
fetch('/api/ideas/\(id)')
```

**Right:**
```swift
let request = UserShowRequest(query: .init(userId: id))
try await request.processRequest(mvvmEnv: mvvmEnv)
```

If you're about to write a URL string, stop and create a ServerRequest.

---

## Computed Properties Don't Serialize

ViewModels are transmitted as JSON. Computed properties don't exist in JSON - only stored properties serialize.

**Wrong:**
```swift
@ViewModel
struct CardViewModel {
    let cards: [Card]
    var hasCards: Bool { !cards.isEmpty }  // Disappears after JSON round-trip
    var cardCount: Int { cards.count }     // Disappears after JSON round-trip
}
```

**Right:**
```swift
@ViewModel
struct CardViewModel {
    let cards: [Card]
    let hasCards: Bool      // Stored - survives serialization
    let cardCount: Int      // Stored - survives serialization

    init(cards: [Card]) {
        self.cards = cards
        self.hasCards = !cards.isEmpty
        self.cardCount = cards.count
    }
}
```

If a Leaf template or SwiftUI view needs a derived value, pre-compute it in `init()` and store it.

---

## The Four Rules of Forward Projection

Everything else about the View ↔ ViewModel ↔ Env relationship in FOSMVVM reduces to these four:

1. **The ViewModel is the only thing Views read.** A View never touches `@Environment(SomeObservable.self)` (or `@State`, `@Binding` to one) for display data. The VM owns presentation.

2. **`@Observable` state is the only thing Operations write.** Views dispatch actions to ops; ops mutate the env; Views never mutate env directly. For client-side ops, the `@Observable` is passed *into* the op function. For server-backed ops, the server owns the `@Observable`-equivalent (usually a database), so no pass-through is needed.

3. **Re-projection happens at the top of the subtree that owns the `.bind`.** The parent whose body constructed the child's `AppState` is the one that re-reads `@Observable` properties on change and re-builds the child VM. That parent's body is where the **projection edge** lives.

4. **The VM holds scalars only; `@Observable` references live on the View via `@Environment(X.self)`.** Not as a View init parameter, `@State`, or `@Bindable` — `@Environment`. When a mutation needs the reference (e.g., to pass to an op as `output storage:`), the View's mutation closure reads the env and hands it over. The VM never stores an `@Observable` reference, **even as a pass-through for child binds**.

Violations of these rules produce the exact bugs you'd expect: stale UI (rule 1), non-functional mutations or double-mutations (rule 2), missed invalidations when scalars get extracted at the wrong site (rule 3), imperative reference leakage into VMs and from VMs into Views (rule 4).

Rule 3 fails in a specific way worth naming: SwiftUI only registers `@Observable` tracking for reads that happen inside a **View body**. Reads that happen inside a VM `init` register nothing. If scalars get extracted from storage anywhere other than the View body that calls `.bind(...)`, the invalidation tree is silently broken — the VM will compile, render once, and then stop updating.

---

## Where the Projection Edge Lives

The `.bind(appState: .init(...))` call site is not just a constructor — it's where SwiftUI's `@Observable` tracking wires itself to your ViewModel pipeline.

**Mental model:**

- Views read pure VM scalars. No `@Observable` tracking happens at the view-body level for those reads; they're just value reads on a struct.
- Tracking lives at the **parent body** — the one where `AppState` is constructed. Reading `settings.isEnabled` in that body is what registers `@Observable` tracking. When `isEnabled` changes, SwiftUI invalidates **the parent**, which passes a new `AppState`, which the resolver re-projects into a new VM.
- VM rebuilds are automatic — the resolver body re-runs the model factory on every invalidation; scalar fields are recomputed each time.

**Why this matters in practice:**

```swift
// Parent body — the projection edge
var body: some View {
    PreferencesView.previewHost(...)
        .bind(appState: .init(
            notificationsEnabled: settings.notificationsEnabled,  // ✅ read here registers tracking
            theme: settings.theme,                                // ✅ read here registers tracking
            fontSize: settings.fontSize                           // ✅ read here registers tracking
        ))
}
```

Reading `settings.notificationsEnabled` in the child's body (after projection) does NOT register tracking for the parent — by then the value is a scalar on the struct. That's why rule 1 is non-negotiable: if the child reads env directly, the projection edge gets bypassed and invalidation routing breaks.

Note what the `.init(...)` arguments are **not**: the `@Observable` reference itself. Even though the VM needs those values to come from `settings`, and even though the ops that will write back to `settings` need the reference, the reference does not pass through the VM. The View holds its own `@Environment(UserSettings.self)` and hands the reference directly to the op inside a mutation closure (see rule 4).

---

## VMs Hold Scalars, Not `@Observable` References

Top-level VMs are snapshots. Stored properties are `Bool`, `Int`, `Double`, `String`, enums, or value-type structs. **No `@Observable` class references** as stored properties.

**Wrong:**
```swift
@ViewModel
struct PreferencesPageViewModel {
    let userSettings: UserSettings    // ❌ grab-bag @Observable
    // ...rationale: "so the child can .bind through me"
}
```

**Right:**
```swift
@ViewModel
struct PreferencesPageViewModel {
    let notificationsEnabled: Bool    // ✅ scalar projection
    let theme: Theme                  // ✅ scalar projection
    // child does .bind from its own parent, not through this VM
}
```

If a child's `.bind(appState: ...)` needs `UserSettings`, the child's **direct parent body** should read that env and construct the `AppState` — not route the reference through an ancestor VM.

---

## `.bind(appState:)` Takes Scalars, Not `@Observable` Instances

`AppState` is a value type (`struct`). The data store is an `@Observable final class`. They may share property **names**, but they have different functional **contracts** — mutability, identity, tracking semantics. They are **not** freely substitutable.

`.bind(appState: .init(...))` is where the `ViewModelFactory` transform happens for `clientHostedFactory` VMs. That transform must be **explicit at the call site** — extract scalars, hand them over.

**Wrong:**
```swift
.bind(appState: .init(settings))   // ❌ passing @Observable instance
// "the property names match, why not just hand it over"
```

**Right:**
```swift
.bind(appState: .init(
    notificationsEnabled: settings.notificationsEnabled,  // ✅ scalar extraction
    theme: settings.theme,
    fontSize: settings.fontSize
))
```

Why the shortcut fails: the struct captures a snapshot of names-and-values. Handing over the `@Observable` reference instead smuggles mutability and identity into a context that expects neither, corrupts projection, and breaks invalidation tracking at the edge (rule 3).

**Red flag — if you're thinking any of these, STOP:**

| Thought | Reality |
|---------|---------|
| "The property names match, this is the same thing" | Names are not contracts. One is mutable and identity-bearing; one is a value snapshot. |
| "I'll just pass the class through, it'll compile" | It'll compile and silently break projection. |
| "The struct is a pointless restatement" | The restatement *is* the transform. Removing it removes the projection boundary. |

---

## Ops Conventions

Client-hosted ops — the methods on your `ViewModelOperations` protocol that mutate `@Observable` storage — follow a small set of conventions covering where they live, their signature, their async-ness, and what they don't do. These conventions exist because client-hosted ops mirror server-side storage with one key asymmetry: on the server the storage path is implicit (Vapor request context); on the client it must be explicit.

### Client-Hosted Mirror of Server-Side Storage

FOSMVVM's core invariant is the same on both sides of the wire:

```
ViewModelFactory.model(context: <storage>) -> ViewModel
```

The difference is *where `<storage>` comes from*.

**Server-hosted.** `<storage>` is the database (or whatever the server persists to), reached through the Vapor request context that `MVVMEnvironment` and `deploymentURLs` configured once at startup. Every op on the server has an implicit path to storage — you don't pass it, the server context already has it.

**Client-hosted.** There is no implicit server context. Storage lives in one or more `@Observable` classes held in `@Environment`. Nothing makes this implicit, so the convention makes it explicit in every op that writes back:

```swift
protocol MyViewModelOperations: ViewModelOperations {
    func myOp(<scalar inputs>, output storage: SomeObservable)
}
```

- Scalar inputs describe **what** changed.
- The write target is the **last** parameter, labeled `output`.
- **Server-backed ops omit `output:`** — the server owns storage, nothing to pass.

### Where Ops Live

On the same `ViewModelOperations` protocol you'd define for any op — not a free function. The protocol is the seam `TestDataTransporter` and stub-ops testing rely on. The `output storage:` convention *extends* that protocol for the client-hosted case; it doesn't bypass it.

```swift
protocol PreferencesViewModelOperations: ViewModelOperations {
    func setTheme(_ theme: Theme, output storage: UserSettings)
}

struct PreferencesOps: PreferencesViewModelOperations {
    func setTheme(_ theme: Theme, output storage: UserSettings) {
        storage.theme = theme
    }
}

final class PreferencesStubOps: PreferencesViewModelOperations, @unchecked Sendable {
    public private(set) var setThemeCalled: Bool = false

    func setTheme(_ theme: Theme, output storage: UserSettings) {
        setThemeCalled = true
        storage.theme = theme
    }
}
```

At the call site, the View reads storage from `@Environment` and hands it to the op:

```swift
Button("Dark") {
    viewModel.operations.setTheme(.dark, output: settings)
}
```

### Signature: Inputs First, `output` Last

**Wrong (buried output, ambiguous label):**
```swift
func applyPreferences(
    storage: UserSettings,            // ❌ buried mid-list, no `output` label
    theme: Theme,
    notificationsEnabled: Bool,
    fontSize: FontSize
)
```

**Right:**
```swift
func applyPreferences(
    theme: Theme,
    notificationsEnabled: Bool,
    fontSize: FontSize,
    output storage: UserSettings      // ✅ last, labeled `output`
)
```

**Why `in storage:` is the wrong label.** `in` reads like an input — it conflates the write target with the scalar inputs that describe the change. One label per role: inputs describe **what** changed, `output` describes **where to write**.

Ops must also not read `storage` for branch decisions. All branches switch on the scalar inputs the caller supplied. If you want to read `storage.foo` to decide something, that scalar belongs in the signature.

### Not `async` by Default

`async` is a statement about what the body does, not a speculative option for future flexibility. Mark an op `async` only when the body genuinely `await`s something.

```swift
// ❌ Gratuitous async — body does no awaiting
func setTheme(_ theme: Theme, output storage: UserSettings) async {
    storage.theme = theme
}

// ✅ Synchronous — matches the body
func setTheme(_ theme: Theme, output storage: UserSettings) {
    storage.theme = theme
}
```

**Why this matters in SwiftUI:** an `async` op call site becomes `Task { try await op(...) }`. Each tap spawns an independent unstructured Task; SwiftUI does not serialize or coalesce them. Multiple in-flight Tasks may complete out of order, so the last write to storage may not reflect the last tap — the user sees the stepper "sometimes stick on the wrong number" after rapid taps.

If a lower layer is async (device I/O, network, disk), the op that wraps that lower layer is async because it `await`s — that's fine. The rule targets ops that add `async` purely "in case we need it later" or "because every other op is async."

### Anti-Pattern: Confusing Storage with VM State

The single biggest failure mode is treating the `@Observable` storage as if it were VM state. It isn't. The VM is a `Codable` snapshot produced from scalars extracted from storage (storage → `AppState` → VM) by the factory — the reference never crosses that chain. If you catch yourself:

- Storing an `@Observable` reference as a VM property ("so the child can bind through me"), **or**
- Writing back to state through the VM instead of through `output storage:`, **or**
- Reading an `@Observable` in a View body for display (instead of reading VM scalars)

…you've conflated the two. The fix is always the same: the reference lives on the View via `@Environment`, scalars flow through the VM via `AppState`, and mutations take storage as an explicit `output storage:` parameter on the op.

---

## Never Fail Silently

No error path may swallow its error. Every failure surfaces — to observable state, a logger, or a real error-handling path.

**Wrong — error vanishes into an empty `Task`:**
```swift
Task {
    defer { refresh() }
    try await onThemeChanged(viewModel.theme)   // ❌ throw → nowhere
}
```

**Wrong — fallible op returns `Void`:**
```swift
func sendUpdate(_ update: Update, service: RemoteService) {
    try? service.send(update)    // ❌ caller can't tell success from failure
}
```

**Right — propagate or report:**
```swift
Task {
    defer { refresh() }
    do {
        try await onThemeChanged(viewModel.theme)
    } catch {
        settings.lastError = error   // ✅ surfaces to UI via projection
        logger.error("theme change failed: \(error)")
    }
}
```

**Red flag — if you're thinking any of these, STOP:**

| Thought | Reality |
|---------|---------|
| "I'll add `try?` to quiet the compiler" | You are silencing the only signal you had that something broke. |
| "An empty `catch {}` is fine for now" | "For now" becomes "forever" and the bug is undiscoverable. |
| "This op can't really fail in practice" | Then don't mark it `throws`. If it's marked `throws`, handle it. |

Silent failures mask real bugs and make downstream debugging impossible. If you don't know what to do with an error yet, store it on the data store or log it — but never let it vanish.

**Surfacing to storage is the entry point into the render pipeline.** Setting `settings.lastError = error` is exactly the projection edge at work — the `@Observable` write triggers re-projection, the error scalar flows into a VM, and that VM renders via the client-hosted pattern described in **Error UI Is Not Special** above. The two sections describe the two ends of the same pipeline: this section covers *how the error reaches observable state*; "Error UI Is Not Special" covers *how observable error state becomes a rendered view*.

---

## Shared Module Is Required

FOSMVVM projects need a shared target that all other targets import:

```
ViewModels/              ← Shared module
├── ViewModels/
├── Requests/
├── FieldModels/
└── Versioning/
    └── SystemVersion+App.swift

WebServer/  ← imports ViewModels
WebApp/     ← imports ViewModels
iOSApp/     ← imports ViewModels
CLITools/   ← imports ViewModels
```

The shared module contains:
- **ServerRequest types** - API contract
- **ViewModels** - Response shapes
- **Fields protocols** - Validation logic
- **SystemVersion** - Version constants

Without this, types drift apart between client and server.

---

## MVVMEnvironment Configured Once

Configure MVVMEnvironment at application startup. Use it everywhere. Never pass raw URLs or headers.

**Wrong:**
```swift
// Scattered configuration
try await request.fetch(baseURL: someURL, headers: someHeaders)
try await request.fetch(baseURL: differentURL, headers: otherHeaders)
```

**Right:**
```swift
// At startup (once)
let mvvmEnv = await MVVMEnvironment(
    currentVersion: .currentApplicationVersion,
    appBundle: Bundle.module,
    deploymentURLs: [.debug: URL(string: "http://localhost:8080")!]
)

// Everywhere else
try await request.processRequest(mvvmEnv: mvvmEnv)
```

This applies to iOS apps, WebApps, CLI tools, background jobs - all clients configure once, use everywhere.
