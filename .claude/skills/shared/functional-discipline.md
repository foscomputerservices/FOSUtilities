# The functional discipline

FOSMVVM is functional programming applied to the whole engineering
effort, not just to code style.

**The chain.** Every artifact is a projection of the layer above it:
requirements → design → ViewModel shape → View — and at runtime,
server state → ViewModel → rendered UI. The codebase is a **build
tree**, not a build product: every artifact has known inputs (View ←
VM; RequestBody + Form VM + Model ← the one Fields definition), and a
change stales exactly its downstream.

**The projection function is a session holding the skill and the
design** — re-projection is re-derivation from the layer above, never a
tool re-run over evolved output. Unchanged subtrees are valid cache:
reused unopened, never read for guidance.

**The one sin, in its three forms.** A projection is valid exactly as
long as its inputs are unchanged; when an input changes, everything
downstream is stale.

- **Patching the output** (editing the .o by hand) — fix the input
  layer and re-project.
- **Shipping stale objects** — an input changed and downstream was
  never re-projected.
- **Re-projecting what isn't stale** (`make clean && make` every
  cycle) — a stochastic function makes this manufactured diff, not a
  no-op. Re-projection scope = the stale subtree, exactly — neither
  less nor more.

**The tells** that you are committing it:

- transcribing a design artifact's CONTENT into a View. The
  discriminator is the artifact's STANDING, not the word "mockup":
  design ratified into the truth layer (e.g. Figma linked from
  requirements) IS an input layer — layout and interaction project from
  it legitimately; an informal sketch is not. Under either standing,
  the sample data and text baked into a design never project — data and
  localized text arrive only through the ViewModel;
- editing generated code instead of changing the VM/design and
  regenerating;
- citing existing code as the pattern to follow (code is output — zero
  votes on what should EXIST; local idiom and conventions arrive via
  the skills and the format/lint gate, not by reading neighbors);
- hand-rolling what a generator or the framework produces (JSON coding,
  test doubles, encoders);
- duplicating a dependency's internals downstream because the framework
  lacks needed functionality — reverse-engineering its primitives into
  the consuming app instead of surfacing the gap upstream as a bug/PR.
  A framework gap is a finding for the framework's owner, never a
  license to fork its internals into app code;
- contorting a design to avoid touching a VM (the VM is derived —
  re-derive it).

**When the projection looks wrong, the input is wrong.** Go up a layer
and fix truth. If the layer above is silent or broken, that is a finding
for the architect — not a license to freelance at this layer.

**The discipline's domain.** It governs artifacts that HAVE a live
projection function: generated Views, ViewModels, Factories, request
scaffolds, Fields conformances. It does NOT govern artifacts ruled
hand-maintained — a committed Xcode project is the standing example
(project generators build original projects; they do not manage them) —
those are truth at their own layer, and "regenerating" them is the sin
there. When unsure which kind an artifact is, ask; do not infer.
