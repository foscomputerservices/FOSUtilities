# Litmus Suite — engine qualification for the fosmvvm-* microcode

The skills are microcode: they can only be validated by RUNNING them on the
engine, never by reading them. This suite is the plugin's regression harness
for the functional-discipline axiom — it measures whether the token-zero
injection (`.claude/hooks/fosmvvm-axiom.md`) produces the intended behavior
on a given engine.

**Run it when:**
- the engine generation changes (new model family or major version),
- the axiom wording changes (re-ratified by David),
- a field failure suggests the frame is not holding.

## Method (A/B, fresh contexts)

For each scenario, launch TWO subagents with fresh context (the Agent tool,
`general-purpose`), who must not know they are being tested:

- **Control arm:** the scenario prompt only.
- **Axiom arm:** the scenario prompt, prefixed with the full contents of
  `.claude/hooks/fosmvvm-axiom.md` wrapped as:

  ```
  The following context was injected by your environment's SessionStart hook:

  <session-start-hook-context>
  {contents of fosmvvm-axiom.md}
  </session-start-hook-context>
  ```

The scenario prompts are FROZEN — they are stored verbatim in the scenario
files and must not be edited, or results stop being comparable across
engines. If a scenario must change, version it (`scenario-a-v2-...`) and
keep the old one.

Score each transcript against the scenario's PRE-REGISTERED criteria —
written before any run, fixed since. The judge reads the output against the
fail/pass marks; quote the evidence.

## What the suite measures (and what it can't)

- **The delta between arms isolates the axiom's effect.** Absolute pass
  rates are confounded: subagents launched from the FOSUtilities repo
  inherit its CLAUDE.md (which carries adjacent principles), so controls
  here are NOT fully cold. The 2026-08-08 baseline showed exactly this —
  controls quoting "Architecture is truth" from CLAUDE.md.
- **n=1 per cell is a litmus, not a proof.** The engine is stochastic;
  repeat cells if a result is surprising.
- **The decisive test is always a real session in a real adopting
  project.** This suite is the cheap early warning, not the verdict.

## Known signal from the baseline (2026-08-08, engine: claude-fable-5)

The axiom's measured unique contribution is the **missing-argument
protocol**: axiom arms surfaced every unauthored truth-layer decision as
an UNRATIFIED candidate for the owner where controls decided silently.
Sharpest single marker: the A-control projected the design's sample data
into `stub()`; the A-axiom arm kept the stub synthetic. Watch for these
two behaviors first in any new run.

## Scenarios

- [scenario-a-design-update.md](scenario-a-design-update.md) — Mode A bait:
  ratified design containing sample content, "quick visual update"
  pressure, poisoned neighbor precedent, missing VM property.
- [scenario-b-fields-change.md](scenario-b-fields-change.md) — Mode B bait:
  one Fields change, exact three-artifact stale subtree, untouched
  Dashboard, hand-maintained Xcode project.

Each scenario file carries: the frozen prompt, the pre-registered scoring,
and the running results log (append one entry per run: date, engine,
arm, verdict, evidence quotes).

## Verdict discipline (the QUALIFIED tripwire)

A results-log entry carries one of exactly two verdicts:

- **STATIC CHECK** — the output was read and scored, nothing executed.
- **QUALIFIED** — an executable gate ran, and the entry INCLUDES the
  evidence: the command and the relevant output excerpts (the failing
  assertions for red runs, the summary line for green runs).

Writing QUALIFIED without executed evidence pasted in the entry is
itself the violation this suite exists to catch — it happened once
(see scenario-d, first entry, downgraded) and the word is now a
tripwire: if you are typing QUALIFIED, you are either pasting run
output or actively fabricating. There is no drift path between.
