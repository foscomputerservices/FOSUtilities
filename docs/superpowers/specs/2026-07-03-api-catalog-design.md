# FOSUtilities API Catalog (Design Spec)

**Status:** Ready for plan.
**Date:** 2026-07-03
**Targets:** `.claude/skills/` (plugin content), `Scripts/`, CI. **No library source changes.**

## Purpose

FOSUtilities' libraries carry ~15 years of accumulated Swift API — helpers under
FOSFoundation's Coding/Collections/Networking/String/etc., plus the FOSMVVM, Vapor, Testing,
and Reporting surfaces. AI (Claude) users of these libraries — in consumer projects via the
`fosmvvm-generators` plugin, **and Claude working inside this repo** — routinely don't know
these APIs exist and reinvent them, or find them and use them non-idiomatically. DocC is
woefully out of date/missing, so today there is no reliable discovery surface at all.

This spec introduces a **curated, categorized API catalog** written for an AI reader, three
delivery channels that put it in context at the moment code is written, and an **audit +
update mechanism** so it cannot silently go stale.

Two failure moments drive the format:

1. **Not knowing what exists** → the catalog must be a browsable, categorized inventory,
   reachable both on-demand (skill) and always-on (CLAUDE.md index).
2. **Non-idiomatic use** → every entry carries "reach for this when…" framing and a short
   idiomatic example, not just a symbol name.

## Non-goals

- **Fixing DocC.** The audit script *reports* public symbols missing DocC (a measurable
  worklist for that future effort), but writing DocC is a separate project.
- **Generating the catalog from DocC/source.** Entries are hand-curated; only the
  *freshness check* is mechanical.
- **Per-domain mini-skills** (one skill per category). Rejected: skill proliferation and
  fragmented cross-cutting answers.
- **API changes of any kind.** The catalog documents what ships; it never drives renames.

## Component 1 — The catalog files

**Location:** `.claude/skills/shared/api-catalog/` (ships with the plugin, alongside
`NAMES.md` / `architecture-patterns.md`).

One file per user-facing library surface:

| File | Covers |
|------|--------|
| `FOSFoundation.md` | FOSFoundation |
| `FOSMVVM.md` | FOSMVVM (incl. macro-exposed API surface) |
| `FOSMVVMVapor.md` | FOSMVVMVapor |
| `FOSTesting.md` | FOSTesting, FOSTestingUI, FOSTestingVapor |
| `FOSReporting.md` | FOSReporting |

**Structure:** `##` category headers mirroring the library's source folders (for
FOSFoundation: Async, Coding, Collections, Data, Extensions, Networking, Numbers, String,
Versioning). Each category opens with 1–2 sentences of orientation ("everything here is
about turning Codable values into wire/storage formats and back").

**Entry format** — dense, task-framed, written for an AI deciding whether to reach for it:

```markdown
### Codable JSON round-trip — `fromJSON()` / `toJSON()`
Reach for this when: converting any Codable to/from JSON strings or Data.
Don't hand-roll `JSONDecoder` configuration — these apply the library's standard
coding strategy (dates, keys) consistently with the server.

​```swift
let user: User = try jsonString.fromJSON()
let json = try user.toJSON()
​```
```

Rules for entries:

- **Title is task-framed** ("Codable JSON round-trip"), not symbol-framed — the reader is
  matching a task, not a name.
- **The entry's own symbols appear in backticks in the `###` title line** — that title line
  is the *only* place the audit script matches for freshness. Backticks in prose and
  examples (which will routinely name stdlib/Foundation types like `JSONDecoder`) are
  ignored by the audit.
- **"Reach for this when:" is mandatory**; an optional "Don't:" line names the reinvention
  it replaces.
- **Example is 2–4 lines**, idiomatic, complete enough to copy.
- **Contracts, never representations** (encapsulation rule): no encoded shapes, token
  formats, or byte layouts — the catalog is a public surface exactly like DocC/README.
- Entries group naturally: one entry may cover a small family (`toJSON()`/`fromJSON()`,
  the casing utilities) when they're reached for as one capability.

## Component 2 — Discovery skill

**New skill:** `.claude/skills/fosutilities-api-catalog/SKILL.md`, shipped in the plugin.

- **Description (the trigger)** enumerates task shapes, not library names: JSON/Codable
  encoding-decoding, HTTP/URL fetching, WebSockets, mocking network calls, collection
  manipulation, string casing/crypto/obfuscation, hex/number formatting, version
  comparison, stubbing/test data, async coordination (semaphores, task helpers), plus the
  FOSMVVM/Vapor/Testing surfaces. Explicit instruction: invoke **before writing helper
  code** in any project that imports these libraries.
- **Body:** a **reach-for index** — organized from the client implementor's point of view,
  keyed by the platform type or task they are about to use, *not* by our library layout.
  One line per reach, mapping to the catalog file + section that covers it, e.g.:

  ```markdown
  - Reaching for `JSONEncoder`/`JSONDecoder`, writing Codable glue → FOSFoundation.md § Coding
  - Reaching for `URLSession`/`URLRequest`, fetching or posting data → FOSFoundation.md § Networking
  - Reaching for `URLSessionWebSocketTask` → FOSFoundation.md § Networking
  - Mocking network calls in tests → FOSFoundation.md § Networking, FOSTesting.md
  - Reaching for string casing/hashing/obfuscation → FOSFoundation.md § String
  - Writing a Vapor route/controller that serves ViewModels → FOSMVVMVapor.md
  ```

  Plus the loading rule: read **only** the catalog file(s) the matched lines point to, from
  `shared/api-catalog/`. The skill body itself stays small; the catalog files carry the
  content. If a reach isn't obvious from the index, the implementor's frame wins — add the
  missing index line (via the update skill) rather than expecting readers to learn our
  category layout.

## Component 3 — Wiring and always-on index

- **Existing generator skills:** each `fosmvvm-*` skill gets a one-line pointer to the
  catalog sections it touches (e.g., viewmodel-generator → FOSMVVM ViewModel surface +
  FOSFoundation `Stubbable`; serverrequest-test-generator → FOSTesting.md). One line, not
  duplicated content.
- **This repo's CLAUDE.md:** a ~10-line index in the same reach-for framing — one line per
  common reach (`JSON/Codable`, `URL/URLSession`, `WebSocket`, `String utilities`,
  `Vapor serving`, `test stubbing`, …) pointing at `.claude/skills/shared/api-catalog/`
  and the discovery skill. Always in context; discovery without an invocation decision.
- **Consumer projects:** `fosmvvm-swiftui-app-setup` (the consumer onboarding skill) adds
  a consumer variant of the index block to the consumer's CLAUDE.md as part of setup. The
  consumer variant references the discovery skill **by name** (`fosutilities-api-catalog`)
  — never a repo-relative path, since `shared/api-catalog/` lives inside the installed
  plugin, not the consumer's `.claude/skills/`.

## Component 4 — Audit script (freshness + DocC worklist)

**`Scripts/api-catalog-audit.swift`** — swift-sh script (Swift, per the typed-language
principle; uses the `"\u{23}!"` shebang form per the swift-sh preprocessing gotcha).

Pipeline:

1. Run `swift package dump-symbol-graph` and parse the per-module symbol-graph JSON for the
   five catalogued surfaces.
2. Extract the **audit surface** at this granularity:
   - public top-level types, protocols, and free functions;
   - public members added by extensions to *external* types (`String`, `URL`, `Array`,
     `Encodable`, …) — these are the invisible ones users miss most;
   - members of a catalogued type are **covered by that type's entry** (the catalog is
     entry-level, not per-symbol);
   - compiler- and macro-synthesized symbols are filtered out (exact mechanism is an
     implementation decision; symbol-graph metadata distinguishes synthesized origins).
3. Collect catalog symbol names from backticks in `###` entry-title lines **only** (prose
   and example backticks are ignored — they legitimately name stdlib types). The audit's
   input is **only the files under `shared/api-catalog/`** — never `SKILL.md` bodies or
   CLAUDE.md indexes (whose reach-for lines legitimately backtick platform types).
   Matching is by **base identifier, arity-insensitive** (`fromJSON()` matches any
   `fromJSON` overload in the symbol graph).
4. Report three lists:
   - **Catalog gaps** — audit-surface symbols not mentioned in any catalog file;
   - **Stale entries** — catalog symbols no longer present in the API;
   - **DocC worklist** — audit-surface symbols whose symbol-graph entry has no doc comment.
5. Exit code: non-zero only on stale entries (a catalog that lies is worse than one that's
   incomplete); gaps and DocC worklist are warnings.

An ignore list (file adjacent to the script) handles deliberate exclusions (e.g.,
deprecated API kept for compatibility), so "warn noise" never trains readers to ignore
the report.

## Component 5 — Update skill

**New skill:** `.claude/skills/fosutilities-api-catalog-update/SKILL.md` (plugin-shipped;
primarily used inside this repo).

Workflow it drives:

1. Run `Scripts/api-catalog-audit.swift`.
2. For each **stale entry**: fix or remove it first.
3. For each **catalog gap**: read the source, then write a curated entry following the
   Component 1 rules — customer framing first ("how do they call it, why do they care"),
   same DocC-first discipline as `fosmvvm-planning`. If the new entry serves a reach not
   yet in the discovery skill's reach-for index, add the index line too.
4. Surface the **DocC worklist** count as a report line (no action in this workflow).
5. **Bump the plugin version** in `.claude-plugin/plugin.json` whenever catalog or skill
   files change (established practice — consumers only receive updates on version bump).

The skill also supports a **non-audit path**: adding or adjusting reach-for index lines
(Component 2/3) for already-catalogued capabilities. When renaming a category section or
splitting a catalog file, sweep the reach-for indexes for dangling pointers — index
pointers are not audited.

## Component 6 — CI check

A CI step runs the audit script on every PR (in the existing `macos-latest` job, after the
build — `dump-symbol-graph` reuses that job's build products):

- **Fails** on stale entries (exit code from Component 4).
- **Warns** (annotation/log, not failure) on catalog gaps and DocC-worklist regressions.

This makes drift visible at the moment API changes merge, while the update skill is the
remediation path.

## Component 7 — Initial population

One curated pass over all five surfaces, category by category, using the audit script's
gap report as the checklist. This is the bulk of the effort and is where the "reach for
this when" framing gets written from design intent (the author's), not reverse-engineered
from code. Population order: FOSFoundation first (most-missed), then FOSMVVM, FOSTesting,
FOSMVVMVapor, FOSReporting. Expect this component to dominate the implementation plan;
treat it as its own phase with a checkpoint per catalog file.

## Verification

- **Audit script:** run against the repo; hand-verify a sample of each report list (a known
  uncatalogued symbol appears as a gap; a deliberately planted fake catalog symbol appears
  as stale; a known undocumented symbol appears in the DocC worklist). Script behavior is
  deterministic given a symbol graph, so fixture-based tests are optional; the planted
  round-trip check is required before first CI enablement.
- **Catalog content:** spot-check that every entry's example compiles conceptually against
  current API (the stale check catches renamed symbols; examples are reviewed by hand).
- **Discovery skill:** verify the plugin packages the new skills and `api-catalog/` files
  (plugin.json `skills` path already covers `.claude/skills/`).

## Risks / open items

- **Symbol-graph noise** (macros, conditional platform compilation): granularity rules in
  Component 4 plus the ignore list are the mitigation; expect one tuning iteration during
  initial population.
- **Platform coverage:** `dump-symbol-graph` runs on macOS in CI, which builds all five
  surfaces (Vapor targets are macOS/Linux; Reporting is Apple-only). Linux-only drift is
  not a realistic concern for API *surface*.
- **Catalog size vs. context:** per-library files + load-only-what's-relevant keeps any
  single load bounded; if FOSFoundation.md grows past ~500 lines, split per category. Any
  split is invisible to readers: the reach-for index is the entry point and its pointers
  update with the split — implementors never navigate our file layout directly.
