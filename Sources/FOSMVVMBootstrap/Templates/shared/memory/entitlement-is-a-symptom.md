---
name: entitlement-disable-library-validation
description: disable-library-validation is a symptom of the wrong embedding or signing shape, never a fix — the scaffold's shape does not need it
metadata:
  type: feedback
---

`com.apple.security.cs.disable-library-validation` is **not** part of this project's shape. If it appears in the app's entitlements, something upstream is wrong.

**Why it is a symptom:** the entitlement tells the hardened runtime to accept frameworks signed by a different Team ID. The only frameworks that would trip that check are ad-hoc-signed SPM package frameworks loaded into a hardened-runtime process. The scaffold never puts the app in that position:

- Every SPM product enters through the single `SPMLibraries` umbrella framework (see [[spm-libraries-settled]]).
- The app alone embeds `SPMLibraries` and re-signs it with the developer's team (`embed: true`, `codeSign: true`). Nothing ad-hoc-signed ships inside the bundle.
- `ENABLE_HARDENED_RUNTIME` is `NO` in Debug and `YES` in Release. Debug keeps macOS UI testing alive; Release keeps notarization.
- `ENABLE_DEBUG_DYLIB` is left unset. Setting it forces SPM packages to build as separate dynamic `PackageFrameworks/`, which is exactly the ad-hoc-signed-framework situation above.

**What to do when it is present:** remove the entitlement and fix the cause. `fosmvvm-doctor` (`swift package fosmvvm-doctor`, or `fosmvvm-bootstrap doctor --project <root>`) names the cause: a framework embedding `SPMLibraries` instead of link-only, hardened runtime on in Debug, or signing off.

**Do not** add the entitlement as a workaround for a dyld crash on launch ("different Team IDs"). That crash is the hardened-runtime-in-Debug finding; the answer is R12, not an entitlement.
