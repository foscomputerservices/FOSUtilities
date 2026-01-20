# FOSMVVM Architecture Patterns

Mental models for working with FOSMVVM. Reference this when you find yourself creating abstractions or over-engineering.

---

## Error UI Is Not Special

**Errors are just data to render.**

When you display a user profile, you:
1. Get data (ViewModel)
2. Pass it to a template
3. Render

When you display an error, you:
1. Get data (error code + message)
2. Pass it to a template
3. Render

There is no difference. Do NOT create:
- `ErrorDisplayable` protocol
- `ErrorPageViewModel`
- `ToastViewModel`
- Unified error handling architecture

**The pattern:**
```swift
// WebApp route - you KNOW the request type, so you KNOW the error type
catch let error as MoveIdeaRequest.ResponseError {
    // Pass error data to template - that's it
    return try await req.view.render("Shared/Toast", [
        "message": error.message.value,
        "code": error.code
    ])
}
```

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
