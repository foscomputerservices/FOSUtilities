# Networking

APIs and patterns to simplify communication between client applications and REST servers that return JSON.

## Overview

The heart of ``FOSFoundation``'s networking support rests on a ``DataFetch``, which
embodies a *URLSession* and adds REST-style APIs that combines REST semantics, Codable
and Error to provide an simple and concise API for making round-trip requests to
web servers.

## URL Extension Methods

While ``DataFetch`` can be used directly, it is expected that the
extension methods on **URL** are used more often.  Those methods provide
the same power as calling ``DataFetch`` directly, but provide
a more concise API.

### URL Example

```swift
struct MyServerError: Decodable, Error { ... }
string MyType: Decodable { ... }
let url = URL(string: "https://myServer/myType")!
let myType: MyType = try await url.fetch(errorType: MyServerError.self)
```

### DataFetch Example

```swift
struct MyServerError: Decodable, Error { ... }
string MyType: Decodable { ... }
let url = URL(string: "https://myServer/myType")!
let dataFetch = DataFetch<URLSession>.default
let myType: MyType = try await dataFetch.fetch(url, errorType: MyServerError.self)
```

## Waiting before retrying

When a service rate-limits you or is briefly unavailable and says when to come back, ``DataFetchError/retryAfter(_:)`` carries the wait as a **Duration**:

```swift
for _ in 1..<3 {
    do {
        return try await boardURL.fetch()
    } catch DataFetchError.retryAfter(let wait) {
        try await Task.sleep(for: wait)
    }
}
return try await boardURL.fetch()
```

> Note: `DataFetch` reads the standard `Retry-After` header in both of its forms, so there is no need to check status codes yourself.

## Adapting a service's own responses

When a service reports problems its own way, such as an error body with a `Retry-After`, or a 200 that carries a failure, adapt it once with ``DataFetch/init(urlSession:errorForResponse:)``. The hook sees each response first and returns your error, or `nil` to let `DataFetch` carry on:

```swift
let dataFetch = DataFetch(urlSession: session) { response, data in
    guard response.statusCode == 429,
          let data, let body: ExchangeError = try? data.fromJSON(),
          let seconds = response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
    else { return nil }
    return RateLimited(message: body.msg, wait: .seconds(seconds))
}
```
