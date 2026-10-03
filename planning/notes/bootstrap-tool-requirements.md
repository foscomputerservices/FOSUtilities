---
status: unratified
last_updated: 2026-10-03
origin: session
title: Requirements for the bootstrap tool
---

**Superseded in part, 2026-10-03 evening.** David ruled the tool's goal is the first representation, with Markdown as an import. req-1 to req-5 stand. req-8, req-9, req-11 and req-12 are now the importer's requirements. The rest await re-drafting against the representation once it is designed. Kept as the trace.

Step 2 of `planning/stream/feat-bootstrap-tool.md`. Drafted from `planning/notes/id-census-2026-10-03.md`. Lives here until the tool's repository exists, then moves to its truth layer.

**Provenance.** A line marked *(David)* restates his ruling of 2026-10-03. A line marked *(session)* is a draft for his red pen. The statement keys `req-1` … are a placeholder form, see OQ6; this page is the live trial of a key grammar the work item asked for.

## The tool

req-1 *(David)* The tool is Swift: a SwiftPM package with one executable target, in its own repository. Name his.

req-2 *(David)* It reads two corpora: fosline's documents and the workflow worktree's specifications and planning files.

req-3 *(David)* It does three things, resolve, reverse and check, and nothing else.

req-4 *(David)* No AI inside it. Same inputs, same output bytes.

req-5 *(David)* No key family and no document form is baked in. Families are discovered from the declarations the tool finds.

## Corpora and scope

req-6 *(session)* A corpus is given to the tool as a root directory, a primary scope and zero or more secondary scopes, each a directory under the root. For fosline: root `fosline/`, primary `docs/`, secondary `archive/` and `plans/`. For the worktree: root the worktree, primary `specs/` and `planning/stream/`, secondary the rest of `planning/`.

req-7 *(session)* Declared-once is judged inside the primary scope. A key not declared in the primary resolves in a secondary. A key declared in both is not a finding; the secondary holds prior versions by design.

## Keys

req-8 *(session)* A block key is declared by a line that starts, after an optional list marker, with a bold run in one of four forms: `**KEY.**`; `**KEY. Title.**`; `**KEY · Title.**`; or a bold title with `(KEY)` inside it. The index form `- **KEY** — …` is not a declaration.

req-9 *(session)* A document key is declared by a filename whose stem is letters, a dash and digits: `spec-0000`, `build-15879`. The key is the stem.

req-10 *(session)* A key's identity is the triple corpus, declaring file, key text. The same text declared in two files of one primary scope is a collision finding, never a merge.

req-11 *(session)* A citation is a key token not touching a letter, digit, underscore, slash or dot on either side. Recognised around it: a possessive `'s`; a range `KEY–KEY` or `KEY-KEY` with one prefix, which expands to every key between; backticks; square brackets; a `*Keys:*` line, every key on it. Declaration and index lines are never citations of their own key.

## Resolve

req-12 *(session)* `resolve KEY` prints `path:line` and the verbatim block: the declaring line and every following line up to the next blank line. A tombstone (a declaration whose text is *Struck* or *Withdrawn*) resolves to its tombstone text, marked as such. An undeclared key exits non-zero with the word *undeclared*.

## Reverse

req-13 *(session)* `reverse KEY` prints every citing site as `path:line: ` and the line verbatim, in path then line order, with the count last. A range that covers the key counts as a site.

## Check

req-14 *(session)* `check` prints one line per finding and exits non-zero if any finding is of a failing kind. Finding kinds: declared more than once in the primary scope; cited but declared in no scope; citation of a tombstone; index of keys disagreeing with the declarations; the same number under two kinds (`chore-19472` and `truth-19472`); a document key cited with no file (OQ8). Reported but not failing: a range claim `KEY1–KEYn` whose n is not the family's maximum (OQ7).

req-15 *(session)* A finding line is `path:line: kind: key: detail`. No colour. No summary sentence that a finding line does not back.

## Proof

req-16 *(session)* Tests run against fixture documents cut from both corpora and checked into the tool's repository. Fixtures are copies; the tool never writes to a corpus.

req-17 *(session)* Acceptance: run on both corpora, compare with the hand census, and account for every difference.

## Not in this tool

The stack view, the ruling ledger, staleness fingerprints, an expectations channel, any UI, any edit to a corpus. Per the work item.

## Open questions

OQ6 The statement key form for this page and for the tool's own specification. `req-n` is a placeholder; David prefers the kind-dash-number form and the case is his to say. -- David: Upper case is nicer, as it stands out.  That said, comparisons between keys should be case-insensitive, e.g., REQ-1 == req-1; case does not change the identity.  So, for example, if there's a command line, passing req-1 as a command line parameter is completely acceptble.  I also really like the OQ format to be OQ-<KEY># as well. That makes all open questions completely discoverable.

OQ7 Range claims: report only (drafted), or fail; and whether a dated claim (*AR1–AR46 approved 2026-09-19*) is exempt by rule or left to the reader. -- David: 

OQ8 A cited document key with no file: fail outright, or resolve through git history before failing. The census found ten such keys that never existed in history and one that did.

OQ9 Tombstone detection by the words present today (*Struck*, *Withdrawn*) or by a marker the documents adopt. Drafted as the words.

OQ10 Block extent for resolve: to the next blank line (drafted), to the next declaration, or through the block's `*Keys:*` line.

OQ11 The repository name. Step 3; David's.
