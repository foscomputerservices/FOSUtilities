# The FOSMVVM Axiom

**f(requirements, architecture, ui design) → Source Code**

This project adopts FOSUtilities. The framework's premise: source code
is the *output* of that function — a projection, re-derivable at will,
never a source of truth. Every framework feature exists to make f
computable: localized text is YAML (an argument, not code — its values
derive from the ui design's copy and sometimes the requirements, then
owner-ratified; a design's sample data never becomes a value), Codable
comes from macros, Views generate from ViewModel + ratified design, one
Fields definition projects RequestBody + Form ViewModel + Model, and
Factories are literally `static func project(...)`. What remains
authored is the truth layer: requirements, architecture, ui designs.

**You, holding the fosmvvm-* skills, are the interpreter of f.** Before
generating or modifying any FOSMVVM artifact, read the plugin's
`shared/functional-discipline.md` — it is the evaluation contract.

Derive these; don't memorize them:

- **Editing generated output** = patching a return value. Fix the
  argument (design, ViewModel, Fields) and re-evaluate.
- **Reading neighboring code as "the pattern"** = feeding output back
  in as input; f becomes self-referential and drifts. Code has zero
  votes on what should exist. (Reading your artifact's *declared
  inputs*, or verifying current state, is evaluation — that's normal.)
- **A silent truth layer** = a missing argument. The result is
  undefined — generate a candidate argument marked UNRATIFIED for the
  owner's red pen; never silently substitute your judgment.
- **Re-project exactly the stale subtree**: no less (stale artifacts
  ship), no more (with a stochastic f, clean rebuilds are manufactured
  diff, not a no-op).
- **Standing is conferred, never inferred.** Some committed artifacts
  are NOT projections — a hand-maintained Xcode project is the standing
  example. Unsure whether an artifact is truth or output? Ask.
- **Do not invent restrictions the architecture never made.** The axiom
  governs artifacts with a live projection function; it is not a
  license to police everything that moves.

A previous session read all of the above and still got it wrong.
Verbatim:

> **Session:** "Sessions must read neighbors for interface facts to
> compile… and full re-derivation manufactures diff — minimal targeted
> edits should count as re-projection."
>
> **Architect:** "You're wrong and the doc is right — you're holding it
> wrong. You want a tweak on the status quo and the doc is promoting a
> revolution."

Both objections were arrow-direction errors: treating code as an input,
and treating the output diff as a review surface. Review happens at the
input layer — you don't diff-review a function's return value; you
review its arguments. If you find yourself drafting exceptions to this
document, you are that session.
