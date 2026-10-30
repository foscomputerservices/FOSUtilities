# Gating Edits on Orientation

Make `fosmvvm-orientation` mandatory in your project: a `PreToolUse` hook blocks edits to ViewModel, View, and Ops code until the session has written its orientation answers to a marker file.

You need four things:

1. The plugin enabled in the project's settings, so every machine that opens the project is offered it.
2. The gate script below, committed to the project.
3. The hook registered in the project's `.claude/settings.json`.
4. The project's own mappings (see [project-mappings-template.md](project-mappings-template.md)).

## 1. Enable the plugin for the project

A gate that names a skill the machine doesn't have leaves the session with no way through. Put the plugin in the project's committed `.claude/settings.json` so Claude Code offers to install it to everyone who opens the project:

```json
{
  "enabledPlugins": {
    "fosmvvm-generators@fosmvvm-tools": true
  },
  "extraKnownMarketplaces": {
    "fosmvvm-tools": {
      "source": {
        "source": "github",
        "repo": "foscomputerservices/FOSUtilities"
      }
    }
  }
}
```

The gate's block message also carries the install commands, for a machine that declined or predates the setting.

## 2. Add the gate script

Save as `.claude/hooks/fosmvvm-orientation-gate.sh` in the project and make it executable (`chmod +x`). Edit `GATED_PATHS` to match where the project keeps its ViewModels, Views, and Ops. In these patterns `*` also matches across directories, so `Sources/ViewModels/*` covers every file below that folder.

The script needs `jq`. Without it the gate blocks and says so, rather than letting edits through unchecked.

```bash
#!/usr/bin/env bash
# PreToolUse gate: blocks edits to FOSMVVM ViewModel, View, and Ops code until
# this session has completed the fosmvvm-orientation skill.
set -u

# Paths (relative to the project root) that require orientation.
# In these patterns `*` also matches across directories.
GATED_PATHS=(
  "Sources/ViewModels/*"
  "Sources/*/Views/*"
)
MIN_BYTES=2000

block() {
  printf '%s\n' "$1" >&2
  exit 2
}

# Fail closed: a gate that can't read its input must not wave edits through.
command -v jq >/dev/null 2>&1 ||
  block "fosmvvm-orientation gate: jq is not installed, so this edit can't be checked. Ask the user to install jq (e.g. brew install jq), then retry."

input=$(cat)
session_id=$(jq -r '.session_id // empty' <<<"$input")
file_path=$(jq -r '.tool_input.file_path // empty' <<<"$input")

[[ -z "$file_path" ]] && exit 0
project_root=${CLAUDE_PROJECT_DIR:-$PWD}
rel_path=${file_path#"$project_root/"}

gated=false
for pattern in "${GATED_PATHS[@]}"; do
  # shellcheck disable=SC2053 # unquoted on purpose: glob match
  if [[ "$rel_path" == $pattern ]]; then
    gated=true
    break
  fi
done
$gated || exit 0

[[ "$session_id" =~ ^[A-Za-z0-9_-]+$ ]] ||
  block "fosmvvm-orientation gate: the hook input has no usable session id, so the orientation marker can't be located."

marker_dir="${TMPDIR:-/tmp}"
marker="${marker_dir%/}/fosmvvm-orientation/${session_id}.md"

if [[ -f "$marker" ]] &&
  (($(wc -c <"$marker") >= MIN_BYTES)) &&
  grep -q '(f)' "$marker" &&
  grep -q 'Scenario A' "$marker" &&
  grep -q 'Scenario F' "$marker"; then
  exit 0
fi

mkdir -p "$(dirname "$marker")"
block "Editing $rel_path requires FOSMVVM orientation first.

Run the fosmvvm-generators:fosmvvm-orientation skill, then write your Section 2 and Section 3 answers to:
  $marker

If that skill is not in your available skills, the fosmvvm-generators plugin is not installed on this machine. Ask the user to run:
  /plugin marketplace add foscomputerservices/FOSUtilities
  /plugin install fosmvvm-generators@fosmvvm-tools"
```

**How it behaves:**

- Edits outside `GATED_PATHS` pass untouched.
- A gated edit passes once the session's marker exists, is at least `MIN_BYTES`, and contains `(f)`, `Scenario A`, and `Scenario F`: the last answer of each section, so a marker cut short does not clear.
- Otherwise the edit is blocked (exit 2). The message goes to Claude, naming the skill and the exact marker path.
- The marker is keyed by Claude Code's `session_id` and lives in the temp directory, outside the repo. Each session orients once; nothing needs `.gitignore`.
- Only `Edit` and `Write` reach the hook. An edit made through a shell command, such as `sed` or a heredoc, is never checked; the gate relies on the session using the file tools.

## 3. Register the hook

Add to the same `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/fosmvvm-orientation-gate.sh"
          }
        ]
      }
    ]
  }
}
```

## 4. Verify the gate

Run these from the project root. Each line feeds the script the JSON Claude Code would send and prints its exit code: `0` allows the edit, `2` blocks it.

```bash
gate=.claude/hooks/fosmvvm-orientation-gate.sh
try() { echo "{\"session_id\":\"$1\",\"tool_input\":{\"file_path\":\"$PWD/$2\"}}" | CLAUDE_PROJECT_DIR=$PWD "$gate"; echo "exit $?"; }

try check-1 Sources/Other/Thing.swift            # outside the gate   → exit 0
marker_dir="${TMPDIR:-/tmp}"
marker="${marker_dir%/}/fosmvvm-orientation/check-1.md"

try check-1 Sources/ViewModels/Thing.swift       # no marker          → message, exit 2
echo stub > "$marker"
try check-1 Sources/ViewModels/Thing.swift       # stub marker        → exit 2
# write ≥ 2000 bytes containing "(f)", "Scenario A" and "Scenario F" to the same file, then:
try check-1 Sources/ViewModels/Thing.swift       # real marker        → exit 0
rm "$marker"
```

Then check it live: in a new session, ask Claude to edit a gated file. The edit should be blocked with the skill name and a marker path.

## Keep project specifics out of the skill

Don't fork `fosmvvm-orientation` to add your type names; a fork goes stale when the architecture changes. Put them in the project's own docs instead. [project-mappings-template.md](project-mappings-template.md) is a starting point.
