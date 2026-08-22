---
name: entitlement-disable-library-validation
description: When disable-library-validation is required vs. a symptom of wrong shape — updated for Xcode 16+ dynamic SPM behavior
metadata:
  type: feedback
---

## Xcode 16+ (ENABLE_DEBUG_DYLIB era)

`com.apple.security.cs.disable-library-validation` is **required** when:

- `ENABLE_DEBUG_DYLIB = YES` on the app target, AND
- `ENABLE_HARDENED_RUNTIME = YES` on the app target

**Why:** `ENABLE_DEBUG_DYLIB` forces SPM `.automatic` packages to build as
dynamic frameworks in `PackageFrameworks/`. Those are linker-signed (ad-hoc,
TeamIdentifier=not set). Hardened runtime rejects loading them into a
developer-signed process (Team ID mismatch). The entitlement permits it.

This is **not** a shape defect — it is the correct companion entitlement for
the dynamic-package build mode Xcode 16 introduced.

**How to apply:** Add to the app target's `.entitlements` file alongside
`app-sandbox`. See [[xcode16-dynamic-spm-packages]].

---

## Pre-Xcode 16 (static SPM era) — historical

Old guidance: you only need the entitlement when embeds ad-hoc PackageFrameworks
(wrong shape) or signing is off. Correct shape (static SPM → SPMLibraries →
signed) made the entitlement unnecessary.

That guidance is **obsolete** for projects using `ENABLE_DEBUG_DYLIB = YES`.
