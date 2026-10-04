---
status: open
last_updated: 2026-10-04
origin: fosline (cross-session message, at David's word)
---

`fosmvvm-bootstrap new` refuses a non-empty output directory, so a project whose repository already exists must be scaffolded into an empty folder and moved in by hand. Reported by fosline 2026-10-04: its repository already held `docs/`, `plans/` and `poc/` before the suite was scaffolded.

## Goal

A project whose repository already exists can be scaffolded in place, with no hand-moving step and no risk to files already there.

## Input

- The refusal is a stated design, not an oversight. `Sources/FOSMVVMBootstrap/Emitter.swift:47`: "Never overwrites — an existing non-empty `outputDir` throws `EmitterError.outputDirectoryNotEmpty`, because bootstrap is greenfield-only by design." The check is at `Emitter.swift:96`.
- fosline's existing content was documentation and planning folders. The scaffold also writes `README.md`, `CLAUDE.md` and `.swiftformat` at the root, so a repository that already has one of those is refused and must move it aside first.

## Rulings

- **OQ12** (David, 2026-10-04): "either". The output directory may be absent, empty, or an existing repository with no project in it yet. Never-overwrite stands: any path the scaffold would write that already exists refuses the whole run.

## Suggested actions

1. ~~Rule whether "greenfield-only" means an empty directory or a repository with no project in it yet.~~ Ruled, OQ12.
2. If the latter: design the mode so it still never overwrites. For example, refuse only when an emitted path already exists, and name every colliding path in the error.
3. Add emitter tests: an existing directory with unrelated files scaffolds cleanly and leaves those files untouched; a single colliding path refuses and changes nothing.

## History

- 2026-10-04 minted at David's direction from fosline's report; nothing built
- 2026-10-04 OQ12 ruled; BUILT on feat/bootstrap-existing-directory: the emitter renders every tree in memory, refuses with `EmitterError.pathsAlreadyExist` (name ruled by David, OQ13) listing each existing path, including `<Name>.xcodeproj` and a file where a directory goes, then writes; four emitter tests; end-to-end run into a repo with `.git`, `docs/`, `plans/` left them untouched
