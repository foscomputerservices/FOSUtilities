---
name: xcode16-dynamic-spm-packages
description: Xcode 16+ ENABLE_DEBUG_DYLIB forces SPM packages dynamic — implications for SPMLibraries and signing
metadata:
  type: project
---

When `ENABLE_DEBUG_DYLIB = YES` is set on an app target, Xcode 16+ builds SPM
`.automatic` packages as **dynamic frameworks** in `PackageFrameworks/` rather
than as static libs compiled into the consuming framework.

**Why:** The debug dylib feature splits the compiled app into a stub +
`.debug.dylib`. All dependencies must be separately loadable as dynamic
frameworks to support this split.

**Implication for SPMLibraries:** The SPMLibraries umbrella was created to solve
the static-SPM type-identity problem (multiple targets → multiple static copies
→ `TypeA != TypeA`). With dynamic SPM packages, the OS dynamic linker loads each
package once per process — the type-identity problem is solved natively. This
means **SPMLibraries may be obsolete for Xcode 16+ projects**.

**Known cons of SPMLibraries that go away with dynamic packages:**
- Xcode dependency scanner warnings: `'FOSMVVM' is missing a dependency on 'Yams'`
- Spurious stale-build failures (graph opacity)
- Shape confusion for tools and people reading the project

**Signing side-effect:** Dynamic PackageFrameworks are linker-signed (ad-hoc).
With `ENABLE_HARDENED_RUNTIME = YES`, this requires the
`com.apple.security.cs.disable-library-validation` entitlement.
See [[entitlement-disable-library-validation]].

**Status (2026-08-08):** Under active evaluation. TestLocalOnly is the test bed.
SPMLibraries retirement is being considered for all Xcode 16+ FOS projects.
