# ``FOSFoundation``

FOSFoundation is a library that provides extensions and patterns to Apple's Foundation library.

## Overview

``FOSFoundation`` is primarily geared towards providing basic patterns for developing client-server applications.  The base assumption is that the client is an application supported by the swift ecosystem (e.g., iOS, iPadOS, macOS, watchOS, visionOS, .etc...) as well as web clients written in swift (e.g., [WASM Applications](https://swiftwasm.org/), [Vapor Leaf](https://docs.vapor.codes/leaf/getting-started/), [Ignite](https://github.com/twostraws/Ignite)).

``FOSFoundation`` provides the building blocks for its companion framework [FOSMVVM](https://swiftpackageindex.com/foscomputerservices/FOSUtilities/main/documentation/fosmvvm), which provides full client and server support for building [Model-View-ViewModel](https://w.wiki/4T5B) applications.

## Topics

### Networking

- <doc:NetworkingSupport>
- ``Stubbable``
- ``AsyncSemaphore``
- ``DataFetch``
- ``DataFetchError``
- ``JSONError``
- ``WebSocketError``

### Localization

- <doc:LocalizationSupport>

### Extensions

- <doc:FoundationExtensions>
- ``HexadecimalPrefixStyle``

### Testing Support

- ``URLSessionProtocol``
