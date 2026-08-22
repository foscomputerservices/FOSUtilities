# Creating a Project

Scaffold a complete, verified FOSMVVM application in about a minute.

## Overview

FOSUtilities ships a scaffolder, `fosmvvm-bootstrap`, that generates a ready-to-run project wired to the patterns described throughout this documentation: ViewModels with localization, the operations seam, UI-test harnesses, and (for client-server projects) a Vapor + Fluent server with live view-model refresh.

Three project shapes are supported:

| Shape | What you get |
| --- | --- |
| `localOnly` | A SwiftUI app with client-hosted ViewModels. No server. |
| `clientServer` | A SwiftUI app plus a Vapor server sharing one ViewModel contract, including a live server-fetched screen backed by Fluent. |
| `sharedLibrary` | A Swift package that publishes a ViewModel contract for other apps to consume. |

## Prerequisites

- Xcode (the app shapes generate an Xcode project)
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Generate

Clone the package and run the scaffolder. With no `--config`, a short interview collects everything it needs, validating each answer as it is given:

```bash
git clone https://github.com/foscomputerservices/FOSUtilities.git
cd FOSUtilities
swift run fosmvvm-bootstrap new --output ~/MyApp
```

With `--verbose`, the interview also prints the equivalent `--config` JSON. Save it to rerun without the questions, or to script generation:

```bash
swift run fosmvvm-bootstrap new --config myapp.json --output ~/MyApp
```

Configuration fields:

- `projectName`: the app and target name.
- `shape`: `localOnly`, `clientServer`, or `sharedLibrary`.
- `platforms`: platform to minimum-version map. Versions must meet the FOSUtilities floors.
- `bundleIdRoot`: reverse-DNS root for bundle identifiers. App shapes only.
- `teamId`: your Apple Development Team identifier. App shapes only.

## Verifying the generated project

Every release of the scaffolder is verified by CI: the generated projects are built and their test suites run, including the UI tests. To additionally prove the skeleton on your machine, pass `--verify` — the scaffolder then builds the generated project and runs its tests before declaring success: `swift build`, `swift test` (for `clientServer` this includes a real Fluent create-and-refresh round trip on an in-memory database), and an `xcodebuild` build of the app. A successful verified run ends with:

```
✅ Walking skeleton verified green
```

Either way, generation finishes with a short checklist of the few steps tooling cannot do for you, such as committing the new repository and confirming code signing.

> Note: The generated project depends on the FOSUtilities release the scaffolder shipped with, using `from:`, so later releases arrive with a normal package update. Running the scaffolder from a checkout between releases pins the most recently stamped release.

## Diagnosing an existing project

A `doctor` command that audits an existing project against the same rules the scaffolder uses is planned as an SPM command plugin.
