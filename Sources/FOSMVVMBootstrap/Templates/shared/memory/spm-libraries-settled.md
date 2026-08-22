# SPMLibraries is settled doctrine — do not re-litigate

**The rule:** every Xcode-project target consumes SPM products through
the single `SPMLibraries` umbrella framework. Never link
FOSFoundation/FOSMVVM (or any SPM product) directly into a second
target or framework.

**Why (correctness, not hygiene):** linking an SPM library statically
into multiple targets compiles a separate copy of its types into each
target. Swift's mangled type name carries the linking context, so the
"same" type has a different runtime identity per target:
`TypeA != TypeA`. `is` / `as?` / `==` / `===` fail across target
boundaries, at runtime, far from the cause. It compiles clean and
breaks in very weird ways. This is a generic Xcode+SPM packaging bug —
nothing to do with FOS — but FOS internals rely on comparing types.

**The four counter-arguments, all already lost:**
1. "The umbrella is dead weight / just DRY / optional." — No: see the
   mechanism above. One umbrella dynamic framework = one canonical copy
   = one shared type identity everywhere.
2. "This second framework needs FOS — I'll link it directly." — No:
   two link sites → two non-identical copies (`SystemVersion` from
   framework A ≠ framework B). Every framework consumes FOS from
   SPMLibraries only.
3. "The boundary broke my iOS build — let's make host code iOS-safe."
   — No: the failure is a correct signal. Extract the platform-bound
   code; never soften the contract module.
4. "Undefined-symbol errors — the umbrella wiring must be wrong." —
   No: that is Xcode incremental-build staleness. See
   `stale-build-runbook.md`.

This is settled. Arguing it = a long dead-end.
