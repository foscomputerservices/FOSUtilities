---
status: open
last_updated: 2026-10-06
origin: the 0.20.1 review (PR #165)
---

The doctor's test-plan check decides whether a reference belongs to the audited project by a file-name suffix, so a reference to a different project that happens to share the audited project's file name is judged as this project's.

Found in the review of the 0.20.1 doctor fixes. The looseness predates 0.20.1, and no one has reported it.

## Goal

A test-plan reference is judged against the audited project only when its container resolves to that exact `.xcodeproj`.

Done means: the match compares the resolved container path, not the file name; fixtures built from test plans Xcode itself wrote; tests for a nested project, a sibling project with the same file name, and a package reference.

## Input

**The match** — `Sources/FOSMVVMBootstrap/Doctor/ProjectRule+TestTargets.swift`, `belongsHere` (around lines 103-109): `container.hasSuffix("/\(name)")` accepts `container:Sub/App.xcodeproj` and `absolute:/elsewhere/App.xcodeproj` as this project's whenever the file name matches.

**David, 2026-10-06:** "You can use xcode's mcp to deal with manipulating these projects."

## Suggested actions

- Use Xcode's MCP to create real test plans that reference a nested project, a sibling project with the same file name, and a package, and record the `containerPath` values Xcode writes (`container:`, `group:`, `absolute:` forms). The doctor itself keeps reading the files; it cannot depend on Xcode.
- Resolve each container path relative to the test plan's location and compare it with the audited `.xcodeproj` path.
- Tests from those real plans, each failing first against the suffix match.

## History

- 2026-10-06 — minted from the 0.20.1 review; deferred to its own work item at David's word.
