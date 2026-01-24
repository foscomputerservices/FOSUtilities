# Skill Generator Reference Templates

Complete templates for generating new skills.

---

## Minimal Skill Template

Use this for simple skills with straightforward generation:

```markdown
---
name: skill-name
description: Brief description. Use when (trigger).
---

# Skill Name

One-line description of what this generates.

## Conceptual Foundation

> For architecture context, see [Architecture.md](../../docs/Architecture.md)

Explain the concept and its role in the architecture.

## When to Use This Skill

- Trigger 1
- Trigger 2
- Trigger 3

## What This Skill Generates

| File | Location | Purpose |
|------|----------|---------|
| `{Name}.ext` | `Path/` | Description |

## Project Structure Configuration

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{Name}` | What this represents | `Example` |

## How to Use This Skill

**Invocation:**
/skill-name

**Prerequisites:**
- Requirement 1 understood from conversation context
- Requirement 2 discussed or documented

**Workflow integration:**
This skill is typically used (when). The skill references conversation
context automatically—no file paths or Q&A needed.

## Pattern Implementation

This skill references conversation context to determine (what):

### Detection

From conversation context, the skill identifies:
- **Element 1** (from discussion or specs read by Claude)
- **Element 2** (from requirements in context)

### Generation

Creates:
1. File 1
2. File 2

### Context Sources

Skill references information from:
- **Prior conversation**: Requirements discussed
- **Files**: If Claude has read specs into context
- **Codebase**: From analysis of existing patterns

## Key Patterns

### Pattern 1

\`\`\`language
// Code example
\`\`\`

## File Templates

See sections below for complete templates.

### Template: Main File

\`\`\`language
// Complete file template here
\`\`\`

## Naming Conventions

| Concept | Convention | Example |
|---------|------------|---------|
| Name | Pattern | Example |

## See Also

- [Related Skill](../related/SKILL.md) - Description
- [Architecture](../../docs/Architecture.md) - Context

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | YYYY-MM-DD | Initial skill |
```

---

## Full Skill Template

Use this for complex skills with multiple generation strategies:

```markdown
---
name: complex-skill-name
description: Detailed description. Use when (specific trigger conditions).
---

# Complex Skill Name

Generate (artifacts) following (architecture) patterns.

## Conceptual Foundation

> For full architecture context, see [Architecture.md](../../docs/Architecture.md)

Detailed explanation of the concept:

\`\`\`
┌─────────────┐      ┌─────────────────┐      ┌─────────────┐
│   Input     │ ───► │   Processing    │ ───► │   Output    │
└─────────────┘      └─────────────────┘      └─────────────┘
\`\`\`

### Key Insight

Explain the architectural decision or pattern this implements.

---

## First Decision: (Choice Point)

Explain major branching decision:

| Option A | Option B | Option C |
|----------|----------|----------|
| When... | When... | When... |

### Option A Details

Explanation...

### Option B Details

Explanation...

---

## When to Use This Skill

- Detailed trigger 1
- Detailed trigger 2
- Following an implementation plan requiring (x)

## What This Skill Generates

### Scenario A (4 files)

| File | Location | Purpose |
|------|----------|---------|
| `{Name}A.ext` | `Path/` | Description |
| `{Name}ATests.ext` | `Tests/` | Test coverage |

### Scenario B (2 files)

| File | Location | Purpose |
|------|----------|---------|
| `{Name}B.ext` | `Path/` | Description |

## Project Structure Configuration

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{Target}` | Target name | `App` |
| `{Name}` | Component name | `User` |

## How to Use This Skill

**Invocation:**
/complex-skill-name

**Prerequisites:**
- Detailed requirement 1 understood from conversation
- Detailed requirement 2 discussed or documented
- Decision made on (choice point)

**Workflow integration:**
This skill is used (when/after). The skill references conversation
context automatically—no file paths or Q&A needed. Often follows
(prerequisite-skill) and precedes (follow-up-skill).

## Pattern Implementation

This skill references conversation context to determine (artifact) structure:

### Major Decision Detection

From conversation context, the skill identifies:
- **Choice point** (which scenario applies)
- **Context A or B** (determining factors)

### Component Analysis

From requirements already in context:
- **Design element 1** (from discussion)
- **Design element 2** (from specs read by Claude)
- **Design element 3** (from codebase analysis)

### Relationship Detection

Identifies connections:
- **Parent relationships** (from model discussion)
- **Child relationships** (from composition patterns)
- **Constraints** (from business rules)

### File Generation

**Scenario A:**
1. Main file with full structure
2. Test file with coverage
3. Configuration file
4. Migration/setup file

**Scenario B:**
1. Simplified main file
2. Configuration reference

### Context Sources

Skill references information from:
- **Prior conversation**: Detailed requirements discussed with user
- **Specification files**: If Claude has read specs/docs into context
- **Existing code**: From codebase analysis of similar components
- **Related artifacts**: From other skills or previous generation

## Key Patterns

### Pattern 1: Core Pattern

Detailed explanation...

\`\`\`language
// Comprehensive code example
\`\`\`

**Key points:**
- Important aspect 1
- Important aspect 2

### Pattern 2: Alternative Pattern

When to use this instead...

\`\`\`language
// Alternative implementation
\`\`\`

### Pattern 3: Advanced Pattern

For complex scenarios...

\`\`\`language
// Advanced example
\`\`\`

## File Templates

See sections below for complete file templates.

### Template: Main File (Scenario A)

\`\`\`language
// Full implementation for Scenario A
// With comments explaining each section
\`\`\`

### Template: Main File (Scenario B)

\`\`\`language
// Simplified implementation for Scenario B
\`\`\`

### Template: Test File

\`\`\`language
// Complete test suite template
\`\`\`

## Naming Conventions

| Concept | Convention | Example |
|---------|------------|---------|
| Main file | `{Pattern}` | `UserViewModel.swift` |
| Test file | `{Pattern}Tests` | `UserViewModelTests.swift` |
| Supporting | `{Pattern}+{Extension}` | `User+Factory.swift` |

## Common Scenarios

### Scenario 1: (Description)

Detailed walkthrough...

### Scenario 2: (Description)

Another common case...

## Troubleshooting

### Issue 1

**Symptom:** What goes wrong

**Cause:** Why it happens

**Fix:** How to resolve

## See Also

- [Related Skill 1](../related-1/SKILL.md) - When to use instead
- [Related Skill 2](../related-2/SKILL.md) - Often used together
- [Architecture Doc](../../docs/Architecture.md) - Full context
- [reference.md](reference.md) - Complete templates

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | YYYY-MM-DD | Initial skill |
```

---

## Front Matter Examples

### Basic Skill

```yaml
---
name: simple-generator
description: Generate simple components. Use when creating basic implementations.
---
```

### Domain-Specific Skill

```yaml
---
name: fosmvvm-component-generator
description: Generate FOSMVVM components following architecture patterns. Use when creating ViewModels, Views, or related artifacts.
---
```

### Test Generator Skill

```yaml
---
name: component-test-generator
description: Generate comprehensive tests for components. Use when adding test coverage or following TDD workflows.
---
```

---

## "How to Use This Skill" Section Variants

### Simple Prerequisites

```markdown
## How to Use This Skill

**Invocation:**
/skill-name

**Prerequisites:**
- Component requirements understood from conversation context

**Workflow integration:**
This skill is used when creating new components. The skill references
conversation context automatically—no file paths or Q&A needed.
```

### Complex Prerequisites

```markdown
## How to Use This Skill

**Invocation:**
/skill-name

**Prerequisites:**
- Architecture understood from conversation context
- Related components identified and discussed
- Fields protocol exists (if form-backed) via prerequisite-skill
- Relationships and constraints clarified

**Workflow integration:**
This skill is used for (specific scenario). For (other scenario), use
(alternative-skill) instead. The skill references conversation context
automatically—no file paths or Q&A needed. Typically follows
(prerequisite-skill) and precedes (follow-up-skill).
```

---

## "Pattern Implementation" Section Structures

### Type Detection Focus

```markdown
## Pattern Implementation

This skill references conversation context to determine component structure:

### Type Detection

From conversation context, the skill identifies:
- **Component category** (A, B, or C)
- **Variant selection** (standard, specialized, or custom)
- **Complexity level** (simple, intermediate, or advanced)

### Property Analysis

From requirements already in context:
- **Required properties** (from discussion)
- **Optional properties** (from specs)
- **Computed properties** (from business logic)

### Generation Strategy

Based on detected type:
1. Select appropriate template
2. Generate main file
3. Generate supporting files
4. Generate tests

### Context Sources

Skill references information from:
- **Prior conversation**: Requirements discussed with user
- **Specification files**: If Claude has read specs into context
- **Codebase patterns**: From analysis of existing components
```

### Relationship Focus

```markdown
## Pattern Implementation

This skill references conversation context to determine entity structure:

### Entity Analysis

From conversation context, the skill identifies:
- **Entity purpose** (domain model, join table, audit record)
- **Data source** (user input, system generated, external)

### Relationship Detection

From requirements already in context:
- **Parent relationships** (one-to-many foreign keys)
- **Child relationships** (reverse of parent)
- **Sibling relationships** (many-to-many through junction)

### Field Classification

Separates fields by source:
- **User-editable** (from Fields protocol)
- **System-assigned** (timestamps, IDs, computed)
- **Relationship fields** (foreign keys, joins)

### File Generation

1. Fields protocol (if user input)
2. Entity model
3. Migration
4. Tests

### Context Sources

Skill references information from:
- **Prior conversation**: Entity requirements, relationships discussed
- **Fields protocol**: If Claude has read Fields code into context
- **Database schema**: From existing models in codebase
```

### Test Focus

```markdown
## Pattern Implementation

This skill references conversation context to determine test structure:

### Component Analysis

From conversation context, the skill identifies:
- **Component type** (from implementation or discussion)
- **Public interface** (methods, properties to test)
- **Dependencies** (what needs mocking)

### Scenario Planning

From requirements already in context:
- **Success paths** (expected behavior)
- **Error paths** (failure handling)
- **Edge cases** (boundary conditions)

### Test Infrastructure

Based on component:
- **Test framework** (XCTest, Swift Testing)
- **Mock strategy** (protocols, test doubles)
- **Fixture needs** (test data)

### Test Generation

Creates:
1. Test class with setup/teardown
2. Success case tests
3. Error case tests
4. Edge case tests

### Context Sources

Skill references information from:
- **Component code**: If Claude has read implementation
- **Prior conversation**: Test scenarios discussed
- **Existing tests**: From codebase patterns
```

---

## Context Sources Variations

### Minimal (Simple Skills)

```markdown
### Context Sources

Skill references information from:
- **Prior conversation**: Requirements discussed with user
- **Codebase**: From existing patterns if available
```

### Standard (Most Skills)

```markdown
### Context Sources

Skill references information from:
- **Prior conversation**: Requirements discussed with user
- **Specification files**: If Claude has read specs/docs into context
- **Existing patterns**: From codebase analysis of similar components
```

### Comprehensive (Complex Skills)

```markdown
### Context Sources

Skill references information from:
- **Prior conversation**: Detailed requirements discussed with user
- **Specification files**: If Claude has read specs/docs into context
- **Existing code**: From codebase analysis of related components
- **Related artifacts**: From other skills or previous generation
- **Architecture docs**: If Claude has read design docs into context
- **Test patterns**: From existing test suites
```

---

## Common Section Combinations

### Code Generator Skill

Required sections:
1. Conceptual Foundation (with architecture diagram)
2. When to Use This Skill
3. What This Skill Generates
4. Project Structure Configuration
5. How to Use This Skill
6. Pattern Implementation (with Type Detection)
7. Key Patterns (2-3 concrete examples)
8. File Templates
9. Naming Conventions
10. See Also
11. Version History

### Test Generator Skill

Required sections:
1. Conceptual Foundation (testing approach)
2. When to Use This Skill
3. What This Skill Generates
4. Project Structure Configuration
5. How to Use This Skill
6. Pattern Implementation (with Scenario Planning)
7. Test Structure (test organization)
8. Common Scenarios (test examples)
9. Troubleshooting
10. Naming Conventions
11. See Also
12. Version History

### Setup/Configuration Skill

Required sections:
1. Conceptual Foundation (what's being configured)
2. When to Use This Skill
3. What This Skill Generates
4. How to Use This Skill
5. Pattern Implementation (with Environment Detection)
6. Configuration Patterns
7. Deployment Scenarios
8. Common Customizations
9. See Also
10. Version History

---

## Anti-Pattern Examples

### ❌ Don't: File Input Documentation

```markdown
## Inputs

The skill accepts Markdown specifications in this format:

\`\`\`markdown
# Component Specification

Name: ComponentName
Type: ComponentType
Properties:
  - name: propertyName
    type: propertyType
\`\`\`

Pass the file path:
/skill-name specs/component.md
```

### ✅ Do: Context Reference

```markdown
## Pattern Implementation

### Component Analysis

From conversation context, the skill identifies:
- **Component name** (from prior discussion)
- **Component type** (from requirements in context)
- **Properties** (from specification or discussion)

If specification files exist and Claude has read them into context,
the skill references that structured information. Otherwise, it infers
from the conversation.
```

### ❌ Don't: Q&A Protocol

```markdown
## Collaboration Protocol

1. Skill asks: "What is the component name?"
2. User provides: "ComponentName"
3. Skill asks: "What properties does it have?"
4. User provides: Property list
5. Skill generates files one at a time
6. User reviews and provides feedback
```

### ✅ Do: Prerequisites

```markdown
## How to Use This Skill

**Prerequisites:**
- Component name understood from conversation context
- Properties discussed or documented
- Type/category identified

The skill is invoked after requirements are clear from discussion.
```

### ❌ Don't: Conditional Input Modes

```markdown
## Input Modes

**Mode 1: File Input**
Provide a specification file path.

**Mode 2: Interactive**
Answer questions when prompted.

**Mode 3: Inline**
Provide all parameters in the invocation.
```

### ✅ Do: Single Mode (Context-Aware)

```markdown
## How to Use This Skill

**Invocation:**
/skill-name

Requirements are understood from conversation context. No parameters needed.
```

---

## Diagram Templates

### Simple Flow

```
┌─────────────┐      ┌─────────────────┐      ┌─────────────┐
│   Input     │ ───► │   Processing    │ ───► │   Output    │
└─────────────┘      └─────────────────┘      └─────────────┘
```

### Architecture Context

```
┌───────────────────────────────────────────────┐
│               Full System                      │
├───────────────────────────────────────────────┤
│  Component A  →  This Skill  →  Component B   │
│                      ↓                         │
│                  Generated                     │
│                  Artifacts                     │
└───────────────────────────────────────────────┘
```

### Process Steps

```
Step 1: Detect     Step 2: Analyze    Step 3: Generate
   ↓                    ↓                   ↓
Context →          Requirements →       Files
```

### Hierarchy

```
Parent Concept
├── Child Concept A
│   ├── Detail 1
│   └── Detail 2
└── Child Concept B
    ├── Detail 3
    └── Detail 4
```

---

## Version History Format

```markdown
## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-24 | Initial skill |
| 1.1 | 2026-01-25 | Added support for X |
| 1.2 | 2026-01-26 | Updated to context-aware approach |
| 2.0 | 2026-02-01 | Major rewrite: generalized from project-specific |
```

**Version numbering:**
- **Major (1.0 → 2.0)**: Complete rewrite, architectural change
- **Minor (1.0 → 1.1)**: New features, significant additions
- **Patch (1.1.0 → 1.1.1)**: Bug fixes, typos (rarely used)

**Date format:** YYYY-MM-DD

**Changes description:** Brief, specific
