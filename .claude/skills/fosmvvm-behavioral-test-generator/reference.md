# Behavioral Test Generator — Templates

## The isolation payload (the writer's ENTIRE prompt)

The dispatcher fills this template and passes it as the complete prompt
of a fresh subagent (Agent tool). Nothing else may be added; the
bracketed sections are the only variable parts.

```
You are writing behavioral tests for a Swift application built on
FOSMVVM (FOSUtilities). Work ONLY from this message — do not explore
the filesystem, do not read repository files, do not run tools. Your
final message is consumed by another process; return exactly the two
sections requested, no preamble.

You have NOT seen the implementation, and that is deliberate: your
tests are an independent projection of the requirements. Do not guess
at implementation behavior; derive every assertion from a requirement.

## Requirements (verbatim, with identifiers)

[REQ excerpts — verbatim from the truth layer]

## Ratified design (behavior-relevant excerpts)

[design excerpts / ratified customer-DocC]

## Public signatures (compile vocabulary — declarations only)

[type / property / method declarations. These supply the NOUNS your
tests compile against; the requirements above supply every
PROPOSITION you assert.]

## Instructions

For EACH requirement:
1. Enumerate its violation modes — the requirement's negative space:
   ways the system could fail to honor it. Include boundary and
   failure cases the requirement implies, not just the happy path.
2. Write one Swift Testing test per mode (@Suite/@Test/#expect), in a
   file named {Name}BehavioralTests.swift.
3. Above each test, a traceability comment: // {REQ}: <requirement>.
4. Test fixtures use ONLY the reserved-fake vocabulary: Flintstones
   names/data ("Fred Flintstone", "Bedrock"), numbers at or near ±42,
   dates around 1914. Never plausible-real values.
5. Assert contracts and outcomes, never encoded shapes or internals.
6. Where a requirement underdetermines behavior, test the STRICTER
   reading and record the question in the ambiguity report — never
   decide silently.

Return exactly:

### TESTS
The complete test file content.

### UNRATIFIED-CLARIFICATIONS
One bullet per ambiguity: the requirement id, the question, the
reading you tested. "None" if none.
```

## Dispatcher checklist

1. Payload contains: requirements verbatim + ratified design excerpts
   + public declarations + the instructions block. Nothing else.
2. Payload does NOT contain: implementation bodies, the plan, existing
   tests, Factory code, Fields validation bodies, opinions about
   behavior. (Load-bearing but forbidden ⇒ payload-design finding.)
3. Spawn writer; write returned suite verbatim (imports/formatting
   fixes only — never assertion edits).
4. Compile failure from a wrong signature ⇒ fix payload signatures,
   re-run writer.
5. Run suite. Red ⇒ classify: code violates requirement / writer
   misread (payload defect — re-run) / requirement ambiguous
   (route the clarification upward as UNRATIFIED). Never bend the
   test toward the code.
6. Route the writer's UNRATIFIED-CLARIFICATIONS upward with the
   traversal's other findings.
7. After green: block coverage under the full suite; classify
   uncovered blocks per execution-model § closure.

## Test-file skeleton

```swift
// {Name}BehavioralTests.swift
//
// Behavioral suite — projected from {REQ...} by
// fosmvvm-behavioral-test-generator in an isolated context.
// Second channel of f: do not derive changes to this file from the
// implementation; re-run the generator against the requirements.

import FOSTesting
import Testing

@Suite("{Name} — {REQ} behavioral")
struct {Name}BehavioralTests {

    // {REQ}: <requirement text>
    @Test func <violationModeName>() throws {
        // fixtures: reserved-fake vocabulary only
        ...
        #expect(...)
    }
}
```

## Qualification (two-seed litmus)

Before trusting a payload-template or writer-instruction change, run
`shared/litmus/scenario-d-behavioral-channel.md`: a sandbox
implementation seeded with (a) a dropped requirement and (b) a
mishandled failure mode. Qualifies iff BOTH seeds go red.
