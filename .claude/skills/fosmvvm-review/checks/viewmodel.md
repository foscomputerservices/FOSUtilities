---
area: viewmodel
generator-skill: fosmvvm-viewmodel-generator
where:
  - "Sources/**/ViewModels/**/*.swift"
  - "Sources/**/*ViewModel.swift"
  - "Sources/**/*Operations.swift"
  - "Sources/**/*Ops.swift"
---

# ViewModel Checks

The positive pattern lives in the `fosmvvm-viewmodel-generator` skill. This file documents review-only concerns: anti-patterns, drift, common mistakes in ViewModels and their Operations.

## Reviewer Guidance

- Do NOT recommend collapsing the VM/data-store separation. The VM is the single source of truth for what Views read; the `@Observable` data store is what Operations write to. The `bind(appState: .init(...))` projection edge is where they meet — do not propose moving or removing it.
- Do NOT treat `@Observable` classes and structs as substitutable. They have different functional contracts: structs are values, `@Observable` classes participate in SwiftUI tracking. Recommending one in place of the other is an architectural error.
- Re-projection happens at the top of the subtree that owns `bind(appState:)`. The parent body that constructs the child's AppState is the projection edge. Do NOT propose moving projection edges to "simplify."

## Check: ops-no-output-reads
**Severity:** blocker
**What:** Operations methods must not read from the same mutable state they write to. They take inputs, transform, write outputs — never read-modify-write on the output struct.
**Anti-pattern:** A method on a `*ViewModelOperations` conformer that both reads from and writes to the same parameter (e.g., `settings.electrodeSettings[index].polarity` read, `settings.selectedPolarity = ...` write).
**Detection:** For each type conforming to a protocol matching `*ViewModelOperations`, read each method body. Flag methods that both READ from and WRITE to the same parameter within the same call.

## Check: ops-not-async-unless-needed
**Severity:** warning
**What:** FOSMVVM Operations should not be `async` unless they actually await something.
**Anti-pattern:** `func toggleEnabled(...) async throws { settings.isEnabled = enabled }` — declared `async throws` with no `await` in the body.
**Detection:** For methods on `*ViewModelOperations` conformers declared `async` (or `async throws`), grep the body for `await`. Flag methods where no `await` is present.

## Check: ops-output-param-last
**Severity:** warning
**What:** For clientHostedFactory ViewModels, the output parameter must be the last parameter in the Operation signature and labeled `output:`.
**Anti-pattern:** `func myOp(output settings: Settings, otherInput: Bool)` — output before inputs. Or `func myOp(inputs..., settings: Settings)` — output not labeled `output:`.
**Detection:** Identify ViewModels using `clientHostedFactory`. For their Operations, verify each method signature ends with `output <name>: <Type>`. Flag methods where the output is not last or not labeled `output:`. Server-based VMs (no `clientHostedFactory`) are exempt.

## Check: appstate-no-observable-args
**Severity:** blocker
**What:** `bind(appState: .init(...))` arguments must be plain values projected from `@Observable` state, not `@Observable` types passed by reference.
**Anti-pattern:** `bind(appState: .init(settings: programmingSettings))` where `programmingSettings` is an `@Observable final class`. Crosses the projection boundary.
**Detection:** Find all `bind(appState: .init(...))` call sites. For each argument, determine if its type is `@Observable`. Flag any `@Observable`-typed argument. (Reading a property OFF an `@Observable` and passing the value is fine.)
