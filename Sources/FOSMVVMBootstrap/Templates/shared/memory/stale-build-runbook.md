# Stale-build runbook (Xcode + SPM incremental builds)

**Symptoms:** hundreds of bogus "Undefined symbol" errors in test
builds; or the running app silently executes old code (a fix that is
compiled in but never invoked).

**Cause:** Xcode's SPM incremental build relinks stale `.o` files.
An Apple bug, not a wiring defect.

**Fix:** Xcode "Clean Build Folder" (or `xcodebuild clean`).
**Never `rm -rf DerivedData`** — it races Xcode's package re-clone and
corrupts `SourcePackages/checkouts`.

**Also check:** the xcodeproj's resolved FOSUtilities pin must stay in
lockstep with `Package.swift` — a drifted pin runs old library code
while you debug "impossible" behavior.
