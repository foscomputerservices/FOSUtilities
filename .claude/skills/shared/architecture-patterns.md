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
