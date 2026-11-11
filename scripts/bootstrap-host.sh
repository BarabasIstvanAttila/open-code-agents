#!/usr/bin/env bash
# Bootstrap a consuming repo to use the LocalAi harness as a git submodule.
#
# Run from the consuming repo root after:
#   git submodule add <localai-repo> .harness && git submodule update --init
#   bash .harness/scripts/bootstrap-host.sh
#
# What it does (idempotent, non-destructive):
#   0. Migrates legacy wiring: removes root AGENTS.md / opencode.json symlinks
#      that point into the harness (old init-submodule.sh flow).
#   1. Seeds the 6 shared MCP servers + tool enables into the GLOBAL OpenCode
#      config (~/.config/opencode/opencode.json), keeping existing entries.
#   2. Symlinks .opencode/agent and .opencode/commands to the harness.
#   3. Creates LOCALAI_ROOT script wrappers in the host's scripts/ dir.
#   4. Merges "instructions": [".harness/AGENTS.md"] into the host config.
#   5. Initializes the HOST's own memory/ + .qmd index (8 collections).
set -euo pipefail

HOST_ROOT="$(pwd)"
HARNESS_DIR=".harness"
SKIP_GLOBAL=0
DRY_RUN=0
CONTEXT_MODE_PATH=""

usage() {
  cat <<'USAGE'
Usage: bash .harness/scripts/bootstrap-host.sh [options]

Options:
  --harness <path>            Harness submodule path (default: .harness)
  --skip-global-mcp           Do not touch ~/.config/opencode/opencode.json
  --context-mode-path <path>  Override the context-mode cli.bundle.mjs path
  --dry-run                   Print planned actions, write nothing
  -h, --help                  Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --harness) HARNESS_DIR="${2:?--harness needs a path}"; shift 2 ;;
    --skip-global-mcp) SKIP_GLOBAL=1; shift ;;
    --context-mode-path) CONTEXT_MODE_PATH="${2:?--context-mode-path needs a path}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

HARNESS_DIR="${HARNESS_DIR%/}"
HARNESS_ABS="$HOST_ROOT/$HARNESS_DIR"

# --- guards ---------------------------------------------------------------
git -C "$HOST_ROOT" rev-parse --git-dir >/dev/null 2>&1 || {
  echo "error: run this from the consuming repo root (not a git repo: $HOST_ROOT)" >&2
  exit 1
}
[[ -d "$HARNESS_ABS" ]] || {
  echo "error: harness dir '$HARNESS_DIR' not found — run 'git submodule update --init' first" >&2
  exit 1
}
[[ -f "$HARNESS_ABS/scripts/session-distill.sh" ]] || {
  echo "error: '$HARNESS_DIR/scripts/session-distill.sh' missing — submodule is not checked out" >&2
  exit 1
}
command -v bun >/dev/null 2>&1 || {
  echo "error: bun is required (https://bun.sh)" >&2
  exit 1
}

echo "=== harness bootstrap ==="
echo "host:    $HOST_ROOT"
echo "harness: $HARNESS_DIR"
echo "mode:    dry-run=$DRY_RUN, global-mcp=$((1 - SKIP_GLOBAL))"
echo ""

# --- 0. legacy auto-migration --------------------------------------------
# Old init-submodule.sh wiring symlinked AGENTS.md and opencode.json into the
# host root. Remove those symlinks so this script's single config model wins.
LEGACY_OPENCODE_REMOVED=0
migrate_legacy() {
  local name="$1"
  local path="$HOST_ROOT/$name"

  [[ -L "$path" ]] || return 0

  local target
  target="$(readlink "$path")"
  case "$target" in
    *"$HARNESS_DIR"*|*"local-ai"*)
      if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "would remove legacy root symlink: $name -> $target"
      else
        unlink "$path"
        echo "legacy migration: removed root symlink $name -> $target"
        if [[ "$name" == "opencode.json" ]]; then
          LEGACY_OPENCODE_REMOVED=1
        fi
      fi
      ;;
    *)
      echo "warning: $name is a symlink to '$target' (not the harness) — left untouched" >&2
      ;;
  esac
  return 0
}

echo "--- legacy wiring migration ---"
migrate_legacy AGENTS.md
migrate_legacy opencode.json
if [[ "$LEGACY_OPENCODE_REMOVED" -eq 1 ]]; then
  echo "note: the host opencode.json symlink is replaced by a real file below;" >&2
  echo "      re-add host-specific providers/permissions/agents to it as needed." >&2
fi
echo ""

# --- 1. global MCP config -------------------------------------------------
if [[ "$SKIP_GLOBAL" -eq 0 ]]; then
  echo "--- global OpenCode MCP config ---"
  export MODE=global DRY_RUN="$DRY_RUN"
  [[ -n "$CONTEXT_MODE_PATH" ]] && export CONTEXT_MODE_PATH
  bun "$HARNESS_ABS/scripts/bootstrap-merge.js"
  unset MODE DRY_RUN CONTEXT_MODE_PATH
else
  echo "--- global OpenCode MCP config: skipped ---"
fi
echo ""

# --- 2. symlinks ----------------------------------------------------------
link_dir() {
  local name="$1"
  local src="$HARNESS_DIR/.opencode/$name"
  local dst="$HOST_ROOT/.opencode/$name"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "would link: .opencode/$name -> $src"
    return
  fi

  mkdir -p "$HOST_ROOT/.opencode"
  if [[ -d "$dst" && ! -L "$dst" ]]; then
    local f
    for f in "$HARNESS_ABS/.opencode/$name"/*.md; do
      [[ -e "$f" ]] || continue
      ln -sfn "$src/$(basename "$f")" "$dst/$(basename "$f")"
    done
    echo "merged (per-file symlinks): .opencode/$name"
  else
    ln -sfn "$src" "$dst"
    echo "symlink: .opencode/$name -> $src"
  fi
}

link_dir agent
link_dir commands
echo ""

# --- 3. LOCALAI_ROOT wrappers --------------------------------------------
wrap() {
  local name="$1"
  local dest="$HOST_ROOT/scripts/$name"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "would write wrapper: scripts/$name"
    return
  fi

  mkdir -p "$HOST_ROOT/scripts"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' 'ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
    printf '%s\n' "exec env LOCALAI_ROOT=\"\$ROOT\" bash \"\$ROOT/${HARNESS_DIR}/scripts/${name}\" \"\$@\""
  } > "$dest"
  chmod +x "$dest"
  echo "wrapper: scripts/$name"
}

wrap session-distill.sh
wrap memory-lint.sh
wrap memory-prune.sh
echo ""

# --- 4. host config instructions -----------------------------------------
echo "--- host opencode.json instructions ---"
HOST_ROOT="$HOST_ROOT" HARNESS_REL="$HARNESS_DIR" MODE=host DRY_RUN="$DRY_RUN" \
  bun "$HARNESS_ABS/scripts/bootstrap-merge.js"
echo ""

# --- 5. host memory + qmd index ------------------------------------------
echo "--- host memory + qmd index ---"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "would run: LOCALAI_ROOT=$HOST_ROOT bash $HARNESS_DIR/scripts/qmd-setup.sh"
else
  LOCALAI_ROOT="$HOST_ROOT" bash "$HARNESS_ABS/scripts/qmd-setup.sh"
fi
echo ""

# --- verify ---------------------------------------------------------------
if [[ "$DRY_RUN" -eq 0 ]]; then
  echo "--- verification ---"
  for entry in agent commands; do
    if [[ -e "$HOST_ROOT/.opencode/$entry" ]]; then
      echo "  .opencode/$entry -> $(readlink "$HOST_ROOT/.opencode/$entry" 2>/dev/null || echo 'real dir')"
    fi
  done
  for name in session-distill.sh memory-lint.sh memory-prune.sh; do
    [[ -x "$HOST_ROOT/scripts/$name" ]] && echo "  scripts/$name executable"
  done
fi

echo ""
echo "=== bootstrap complete ==="
echo "Next: restart OpenCode. /distill and /prune should appear;"
echo "global MCP servers apply to every project on this machine."
