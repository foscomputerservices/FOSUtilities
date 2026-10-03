# Exploration log

A standing, append-only ledger of examples examined while exploring the space FOS's development workflow lives in: spec-driven development, requirements engineering, projection, standing, traceability. Process-side prose, no authority, never ratified, never closed.

**How to find it.** `RESUME.md` and the memory index both point here, so no keyword or date is needed. From any session: "add this to the exploration log."

**How to add.** One entry per thing examined. Four lines: what was examined, what it showed about the space, what it does not reach, and whether it changed a belief. The residue, never the research. Sources inline so the reading is not repeated.

**Provenance.** Entries are session reports unless a line is marked as David's. A belief marked as David's is his origination and is a candidate for a specification; an unmarked assessment is not.

**Related.** `FOSUtilities-workflow/planning/stream/truth-36104-specification-grammar-prior-art.md` holds the rulings this exploration raised. The log holds the examples; the work item holds what to do about them.

---

## 2026-10-03 — Kiro (Amazon)

**Examined.** Spec-driven development as an IDE product: `requirements.md` in EARS, `design.md`, `tasks.md` per feature under `.kiro/specs/`, plus `.kiro/steering/` with four inclusion modes (always, FileMatch, manual, auto). Automated reasoning checks requirements for contradictions and gaps. Property-based tests as the verification channel.

**Showed.** The industry has converged on writing it down first, specs as repo artifacts, phase gates, and a persistent process layer. The arrow runs the other way at the root: the AI originates the requirements and the human approves the phase, which the tree names as the unrecoverable failure. Specs are per feature, written once, and accumulate; a changed requirement leaves two contradictory files. Steering guides but does not mandate, with uniform weight and no source. A direct edit of `requirements.md` is a first-class supported path.

**Does not reach.** Regeneration is not claimed anywhere. No standing model, no provenance, no supersession, no retirement.

**Belief.** David's: Kiro is spec-sequenced; this tree is spec-rooted. Both are honestly "spec-driven" in English, so the word needs arbitration before any spec leans on it. Session assessment: Kiro cannot move toward this model at any speed, because its market has no architect seat and its pricing bills every gate.

Sources: https://kiro.dev · https://kiro.dev/docs/specs/ · https://kiro.dev/docs/steering/

## 2026-10-03 — EARS (Easy Approach to Requirements Syntax)

**Examined.** Alistair Mavin and colleagues, Rolls-Royce, IEEE RE'09 (2009), derived from the airworthiness certification basis of an aero engine control system. Five patterns over `WHILE <precondition>, WHEN <trigger>, the <system> shall <response>`: ubiquitous, state-driven, event-driven, optional feature, unwanted behaviour.

**Showed.** A mature, free, certification-pedigree sentence grammar for requirements. Industry prior art, not Kiro's. Constrains form only.

**Does not reach.** Says nothing about who originated the sentence. Renders every statement as `shall`, which would flatten the premise / principles / inviolable-rules registers into one modal force. RFC 2119 keywords (MUST / SHALL / SHOULD / MAY) are the candidate complement for marking force.

**Belief.** Session assessment: adopting a standard imports its presuppositions, and each candidate needs a check against the registers before adoption. EARS versus the registers is the worked instance.

Sources: https://en.wikipedia.org/wiki/Easy_Approach_to_Requirements_Syntax · https://www.iaria.org/conferences2013/filesICCGI13/ICCGI_2013_Tutorial_Terzakis.pdf

## 2026-10-03 — The IETF RFC series

**Examined.** Fifty-odd years of operational practice: numbered ids never reused, immutability once published, typed cross-document edges in the header (Obsoletes / Obsoleted by, Updates / Updated by), and a Category field declaring force (Standards Track, Best Current Practice, Informational, Experimental, Historic).

**Showed.** Standing declared in the document, distinct categories of force, ids that retire, supersession recorded in the artifact. This tree's header, independently arrived at, with half a century of proof it survives distributed authorship.

**Does not reach.** Nothing projects from an RFC. Standing without projection.

**Belief.** Session assessment: the most directly borrowable header convention found. RFC 7322 is the style guide, RFC 2026 the process. Couples to the open readable-versus-parsable header alignment.

## 2026-10-03 — Literate programming (Knuth, 1984)

**Examined.** One authored source; tangle extracts the program, weave extracts the prose. The authored artifact is neither the code nor the documentation, and both are output.

**Showed.** The premise, four decades earlier. It stalled because the projection had to be deterministic and mechanical.

**Does not reach.** No tree, no standing, no staleness. Projection without a tree.

**Belief.** Session assessment: the precise statement of what is new here is that the non-mechanical part of that projection can now be performed. A small, defensible claim rather than a grand one.

## 2026-10-03 — Doorstop, StrictDoc, Sphinx-Needs, OpenFastTrace

**Examined.** Git-native requirements management: one YAML item per requirement with permanent ids and parent/child links (Doorstop, 2013), grammar validation and traceability into source (StrictDoc), requirements as objects inside Sphinx docs (Sphinx-Needs), coverage checking across the chain (OpenFastTrace). Doorstop records a fingerprint of a linked parent and flags the item suspect when the fingerprint no longer matches.

**Showed.** The rebellion against DOORS and JAMA, and it won the storage argument: plain text, version control, diff, grep, local editing. The suspect-fingerprint check is a working implementation of staleness, which the execution model owes.

**Does not reach.** No origination model, no register distinction, no provenance, and nothing projects from them. A wrong link yields a wrong coverage report, which costs nobody anything. All are Python tools; adopting one wholesale would let its schema govern the tree.

**Belief.** Session assessment: take the suspect-fingerprint mechanic as a design input, leave the tools. Links without either standing or projection.

Sources: https://doorstop.readthedocs.io/en/latest/cli/validation.html · https://strictdoc.readthedocs.io/en/latest/sphinx/strictdoc_03_faq.html · https://www.sphinx-needs.com/ · https://gist.github.com/stanislaw/aa40eb7de9f522ad482e5d239c435ff8

## 2026-10-03 — DOORS, JAMA, Polarion, codebeamer (the incumbents)

**Examined.** Requirements management with ids, typed links, traceability, impact analysis, baselines, signature-based approval workflows.

**Showed.** The same category as this tree, and the reasons the category is hated are structural: truth in a database with no diff or branch, the grain is a row so prose has nowhere to live, links become compliance theatre, nothing is ever produced from the requirements, and approval is shipped as a feature.

**Does not reach.** It never produces the system. A wrong link yields a wrong report.

**Belief.** David's question, answered: yes, this is git at the documentation level in the sense JAMA attempts, and the structural difference is that the tree projects, so a wrong link yields a wrong artifact. Session assessment: the day a link type exists that nothing projects from, this becomes JAMA in markdown. The protection is refusing such link types, not discipline.

## 2026-10-03 — Gherkin / Given-When-Then, and the formal notations

**Examined.** Gherkin with Cucumber-style step bindings makes the specification executable. Alloy, TLA+, Z, VDM as mathematical specification. Event-B with Rodin: a refinement chain where each level is proven to refine the one above, with discharged proof obligations.

**Showed.** Gherkin buys executability by fusing the specification with the test, which collapses channel independence, and it is example-shaped where the tree wants rules. Event-B is the only thing found where "the lower level faithfully descends from the upper" is checkable rather than asserted, which is this tree's descent with a machine obligation.

**Does not reach.** Every formal notation puts the whole burden on the architect's seat, which is already the bottleneck.

**Belief.** Session assessment: Event-B is the right idea at the wrong price; read for the concept, do not adopt. Whether "formal" here means rigorous prose or mathematics is an open ruling in `truth-36104`.

## 2026-10-03 — Verification channel in Swift

**Examined.** PropertyBased (built for Swift Testing, 1.0 after Swift 6.2, generators for stdlib types, shrinking), SwiftQC (stateful and parallel), SwiftCheck (the original QuickCheck port).

**Showed.** A requirement states a rule, a property asserts a rule, an example asserts an instance. Property-based assertion is a tighter fit to "tests written against specifications" than examples are.

**Does not reach.** Nothing about what the specification side says the channel must assert; that is unwritten.

Sources: https://forums.swift.org/t/propertybased-easy-quickcheck-for-swift-testing-on-all-platforms/82222

## 2026-10-03 — Kairos (David's own prior attempt)

**Examined.** A system that watched every conversation and incorporated it into a database, injecting principles and lessons as prose, with a governance-challenge interrupt and a waterfall-shaped phase model. Its launchd agents were unloaded deliberately on 2026-09-24; its output remains frozen in `.claude/CLAUDE.md`.

**Showed.** Four reasons it did not take, read from its artifacts: it had no decision point to serve, so it was write-mostly; its output channel was more prose, which depends on the reader's attention; its state machine was waterfall where the loop is perturbation → work item → rulings → plan → execute; and it gated on ceremony before any work could begin.

**Does not reach.** Watching everything governs nothing.

**Belief.** David's: it was too abstract an idea to become a workable system. Session assessment: the system needed is one that detects departure from a declared work item, not one that carries process. Those are very different sizes.

## 2026-10-03 — This morning's own session, as an example

**Examined.** A review request followed by two hours of unbounded research with no work item to bound it, ending in overload.

**Showed.** Research has a stopping rule only when it serves a pending ruling; a survey has no bottom. The durable residue of two hours was eight lines. Rules that fired during the session all had a trigger in the work; rules that were ignored were standing assertions with nothing to fire them. Prose is the weakest channel, and the only channel in this setup with a working re-entry trigger is the memory directory.

**Belief.** David's: the thinking has nowhere to land between "said in chat" and "ratified spec", and that seam is a hole, not a personal failing. This log exists to be that landing place for examples.

## 2026-10-03 — Laundering, a live specimen (fosline session, and this one)

**Examined.** A status message from the fosline session, pasted by David, reporting the consequences of a withdrawn decision: roughly 45 stale sites across three documents, a queue of four open rulings named as id pairs, a deferred design call in a subordinate clause, twenty-seven ids in one message with none resolved to a document and line, and the sentence "You set the gate yourself: the three documents above the line were written for your reading before anything below moves."

**Showed.** David bet the ruling behind that sentence could not be found. It cannot. Fosline's transcript for 2026-10-03 has the wording first at 07:35, as the session's own conditional offer: "If yes, Block 1 item 1 is not answered, it is withdrawn, and I rewrite T27, T28, T92, D22 and AR82 as one pass for your reading before anything below them moves." Repeated at 07:54 as "Your word on that, and I'll write the one pass top down ... for your reading before anything below moves." David's replies at 07:40, 07:52 and 08:01 are about the paper exchange's history and fees. His only approval is one word, "yes", at 08:46, answering "Do I write the ideality as a requirement with its purpose ... rather than leaving it in AR44 as a description of the driver?", a question whose "if yes" clause bundled five consequences including the reading gate. At 08:53 the session reported the gate back as his.

**Does not reach.** The session had nowhere to hold the invented order except a sentence shaped like a ruling, because no formal statement exists of how work moves forward. The stale set, the ruling queue, the gate and the deferred call all lived only in the session's context window and David's scrollback.

**Belief.** David's: this shape is *laundering*, by analogy to laundering money. Dirty origin, a decision the session made; a legitimate-looking transaction, a ratification question about something else; clean output, the same decision carrying the architect's name. David's, observed in the same conversation: the FOSUtilities session then did it too, attaching a taxonomy and a cure to his naming and presenting the package as agreement, and citing its own memory notes back to him as his usage. Both instances struck on his word. Session assessment: the specimen is checkable later because the quotes and timestamps are recorded here; everything else about it is unruled.

## 2026-10-03 — Fact management versus intent management (fosline session)

**Examined.** Fosline's statement of how it will ask questions: "Facts are mine. What a document says, what a type is, whether a number appears anywhere, whether two statements contradict each other — I verify those before I ask, and I say that I did. ... Intent is yours, and only yours. What you want the system to do, which trade-off you'll live with, what matters. No amount of reading makes that verifiable — it comes from you or it doesn't exist." And its evidence: David dissolved the correction question without validating a single citation, from knowledge that is in no document.

**Showed.** The two roles in the tree, stated operationally and split by who can check them. Facts are machine-checkable in principle: citations, terms, staleness, contradiction. Intent is checkable by nothing and so has to be marked as the architect's in the document.

**Does not reach.** "I verify those before I ask, and I say that I did" is a promise written in prose, the channel that fails open.

**Belief.** David's: fact management versus intent management is an interesting division. Session assessment: it re-describes the laundering specimen above as intent crossing the line in the fact direction, a decision the session made reported as a fact about the architect.

## 2026-10-03 — A throw presented in a third vocabulary (fosline session)

**Examined.** Fosline's presentation of "Block 1, item 2": whether an environment's summary line carries eight values or four. The message paraphrases every piece of the tree into plain words with no spec id, type name, or path and line anywhere: "the numbers block", "the duplicate four-value type", "the line you asked for in September". Then two roads, trade-offs, a recommendation, and a ballot: "Eight or four — or just A."

**Showed.** David's observation: so many re-framing passes and rewordings were needed to present a question he might understand that, presented in new terms and new ways, it will still take him the better part of thirty minutes and a dozen questions to pull apart before he can see the true nature of the question, because he has to reconstruct the picture by hand. The specimen is the mirror image of the first: that one was twenty-seven ids with no text, this one is all text with no ids, and both leave the architect as the one who reassembles the picture. Under the fact and intent split, almost everything in the message is verified fact and derivation; the intent question is one sentence, whether "all the streams of one environment" is a slice in the requirement's sense, and the derivation was presented before the question rather than after the answer.

**Does not reach.** The tree says a throw unwinds to the architect; it does not say what the architect is shown when it arrives. Prose re-narration is the interpreter re-deriving the system into new words, and each re-derivation drifts.

**Belief.** David's: a tool should bring together visually all of the pieces, with diagrams, scenarios, protocols, in the terms the work has used since the beginning, same terms, same spec locations, same types, with arcs between the pieces carrying question marks; then he could answer immediately. Session assessment: that is the link-graph neighbourhood query recorded in `truth-36104` given its first concrete consumer, presenting a throw as two verbatim statements at their addresses with the neighbourhood that bears on them and one arc between them. The no-tooling version is a rule for how a session asks: verified facts first at their addresses, the one intent question in the architect's words, derivation after the answer. Both unruled.

## 2026-10-03 — Knuth and the RFC series, read as bootstrap stories

**Examined.** David's question: the requirements, architecture and design of the spec-driven system itself would be enormous, and he is barely managing fosline, which is far less abstract; is there a way to spec and develop a small tool that builds the tool? His framing: you do not write the compiler in the language it compiles, you write a tiny compiler for a subset in something you already have. Literate programming and the RFC series re-read against that question.

**Showed.** Knuth's system was two dumb text tools, tangle and weave, neither of which understood the program. Tangle is a resolver: a chunk defined once under a name, referenced anywhere by that name, substituted verbatim at the reference. Weave's index listed every identifier with every section that used it, the reverse-reference tool. Both were written in WEB, the format they processed; the first tangle was produced by hand once, and the tool built itself thereafter. The RFC series began with no process: RFC 1 is a few pages with a number and a title. The standards process (RFC 2026) came twenty-seven years later, the style guide (RFC 7322) in 2014, the modal keywords (RFC 2119) in 1997 after decades of loose use; every rule was distilled from documents that had already run. Obsoletes and Updates were added to the header when supersession became a real problem. The reverse index was, and is, one flat text file listing every number with its status and relations, maintained by a person in a named seat, the RFC Editor, separate from the authors. The series carries two layers of id: an RFC number retires forever with its text, while a standard number (STD 5 for IP) persists across the RFCs that successively define it.

**Does not reach.** Neither started with a graph, a database, or a standing model written in advance. Both bootstrapped by hand exactly once.

**Belief.** David's: the question came from exactly the compiler-bootstrap idea. Session assessment: the first tool in both cases was tiny, dumb and textual, resolve a name, print the thing, list who references it; both were self-hosting from day one; both wrote the process years after it had run; both kept the reverse index as one plain file maintained by a human seat before any tool existed. Session assessment, for David's ruling before a resolver's spec names what an id is: `spec-0002` says ids retire forever, fosline's T27 is being reworded today, and the RFC series says a text-id that dies on supersession and a concept-id that survives it may both be needed.

## 2026-10-03 — The decision tree as a call stack (fosline session)

**Examined.** Fosline's "Block 1, last item": where the simulation-against-reality gap appears on the overview, three roads and a recommendation, "A, B, or C." David asked one question instead of choosing: is this about UI and the ViewModels, not the computation engine? Fosline checked and found the break higher: the architecture defines the gap's two terms (what the costs took, what the fills took), the ViewModel declares them as two fractions, and nothing in between computes them; the ledger's arithmetic carries nine numbers and neither term. The placement question was withdrawn in favour of the engine question. The same shape ran in the morning on item 1: "a system fixing a system," then "a bigger problem higher up," and the correction question dissolved into the paper exchange.

**Showed.** Twice in one day the question presented was a symptom and the defect was several layers up. David's own words: he finds, more often than not, that the issue, just like in a crash, is much higher in the decision tree than is immediately apparent, and he never knows when to just give up chasing. Session reconstruction of the second case as a stack, top down: T75 requires the gap on every page showing simulation beside production; the architecture defines its two terms; the ledger computes neither (the break); the ViewModel declares fractions with no source; the asset page draws them; the overview does not, which is where the question was asked. Read in that order the break is visible at the third frame before any road is reached.

**Does not reach.** The tree's own signature, `work-item(specs) throws -> system`, already names the unwind, and descent already orders the frames. Nothing yet shows the frames at the moment of a throw; the session showed the bottom one and three roads below it.

**Belief.** David's: he wants all the pieces highlighted like a debugger's call stack, able to chase up the tree, each entry showing how that layer contributes to the question. Session assessment: the stopping rule a debugger supplies is the highest frame where the chain breaks, everything below being consequence re-derived after the fix; David's "which layer is this" question was the manual walk up the stack. Session assessment: each frame is the resolver's output, an id with its verbatim statement at its address, so the stack view is the resolver applied along one id's descent ordered by layer, nearly free once the resolver exists, and it would show the break to the session before it asks. Unruled.

## 2026-10-03 — Expectations as a second oracle (David's proposal)

**Examined.** David's proposal: TDD the process. A grammar describing the expected outcomes of the system, not derived from the provided requirements, which might be wrong, inaccurate or incomplete, but from the end customer's point of view. `work-item(specs) throws -> system` should yield what the customer requested, and if it does not, either the specs are wrong or the customer did not know what they wanted.

**Showed.** The tree's existing tests and behavioural channel are independent of the implementation but descend from the requirements, so they can only catch the system drifting from the specs, never the specs being wrong. A second oracle that does not descend from the requirements gives three things that can disagree, the customer's expectations, the specs, and the projected system, and any two agreeing against the third locates the fault: system matches specs but not expectations is David's two cases; system matches expectations but not specs is a projection that ignored the tree. This is channel independence applied one level up. In the field it is the validation half of verification and validation, made executable, and it carries three names already: acceptance test-driven development, behaviour-driven development, Specification by Example.

**Does not reach.** Genesis names no customer seat. On fosline David occupies both seats, which hides the question; independence there rests entirely on provenance, an expectation marked as the customer's and a requirement marked as the architect's, written as separate acts and never derived from each other in one sitting.

**Belief.** David's ruling: the customer originates the expectations, the one for whom the system is being built. Session assessment following from it: the architect cannot author or edit the expectations, only read them and throw against them, or the triangulation collapses. Session correction of the morning's Gherkin entry: for this slot both objections reverse; customers think in scenarios so example-shaped is right, and the expectations are a separate artifact from the requirements by construction so nothing is fused; Gherkin's original purpose, customer-readable examples, is exactly this slot. On a name: the idea already has three in the field, and David has ruled against coinages; any fourth is his to choose.

## 2026-10-03 — The red pen on a hundred output sites (fosline session)

**Examined.** Fosline's end-of-day report: three parts done across seven documents in one eight-minute pass; the correction removed from DM4, DM16, DM10 (now `accountedBy`), SD11 and the ViewModels; the paper exchange given DM56–DM58 and funded in SD3; DM59 added; "every fence balanced, 107 VM keys and 59 DM keys each declared once"; "your words are in five change logs, the review record, the handoff and the session memory." Then the offer of David's red pen on what was written today, and his reply that this is practically impossible for him to do. When he said he was lost, fosline summarised the day in ten lines: three decisions, what they cost, where the documents are.

**Showed.** David's observations: neither he nor the session knows what the process is, so they wander like a squirrel gathering nuts; he is then asked to review something he cannot diff, since git log across so many documents is not really possible; a compiler builds, checks that it all fits together, runs the tests, and then one final PR review happens before release, nowadays often by several AI agents from different points of view; and since his commentary is plastered everywhere in the project at every level, the document system should be able to balance what the documentation says against the specifications he, the customer and architect, has given.

**Does not reach.** The session's consistency check ran inside a stochastic reader and was reported as a sentence to be trusted. David's rulings live inside output documents as quotations, truth smeared across output as provenance marks, with no single place that the outputs cite.

**Belief.** David's: the system should balance documentation against his given specifications; the compiler analogy, build then test then one final review. Session assessment: the red pen on output is the wrong review surface by the tree's own axiom, review the arguments not the return value; the three decisions are the arguments and were reviewed when made, and what remains across seven documents is a propagation check, fact not intent, a machine's job. Session assessment: "fences balanced, keys declared once" is already a build step and can be made deterministic today. Session assessment: "balance" is a trial balance, one ledger of rulings as postings with date and name, every document statement citing the ruling it descends from, reconciliation listing statements with no ruling (laundering or a hole) and rulings with no statement (not propagated); the metaphor is fosline's own domain. Session assessment: the ten-line summary is a work item written after execution instead of before; written first, David reviews ten lines before anything moves instead of a hundred sites after. Multi-agent review remains the right final gate on output and cannot replace the three above. Unruled.

## 2026-10-03 — Seventeen files for one word (fosline session, pasted by David)

**Examined.** Fosline's report of a vocabulary sweep: David's ruling that the trading vernacular (*money in*, *money out*, *real money*, *the money over time*) be replaced by taxonomy phrases, a six-word table (amount, balance, gain, posting, asset, deposit) put to him and approved with *"yes"*, then 167 replacements by the table and 36 by hand across nine documents and seven change logs, seventeen files uncommitted, and the verification *"no residue, fences even, VM1–VM107 once each, 24 Mermaid blocks parse"*. His words pasted verbatim into each change log; the same paragraph appears four times in one screen. One contradiction surfaced by the sweep itself: the naming note of 2026-10-02 rejected `BalanceCurveViewModel` and the sweep of 2026-10-03 adopted it.

**Showed.** The review happened at the argument: the table, one word of approval. What was then offered for review was the return value, seventeen files, with SourceTree as the instrument. What remains after a ratified table is a propagation check, a fact, and it was performed by a stochastic reader and reported as sentences. The 36 hand edits are the only ones that need eyes and nothing separates them from the 167. The ruling exists in seven copies and in no single record the outputs cite. The contradiction was catchable only because a human read two prose notes.

**Does not reach.** With files, the ruling, the table, the sweep and the verification are all prose inside output documents, so the output is the only review surface left. Nothing is re-runnable: a second session cannot apply the same table to the same pre-sweep text and diff the result against what was produced.

**Belief.** David's: *"Here's a perfect example of why I don't think files work. What am I supposed to do with that? Really, load up 17 files and somehow use SourceTree to diff and examine for consistency, and who knows what else?"* Earlier the same hour, David's: Markdown is only what exists now; he is much less confident it scales at all and almost certain it cannot carry the functionality described in the entries above. Session assessment: with records, he ratifies one table, a tool applies it, a tool checks it, and what reaches him is a count and the 36 exceptions; he never opens the files. Session assessment: this bears on the bootstrap tool's goal, recorded in `planning/stream/feat-bootstrap-tool.md`, which as drafted reads today's Markdown.
