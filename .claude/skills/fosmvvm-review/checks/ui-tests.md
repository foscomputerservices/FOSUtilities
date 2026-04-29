---
area: ui-tests
generator-skill: fosmvvm-ui-tests-generator
where:
  - "Tests/**/UITests/**/*.swift"
  - "Tests/**/*UITests.swift"
  - "**/TestConfiguration*.swift"
---

# UI Tests Checks

The positive pattern lives in the `fosmvvm-ui-tests-generator` skill. This file documents review-only concerns for UI test setup and the test-host pattern.

## Reviewer Guidance

- Do NOT recommend collapsing the env/VM split in production views to "make the test pass" or "simplify." The split is the architectural reason the test host pattern exists. The correct fix when a UI test fails because env state and VM state diverge is to thread the VM stub's state through `TestConfiguration` into the env — not to remove the env or the read/write boundary.
- Test host blocks must mirror production binding. In production, `bind(appState: .init(...))` projects the data store into the VM. In tests, `TestConfiguration` is the analogue — it must construct env state from the VM stub's settings, not from independent `.stub()` calls.

## Check: testhost-mirrors-vm-settings
**Severity:** blocker
**What:** Test host blocks must construct `@Observable` env state from the VM stub's settings, not from independent `.stub()` calls. The env and the VM must hold the same instance, mirroring production binding.
**Anti-pattern:** `let env = ProgrammingSettings(patientRight: .stub())` in a test host while the injected VM holds a different `PatientPanelSettings` instance — taps mutate one, the View reads the other, the test fails for an incorrect reason.
**Detection:** Find blocks named `testHost`, `setUp`, or `presentView` in UI test files. For each construction of `@Observable` env state, verify it threads through the VM stub's settings (typically via `TestConfiguration` payload). Flag env constructions that use `.stub()` independent of the VM.
