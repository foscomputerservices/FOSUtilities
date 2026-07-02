---
area: swiftui-view
generator-skill: fosmvvm-swiftui-view-generator
where:
  - "Sources/**/Views/**/*.swift"
  - "Sources/**/*View.swift"
---

# SwiftUI View Checks

The positive pattern lives in the `fosmvvm-swiftui-view-generator` skill. This file documents review-only concerns for View bodies and their interaction with VMs and the `@Observable` data store.

## Reviewer Guidance

- Do NOT recommend removing `@Environment(SomeAppState.self)` from a view to "simplify" by reading through `viewModel.someObservableRef.x`. Production may bind both to the same instance, but tests inject independently — collapsing the split breaks test host injection.
- Do NOT recommend collapsing env/VM read-write splits. The split is required for test host injection (TestConfiguration pattern). View reads come from the VM; mutations go through Operations to the `@Observable` store; tests inject the VM stub's state into the env to mirror this.
- The VM is the single source of truth for what Views display. If a value needs to appear in a View, expose it as a frozen scalar on the VM at projection time. Do NOT recommend reaching back into the data store from the View body for display data.

## Check: view-reads-vm-only
**Severity:** blocker
**What:** Views read display data from the VM, never directly from `@Environment`-shadowed data store types when the VM exposes the equivalent.
**Anti-pattern:** A View reads `programmingSettings.amplitudeValue` from `@Environment(ProgrammingSettings.self)` for display when the VM already exposes `amplitudeValue` as a frozen scalar.
**Detection:** For each View, find `@Environment` declarations of `@Observable` types. For each property read off those env values in the View body, check whether the VM exposes the same property name. Flag overlapping reads — the View should be reading from the VM.

## Check: view-no-env-mutation
**Severity:** blocker
**What:** View bodies do not mutate `@Observable` state directly. Mutations go through Operations.
**Anti-pattern:** `programmingSettings.isEnabled = true` written inline in a View body or button action closure.
**Detection:** Inside View bodies and the closures they construct, find assignments where the LHS resolves to a property of an `@Observable` env value. Flag any such assignment. (Operations dispatched from button actions are fine — they call methods on a `*ViewModelOperations` conformer, which mutates internally.)

## Check: view-no-read-through-vm-ref
**Severity:** warning
**What:** A VM may hold a reference to its `@Observable` state for ops dispatch, but Views must not read display data through that reference.
**Anti-pattern:** `viewModel.patientPanelSettings.electrodeSettings[0].isLocked` read in a View body for display.
**Detection:** In View bodies, find chained reads through VM properties whose type is `@Observable`. Flag reads of properties that the VM could expose as frozen scalars at projection time.
