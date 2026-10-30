# Project Mappings Template

`fosmvvm-orientation` asks its questions with neutral names (`WorkspaceSettings`, `WorkspacePreferencesViewModel`). A project tells the session what those names mean locally, so the answers are about the code it is about to edit.

Save the template below as `CLAUDE.md` at the root of the project's ViewModel tree (for example, `Sources/ViewModels/CLAUDE.md`). Claude Code loads it automatically whenever the session works in that tree, and the orientation skill tells the reader to look for it.

## What belongs here

- **Interface facts:** the names of the project's store types, where files live, which module is which. These are declared inputs a session needs in order to compile.
- **Links to the truth layer:** requirements and design documents that constrain this tree.

## What doesn't

- **"Model your ViewModel on this one" examples.** Pointing at existing code as the pattern feeds output back in as input (see [`shared/functional-discipline.md`](../shared/functional-discipline.md)). The patterns come from [`shared/architecture-patterns.md`](../shared/architecture-patterns.md).
- **Restated FOSMVVM rules.** A copy drifts from the source. Link to the section instead.
- **Exceptions to the architecture.** If the project genuinely needs one, it belongs in the architecture docs, approved by the owner, not here.

## Template

```markdown
# ViewModels: project mappings

FOSMVVM rules for this tree come from the fosmvvm-generators plugin
(`shared/architecture-patterns.md`). This file only maps them to this project.

## Application state

- Top-level App State: `<AppStateType>` (`<path>`), injected once at `<App or root view>`.
- Other `@Observable` types vended through `@Environment`, each with the reason it
  can't live on the App State:
  - `<Type>`: <reason>

## Names for the orientation scenarios

| Orientation name | This project |
|------------------|--------------|
| `WorkspaceSettings` (an `@Observable` store) | `<StoreType>` |
| `WorkspacePreferencesViewModel` (a parent VM) | `<ParentViewModel>` |

## Where things live

- ViewModels: `<path>`
- Views: `<path>`
- Ops protocols, Ops, and StubOps: `<path>`
- Localization YAML: `<path>`

## Truth layer

- Requirements: `<link or path>`
- UI design: `<link or path>`
- Architecture decisions specific to this project: `<link or path>`
```
