# FOSMVVM Naming Dictionary

The canonical reference for naming FOSMVVM types. The generator skills cite this file;
when a type name feels ambiguous, **this file decides**. Naming is not cosmetic in
FOSMVVM — the module *is* the namespace and paths are derived from type names, so a
name is part of the contract.

> **Why naming is load-bearing (SOLID).** A FOSMVVM name should encode the type's
> *single responsibility* and its *place in the namespace*, not fight the type system:
> - **Single Responsibility (SRP):** the *primary* axis a type belongs to leads its
>   name, so a family of related types stays cohesive and discoverable.
> - **Interface Segregation / "the module is the namespace" (ISP):** you name a type
>   for what it *means* inside its module, never to dodge a collision with a type in
>   another module.
> - **Development velocity is lifetime velocity:** consistent, sortable names are how a
>   maintainer *finds* the right type six months later. Inconsistent naming is a slow,
>   compounding tax.

---

## 1. Request type names

### 1a. Write / action requests → `<Noun><Verb>Request` (noun **first**)

The concrete request type leads with the **entity/noun**, then the **action verb**,
then `Request`. This holds for the standard REST verbs **and** for semantic actions.

| Operation | ✅ Correct (noun-first) | ❌ Wrong (verb-first) |
|-----------|------------------------|----------------------|
| Create a User (POST) | `UserCreateRequest` | `CreateUserRequest` |
| Update a User (PATCH) | `UserUpdateRequest` | `UpdateUserRequest` |
| Replace a User (PUT) | `UserReplaceRequest` | `ReplaceUserRequest` |
| Delete a User (DELETE) | `UserDeleteRequest` | `DeleteUserRequest` |
| Semantic action ("move an idea") | `IdeaMoveRequest` | `MoveIdeaRequest` |
| Semantic action ("mint a token") | `AgentTokenMintRequest` | `MintAgentTokenRequest` |

**Why noun-first (SRP — cohesion on the primary axis).** The entity is the primary
axis a request belongs to. Noun-first keeps a whole entity's request family together —
`UserCreateRequest`, `UserDeleteRequest`, `UserShowRequest`, `UserUpdateRequest` sort
and read as one group. Verb-first *scatters* the same family across the alphabet
(`Create…` under C, `Delete…` under D) and buries the thing that actually matters
(which entity). It also matches the read-request forms below, so **every** request for
an entity shares one prefix.

**Anti-pattern callout:** `CreateUserRequest` / `MoveIdeaRequest` / `MintAgentTokenRequest`
are verb-first and **wrong**. If you have existing verb-first names, they are a rename
item — do not add more.

### 1b. ViewModel read requests → `<Noun>Request` (Show is implied — **no verb**)

A request that fetches the data to render a screen/page ViewModel takes the ViewModel's
noun with **no verb** — the read is the one canonical fetch, so a "Show" verb would be
noise.

| Screen ViewModel | ✅ Read request |
|------------------|----------------|
| `LandingPageViewModel` | `LandingPageRequest` |
| `DocksViewModel` | `DocksRequest` |
| `DashboardViewModel` | `DashboardRequest` |

This is still noun-first — the noun is the screen. It composes with 1a: an entity that
has both a screen read and writes reads as `Docks` + `Docks…Request`.

### 1c. Raw-data Show requests → `<Entity>ShowRequest`

A request that reads **raw entity data** (not a screen ViewModel) keeps an explicit
`Show`, noun-first: `UserShowRequest`. The explicit verb distinguishes it from other
reads that may operate on the same entity.

---

## 2. Duplicate type names across modules are fine — the module *is* the namespace

A DataModel/wire type and a ViewModel display type **may share a name**. Do **not**
contort a display type's name to avoid colliding with its domain counterpart.

```swift
HarborChannel.Tier      // the wire/DataModel type (domain module)
HarborViewModels.Tier   // the display projection (ViewModel module) — distinct type, fine
```

Each module *is* a Swift namespace, and the Data-vs-View context is part of the
contract, so the two `Tier`s coexist as distinct types. The `ViewModelFactory` holds the
module-qualified mapping between them.

**Why (ISP + the projection boundary).** The ViewModel `Tier` is a *projection of* the
domain `Tier`, not the same type — often a subtly different shape. A same-named-but-
distinct type is **correct**, not a smell. (This is the naming corollary of the
Dependency-Inversion boundary: the ViewModel module must not import the domain module —
see the viewmodel-generator's "ViewModel module must not depend on domain types"
section. The Factory is the one place that sees both.)

**Name a display type for what it *means*, not to dodge a collision.** If a
more-descriptive display name is clearer (`GuestPlatform` vs a bare `Platform`), choose
it for *meaning* — not out of fear of the collision, which is harmless.

---

## Quick reference

| You are naming… | Form | Example |
|-----------------|------|---------|
| Create/Update/Replace/Delete request | `<Noun><Verb>Request` | `UserCreateRequest` |
| Semantic-action request | `<Noun><Action>Request` | `IdeaMoveRequest` |
| Screen/page ViewModel read request | `<Noun>Request` | `DocksRequest` |
| Raw-entity read request | `<Entity>ShowRequest` | `UserShowRequest` |
| Display type colliding with a domain type | name for meaning; collision is fine | `HarborViewModels.Tier` |

## Red flags — STOP

- A request name that **starts with a verb** (`Create…`, `Update…`, `Move…`, `Mint…`) —
  flip it noun-first.
- Adding a suffix/prefix to a ViewModel display type **only** to avoid a same-named
  domain type — the collision is harmless; name for meaning instead.
- A screen read request carrying a `Show`/`Get`/`Fetch` verb — drop it; the noun alone
  is the read.
