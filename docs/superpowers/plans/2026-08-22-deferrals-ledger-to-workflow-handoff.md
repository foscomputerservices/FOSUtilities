# Handoff: deferrals-ledger incorporation — for the fos-development-workflow session

**Thread position:** answers the ledger-location question (§10.2) of `2026-08-22-fosmvvm-bootstrap-migration-design.md`. Written by the bootstrap-migration session; to be picked up by the session working in `/Users/david/Repository/FOS/FOSUtilities-workflow` (`feature/fos-development-workflow`) **when it merges its process out**.

**Status:** WAITING — no action needed until the workflow process merges to main.

## What you are picking up

David ruled (2026-08-22) that the planning process you are building is what FOSUtilities will support, and that the bootstrap deferrals ledger should be incorporated into *your* process rather than parked in an interim location. Until you merge, the ledger stays at its current home: `/Users/david/Repository/FOS/fosmvvm-bootstrap/docs/deferrals.md` (repo may be archived by then — the file travels with wherever the migration design's §9 put it; check that design's execution state first).

## What needs to happen when you merge

1. Absorb the ledger's open items into your process's equivalent structure. As of this writing the open items are: multi-platform app emission (partially superseded — the migration design's §4 now owns the immediate Apple-five scope; reconcile rather than duplicate), the Plan 5 roadmap items (`doctor` implementation, plugin-skill wrapper, example publishing — release CI is absorbed by the migration design's §7), credential-middleware auth group, serverrequest-generator skill update, key-echo generator doors, iCloud-output-path check for `doctor`, and the Deferred/future section (display technologies, FOS release automation).
2. Preserve the ledger's maintenance rule in whatever form your process uses: deferrals are recorded in the same pass that defers them, cross-referenced to the originating doc, and reviewed before the next plan is written.
3. The migration design itself (§10.2) records that ledger-location was deferred to you — close that loop by noting where the items landed.

## Findings that may matter to your process design

- The ledger's two-tier split (Tracked = real pending work with a home; Deferred = future/unproven) has worked well across five plans — worth keeping as a distinction.
- Items age poorly when their origin docs move repos; your process may want origin references that survive migration (the bootstrap → FOSUtilities move is the live example).

No confidentiality wall applies — both sides of this handoff are FOS-internal.
