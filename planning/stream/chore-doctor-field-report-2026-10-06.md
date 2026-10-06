---
status: open
last_updated: 2026-10-06
origin: a consumer's fosmvvm-doctor audit on 0.20.0 (field report, relayed 2026-10-06)
---

`fosmvvm-doctor` reports a SwiftPM package's test plan as dangling references, reads the generated `.swiftpm/` folder, and gives three remedies whose wording is wrong or incomplete for shapes it meets in the field.

A consumer audited a hand-maintained Xcode project with a root `Package.swift` and reported six suspected false positives. Reviewed against the doctor design doc, the architecture doc, and the scaffolder's templates (2026-10-06): one is a doctor bug, three are the consumer departing from doctrine, one is a remedy whose stated reason is wrong though the rule stands, and one is a documentation gap (`docs-fosforms-stock-titles.md`).

## Goal

The doctor never reports a package-scheme test plan or a generated `.swiftpm/` file, and every remedy states a true reason and a fix that works for the shape it fires on.

Done means: the R9 fix with tests that fail before it; the three remedy texts below rewritten; doctor tests updated.

## Input

**R9, test-plan references — a bug.** `belongsHere` (`Sources/FOSMVVMBootstrap/Doctor/ProjectRule+TestTargets.swift:103-107`) treats any non-`.xcodeproj` container as this project's, so a package plan's `container:` references are judged against pbxproj identifiers they can never match. `files(under:)` (`AuditedProject.swift:464`) skips `.build`, `.git`, `DerivedData`, and `build`, but not `.swiftpm`, so the generated `.swiftpm/**/*.xctestplan` is read. No test covers either (`DoctorTests.swift:301-360` uses only `.xcodeproj` containers).

**R5, single-embed — the rule stands, the reason is wrong for UI-test bundles.** David, 2026-10-06 (OQ41): link-only for UI-test bundles is doctrine ("with trial and error we finally settled this in FOSUtilities"). The remedy and DocC (`ProjectRule+Linkage.swift:104-106`, `:125`; `.claude/docs/FOSMVVMArchitecture.md:1689`) give the reason "the test host already carries the embedded copy", which is false for a UI-test bundle: it has no host and runs in a separate runner process (`Templates/client-server/project.yml.tmpl:194-196`).

**R4b, testing products — the rule stands, the remedy is incomplete.** For a non-test framework whose own sources import FOSTesting, "link it on each test target instead" cannot compile. The doctrine's answer (`FOSMVVMArchitecture.md:1688`; the templates' per-test-target helpers) is to move those sources into the test targets that use them.

**R13, shared module — the rule stands, the remedy overstates.** "Have every other target import it" (`ProjectRule+SharedModule.swift:46`) reads as forcing a harness-only ViewModel into a shipping library; a framework only the using app embeds satisfies the rule.

**R3, hosted unit-test bundles — no change.** The consumer proposed inferring hosting from `TEST_HOST`; that would make R3 unable to catch a missing `TEST_HOST`. The crash it reported came from FOSTesting inside a framework the host app embeds (the R4b shape).

## Suggested actions

- R9: in `belongsHere`, return true only for a nil container or this project's `.xcodeproj`; add `.swiftpm` to the skipped directories. Tests for a `container:` reference and a `.swiftpm` plan, each failing first.
- R5: rewrite the reason for UI-test bundles to the true one (the scaffolder's settled shape links without embedding), in the remedy, the rule's DocC, and the architecture doc line.
- R4b: add "or move this target's sources into the test targets that use it" to the remedy.
- R13: "the targets that use it" in place of "every other target".
- Whether the doctor should honour `.gitignore` in general is a smaller question for David, not part of this item.

## History

- 2026-10-06 — minted from the field report and the doctrine review; OQ41 ruled by David.
