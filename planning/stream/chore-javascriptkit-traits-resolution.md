---
status: open
last_updated: 2026-09-30
origin: session
---

SwiftPM 6.4 refuses to resolve JavaScriptKit above 0.26.2 for this package: "Disabled default traits on package 'javascriptkit' (JavaScriptKit) that declares no traits. This is prohibited to allow packages to adopt traits initially without causing an API break." The resolver falls back to 0.26.2 (tools-version 5.x, no traits). Pinning 0.46.3 (tools 6.1, no traits) or 0.59.0 (tools 6.2, declares a `Tracing` trait) by hand in Package.resolved fails the build with the same message; `swift package update JavaScriptKit` returns to 0.26.2. Surfaced 2026-09-30 while re-resolving for the swift-syntax 604.0.0 pin on `feat/datamodel-validation-lifecycle`. Nothing built on Apple or Linux uses JavaScriptKit (`.wasi`-only product condition, `Package.swift:127`), so 0.26.2 is harmless today, but the wasi work David wants to resume needs a current JavaScriptKit.

## Goal

FOSUtilities resolves a current JavaScriptKit (0.59.0 or later) under SwiftPM 6.4 without the traits refusal, on every CI leg, with the wasi product condition intact.

## Input

- `Package.swift:98` — `.package(url: "https://github.com/swiftwasm/JavaScriptKit", from: "0.19.0")`; `:127` — `.product(name: "JavaScriptKit", package: "JavaScriptKit", condition: .when(platforms: [.wasi]))`. FOSUtilities passes no `traits:` anywhere, so the "disabled default traits" comes from SwiftPM's own handling, likely of the platform-conditioned product dependency.
- The message names `javascriptkit` even when 0.59.0 (which declares `traits: [tracingTrait]`) is pinned, so the check is not reading the pinned manifest, or applies to a manifest in JavaScriptKit's own dependency graph.
- The pin that works: revision `f4d52190ad1a4011c489165d43d25ae8e321bc4d`, version 0.26.2 (committed in `aa22146`).
- Related memory: the 0.4.0 release made Yams dormant for WASM; the wasi build has not been exercised since.

## Suggested actions

1. Reproduce with a minimal package: one target, `.product(... condition: .when(platforms: [.wasi]))` on JavaScriptKit 0.59.0, SwiftPM 6.4. Determine whether the refusal is the platform condition, the `from:` range spanning trait-less and trait-declaring versions, or a SwiftPM bug; check swiftlang/swift-package-manager issues for the message text.
2. If the range is the cause, raise `from:` to the first trait-declaring release and add `traits: [.defaults]` or the explicit `Tracing` decision.
3. Verify on the Linux 6.3.2 legs and the Xcode 26.3 floor leg; CHANGELOG line.
4. Then the wasi build itself: a `swift build --triple wasm32-unknown-wasi` smoke on a CI leg, as the entry to resuming the wasi work.

## History

- 2026-09-30 minted from the swift-syntax 604.0.0 pin; 0.26.2 accepted on the lifecycle branch
- 2026-09-30 David: deferred until after PR #157 and feat-containerless-loads
