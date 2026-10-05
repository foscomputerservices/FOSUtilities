---
status: open
last_updated: 2026-10-05
origin: the 0.20.0 stub-identity build (OQ19, deferred to this work item at David's word)
---

A Leaf page has no way to identify an entity in its HTML once a ViewModel carries an opaque `ModelIdentity`: `fosmvvm-leaf-view-generator` teaches templates that render a raw id for JavaScript (`data-card-id="#(card.id)"`), with ViewModel rows carrying `id: ModelIdType`, but a `ModelIdentity` has no public raw id.

Found while building `feat-stub-model-identity.md` (0.20.0). The Leaf skill was left unchanged rather than half-converted; every other generator skill now teaches the opaque identity.

## Goal

A Leaf template can put an entity's identity into the page and read it back when the page acts on that entity, without exposing a raw id and without a stringly-typed door.

Done means: one ruled way to carry an identity through HTML, implemented if it needs library support, and the Leaf skill teaching it in place of `#(card.id)`.

## Input

**The question, OQ19** — `planning/notes/fosline-request-rulings-2026-10-05.md`: how a Leaf web page identifies an entity.

**Where the Leaf skill renders a raw id** — `.claude/skills/fosmvvm-leaf-view-generator/SKILL.md` around lines 143, 203, 425, 608; `reference.md` around 118, 162, 347, 414.

**The rules it must meet:** David's transport rule (a ViewModel carries the identity opaquely, passes it to its Operations, and roots `vmId` in it); the repo's encapsulation rule (no raw getters, no stringly-typed identities, no published representation).

**Also waiting on this:** `fosmvvm-serverrequest-generator/reference.md` (around line 276) bridges a browser's raw `dataset.entityId` string into a request; it changes with the Leaf answer.

**Options named so far:** render the row's `vmId`; or an official, opaque way to put an identity into HTML and read it back.

## Suggested actions

- Design first, through the planning gate: what the page's JavaScript needs the value for (a request back to the server, element lookup, or both), and whether `vmId` serves each.
- If library support is needed, its names go to David's naming table (OQ8).
- Then convert the Leaf skill's examples and templates, with a SOLID line, matching the other generator skills.

## History

- 2026-10-05 — OQ19 raised during the 0.20.0 stub-identity build; the Leaf skill left unchanged.
- 2026-10-05 — deferred to this work item at David's word ("can we leave this as a work item for later?").
