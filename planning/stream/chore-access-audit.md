# Public-Access Audit — candidates for `package` or deletion

**Status:** FINDINGS, UNRATIFIED. No code changed. Out of scope for the `designedFor:` arc by David's ruling (2026-09-21) — this is its own thread.

**Why this exists.** `TestDataTransporter.accessibilityIdentifier` was `public` because `package` did not exist in Swift when it was written (5.9 introduced it). Anything in the repo predating 5.9 that needed a sibling module had no other option, and nothing since would have flagged it. This audit asks how much else is in that position.

**What was ruled already:** that one identifier is demoted inside the `designedFor:` arc (see `feat-designed-parents.md` §1.5). Everything below is separate.

---

## Method, and what it cannot see

A regex sweep of `Sources/` found **985** `public`/`open` declarations, including members inside `public extension` blocks. For each symbol, references were counted in: its own module, every other module in the package, `Tests/`, `Tools/` (a **separate** package consuming FOSUtilities by path), the bootstrap app templates (emitted into consumer apps), and the taught corpus (`.claude/skills/`, api-catalog, `.docc`, `docs/`).

Of 985, **61** were filtered as too short or too common to count reliably, and **187** were excused as known false-positive classes:

- **120** likely protocol requirements — public by necessity when the protocol is public and conformers live outside.
- **20** WASI Foundation shims — deliberate source-compatibility surface for WebAssembly, not API anyone calls in-repo.
- **15** in `FOSNetworkSecurity` / `FOSReporting` — modules with no in-repo consumer, so absence of readers proves nothing.
- **12** property-wrapper machinery (`wrappedValue`, `projectedValue`) — public is language-required for `$foo`.
- **3** underscore-prefixed macro support types — macros expand into *consumer* modules, so anything emitted must be public.
- **17** in `Sources/FOSMacros/SystemVersion.swift`, which is a **symlink** to `../FOSFoundation/Versioning/SystemVersion.swift` — the same declarations counted twice.

**The limit that matters most.** Counting cannot distinguish a call to *our* symbol from a call to a stdlib member of the same name. This was caught in the results rather than predicted: `removeValue` showed 8 cross-module references, and every one is `Dictionary.removeValue(forKey:)`. The verdict survived, but the evidence was wrong — so treat every count below as an upper bound, and the per-item verdicts, not the numbers, as the finding.

Static analysis also cannot see protocol witnesses, generic constraints, `@_spi`, dynamic conformances, or string-based macro resolution. **Nothing here should be applied without a compile.**

---

## A. Dead — public, no reader anywhere (2)

Neither has a reference in any module, test, tool, template, or document.

- **`hasValue`** (var) — `Sources/FOSMVVM/Forms/FormFieldModel.swift:59`
- **`allValueStrings`** (var) — `Sources/FOSMVVMBootstrapCLI/DoctorCommand.swift:67`

**Verdict:** delete, don't demote. Both are small enough to read in full before deciding; `allValueStrings` in particular smells like a leftover from an `ArgumentParser` idiom that moved on.

---

## B. `package` candidates — cross-module readers, taught nowhere (13 after triage)

These have real readers in sibling modules and appear in no skill, api-catalog entry, `.docc` article, `Tools/`, or template. `package` reaches every reader.

**High confidence — small, self-contained, single obvious caller:**

- **`removeValue`** — `Sources/FOSFoundation/Collections/GlobalStringStore.swift:45`. One genuine caller, `Deployment.swift:243` (FOSMVVM). The other eight hits were `Dictionary.removeValue`.
- **`isValidProjectName`** — `Sources/FOSMVVMBootstrap/BootstrapConfig.swift:70`
- **`isValidBundleIdRoot`** — `Sources/FOSMVVMBootstrap/BootstrapConfig.swift:74`
- **`isValidTeamId`** — `Sources/FOSMVVMBootstrap/BootstrapConfig.swift:78`
- **`buildDestination`** — `Sources/FOSMVVMBootstrap/Verifier.swift:82`
- **`generationSteps`** — `Sources/FOSMVVMBootstrap/Verifier.swift:104`
- **`iosDevices`** — `Sources/FOSMVVMBootstrap/BootstrapConfig.swift:36`
- **`macDesignedForIPad`** — `Sources/FOSMVVMBootstrap/BootstrapConfig.swift:40`
- **`visionDesignedForIPad`** — `Sources/FOSMVVMBootstrap/BootstrapConfig.swift:44`

The `FOSMVVMBootstrap` cluster is the clearest win — nine symbols read only by `FOSMVVMBootstrapCLI`, its own CLI front-end in the same package. That is textbook `package`.

**Needs a look before ruling:**

- **`setMinimumSupportedVersion`** — `Sources/FOSFoundation/Versioning/SystemVersion.swift:117`. Versioning is consumer-facing territory even if nothing in-repo calls it from outside; check whether it is part of the taught bootstrap story before demoting.
- **`jsonVersionString`** — `Sources/FOSFoundation/Versioning/SystemVersion.swift:149`. Same file, same question.
- **`factoryType`** — `Sources/FOSMVVM/Protocols/ComposedChild.swift:37`. Lives in a protocol file; the excuse-filter did not catch it because it is a `let` on a struct, but verify it is not a witness.
- **`modelSync`** — `Sources/FOSMacros/ViewModelMacro.swift:291`. Six test references; confirm none are contract tests that would need the public spelling.

**Excluded after checking — do not demote:**

- **`LocalizableErrorMacro`**, **`ViewModelFactoryMacro`**, **`ViewModelFactoryMethodMacro`** — listed in `FOSMacros.swift:26-29`'s `providingMacros` (same module, so internal would compile) *and* named as **string literals** in `Sources/FOSMVVM/Macros/Macros.swift:44,57,63`. String-based resolution is invisible to the compiler, so this needs a real build to settle, and the payoff is low. Leave.

---

## C. Internal candidates — own module only (15)

`public` with no reader outside the declaring module at all. Lower value than B — `internal` is the right level but the blast radius is a consumer we cannot see from here, so each needs a judgement call.

**Macro diagnostics** — thrown during expansion, never surfaced to a consumer as a type. Strong candidates:

- **`FieldValidationModelMacroError`** — `Sources/FOSMacros/FieldValidationModelMacro.swift:22`
- **`ViewModelFactoryMacroError`** — `Sources/FOSMacros/ViewModelFactoryMacro.swift:23`
- **`ViewModelMacroError`** — `Sources/FOSMacros/ViewModelMacro.swift:23`

**Forms internals** — the largest cluster, and the one most likely to contain genuine consumer API that simply has no in-repo caller. Needs a human read, not a sweep:

- `saveButtonTitle` — `FormFieldModel.swift:57`
- `wrappedValueRemovingWhitespace` — `FormFieldModel.swift:204` and `:210`
- `dummy` — `FormFieldModel.swift:217` *(the name alone earns a look)*
- `defaultDateSize` / `defaultDateTimeSize` — `FormInputOption.swift:23`, `:30`
- `textAutocapitalizationType` — `FormInputOption.swift:154`, `:165`
- `htmlAttributeValue` — `FormInputOption.swift:184`, `FormInputType.swift:198`

**Leave alone:**

- **`loadingView`** — `Sources/FOSMVVM/SwiftUI Support/MVVMEnvironment.swift:233`. A stored `let` on a public struct whose public `init` takes it. Consumers set it; that nothing in-repo *reads* it from outside is expected. Demoting a stored property while its initializer parameter stays public is legal and strange. Not worth it.
- **`resolveClientLocalizationStore`** — `MVVMEnvironment.swift:258`. Documented as the uncached sibling of `clientLocalizationStore`; the DocC names it as a choice a consumer makes.

---

## Suggested shape, if this thread runs

1. **A first** — two deletions, no demotion risk, immediate.
2. **The `FOSMVVMBootstrap` cluster next** — nine symbols, one consumer, one commit, high confidence.
3. **B's "needs a look" and C** — one at a time, each with a compile, each its own judgement.
4. **Add the guard** so this does not regrow: a CI check, or a rule in `fosmvvm-doctor`, that flags a new `public` whose readers are all in-package. That is the durable fix; everything above is one-time cleanup.

Item 4 is the one with lasting value. Without it this audit is a snapshot that decays from the day it is written.

---

## What this audit did not cover

- The **61 filtered names** — too short or too common to count. Some may be real; a name-aware pass (an index built from a compiler symbol graph rather than regex) would see them.
- **`@_spi` surface**, if any exists.
- **Access levels below `public`** — no attempt was made to find `internal` that should be `private`, which is the same discipline one level down and probably a larger population.
