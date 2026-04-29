# Check File Authoring Guide

This guide specifies the structure and style for files in `checks/`. Each file documents one FOSMVVM area's review knowledge.

## File Naming

`checks/<area>.md` where `<area>` is one of: `fields`, `serverrequest`, `swiftui-app-setup`, `swiftui-view`, `ui-tests`, `viewmodel`, `viewmodel-test`, `viewmodelrequest`, `cross-cutting`.

## Frontmatter (Required)

```yaml
---
area: <area-identifier>
generator-skill: fosmvvm-<area>-generator
where:
  - "<glob pattern>"
  - "<glob pattern>"
---
```

- `area` — matches filename stem.
- `generator-skill` — the corresponding generator skill that owns the positive pattern. Use `none` for `cross-cutting.md`.
- `where` — globs the triage layer matches against scoped files. Multiple globs allowed.

## Body Sections

### `## Reviewer Guidance` (optional)

Free-form meta-instructions read by the subagent BEFORE running checks. Use for:
- Anti-recommendations: things the reviewer must NOT suggest, even if they look like simplifications.
- Mental-model corrections: architectural framings the reviewer must hold.
- Reviewer-mindset guards: known traps that bias review toward leniency.

### `## Check: <name>` (zero or more)

Each check has four required fields:

- **Severity:** `blocker` | `warning` | `nit`
- **What:** one-sentence description of the rule.
- **Anti-pattern:** what wrong code looks like (concrete shape).
- **Detection:** how the subagent identifies hits — grep targets, semantic checks, conditions for true positive.

## Authoring Style (Model-Agnostic)

Code under review may be authored by any LLM. Check files MUST be model-agnostic:

- Describe **the code pattern and why it's wrong** architecturally — never the author's tendencies.
- Anti-patterns describe **shapes** (read-modify-write on outputs, env mutation in views, silent swallows), never authorship.
- Reviewer Guidance describes **what NOT to recommend** with architectural reasons, never "because LLM X reaches for this."

✅ Good: "Operations methods must not read from the same mutable state they write to."
❌ Bad: "Claude tends to write read-modify-write Operations; flag these."

## Stub Form

A stub file has frontmatter + a one-sentence pointer to the generator skill + zero `## Check:` entries. Triage still routes to it; the subagent reports "no checks defined yet."

```markdown
---
area: fields
generator-skill: fosmvvm-fields-generator
where:
  - "Sources/**/Fields/**/*.swift"
  - "Sources/**/*Fields.swift"
---

# Fields Checks

The positive pattern lives in the `fosmvvm-fields-generator` skill. No review-only checks defined yet.
```

## Example: Full Check

```markdown
## Check: ops-no-output-reads
**Severity:** blocker
**What:** Operations methods must not read from the same mutable state they write to.
**Anti-pattern:** Reading `electrodes[index].polarity` then writing `settings.selectedPolarity = ...` in the same method.
**Detection:** For each type conforming to `*ViewModelOperations`, read each method body. Flag methods that both READ from and WRITE to `settings.*` (or other mutable parameter) within the same call.
```
