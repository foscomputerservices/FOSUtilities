---
name: fosutilities-api-catalog-update
description: Update the FOSUtilities API catalog after API changes. Runs the symbol-graph audit, fixes stale entries, writes curated entries for gaps, maintains the reach-for index, and bumps the plugin version. Use in the FOSUtilities repo when CI's catalog audit warns/fails, after adding or renaming public API, or when a reach-for index line is missing.
homepage: https://github.com/foscomputerservices/FOSUtilities
metadata: {"clawdbot": {"emoji": "🗃️", "os": ["darwin"]}}
---

# FOSUtilities API Catalog — Update

This skill keeps `.claude/skills/shared/api-catalog/` truthful and complete. The
catalog is the discovery surface for every project that imports FOSUtilities
(via the `fosutilities-api-catalog` skill); an entry that lies about the API is
worse than a missing one, which is why the audit fails CI on stale entries but
only warns on gaps.

Run this on **macOS** — that builds the full API surface. On Linux the
Apple-only modules (FOSReporting) produce no symbol graph, and the audit skips
the stale checks for those files, so a Linux run can pass while an Apple-only
entry is stale. (This platform note lives here, in the maintainer skill — never
in the catalog files themselves, which serve the customer audience only.)

## Audit-driven workflow

1. **Run the audit** from the package root:

   ```bash
   swift scripts/api-catalog-audit.swift
   ```

   It builds the package (`swift package dump-symbol-graph` — may take a
   while), then reports three sections: **Catalog gaps** (warning), **Stale
   entries** (ERROR — exit code 1), and the **DocC worklist** (warning).

   Gotcha: the gaps section and the DocC-worklist section share the same
   `Module: symbol [source file]` line format. Any grep over the output must be
   scoped to one section, e.g.:

   ```bash
   swift scripts/api-catalog-audit.swift | awk '/== Catalog gaps/,/== Stale/'
   ```

2. **Fix stale entries FIRST** — they fail CI. A stale entry means the API
   changed out from under the catalog: a symbol named in an entry's `###` title
   no longer exists in that file's modules. Read the source to find what
   happened, then either update the entry's title symbols (rename), rewrite the
   entry (redesign), or remove it (deletion).

   Cross-module caveat: each catalog file's stale universe is **only its own
   modules' symbol graphs** (see `moduleToCatalog` in the audit script). A title
   symbol that actually lives in another file's module reports stale even
   though it exists. Remediation is moving the entry to the owning module's
   catalog file — or, rarely, the ignore list.

3. **Write a curated entry for each gap**, per the entry format rules below.
   Always read the actual source first — never write an entry from the symbol
   name alone. If the symbol is **not customer-reachable** (deprecated,
   compatibility shim, macro plumbing), add its base identifier to
   `scripts/api-catalog-ignore.txt` with a `#` comment stating the reason —
   never leave a silent gap.

4. **Update the reach-for index** when a new entry serves a reach that the
   discovery skill (`.claude/skills/fosutilities-api-catalog/SKILL.md`) doesn't
   index yet. Index lines are keyed by **what the implementor is reaching for**
   (`Reaching for URLSession…`), never by our library layout, and point to a
   real `## ` header: `` `FILE.md § Section` ``.

5. **Report the DocC-worklist count.** No DocC action happens in this workflow
   — the count is the measurable backlog for the separate DocC effort. Just
   surface it in your report so the trend is visible.

6. **Re-run the audit** and repeat until: 0 stale entries, 0 non-ignored gaps,
   exit code 0.

7. **Bump the plugin version** in `.claude-plugin/plugin.json`. Consumers only
   receive catalog and skill updates on a version bump — an unbumped update
   ships to no one.

## Non-audit path: index and structure maintenance

Some catalog work has no audit signal:

- **Adding or adjusting reach-for index lines** for already-catalogued
  capabilities (a reach was missing, or its wording didn't match how
  implementors think): edit the discovery skill's index directly, then do
  step 7 (version bump).
- **Renaming a `##` section or splitting a catalog file:** sweep the reach-for
  indexes — the discovery skill and any CLAUDE.md index blocks — for dangling
  `` `FILE.md § Section` `` pointers and fix them. Pointers are **not**
  audited; a rename silently breaks them.

## Entry format rules (binding)

These rules are the single source of truth for catalog entry format. They exist
because the audit parses entries mechanically and because the catalog ships on
a public plugin surface.

1. **`##` categories mirror the library's source folders** (e.g. `## Coding`
   for `Sources/FOSFoundation/Coding/`). Each category opens with 1–2
   orientation sentences that cover **everything** in the section — including
   naming internal files as internal when relevant, so a reader doesn't go
   hunting for API that isn't public.

2. **`###` titles are task-framed with the entry's own symbols in backticks in
   the title line.** The title line is the audit's **only** freshness anchor —
   prose and example backticks are ignored by design.
   - **Label-free symbol forms only**: `count()`, never `count(of:)`. The
     parser tokenizes on non-identifier characters and would flag `of` as a
     stale symbol.
   - **Never backtick stdlib/Foundation/SwiftUI/Vapor types in titles** —
     they aren't in our symbol graphs and would report stale. Mention them in
     prose or examples, which the audit ignores.
   - **Only symbols owned by THIS file's modules go in titles** (stale checks
     are scoped per file). A cross-module symbol goes in prose with a pointer
     to its own catalog file.
   - Mixed title grammar is fine: imperative ("Compare versions — …") or
     noun-phrase ("Codable JSON round-trip — …").

3. **Mandatory "Reach for this when:" line** describing the reader's mid-task
   moment — the situation they're in, not a restatement of the API name.
   Optional **"Don't:"** line naming the concrete reinvention the entry
   replaces (`Don't hand-roll JSONDecoder configuration…`).

4. **Examples are short and real.** 2–4 lines for call-style APIs; up to ~8
   lines for inherently structural declarations (type conformances, macro
   expansions). Never padded to look thorough. **Every example must be
   verified against real source** — an example calling a nonexistent API is
   the catalog's worst possible failure.

5. **Contracts, never representations.** The catalog is a public,
   plugin-shipped surface: no encoded shapes, token formats, byte layouts, or
   internal implementation details. State what the API guarantees, not how it
   does it.

6. **One entry may cover a small family** of symbols reached for as one
   capability (e.g. an encode/decode pair) — but **every family symbol goes in
   the title backticks**, or the audit reports the missing ones as gaps.

7. **House style:** honest limitation notes (say what an API does *not* do);
   cross-references between related entries; generator-skill pointers limited
   to one prose line; customer audience only — no maintainer or tooling
   commentary in catalog files (that belongs here).

### Canonical example

From `FOSFoundation.md § Coding` — title symbols as freshness anchor, family in
one entry, "Reach for" + "Don't" lines, minimal verified example:

````markdown
### Codable JSON round-trip — `fromJSON()` / `toJSON()` / `toJSONData()`
Reach for this when: converting any Codable to/from JSON strings or Data.
Don't hand-roll `JSONDecoder` configuration — these apply the library's standard
coding strategy (dates, keys) consistently with the server.

```swift
let user: User = try jsonString.fromJSON()
let json = try user.toJSON()
let data = try user.toJSONData()
```
````

## Why these rules protect the architecture

Entries state **contracts, never representations** — the catalog ships publicly
with the plugin, and publishing an encoded shape or internal layout there would
make it a de-facto schema consumers parse and depend on, freezing internals
forever (see CLAUDE.md, "Encapsulation Is the Precondition SOLID Assumes").
Titles are the audit's freshness anchor precisely so the catalog **cannot
silently lie**: any entry whose title symbols drift from the real API fails CI.
Prose and example backticks are ignored by design — they may freely mention
foreign types and context without polluting the freshness check.
