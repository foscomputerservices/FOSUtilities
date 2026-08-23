# macOS testing and FOS PackageFrameworks — two known failure faces

With test targets present, Xcode builds FOS as separate dynamic
`PackageFrameworks/*.framework` dylibs. Two distinct failures trace back
to that, depending on Xcode version:

**Face 1 — `Ld` failure at build-for-testing.** The umbrella no longer
carries the FOS symbols and the link fails. Seen identically across four
independent apps on older Xcode.

**Face 2 — dyld abort at app launch under UI testing.** The build
succeeds, but the app dies before `main()`:
`Library not loaded: @rpath/FOSFoundation.framework … code signature …
mapping process and mapped file (non-platform) have different Team IDs`.
Cause: Xcode signs PackageFrameworks **ad-hoc** (`TeamIdentifier=not
set`) in Debug, and an app with **hardened runtime** refuses to map
them (library validation). Deterministic on every clean build; the UI
test reports only "Application '…' does not have a process ID".

**Fix (emitted by the scaffolder):** `ENABLE_HARDENED_RUNTIME` is
per-config — `NO` for Debug (where ⌘U lives), `YES` for Release (where
notarization needs it). Do not set it in `settings.base`.

**Still open on macOS:** with launch fixed, interaction tests
(tap → stub-op recorded) can still fail on the macOS destination while
identical tests pass on the iOS simulator — under investigation at the
FOSUtilities level. The iOS simulator is the fully-green UI-test
destination.
