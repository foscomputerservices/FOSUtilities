# Memory Index

- [SPMLibraries is settled doctrine](spm-libraries-settled.md) — one umbrella dynamic framework for all SPM products; do not link SPM packages directly into multiple targets
- [disable-library-validation entitlement](entitlement-is-a-symptom.md) — required with ENABLE_DEBUG_DYLIB + ENABLE_HARDENED_RUNTIME; was a shape-symptom pre-Xcode 16
- [Xcode 16 dynamic SPM packages](xcode16-dynamic-spm-packages.md) — ENABLE_DEBUG_DYLIB forces SPM packages dynamic; SPMLibraries may be obsolete for Xcode 16+ projects
- [Stale build runbook](stale-build-runbook.md) — Clean Build Folder (not rm -rf DerivedData) for bogus undefined-symbol errors
- [macOS build-for-testing FAQ](macos-build-for-testing-faq.md) — common macOS test build issues
