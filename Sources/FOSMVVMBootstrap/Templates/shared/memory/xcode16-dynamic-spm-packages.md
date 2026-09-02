---
name: xcode16-dynamic-spm-packages
description: ENABLE_DEBUG_DYLIB was evaluated as a replacement for SPMLibraries and is not the scaffold's shape — leave it unset; SPMLibraries stands
metadata:
  type: project
---

**Do not set `ENABLE_DEBUG_DYLIB` on the app target.** Leave it unset, as the scaffold ships it.

When `ENABLE_DEBUG_DYLIB = YES`, Xcode 16+ builds SPM `.automatic` packages as separate dynamic frameworks under `PackageFrameworks/` instead of compiling them into the consuming framework. Those frameworks are linker-signed ad-hoc, so a hardened-runtime process refuses to load them and the app dies in dyld before `main()`. Working around that requires the `disable-library-validation` entitlement, which is a symptom, not a shape (see [[entitlement-disable-library-validation]]).

This route was evaluated (2026-08-08, on a local-only test bed) as a way to retire `SPMLibraries`, on the theory that dynamic packages give one copy per process and so solve type identity natively. The scaffold did not take it. `SPMLibraries` remains the one doorway for SPM products, the app alone embeds and re-signs it, and hardened runtime is off in Debug only. That shape needs no entitlement and no `ENABLE_DEBUG_DYLIB`, and it is the shape `fosmvvm-doctor` audits against. See [[spm-libraries-settled]].
