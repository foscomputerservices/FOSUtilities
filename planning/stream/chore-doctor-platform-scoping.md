---
status: open
last_updated: 2026-10-04
origin: fosline (cross-session message, at David's word)
---

`fosmvvm-doctor` applies macOS-only signing rules to app targets on other platforms, so a project `fosmvvm-bootstrap new` emitted fails its own doctor run. Reported by fosline 2026-10-04: `swift package fosmvvm-doctor --json --shape clientServer` at fosline's root returns two errors on `FOSTraderWatch`, a watchOS app target bootstrap emitted from the clientServer shape with Watch chosen. Under the review gate (structural errors halt the area review) fosline's five libraries got no area review.

## Goal

Doctor's hardened-runtime and app-sandbox rules fire only on targets that build for macOS, every doctor error a project may reasonably decline carries a `rule` identifier, and a fresh multi-platform bootstrap passes doctor clean.

## Input

- **R12 misclassifies the target.** `ProjectRule+BuildSettings.swift:129` gates on `target.buildsForMacOS`, which is `true` when `MACOSX_DEPLOYMENT_TARGET` is set (`ProjectRule.swift:143`). Doctor merges project-level settings into each target (`AuditedProject.swift:236`), and XcodeGen writes `MACOSX_DEPLOYMENT_TARGET = 27.0` at project level for a suite whose `deploymentTarget:` names macOS. The watch target's own `SDKROOT = watchos` is never consulted. Every non-macOS app target in such a suite is misread the same way.
- **R7 has no platform gate.** `ProjectRule+Shape.swift:39` iterates every `target.kind == .application` and requires `com.apple.security.app-sandbox`, which is a macOS-only entitlement. A pure iOS, tvOS or watchOS app target fails it.
- **Undisableable findings.** "declares no entitlements file." (R7) and both R12 findings carry no `rule`; `DisableableRule` (`Finding.swift:63`) has one case, `appSandbox`, reached only when an entitlements file exists but lacks the sandbox key. So `doctor.disabled_rules` cannot record a reasoned choice against them.
- fosline evidence: `/Users/david/Repository/FOS/fosline/validation/fosmvvm-review-2026-10-04.md` (Structure section); `project.yml` target `FOSTraderWatch` (`type: application`, `platform: watchOS`); pinned FOSUtilities `36d1426` (0.19.0 content), plugin 2.67.0. fosline added nothing to the watch target to appease doctor.
- The macOS app target `FOSTrader` carries both settings as the template emitted them, so the macOS half of each rule is working.

## Rulings

- **OQ7** (David, 2026-10-04): iOS, tvOS and watchOS app targets carry nothing for R7 or R12; doctor skips both rules for them. The OS sandboxes those apps unconditionally, `app-sandbox` and `network.client` are macOS keys, and hardened runtime and notarization exist only on macOS. An entitlements file there serves app-specific capabilities (push, app groups), not the shape.
- **OQ8** (David, 2026-10-04): "hardened runtime not YES in Release" gets a `DisableableRule` case, since notarization applies only to distribution outside the Mac App Store. "Hardened runtime YES in Debug" and a macOS app with no entitlements file stay undisableable errors; opting out of the sandbox is already covered by `appSandbox`.

## Suggested actions

1. ~~Rule what, if anything, a watchOS, tvOS or iOS app target must carry.~~ Ruled, OQ7.
2. Make `buildsForMacOS` decide by the target's effective `SDKROOT` (and `SUPPORTED_PLATFORMS`) before an inherited deployment target.
3. Scope R7 entirely (missing file, required entitlements, library-validation check) to targets that build for macOS.
4. Add the `DisableableRule` case OQ8 rules, attach it to R12's Release finding, and document it wherever `app_sandbox` is documented for `doctor.disabled_rules`.
5. Add a doctor test over a multi-platform suite fixture (project-level macOS deployment target, watchOS and tvOS app targets) that fails before the fix; confirm a fresh clientServer bootstrap with every platform chosen passes doctor clean.

## History

- 2026-10-04 minted at David's direction from fosline's report; root cause of the R12 misfire traced to the project-level `MACOSX_DEPLOYMENT_TARGET` merge; nothing built
- 2026-10-04 OQ7 and OQ8 ruled as recommended; nothing built
- 2026-10-04 BUILT on fix/doctor-platform-scoping: `buildsForMacOS` decides by SUPPORTED_PLATFORMS, then SDKROOT, then the inherited deployment target; R7 scoped to macOS app targets; `hardened_runtime_release` added (name ruled by David, OQ10); MultiPlatform fixture (macOS+iOS+tvOS+watchOS clientServer) whose clean test fails before the fix; 106 bootstrap tests green; fixed doctor reports fosline clean
