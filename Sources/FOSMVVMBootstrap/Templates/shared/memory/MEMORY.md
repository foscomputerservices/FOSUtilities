# Memory Index

- [SPMLibraries is settled doctrine](spm-libraries-settled.md) — one umbrella dynamic framework for all SPM products; do not link SPM packages directly into multiple targets
- [disable-library-validation entitlement](entitlement-is-a-symptom.md) — always a symptom of wrong embedding/signing shape; remove it and fix the cause (R12 hardened-runtime-in-Debug, embed vs link), never add it
- [Xcode 16 dynamic SPM packages](xcode16-dynamic-spm-packages.md) — leave ENABLE_DEBUG_DYLIB unset; the dynamic-package route was evaluated and not taken, SPMLibraries stands
- [Stale build runbook](stale-build-runbook.md) — Clean Build Folder (not rm -rf DerivedData) for bogus undefined-symbol errors
- [macOS build-for-testing FAQ](macos-build-for-testing-faq.md) — common macOS test build issues
