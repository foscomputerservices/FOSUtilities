# Localization

Patterns and APIs to streamline cross-platform application localization.

## Overview

When writing applications that exclusively use Apple's APIs, [Apple provides Localization APIs](https://developer.apple.com/localization/) that work very well and should be considered as opposed to these APIs.  ``FOSFoundation``'s Localization APIs should be considered for applications that have any of the following criteria:

- Require (or desire) localization to be performed on the server instead of the client application
- Swift applications that will run on non-Apple platforms (e.g., [WASM Applications](https://swiftwasm.org/), [Vapor Leaf](https://docs.vapor.codes/leaf/getting-started/), [Ignite](https://github.com/twostraws/Ignite))

### [YAML](https://yaml.org/)

``FOSFoundation``'s localization support is based on YAML files
