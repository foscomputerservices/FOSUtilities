# L1 registration cleanup — punch list

Surfaced by a downstream consumer's L1 integration. The finding wasn't a consumer gap —
it was **over-restriction on our side**: the L1 registration surface made hard what a
plain Vapor middleware-group + `register(collection:)` has always made simple.

Discipline this serves: [[compose-onto-general-never-butcher]] — the specialized door
must compose onto the general layer, not fence it off. And [[issue-reporting-taxonomy]]:
captured here rather than parked as "pre-existing, unrelated."

---

## C1 — drop `.grouped(.constant(groupName))` from `ServerRequestController.boot` · ✅ DONE (`cbe9f0b`)

Landed on this branch. The path group was a roundabout restatement of "register at
`TRequest.path`"; the handler now registers at `TRequest.path.pathComponents` directly on
the middleware-grouped routes. The route — method *and* path — falls out of the request,
and the latent multi-segment bug is fixed for free: `.constant(_)` takes a **single**
component, so a slash-bearing `TRequest.path` was previously corrupted into one segment;
`.pathComponents` splits it correctly.

Verified: served path unchanged for single- and multi-segment `TRequest.path`; full suite
green (553); no `ControllerRouting.path` test asserts the old group shape.

> The remaining `ControllerRouting.path` incoherence flagged alongside C1 (arch §C8 note)
> was **not** folded in here — it stands as its own item if it still bites.

---

## C2 — restore group parity for `register(request:)` (undo the Application-only over-restriction) · **ARCHITECTURE — reopens §3.10 · David's design call**

`register(request:)` is Application-only *by construction* — C8 §3.10 declared
grouped/`Routes`-level registration "structurally gone." The stated reason was **plan
derivation** for *composable* bodies ("RoutesBuilder cannot reach Application"). That
reason never covered a **non-composable** read that needs a **middleware group** for
transport authentication — which the thesis explicitly permits ("routes gate only
authentication").

The consequence a downstream consumer hit: a transport-authenticated (e.g. mutual-TLS)
read cannot use the `register(request:)` door at all, and had to drop to the general
`register(collection:)`-on-a-group layer. That layer is correct and shipped — but the
*sugar* fences off exactly the composition (`.grouped(middleware)` + register) that has
always been the norm.

**The narrow fix (do NOT implement without David's ruling — it reverses a frozen spec
decision):** give the door a mount point while keeping the **Application** as registrar,
so plan derivation is byte-identical and the "never register a composable body without its
plan" invariant holds:

- Application stays the registrar (reaches `self`, derives + validates the plan).
- Only the **mount target** becomes a passed-in `RoutesBuilder` (a middleware group).
- The C7 "lazy-derive+validate" hatch (already sketched in the C7 plan) is the alternative
  if a bare group must be the entry.

This is a §3.10 reopen: it needs a spec amendment + David's design pass, not a code edit.
It is *not* required to unblock the consumer (their general-controller path works); it's a
"make the simple thing simple again" cleanup.

**Disposition:** David decides (a) whether it lands on this branch pre-PR or as a fast
follow after merge, and (b) the shape. Until then, the documented guidance stands:
authn-gated / non-composable read → `ServerRequestController` on the middleware group;
composable / plan-derived read → `register(request:)`.

---

## Also queued (doc-only, from the same integration)

- **Migration line:** "don't raw-decode a served ViewModel — use `fromJSON()` /
  `JSONDecoder.defaultDecoder` / the `app.test(_:afterResponse:)` harness." (A raw
  `JSONDecoder()` broke on a `Date` field.) DocC / migration guide.
- **CHANGELOG line:** each `ServerRequest` conformer adds the 5-arg
  `init(query:sort:fragment:requestBody:responseBody:)`; call sites unaffected.
- **Instructions line:** local-branch consumers use
  `.package(name: "FOSUtilities", path: …)` when the dir name differs.
