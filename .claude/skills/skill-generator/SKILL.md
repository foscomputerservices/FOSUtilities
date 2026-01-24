---
name: skill-generator
description: Generate new Claude Code skills following the context-aware pattern. Use when creating skills for code generation, testing, or other development workflows.
---

# Skill Generator

Generate new Claude Code skills following established patterns and best practices.

## Conceptual Foundation

A **skill** is a specialized capability that Claude can invoke to perform specific development tasks. Skills follow the context-aware pattern:

```
User discusses requirements → Skill invoked → References context → Generates code
                    ↑                                    ↓
            (no file paths)                    (no Q&A prompts)
```

**Key principle:** Skills reference conversation context automatically. They don't parse files or ask questions—they infer requirements from what's already been discussed.

---

## The Context-Aware Pattern

Skills shifted from file-parsing/Q&A to context-awareness because:

1. **Claude reads naturally** - Files are read into context like any other information
2. **Conversation is primary** - Requirements are discussed before invocation
3. **No rigid input format** - No need for structured specification files
4. **Specifications are documentation** - Not machine-parsed inputs, but human reference

### Anti-Pattern (Old Approach)

```markdown
## Inputs

**Primary mode:** File path to Markdown specification
/skill-name specs/component-spec.md

**Fallback mode:** Conversational protocol (asks questions if no file provided)
```

### Pattern (Context-Aware Approach)

```markdown
## How to Use This Skill

**Invocation:**
/skill-name

**Prerequisites:**
- Requirements understood from conversation context
- (Specific prerequisites for this skill)

**Workflow integration:**
This skill is typically used after (context). The skill references
conversation context automatically—no file paths or Q&A needed.
```

---

## Required Skill Sections

Every skill must have these sections:

### 1. Front Matter (YAML)

```yaml
---
name: skill-name
description: One-line description. Use when (trigger conditions).
---
```

**Description format:**
- First sentence: What the skill generates
- Second sentence: When to use it (triggers)

### 2. Title and Introduction

```markdown
# Skill Name

Brief description of what this skill generates.

## Conceptual Foundation

> For full architecture context, see [Architecture.md](../../docs/Architecture.md)

Explain the "why" before the "how":
- What problem does this solve?
- Where does this fit in the architecture?
- What are the key concepts?
```

**Use diagrams** for complex relationships:
```
┌─────────────┐      ┌─────────────────┐      ┌─────────────┐
│   Source    │ ───► │    Generator    │ ───► │   Output    │
│   (Input)   │      │  (This Skill)   │      │  (Artifact) │
└─────────────┘      └─────────────────┘      └─────────────┘
```

### 3. When to Use This Skill

```markdown
## When to Use This Skill

- Trigger condition 1
- Trigger condition 2
- Following an implementation plan that requires (x)
```

Be specific about when the skill should be invoked.

### 4. What This Skill Generates

```markdown
## What This Skill Generates

| File | Location | Purpose |
|------|----------|---------|
| `{Name}.swift` | `Sources/{Target}/` | The main artifact |
| `{Name}Tests.swift` | `Tests/{Target}Tests/` | Test coverage |
```

List all files the skill creates, with placeholders explained.

### 5. Project Structure Configuration

```markdown
## Project Structure Configuration

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{Target}` | The target name | `App`, `ViewModels` |
| `{Name}` | The component name | `User`, `Dashboard` |
```

Explain placeholders used throughout the skill.

### 6. How to Use This Skill

```markdown
## How to Use This Skill

**Invocation:**
/skill-name

**Prerequisites:**
- Requirement 1 understood from conversation context
- Requirement 2 discussed or documented
- Requirement 3 identified

**Workflow integration:**
This skill is typically used (when/after what). The skill references
conversation context automatically—no file paths or Q&A needed.
Often follows (related-skill).
```

**Key elements:**
- Simple invocation (no arguments)
- Prerequisites list (what needs to be in context)
- Workflow integration (where this fits)
- Related skills mention

### 7. Pattern Implementation

```markdown
## Pattern Implementation

This skill references conversation context to determine (what it builds):

### (Type) Detection

From conversation context, the skill identifies:
- **Key element 1** (from prior discussion or specifications read by Claude)
- **Key element 2** (from requirements already in context)
- **Key element 3** (from codebase or discussion)

### (Aspect) Analysis

From requirements already in context:
- **Design decision 1** (what guides this choice)
- **Design decision 2** (what guides this choice)

### (Output) Generation

Based on detected patterns:
1. First generated artifact
2. Second generated artifact
3. Third generated artifact

### Context Sources

Skill references information from:
- **Prior conversation**: Requirements discussed with user
- **Specification files**: If Claude has read specs/docs into context
- **Codebase analysis**: From reading existing code patterns
- **Related artifacts**: From other skills or previous generation
```

**Structure:**
- **Detection sections** - What the skill identifies from context
- **Analysis sections** - How the skill interprets requirements
- **Generation section** - What the skill produces
- **Context Sources** - Where information comes from

### 8. Key Patterns

```markdown
## Key Patterns

### Pattern Name 1

Explain the pattern with code examples:

```swift
// Code example showing the pattern
```

### Pattern Name 2

Another important pattern...
```

Show concrete examples of what the skill generates.

### 9. File Templates

```markdown
## File Templates

See [reference.md](reference.md) for complete file templates.
```

Reference a separate file with full templates (don't inline massive templates).

### 10. Naming Conventions

```markdown
## Naming Conventions

| Concept | Convention | Example |
|---------|------------|---------|
| File name | `{Pattern}` | `UserViewModel.swift` |
| Test name | `{Pattern}Tests` | `UserViewModelTests.swift` |
```

Establish consistent naming across generated files.

### 11. See Also

```markdown
## See Also

- [Related Skill 1](../related-skill-1/SKILL.md) - When to use instead
- [Related Skill 2](../related-skill-2/SKILL.md) - Often used before this
- [Architecture Doc](../../docs/Architecture.md) - Full context
- [reference.md](reference.md) - Complete templates
```

Link to related skills and documentation.

### 12. Version History

```markdown
## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | YYYY-MM-DD | Initial skill |
```

Track changes over time.

---

## Sections to NEVER Include

### ❌ Collaboration Protocol

```markdown
## Collaboration Protocol

1. Confirm X with user
2. Ask about Y
3. Generate Z one file at a time with feedback
```

**Why not:** This implies Q&A interaction, which contradicts context-aware pattern.

### ❌ Generation Process with "Ask:"

```markdown
## Generation Process

### Step 1: Understand Requirements

Ask:
1. **What is the name?**
2. **What fields does it have?**
```

**Why not:** Skills infer from context, they don't ask questions.

### ❌ File Input Documentation

```markdown
## Inputs

**Primary mode:** File path to specification
/skill-name specs/spec.md

**Fallback mode:** Q&A if no file provided
```

**Why not:** Claude reads files naturally into context. No special input mode needed.

---

## Language Patterns

### ✅ Use This Language

- "From conversation context, the skill identifies..."
- "Based on requirements already in context..."
- "References information from prior discussion..."
- "The skill detects..."
- "If Claude has read (files) into context..."

### ❌ Avoid This Language

- "Ask the user..."
- "Confirm with the user..."
- "The skill accepts file paths..."
- "Conversational fallback mode..."
- "Parse the specification file..."

---

## Example Skill Structure

Here's a minimal complete skill:

```markdown
---
name: example-generator
description: Generate example components. Use when creating demo code or sample implementations.
---

# Example Generator

Generate example components following established patterns.

## Conceptual Foundation

An example component demonstrates (purpose). It shows how to use (API/pattern).

## When to Use This Skill

- Creating demo code
- Generating sample implementations
- Following tutorials or guides

## What This Skill Generates

| File | Location | Purpose |
|------|----------|---------|
| `Example.swift` | `Sources/Examples/` | The example implementation |

## Project Structure Configuration

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{Name}` | Example name | `HelloWorld` |

## How to Use This Skill

**Invocation:**
/example-generator

**Prerequisites:**
- Example purpose understood from conversation
- Target API discussed

**Workflow integration:**
This skill is used when demonstrating concepts. The skill references
conversation context automatically—no file paths or Q&A needed.

## Pattern Implementation

This skill references conversation context to determine example structure:

### Example Type Detection

From conversation context, the skill identifies:
- **Purpose** (demonstration, tutorial, testing)
- **API target** (what to demonstrate)
- **Complexity level** (simple, intermediate, advanced)

### Code Generation

Generates example with:
1. Clear comments explaining each step
2. Minimal dependencies
3. Runnable implementation

### Context Sources

Skill references information from:
- **Prior conversation**: Example requirements discussed
- **API documentation**: If Claude has read API docs into context

## Key Patterns

### Simple Example Pattern

\`\`\`swift
// Example showing basic usage
func example() {
    // Step 1: Setup
    // Step 2: Execute
    // Step 3: Verify
}
\`\`\`

## File Templates

See [reference.md](reference.md) for complete templates.

## Naming Conventions

| Concept | Convention | Example |
|---------|------------|---------|
| Example file | `{Name}Example.swift` | `HelloWorldExample.swift` |

## See Also

- [Architecture Doc](../../docs/Architecture.md) - Full context
- [reference.md](reference.md) - Complete templates

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-24 | Initial skill |
```

---

## Common Skill Categories

### 1. Code Generation Skills

Generate source files (models, views, controllers, etc.)

**Focus on:**
- Type detection (what kind of component)
- Property/field analysis
- Relationship detection
- Pattern selection

**Example:** fosmvvm-viewmodel-generator

### 2. Test Generation Skills

Generate test files for existing code

**Focus on:**
- Test type detection (unit, integration, UI)
- Scenario identification (success, error, edge cases)
- Infrastructure detection (existing test patterns)
- Coverage planning

**Example:** fosmvvm-serverrequest-test-generator

### 3. Setup/Configuration Skills

Generate infrastructure or configuration

**Focus on:**
- Environment detection
- Configuration requirements
- Integration points
- Deployment targets

**Example:** fosmvvm-swiftui-app-setup

### 4. Specialized Pattern Skills

Generate specific architectural patterns

**Focus on:**
- Pattern applicability
- Variant selection
- Constraint satisfaction
- Integration requirements

**Example:** fosmvvm-fields-generator

---

## Skills Don't Need Q&A Because...

1. **Requirements are discussed first** - Before invoking a skill, the user and Claude discuss what's needed
2. **Claude reads naturally** - Files are just more context, not special input
3. **Context persists** - Information from earlier in conversation is available
4. **Skills can ask IF needed** - If genuinely unclear, the skill can ask—but this should be rare

**The workflow:**
```
User: "I need a ViewModel for the dashboard"
↓
[Discussion of requirements - properties, relationships, etc.]
↓
User: "/fosmvvm-viewmodel-generator"
↓
Skill references prior discussion → Generates ViewModel
```

NOT:
```
User: "/fosmvvm-viewmodel-generator"
↓
Skill: "What properties does the ViewModel have?"
↓
User: "Title, cards, user"
↓
Skill: "What types are those?"
```

---

## Skill Generator Workflow

When creating a new skill:

### 1. Understand the Domain

- What does this skill generate?
- What architecture/framework does it support?
- What are the key concepts?

### 2. Identify Triggers

When should this skill be invoked?
- After what discussion?
- Following which other skills?
- For what user request?

### 3. Map Inputs to Context

What information does the skill need?
- From prior conversation
- From files Claude has read
- From codebase analysis

### 4. Design Detection Logic

How does the skill identify:
- Component type/category
- Properties/fields
- Relationships
- Constraints

### 5. Define Generation Strategy

What files does it create?
- In what order?
- With what dependencies?
- Following what patterns?

### 6. Document Patterns

Show concrete examples:
- Code snippets
- File structures
- Naming conventions

### 7. Link Related Skills

What skills work together?
- Prerequisites (run before)
- Complements (run after)
- Alternatives (run instead)

---

## Testing Your Skill

After creating a skill, verify:

1. **Invocation is simple** - Just `/skill-name`, no arguments
2. **Prerequisites are clear** - What must be in context?
3. **Detection is documented** - How does it identify types/patterns?
4. **Generation is concrete** - Real code examples, not abstract descriptions
5. **Context sources are listed** - Where does information come from?
6. **No Q&A language** - No "Ask:", "Confirm:", "The user provides:"
7. **Version history started** - v1.0 with today's date

---

## Common Pitfalls

### 1. Over-Specifying Input Format

❌ **Bad:**
```markdown
The skill accepts JSON in this format:
{
  "name": "ComponentName",
  "fields": [...]
}
```

✅ **Good:**
```markdown
From conversation context, the skill identifies:
- Component name (from prior discussion)
- Fields (from requirements already in context)
```

### 2. Building File Parsers

❌ **Bad:**
```markdown
The skill parses the specification file to extract field definitions.
```

✅ **Good:**
```markdown
If Claude has read specification files into context, the skill
references that information.
```

### 3. Q&A Protocols

❌ **Bad:**
```markdown
Step 1: Ask what type of component
Step 2: Ask what properties it has
```

✅ **Good:**
```markdown
From conversation context, the skill identifies:
- Component type
- Properties
```

### 4. Assuming Skill Runs Blind

❌ **Bad:**
```markdown
The skill cannot proceed without a specification file.
```

✅ **Good:**
```markdown
Prerequisites:
- Requirements understood from conversation context
```

### 5. Generic "Handle All Cases"

❌ **Bad:**
```markdown
This skill generates any type of component based on user input.
```

✅ **Good:**
```markdown
This skill generates ViewModels for MVVM architecture.
(Specific purpose, specific output)
```

---

## Skill Naming Conventions

| Pattern | Example | When to Use |
|---------|---------|-------------|
| `{domain}-{type}-generator` | `fosmvvm-viewmodel-generator` | Generates a specific type |
| `{domain}-{action}-{type}` | `fosmvvm-serverrequest-test-generator` | Generates tests for a type |
| `{domain}-{component}-setup` | `fosmvvm-swiftui-app-setup` | Sets up infrastructure |
| `{specific-task}` | `skill-generator` | Meta-skills or utilities |

---

## Skill Directory Structure

```
.claude/skills/
├── skill-name/
│   ├── SKILL.md              # Main skill documentation (this file)
│   ├── reference.md          # Complete file templates
│   └── examples/             # Optional: example outputs
│       ├── example1.swift
│       └── example2.swift
```

**SKILL.md** - Main documentation (what you're reading)
**reference.md** - Full templates (too large for SKILL.md)
**examples/** - Optional concrete examples

---

## See Also

- [fosmvvm-viewmodel-generator](../fosmvvm-viewmodel-generator/SKILL.md) - Example of context-aware skill
- [fosmvvm-react-view-generator](../fosmvvm-react-view-generator/SKILL.md) - Another example
- [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md) - Architecture context

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-24 | Initial skill-generator meta-skill |
