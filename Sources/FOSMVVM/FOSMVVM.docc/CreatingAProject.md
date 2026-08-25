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

`doctor` audits a project against the same rules the scaffolder generates by, and tells you what has drifted. It never changes anything.

There are two ways to run it, and which one applies depends on whether your project has a `Package.swift`.

### Your project is a Swift package

Client-server and shared-library projects are. If the package already depends on FOSUtilities, there is nothing to install — run it from the project directory:

```bash
swift package fosmvvm-doctor --shape clientServer
```

### Your project is an Xcode project only

An app with a `.xcodeproj` and no package manifest — the local-only shape, and most apps that predate FOSUtilities — cannot use the command plugin: `swift package` has no manifest to attach to and stops with `Could not find Package.swift`.

Run the audit from a FOSUtilities checkout instead, pointing it at your project:

```bash
git clone https://github.com/foscomputerservices/FOSUtilities.git
cd FOSUtilities
swift run fosmvvm-bootstrap doctor --project ~/MyApp --shape localOnly
```

The first run builds the scaffolder, so it takes a few minutes; later runs are immediate. The checkout is only a host for the command — nothing is written to it, and nothing is written to your project either.

> Note: A standalone binary you could install once, without the checkout, is planned. Until it ships, the checkout is the supported route for Xcode-only projects.

Reach for it after adding a framework target by hand, or when adopting FOSUtilities in a project the scaffolder never created. The settings it checks are the ones that fail far from their cause: a second direct link to a FOS product (two non-identical copies of the same types, so `is` and `as?` fail across target boundaries at runtime), a misspelled `BUILD_LIBRARY_FOR_DISTRIBUTION` that Xcode silently ignores, a missing `DEVELOPMENT_TEAM` that surfaces as a dyld rejection at launch, a deployment target below the FOSUtilities floor, and a test plan pointing at target identifiers a regeneration re-minted. It also audits the shared-module doctrine: ViewModels declared outside a shared ViewModels module, and server imports (Vapor, Fluent) inside one.

Every finding names the setting and the value to use, because fixing it is yours to do.

Findings are either errors or warnings, and `doctor` exits non-zero only when there is at least one error — so it works as a build step or a gate in a generator skill.

For tooling that parses rather than reads, pass `--json` to either door: the report becomes stable, sorted-key JSON carrying `findings` (each with `severity`, `target`, `summary`, and `remedy`), `unchecked`, and a `hasErrors` verdict. The `fosmvvm-review` skill runs exactly this as its structural first pass.

> Note: `--shape` is optional but worth passing. Two rules — entitlements posture and localization YAML layout — can only be judged against a known shape, and without one they are listed as unchecked rather than guessed at.

A clean project says so:

```
✅ No findings — the project matches the generated structure.
```
