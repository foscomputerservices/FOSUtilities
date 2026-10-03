---
status: open
last_updated: 2026-10-03
origin: session
---

`fosmvvm-review` stops before its code-quality checks on this repository. Doctor grades the two ViewModels in `Tools/UITestingProbe/App/ProbeShared.swift` an error for living outside a shared ViewModels module, and the gate ruled 2026-08-25 dispatches no area subagent while any doctor finding remains at `error`. The run is not silent — it prints a halted line — but the code-quality half never executes, including the six checks that cite `.claude/CLAUDE.md` as their authority. Surfaced 2026-10-03 by a planted-violation test: four deliberate violations were introduced and none was evaluated.

## Goal

`fosmvvm-review` completes both stages on FOSUtilities itself, with doctor's shared-ViewModels-module rule applying where it is meant to apply and not where it is not.

## Input

- The gate — `.claude/skills/fosmvvm-review/SKILL.md` Step 2: "When any doctor finding remains at `error` after the disabled rules are applied, do not dispatch any area subagent — fix structure first." Ruled 2026-08-25. The behaviour is correct per that ruling; the question is the triggering condition.
- Doctor's finding, verbatim from `swift package fosmvvm-doctor --json`: severity `error`, summary "1 ViewModel declaration lives outside a shared ViewModels module: Tools/UITestingProbe/App/ProbeShared.swift.", remedy "Create a shared module — Sources/<Name>ViewModels, its own framework or library target — holding the ViewModels, ServerRequests, and Fields, and have every other target import it."
- The declarations: `Tools/UITestingProbe/App/ProbeShared.swift:24` `TallCardViewModel`, `:35` `BareCardViewModel`. The file first appeared in `e2c877d` (2026-09-21) and was last touched in `acbe47e` (2026-09-24), so the blocking condition is roughly twelve days old, not coincident with the gate ruling.
- The finding carries **no `rule` identifier**, and SKILL.md Step 2 states "Only findings that carry a `rule` identifier can be disabled." So `doctor.disabled_rules` cannot reach it. There is no `.fosmvvm-review.yml` at the repo root, and adding one would not help.
- What is unreachable while the gate holds: every `checks/*.md` area, including the six that name `.claude/CLAUDE.md` as their source — `cross-cutting.md:18` (encapsulation), `:175` (API catalog), `:193` (tests never touch production data), `:216` (existentials, scope ruled 2026-08-25), `:229` (documentation audiences, ruled into review 2026-08-25), `:239` (`.serialized`, confirmed as doctrine 2026-08-25).
- Doctor additionally reports two entries as not checked, both needing `--shape`: entitlements match the project shape, localization YAML split by hosting. FOSUtilities' own shape has not been passed on any run observed.
- The probe's ViewModels appear deliberately local to the probe app rather than shared — the rule they trip is aimed at scaffolded projects adopting FOSMVVM, where a shared module is the prescribed shape.
- Test evidence and the wider context audit: `planning/notes/context-injection-inventory.md`.

## Suggested actions

1. Rule whether doctor's shared-ViewModels-module rule should apply to this repository at all. It exists for adopting projects; FOSUtilities is the framework plus tooling, and `Tools/UITestingProbe` is a probe app, not a product target.
2. If the rule stands here, restructure the probe's two ViewModels into a shared target, or place the probe outside doctor's scan scope — then confirm doctor returns clean.
3. If the rule should not stand here, decide the mechanism: give this finding a `rule` identifier so a project can record the exception with a reason the way other doctor findings allow, or scope the rule by target kind so probe and tooling targets are exempt by construction. Both are changes to doctor, not to the review skill.
4. Consider whether a halted run reports loudly enough. The halted report carries a stated line, but its Blockers, Warnings, and Nits sections are empty, so at a glance it reads closer to a clean run than to a review that never happened.
5. Pass FOSUtilities' own shape on review runs so the two unchecked doctor entries are actually audited.
6. Re-run the planted-violation test afterwards to confirm the code-quality checks fire: a stored existential on a ViewModel, a `ModelIdType` requirement on a Fields protocol, a raw `UUID` field outside `@ID()` on a DataModel, and a shared-state test suite without `.serialized`. None of the four was evaluated on the 2026-10-03 run.

## Adjacent, not this item

`spec-0001` § *Output holds no authority* names `.claude/CLAUDE.md` as a projection with no authority, while six review checks cite that same file as the authority for firm principles, three of them with ruling dates. That conflict belongs to the workflow specification tree, not to this defect, and is recorded in `planning/notes/context-injection-inventory.md`.

## History

- 2026-10-03 minted at David's direction, from a planted-violation test run during a context-injection audit. The test confirmed doctor fires correctly and deterministically; the finding is the gate's triggering condition, not doctor's accuracy.
