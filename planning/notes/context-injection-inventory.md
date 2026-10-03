# Context injection inventory — what a session in this repo is fed, and whether its source is alive

Working prose, no authority. Classification run 2026-10-03 at the architect's request, after the architect observed that the injected context is invisible from the chat interface. Read-only: nothing was edited, nothing was deleted.

## The four categories

**R — Redundant.** Said elsewhere in the context, or covered by a mechanism that loads at the moment it matters (a generator skill, a review check, the architecture document). Removing it changes nothing but token cost. Determined by reading, no experiment needed.

**D — Dead.** References a mechanism that cannot fire. Determined by reading.

**S — Load-bearing and sourced.** Traces to an architect ruling on record, or states a verifiable fact about the repository.

**U — Load-bearing and unsourced.** Shapes behaviour, and nothing ratifies it. The only category needing the architect's judgment.

## Headline

Of roughly 210 lines of injected project guidance, **one statement lands in category U**, and it is already an open thread the architect owns.

**Amended after a live-fire test (see *Amendment* below).** The first pass labelled the Governance Principles and Lessons R — redundant with the review skill. That was wrong in both directions: six review checks cite `.claude/CLAUDE.md` *as their authority, by name*, so those lines are the cited source of enforced checks rather than duplicates of them. Striking them would orphan the checks. The architect's own observation — that the doctrine is visibly not heeded — has a different cause, established below: the gate in front of tier 2 is permanently closed in this repository.

## What is injected into a session here

Six sources, none of them visible from the chat interface without opening the files.

`~/.claude/CLAUDE.md` — the architect's own global rules. Not classified here: originated by the architect, so sourced by definition.

`.claude/CLAUDE.md` — 212 lines of project guidance. The subject of this inventory.

`.claude/hooks/fosmvvm-axiom.md` plus `hooks.json` — SessionStart injection, fires every cold session.

`MEMORY.md` — roughly sixty index lines, plus individual memory files pulled in mid-session.

The skill listing — every skill name and description.

## `.claude/CLAUDE.md`, block by block

**Attribution Moratorium (5–7) — S.** The architect's ruling of 2026-08-22, on record. Duplicated in the global file, but the duplication is deliberate: the rule was ruled to travel with the repository for other users.

**Build & Test Commands (9–23) — S.** Verifiable; all four commands are real.

**SOLID Is the Foundation (29–48) — S, with one U.** The doctrine is the architect's, on record. The exception is the source-of-truth ordering at 36–38, *SOLID → the architecture docs → code*: `spec-0001` names this file by path and states that no ratified specification ever stated that ordering, and RESUME lists its disposition as undispositioned. **This is U-1, and it is a thread the architect already owns rather than a new finding.**

**Encapsulation Is the Precondition (50–80) — S.** The architect's, on record. Longest single block at 31 lines; partially overlaps `.claude/skills/shared/architecture-patterns.md`, so some of it may reduce to R on a closer read.

**Documentation & Comments (82–104) — S.** The architect's, on record.

**API Catalog (106–133) — R, with a real tradeoff.** 28 lines of reach-for index, duplicated by the `fosutilities-api-catalog` skill whose own purpose is that full index. The tradeoff is genuine: the CLAUDE.md copy is always present, the skill must be invoked. This is precisely the always-on versus load-on-match question, and candidate mechanisms for it are recorded in `truth-36104`.

**Library Hierarchy (135–152) — S.** Verifiable fact.

**Key Patterns (154–170) — R, and a drift risk.** The ViewModel declaration snippet duplicates `fosmvvm-viewmodel-generator`. It is also a code sample pinned inside a projection, so it can go stale against the macro with nothing to detect it.

**Platform Constraints (172–177) — S.** Verified against `Package.swift`: `.iOS(.v17)`, `.macOS(.v14)`, `swiftLanguageModes: [.v6]`. Note that a pending floor ruling, if confirmed, would make this block stale.

**Test Notes (179–181) — S.** Verifiable fact.

## Governance Context (the Kairos block)

**Challenge Response Protocol — D.** It instructs the session, in bold MUST language, how to respond to `<governance-challenge>` blocks. The three Kairos launchd agents were unloaded with `-w` on 2026-09-24, deliberately, so nothing can emit that block. Instructions for a signal that cannot arrive.

**Principles — S, with one U.**

**Six of this file's doctrines are the cited authority for named review checks.** The checks name the file, and three of them record a ruling date:

`cross-cutting.md:18` — encapsulation, pointing at *Encapsulation Is the Precondition SOLID Assumes*. `cross-cutting.md:175` — the API-catalog rule. `cross-cutting.md:193` — *Tests never modify production data*, "repo `CLAUDE.md`, firm governance principle". `cross-cutting.md:216` — existentials, "firm principle; scope ruled 2026-08-25". `cross-cutting.md:229` — Documentation & Comments, "ruled into review 2026-08-25". `cross-cutting.md:239` — the `.serialized` lesson, "repo `CLAUDE.md` lesson, confirmed as doctrine 2026-08-25".

So *Existential Types Are a Code Smell*, *Fields Protocols Define Form Contracts Only*, *ModelIdType Requires Junction Tables Except for @ID* and *Tests Must Never Modify Production Data* are all **S** — load-bearing as the source the checks cite. The last of these was the first pass's U-3; it is sourced after all, and the scope doubt was unfounded.

*Code is Artifact, Architecture is Truth* and *Development Velocity is Lifetime Velocity* remain S.

**U-2 stands: *Production Systems Require Type Safety*.** No ratified source found in the specifications, the ruling record, or any review check. The global file's language-choice rule is adjacent but different in kind — that rule is about who decides, not about typing.

**Lessons — not R.** At least `.serialized` is cited by `cross-cutting.md:239` as the authority for an active check and was confirmed as doctrine on 2026-08-25. The remainder are also present in the 1736-line architecture document and the generator skills, so some may still reduce to R, but the blanket label was wrong and none should be struck without checking whether a check cites it.

**This surfaces a conflict the architect owns.** `spec-0001` § *Output holds no authority* names `.claude/CLAUDE.md` by path and grades it a projection with no authority. Six review checks cite that same file as the authority for firm principles, with ruling dates. Either the file holds ratified principles — and `spec-0001`'s listing is wrong about it — or it does not, and six checks cite a void source. On the architect's own terms that is a throw.

## Session evidence

In this session — a full day of specification work — **zero of the seven Principles and zero of the fourteen Lessons were consulted**, and the Challenge Protocol could not fire. The guidance actually used was: the specification-versus-documentation rule, paragraph-per-line, the attribution moratorium, and readback-before-action. Not a controlled experiment, but it is the first direct evidence available on which injections earn their place in which kind of session.

## Two orphaned outputs, same defect

`.claude/hooks/fosmvvm-axiom.md` is live on `main` and fired into this session. Its text teaches `f(requirements, architecture, ui design) → Source Code` and the word *axiom* — the signature `spec-0000` 1.2 retired in favour of `work-item(specs) throws -> system`, and the register word 0.9 retired. Its deletion exists as commit `90897f1` on `feature/fos-development-workflow` and has never reached `main`.

The Kairos Governance block is the same shape: output still injected after its source stopped existing.

## Amendment — live-fire test of the enforced channel, 2026-10-03

Run at the architect's request, to test the observation that the doctrine is visibly not heeded. Four violations were planted in a throwaway file — a stored `[any BoardOperations]` on a `@ViewModel`, a `ModelIdType` requirement on a Fields protocol, a raw `UUID` field outside `@ID()` on a DataModel, and a shared-state test suite with no `.serialized` — and `fosmvvm-review` was run scoped to that path. The planted files have since been deleted; the repository carries no test residue.

**Tier 1 fired, deterministically, and was correct.** `swift package fosmvvm-doctor --json` named the planted file and gave a remedy: two ViewModel declarations outside a shared ViewModels module.

**Tier 2 was halted, and none of the four planted doctrine violations was ever evaluated.** Per the gate ruled 2026-08-25, any doctor finding remaining at `error` stops every area subagent from being dispatched.

**The halting error pre-exists the test.** With the planted directory removed, doctor still reports one `error`: `Tools/UITestingProbe/App/ProbeShared.swift` declares `TallCardViewModel` and `BareCardViewModel` outside a shared ViewModels module. So the gate is closed on this repository independent of anything planted.

**And the finding carries no `rule` identifier**, which the skill requires before `doctor.disabled_rules` can reach it. There is no `.fosmvvm-review.yml` here, and no configuration could silence this finding if there were. The only exit is restructuring the probe.

**Consequence.** On FOSUtilities itself, `fosmvvm-review` halts at tier 1 on every invocation and has done since the gate was ruled. The six checks that cite this file as their authority have therefore never run here. That is a far better explanation for the architect's observation than any claim about prose: the doctrine is encoded, it is cited, and it is unreachable.

**Worth the architect's eye:** doctor's shared-ViewModels-module rule is aimed at scaffolded adopting projects. This repository is the framework plus a UI-testing probe whose ViewModels are deliberately local to the probe app. Whether the rule is mis-scoped for a framework repository, whether the probe should be restructured, and whether a finding this consequential should be disable-able are all the architect's to say.

## What needs the architect

**U-2 — *Production Systems Require Type Safety*.** Ratify it into a specification, restate it as the architect's, or strike it. The only genuinely unsourced statement found.

**U-1 — the SOLID source-of-truth ordering (`:36-38`).** Already an open thread: `spec-0001` states no ratified specification stated that ordering, and RESUME lists the disposition as undispositioned.

**The authority conflict.** `spec-0001` grades this file as authority-free output; six review checks cite it as the authority for firm principles. One of the two positions has to move.

**The closed gate.** Until the probe's ViewModels are restructured or the rule becomes disable-able, no area review runs in this repository.

**The dead Protocol.** The Challenge Response Protocol can be struck on the architect's word; nothing can emit its signal.

**The orphaned hook.** Land `90897f1` on `main`, or revive the premise it was delivering from a ratified source.

## History

- 2026-10-03 — first pass: four-category classification of the injected context, read-only.
- 2026-10-03 — amended after the live-fire test: the Governance Principles and Lessons reclassified from R to S (the review checks cite this file as their authority), U-3 withdrawn as sourced, the `spec-0001` authority conflict recorded, and the permanently-closed tier-2 gate established as the cause of the unheeded doctrine.
