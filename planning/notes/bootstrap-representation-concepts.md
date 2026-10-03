---
status: unratified
last_updated: 2026-10-03
origin: session
title: The representation, concepts before names
---

The next step of `planning/stream/feat-bootstrap-tool.md` (A new beginning all over again), after your ruling of 2026-10-03 evening that the goal is the first representation and Markdown is an import.

**Recut 2026-10-03, night.** The first cut put twelve questions to you. You asked whether you had already answered them. Nine were answered by rulings already on record. This cut states each concept, then quotes the ruling it rests on at its address, and leaves only the three that no ruling reaches. Nothing here has a name yet; every word in bold is a placeholder you will name later.

**Reading the addresses.** `spec-0000.md` lines are the working tree's 2.0 draft; every sentence quoted from it is carried unchanged from 1.4, the version in force since 2026-08-11 (`spec-0000.md:7`). `spec-0002.md` is ratified 1.2. The exploration log and the work item hold your words marked as yours at the lines given.

**Provenance.** *Rests on* lines are your words or ratified text, quoted. *Follows* lines are the session's derivation from them, unratified. A block with no *Awaiting* line asks you nothing.

## A. The grain

A statement is the unit the tool resolves, links, fingerprints and audits. A specification is a keyed container of statements. Two grains.

Rests on: "a representation that can hold ... statements with keys, typed links between them, a layer order, provenance on every statement" (your Goal ruling, `planning/stream/feat-bootstrap-tool.md:24`). "Standing is recorded in the specification's own header" (`spec-0000.md:63`).

Follows: status is per statement, since fosline strikes T81 while its document lives (census). Standing is per specification, since the header carries it. Neither grain reduces to the other. A statement belongs to exactly one specification. fosline's `T49's second test` stays an importer detail, not a third grain.

## B. Key identity

A key is text, case-folded for identity, upper case for display, immutable, never reused. The number is allocation order, never position.

Rests on: "comparisons between keys should be case-insensitive, e.g., REQ-1 == req-1; case does not change the identity" and "Upper case is nicer" (your OQ6 answer, `planning/notes/bootstrap-tool-requirements.md:68`). "An id retires with its document and is never reused" (`spec-0002.md:41`). The kind-dash-number form preferred, neither form baked in (`feat-bootstrap-tool.md:50`).

Follows: the census finding that numbers are allocation order holds for the representation too.

Retired, OQ13 (2026-10-03, night). The first cut asked whether the number inside a key is unique across kinds. You asked whether that assumes the id is inspectable. It does. An id is opaque, unique, allocated by the tool, never reused and never parsed; your encapsulation rule already says so. The kind is a property of the statement, not something read out of its key. The display form (`truth-19472`) is minted by the tool from the id and the statement's properties, and nothing downstream may split it. Lookup conveniences, a short-fragment search or a kind-mismatch hint, are later tool features judged on their own and may never read structure out of an id. Closed by a principle on record, not by a ruling.

## C. Imported keys

fosline's `T1`, and the two different `R1`s, enter the representation without a merge and without any change to fosline.

Rests on: "fosline's keys are fosline's question, not this item's" and "Neither form is baked into the tool: families come from the declarations it finds" (`feat-bootstrap-tool.md:50`; req-5 at `bootstrap-tool-requirements.md:24`).

Follows: family is prefix plus document (census), so an imported key's identity carries its source specification.

**Awaiting your ruling, OQ14.** How an imported key keeps working as a lookup without being the identity. Candidates: the importer allocates a fresh tool key per imported statement and records fosline's text as an **alias**; or the imported key is qualified by its source specification and stays the identity. Recommendation: the alias, because it is the only form under which the id stays opaque and tool-allocated for imported statements too.

## D. Links

A link is a typed edge from one keyed thing to another, written from the dependent side to the thing it depends on. Five types, each consumed by something you asked for.

Two populations share the graph. **Truth statements** carry a bare key, `T27`, `spec-0002`: what the architect or the customer originated. **Metadata statements** carry `<MD><n>-<KEY>`, where `<KEY>` is the primary truth statement they are about and `<MD>` their kind: `OQ1-T27`, `RUL2-T27`. The number is drawn from one sequence per truth statement, shared by every metadata kind attached to it, so no two metadata nodes on T27 ever share a number. The id is the whole form. Your words, 2026-10-03 night: "now we have a cyclic graph that can be navigated where there are truth statements <KEY># and there are metadata <MD>#-<KEY>#"; and on the number, "we probably want <MD><n>-<KEY> to be able to be stable across all MD nodes attached to <KEY>."

Follows: the graph is navigable both ways, from T27 to everything said about it and from any metadata node to its subject by its own id. Cycles are fine through `cites`, `asks about` and `rests on`. `descends from` must stay acyclic, since conflict resolution walks it toward the origin and must terminate; that is a check. Expectations are the customer's truth, bare-keyed, not metadata.

- **descends from**. Rests on: "he wants all the pieces highlighted like a debugger's call stack, able to chase up the tree" (log, `exploration-log.md:167`); "Resolution runs toward the origin: up the chain of descent" (`spec-0000.md:69`).
- **cites**. Rests on: "It does three things, resolve, reverse and check" (req-3, `bootstrap-tool-requirements.md:20`). Reverse is the walk over this type.
- **supersedes**. Rests on: "A superseding specification names its predecessor in History; a reference to a retired id throws" (`spec-0002.md:41`).
- **rests on**. Rests on: "the document system should be able to balance what the documentation says against the specifications he, the customer and architect, has given" (log, `exploration-log.md:187`); the laundering detector, "rulings as records holding his verbatim words" (`feat-bootstrap-tool.md:71`).
- **asks about**, one or more targets, one marked primary. Rests on: "I also really like the OQ format to be OQ-<KEY># as well. That makes all open questions completely discoverable" (OQ6, `bootstrap-tool-requirements.md:68`).

Follows: every link is a record. The importer marks the ones it derived from prose (fosline's inline mentions, ranges, possessives, `*Keys:*` lines); a derived link stays visibly derived until an act confirms it. The log's unratified principle, no link type that nothing consumes, is satisfied by construction: each type above names its consumer.

## E. Provenance

Every statement carries two separate marks: whose thinking it is, and what approved it.

Rests on: "Standing comes from origination; approval is not authorship" (`spec-0000.md:33`). The three roles, and that the operator never originates (`spec-0000.md:61`). "David's ruling: the customer originates the expectations" (log, `exploration-log.md:177`).

Follows: four originating seats, architect, interpreter, customer, and unknown for imported history. Originator is a field on the statement. Approval is not a field; it is a `rests on` link to a ruling of the ratifying kind. The importer sets originator from `(David)`, `*(session)*`, `-- David:` and change-log quotations, and marks everything else unknown rather than guessing. The laundering detector reads the two marks and the `rests on` link and nothing else.

## F. The ruling ledger

A ruling is a record of your verbatim words, dated, with the question it answered. Append-only: never edited, superseded only by a later ruling that links to it.

A ruling is a metadata statement, block D: its id is `<MD><n>-<KEY>` with the primary statement it ratifies or answers as the key, and its number from that statement's shared metadata sequence. Where one ruling ratifies many statements at once, as the six-word table did, the primary key is chosen and the rest are linked.

Rests on: "rulings as records holding his verbatim words" (`feat-bootstrap-tool.md:71`). "your words are in five change logs, the review record, the handoff and the session memory" as the complaint, and "balance ... against the specifications he ... has given" as the ask (log, `exploration-log.md:179`, `:187`). Append-only is spec-0002's History convention (`spec-0002.md:41`).

Follows: fields are your words verbatim, the date, the question answered (a key from block J, or none), the seat. Two entry doors, same record: you type it where you type it now and the tool records it; or the tool asks and records the answer born linked to its question. The importer harvests the existing quotations as rulings marked derived, with source addresses, so the trial balance runs on fosline on day one.

## G. Status

A statement is unratified, ratified, struck, withdrawn or superseded.

Rests on: "Standing is recorded in the specification's own header" (`spec-0000.md:63`). "Output shall never be read as authority" (`spec-0000.md:49`).

**Awaiting your ruling, OQ18.** Whether status is stored or derived. Stored: a field, set by hand or by the importer, as the header does today. Derived: ratified means a ratifying ruling rests under the statement; struck or withdrawn means a ruling of that kind rests under it; superseded means a `supersedes` link points at it; otherwise unratified. Recommendation: derived, so a status can never disagree with the ledger and the word "ratified" in a header becomes a claim the check verifies. The header still records it, as a projection of the ledger. The cost: every fosline tombstone needs a harvested ruling behind it or shows as unbalanced, which is the finding the trial balance exists to show you.

## H. Layer

No layer field. The order from the origin downward is the `descends from` graph. A kind label on each specification is for display.

Rests on: "Genesis asserts no fixed ranking among the kinds. Descent settles what it can; everything else unwinds to the architect" (`spec-0000.md:75`).

Follows: a stored layer number would be a ranking genesis refused. Where the graph has no path between two statements, that is the throw genesis describes.

## I. Expectations

The customer's expectations are statements with originator customer, in their own specification, never descending from a requirement, architecture or design statement, and never descended from.

Rests on: "the customer's expectations held apart" (your Goal ruling, `feat-bootstrap-tool.md:24`). "David's ruling: the customer originates the expectations, the one for whom the system is being built" (log, `exploration-log.md:177`).

Follows: the representation holds the kind and one check, no `descends from` link in either direction across that boundary. Reconciliation between expectations, specifications and the projected system is a later tool's output over this separation, not a stored link. No fosline import of expectations exists to run.

## J. Open questions

An open question is a metadata statement, block D, with an `asks about` link to each statement it bears on, one of them primary. Its id is `OQ<n>-<KEY>`: the kind first, the number, then the primary key. Its answer is a ruling that cites it.

Rests on: OQ6 (`bootstrap-tool-requirements.md:68`), quoted in block D. Clarified by you in session, 2026-10-03 night: the key inside the form is the full key of the statement questioned, "so that all ids are permanently unique"; the order is "OQ<q#>-<KEY>"; and the key names "the primary thing that it questions."

Follows: the id is minted, never parsed. The tool holds the kind, the primary target's key and that target's shared metadata sequence, and mints `OQ1-T27` from them; the `asks about` link carries the relationship. The number is not a count of questions: it comes from the one sequence every metadata kind on T27 shares (block D), so `OQ1-T27` and `RUL2-T27` can never be confused for two unrelated firsts. Every open question sorts and greps together under `OQ`. "Completely discoverable" is a query, every open question with no ruling citing it, per key or per store; no document needs an *Open questions* section of its own. The first cut's reading of the form as family plus number, fosline's `OQ-VM10`, was wrong and is withdrawn.

## K. The substrate

Plain-text records in a git repository are the truth. One record per statement, under a directory per specification. The tool is the only writer. Every index, a database included, is derived and never committed.

Rests on: "Filenames are global ids" and "The path is pure address, mechanically derivable from the id, carrying no semantic content" (`spec-0002.md:25`, `:29`). "Git history is the archive" (`spec-0002.md:39`). "the specification is addressable, so that every claim about it is checkable by him, by hand, in seconds" (your "seems good", `feat-bootstrap-tool.md:16`). "Here's a perfect example of why I don't think files work. What am I supposed to do with that?" and Markdown "almost certain it cannot carry the functionality" (log, `exploration-log.md:197`).

Follows: your objection was to files as the review surface, and under this design you never open a record to review. You ratify a table or a ruling, the tool applies and checks, and what reaches you is a count and the exceptions. A claim is one `cat` away. The database is output.

Consequence, already ruled but worth your eyes: after import, fosline's thirteen Markdown documents become output projected from the records, and the only door for a change becomes the record. Rests on: "Where a specification exists, it is the only door" (`spec-0000.md:53`). That is a process change for fosline on the day its import is accepted, not a tool detail.

## L. One store per repository

Each repository holds its own store. A citation into another repository's store is a link whose target carries that store's name.

Rests on: spec-0002 is a repository's layout, ratified for one repository. The architect is "David Hunt here, and in an adopting project whoever is driving" (`spec-0000.md:61`), one seat per project.

Follows: one store spanning both corpora would hold two seats the day a second project adopts it.

## M. What the importer owes the representation

For the trace, not for ruling. From today's Markdown the importer produces: specifications from files and headers; statements from the four declaration grammars in the census; `cites` links from inline mentions, ranges, possessives and `*Keys:*` lines, marked derived; `supersedes` from the taxonomy's appendices and spec-0002's History where the text names it; rulings from `(David)`, `-- David:` and change-log quotations, marked derived, with source addresses; originator marks; and nothing else. OQ7 to OQ10 in the requirements draft remain the importer's questions.

## Retired questions

OQ12, OQ15, OQ16, OQ17, OQ19, OQ20, OQ21, OQ22 and OQ23 from the first cut were answered by rulings already on record, quoted in blocks A, D, E, F, H, I, J, K and L. OQ13 was closed by the opaque-id principle, block B. The labels are retired, not reused.

## Not decided here

Names for every bold placeholder above. The record encoding. The command-line surface. The repository name (OQ11, yours). Whether the existing kairos documents import.

## Awaiting your ruling

OQ14 Block C, alias or source-qualified identity for imported keys.

OQ18 Block G, status derived from the ledger or stored.
