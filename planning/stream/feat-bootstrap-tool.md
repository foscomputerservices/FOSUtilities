---
status: open
last_updated: 2026-10-03
origin: human
title: A new beginning all over again
---

An MVP tool to bootstrap the spec-driven development system: the tiny compiler for a subset, written in something already at hand, used to build the next tool. Minted 2026-10-03 at David's direction after a day of specimens recorded in `planning/notes/exploration-log.md`. The filename slug is a placeholder; the title is David's.

**Provenance.** Rulings under *Input → Rulings* are David's, dated. Scope, suggested actions and the OQ4 decision are the session's, the last on David's explicit delegation.

## Vision

The vision the tool serves is genesis's, ratified, at `FOSUtilities-workflow/specs/spec-0000.md:15`: *Deliver a fully specified system that can be regenerated from specification.* Its premise, `spec-0000.md:23`: *The system is a projection, and output is never truth.*

One sentence added, David's "seems good" 2026-10-03: the specification is addressable, so that every claim about it is checkable by him, by hand, in seconds.

Open: whether the kairos vision (`kairos/docs/kairos-vision.md`, an AI workflow platform for small businesses) carries over, or kairos v2 is a name and a repository only. David's to say.

## Goal

**Ruled by David, 2026-10-03, later:** the goal becomes the first representation; Markdown is an import.

The tool's first deliverable is a representation that can hold what the exploration log's entries of 2026-10-03 describe: statements with keys, typed links between them, a layer order, provenance on every statement, a fingerprint for staleness, a ruling ledger the statements cite, and the customer's expectations held apart. Both corpora enter it through an importer that reads today's Markdown. Resolve, reverse and check run over the representation, not over files. Built in Swift, in its own repository, and then used on the next real question before any further tool is specified.

**Superseded goal, for the trace.** The goal as minted the same morning: resolve a key to its verbatim block at file and line, list every citation, check declared-once and every-citation-resolves, over the Markdown as it is. That goal survives as the importer's acceptance and as the three operations, not as the tool.

**What this changes in the sections below.** Step 1, the census, stands: it is the importer's input grammar. Step 2's draft (`planning/notes/bootstrap-tool-requirements.md`) is superseded in part: req-8, req-9, req-11 and req-12 bind to Markdown and move to the importer; req-1 to req-5 stand; the rest are re-drafted against the representation. The second bullet of *Why this is the first step* no longer holds as written: the representation needs rulings the Markdown reader did not, at least what a statement is, what link types exist, and how provenance and layer are recorded. Concepts before names; that design is the next step and David arbitrates it.

## Why this is the first step (session's, David's "seems good" 2026-10-03)

- It is the floor under every specimen in the exploration log: bare keys that could not be opened, a paraphrase with no key, a stochastic count of stale sites, a consistency claim reported as a sentence, a review that could not be diffed. Each reduces to resolve, reverse or check.
- It depends on no open ruling. The stack view needs a layer order; the ruling ledger needs a document convention; the grammar is parked in truth-36104. The resolver needs only the declarations that exist, and the census shows them regular: four forms, one tokenizer, one scope rule.
- It moves claims from trust to verification at once: "T24 says X" is checked in one command, and a session with no key has nothing to stand on.
- It is the tiny compiler: its own requirements are keyed and checked by itself, and its first real use writes the next tool's specification.
- No AI in it, so it cannot feed output back in as input.

It is not a vision for the whole workflow system, a grammar ruling, or a home for the kairos documents.

## Input

### Rulings (David, 2026-10-03)

- OQ1 Language: Swift.
- OQ2 First corpus: both. Fosline's documents and the workflow worktree's specifications; they were derived with various ideas of how to get them to the point they are at.
- OQ3 Home: a new project, its own repository. Name open. David's candidate is `kairos`, as a v2 of those concepts (concepts morphing, not a version). If so, the existing kairos project is archived and started again, on his word at that time. The kairos architecture documents and the worktree's documents are both to be incorporated at some point; the worktree's are believed to still form the foundation of the process.
- OQ4 Text-id versus concept-id: delegated to the session.
- OQ5 Title: "A new beginning all over again". Tool and repository names remain David's.
- OQ6 Key case and open-question form (2026-10-03, written by David into `planning/notes/bootstrap-tool-requirements.md`): "Upper case is nicer, as it stands out. That said, comparisons between keys should be case-insensitive, e.g., REQ-1 == req-1; case does not change the identity. So, for example, if there's a command line, passing req-1 as a command line parameter is completely acceptable. I also really like the OQ format to be OQ-<KEY># as well. That makes all open questions completely discoverable." OQ7 was opened by him in the same file and left blank.
- OQ6 clarified (2026-10-03, night, in session): the open-question form is `OQ<q#>-<KEY>`, the key being the full key of the statement questioned "so that all ids are permanently unique", "or at least the primary thing that it questions." Session's wrong reading (family plus number) withdrawn.
- OQ13 closed, not ruled (2026-10-03, night): David asked whether cross-kind number uniqueness "kinda assumes that the id is inspectable." It does; ids are opaque under the encapsulation rule already on record, kind lives on the statement, display forms are minted and never parsed.
- Two populations (2026-10-03, night, in session): "now we have a cyclic graph that can be navigated where there are truth statements <KEY># and there are metadata <MD>#-<KEY>#"; the metadata number is "stable across all MD nodes attached to <KEY>", one sequence per truth statement shared by every metadata kind; the id is the whole form. Session's "the number and key alone identify the node" struck on his word.
- Key form (2026-10-03, after the census): David prefers the worktree's kind-dash-number form (`spec-0000`, `build-15879`; he wrote it `SPEC-#`, case his to say) over fosline's letter-prefix keys (T1, AR77). Neither form is baked into the tool: families come from the declarations it finds. fosline's keys are fosline's question, not this item's.

### OQ4, decided by the session on delegation

The MVP resolves the ids that exist in the documents today, as text-ids: the id names the block that carries it, and nothing else. No concept-id layer until supersession first bites a real id. The census reports whether any id has already been re-pointed or reworded, which is the evidence that decides when. Lowest commitment, reversible, and it adds no link type that nothing projects from.

### Facts gathered 2026-10-03

- Fosline's thirteen documents under `fosline/docs/` carry roughly 6,000 id mentions across seven prefixes: T (requirements, about 2,059), AR (architecture, 1,626), UI (711), VM (547), C (509), DM (359), SD (246). Declarations are anchored at line start as bold id plus period, for example `**T1.**` at `fosline-trading-requirements.md:100` and `**DM1.**` at `fosline-suite-data-models.md:106`. Citations appear inline in prose: `T2's`, `(AR77)`, `T49's second test`.
- The workflow worktree (`FOSUtilities-workflow`, branch `feature/fos-development-workflow`) holds `specs/spec-0000.md`, `spec-0001.md`, `spec-0002.md`, with planning notes and work items under `planning/`. Its filename is the global id; references are by id, never path (spec-0002). The tree is uncommitted working state, six weeks old.
- The existing kairos repository at `FOS/kairos` holds `docs/kairos-vision.md`, `core-concepts.md`, `governance-architecture.md`, `technical-architecture.md`, `workflow-model.md`, `architecture-plan.md`, `execution-plan.md`, `strategy.md`, plus `docs/investigations/` (sixteen files, including `intent-problem-validation.md`, `ai-governance-bypass-pattern.md`, `session-state-architecture.md`) and `docs/analysis/`. Its launchd agents were unloaded 2026-09-24.
- A shipped precedent for the tool's shape: `swift package fosmvvm-doctor`, a deterministic compiled audit run as a SwiftPM command plugin, reading a project and printing findings with remedies.

### Why this subset, from the day's specimens

Every specimen in the exploration log reduced to the same missing operations. Twenty-seven bare ids in one message that David could not open. A question paraphrased into a third vocabulary with no id, type or address that David could not audit. Roughly 45 stale sites counted by a stochastic reader, one count approximate. A consistency check ("107 VM keys and 59 DM keys each declared once") run inside a session and reported as a sentence to be trusted. A review request over seven documents that David cannot diff. Resolve, reverse and check are the floor under all of them, and the first node of the link graph recorded as session assessment in the worktree's `truth-36104`.

### Not in the MVP, by design

The stack view (resolve along one id's descent, ordered by layer) is the first increment and needs a layer order per corpus. The ruling ledger and its trial balance (every statement cites a ruling; unbalanced entries are the review list) is the second and needs a document convention first. Staleness fingerprints, the expectations channel, any UI, and any link type nothing projects from are later items or never. David's own pattern, named 2026-10-03, is aiming at the general system; this item is allowed to stay dumb.

**A laundering detector, David's ask of 2026-10-03 (evening):** *"only thing that we need to create at some point is a 'laundering' detector that can be used to feed back into the review process."* Its own work item when the representation exists. What it needs from the representation: provenance on every statement, and rulings as records holding his verbatim words. The detection, as the session reads it: a statement marked as David's that cites no ruling, or whose cited ruling's words do not contain it, is unbalanced and goes on the review list. The trial balance named above, applied to provenance.

## Suggested actions

1. Census both corpora, read-only: every id prefix, how declarations are anchored, how citations are written, counts, ids cited but never declared, ids declared more than once, and any id that has been re-pointed. Written to `planning/notes/` in the new repository once it exists, or here until then. This is the first fact the spec needs and it decides whether the build is a day or a week.
2. Write the one-page requirements for the tool from the census: id grammar per corpus, resolve, reverse, check, output shape. David's intent lines marked as his; the session's drafts marked as unratified. The requirement sentences are a cheap live trial of the grammar questions parked in `truth-36104`, without ruling them.
3. Name the repository (David) and create it as a SwiftPM package with one executable target. Decide then whether the existing kairos repository is archived.
4. Build resolve, reverse and check. Deterministic. No AI in the tool. Tests against fixture documents cut from both corpora.
5. Run it on both corpora and record what it finds as the first census-by-tool; compare with the hand census from step 1.
6. Use it on the next fosline question: quote every id verbatim at its address, never paraphrase. That use is the work item the next tool's spec is distilled from.
7. Then, as separate items: the stack view; the ruling ledger; incorporating the kairos documents and the worktree's documents into the new project's truth layer.

## History

- 2026-10-03, night: representation concepts drafted for David's reading, `planning/notes/bootstrap-representation-concepts.md`, blocks A to M. First cut asked OQ12 to OQ23; David asked whether he had already answered them, and nine had rulings on record (genesis, spec-0002, the log, OQ6). Recut: each block quotes the ruling it rests on at its address; OQ12/15/16/17/19/20/21/22/23 retired as answered; OQ13, OQ14, OQ18 remain. OQ6 found answered by David inside the requirements draft and recorded under Rulings.
- 2026-10-03, evening: David ruled the goal becomes the first representation, Markdown an import, after the seventeen-files specimen (exploration log). Goal section rewritten with the superseded goal traced; step 2 draft marked superseded in part; next step is the representation design.
- 2026-10-03, later still: step 2 drafted, `planning/notes/bootstrap-tool-requirements.md` (req-1 … req-17, OQ6–OQ11), awaiting David's red pen. Vision, goal and why recorded above the same day.
- 2026-10-03, later: step 1 done. The census is `planning/notes/id-census-2026-10-03.md` (session's, unratified). It corrects the fact sheet above: nine core families in fosline's `docs/` (L and D added), four declaration grammars, sixteen further families, R and Q collide across documents, the workflow corpus has document keys only, and re-pointing has already happened in the taxonomy (F7/F8/F18/F19 became A1–A4) and in the workflow worktree (spec-0001 reassigned). Next is step 2, the one-page requirements.
- 2026-10-03 minted at David's direction, after OQ1–OQ3 and OQ5 ruled and OQ4 delegated. Preceded by the day's specimens in `planning/notes/exploration-log.md` and the prior-art work item `truth-36104` in the workflow worktree. Written before any execution, as the day's own lesson required.
