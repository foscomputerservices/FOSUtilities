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
