#!/usr/bin/env bash
# Distill an OpenCode session into OKF memory records (Phase 1).
# Manual trigger: scripts/session-distill.sh [--session ses_…] [--dry-run]
#                 [--force] [--note] [--model provider/model]
#
# Pipeline: session export (raw) → transcript compaction → free-model summary
# (six sections) → deterministic OKF writer → secret gate → lint → qmd update.
# The model never writes frontmatter, slugs, or paths.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MEMORY_DIR="${PROJECT_DIR}/memory"
TMP_DIR="${PROJECT_DIR}/.agent/tmp"
PROMPT_TEMPLATE="${PROJECT_DIR}/templates/session-distill-prompt.md"
WRITER="${PROJECT_DIR}/scripts/distill-write.js"
QMD_CMD="${QMD_CMD:-bunx @tobilu/qmd}"
MODEL="opencode-go/deepseek-v4.1-flash"

SESSION_ID=""
DRY_RUN=0
FORCE=0
NOTE=0

usage() {
  cat <<'USAGE'
Usage: scripts/session-distill.sh [options]

Distills an OpenCode session into memory/decisions/, memory/mistakes/, and
memory/builds/, then lints and indexes it with qmd.

Options:
  --session <ses_…>   Session to distill (default: newest non-distill session)
  --dry-run           Summarize and show planned files; write nothing
  --force             Re-distill a session already recorded in the state file
  --note              Attach a git note on HEAD under refs/notes/ai-sessions
  --model <id>        Summarizer model (default: opencode-go/deepseek-v4.1-flash)
  -h, --help          Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session) SESSION_ID="${2:?--session needs a session id}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --force)   FORCE=1; shift ;;
    --note)    NOTE=1; shift ;;
    --model)   MODEL="${2:?--model needs a model id}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

mkdir -p "$TMP_DIR" "$MEMORY_DIR/decisions" "$MEMORY_DIR/mistakes" "$MEMORY_DIR/builds"

# 1. Resolve the session id (skip distiller sessions by title).
if [[ -z "$SESSION_ID" ]]; then
  SESSION_ID="$(cd "$PROJECT_DIR" && opencode session list 2>/dev/null \
    | awk '$0 !~ /memory-distill/ {print $1; exit}')"
fi
[[ "$SESSION_ID" == ses_* ]] || {
  echo "error: no session id (got '${SESSION_ID}'); pass --session ses_…" >&2
  exit 1
}

# 2. Idempotency: derived from the versioned memory records themselves.
# Build records, decisions, and mistakes all carry the session id, so the
# curated memory is the source of truth — no separate bookkeeping file.
if [[ "$FORCE" -eq 0 ]] && grep -rq "$SESSION_ID" \
     "$MEMORY_DIR/builds" "$MEMORY_DIR/decisions" "$MEMORY_DIR/mistakes" 2>/dev/null; then
  echo "Session ${SESSION_ID} already distilled (use --force to redo)."
  exit 0
fi

echo "=== session distill === (session ${SESSION_ID}, model ${MODEL})"

# 3. Raw export (no --sanitize: that redacts all text; our writer guards secrets).
RAW_JSON="${TMP_DIR}/session-${SESSION_ID}.json"
if ! (cd "$PROJECT_DIR" && opencode session export "$SESSION_ID" > "$RAW_JSON"); then
  echo "error: session export failed for ${SESSION_ID}" >&2
  exit 1
fi

# 4. Compact transcript: user/assistant text + touched file paths, capped.
TRANSCRIPT="${TMP_DIR}/session-${SESSION_ID}.md"
RAW_JSON="$RAW_JSON" TRANSCRIPT="$TRANSCRIPT" bun -e '
const fs = require("node:fs");
const d = JSON.parse(fs.readFileSync(process.env.RAW_JSON, "utf8"));
const out = [];
for (const m of d.messages || []) {
  if (m.type === "user" && m.text && m.text.trim()) {
    out.push("### User\n" + m.text.trim());
  } else if (m.type === "assistant") {
    const text = (m.content || [])
      .filter((p) => p.type === "text" && p.text)
      .map((p) => p.text.trim())
      .join("\n")
      .trim();
    if (text) out.push("### Assistant\n" + text);
  }
}
const files = new Set();
for (const m of d.messages || []) {
  for (const p of m.content || []) {
    if (p.type === "tool") {
      const fp = p.state?.input?.filePath || p.state?.input?.path;
      if (fp) files.add(fp);
    }
  }
}
if (files.size) out.push("### Touched files\n" + [...files].sort().join("\n"));
let s = out.join("\n\n");
if (s.length > 12000) s = s.slice(0, 12000) + "\n\n[...transcript truncated...]";
fs.writeFileSync(process.env.TRANSCRIPT, s);
'

# 5. Summarize with the free-tier model.
SESSION_TITLE="$(RAW_JSON="$RAW_JSON" bun -e '
const d = JSON.parse(require("node:fs").readFileSync(process.env.RAW_JSON, "utf8"));
console.log((d.info?.title || "").replace(/\s+/g, " ").trim());
')"
[[ -n "$SESSION_TITLE" ]] || SESSION_TITLE="$SESSION_ID"

PROMPT="$(cat "$PROMPT_TEMPLATE")

$(cat "$TRANSCRIPT")"

SUMMARY="${TMP_DIR}/distill-${SESSION_ID}.md"
if ! (cd "$PROJECT_DIR" && opencode run --title "memory-distill ${SESSION_ID}" \
      --model "$MODEL" "$PROMPT" > "$SUMMARY" 2> "${TMP_DIR}/distill-${SESSION_ID}.err"); then
  echo "error: summarizer failed; see ${TMP_DIR}/distill-${SESSION_ID}.err" >&2
  exit 1
fi

if ! grep -Eq '^#{1,4}[[:space:]]+Intent' "$SUMMARY"; then
  echo "error: summarizer output missing an Intent section; raw kept at ${SUMMARY}" >&2
  exit 1
fi

# 6. Deterministic write (frontmatter, slugs, secret gate).
BRANCH="$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
COMMIT="$(git -C "$PROJECT_DIR" rev-parse --short HEAD 2>/dev/null || echo none)"
DATE="$(date +%F)"
RESULT="$(SUMMARY="$SUMMARY" DATE="$DATE" SESSION_ID="$SESSION_ID" \
  SESSION_TITLE="$SESSION_TITLE" BRANCH="$BRANCH" COMMIT="$COMMIT" \
  MEMORY_DIR="$MEMORY_DIR" DRY_RUN="$DRY_RUN" bun "$WRITER")"
echo "$RESULT"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo ""
  echo "--- parsed sections ---"
  sed -E -n '/^#{1,4}[[:space:]]+Intent/,$p' "$SUMMARY" | head -80
  echo ""
  echo "dry-run: nothing written, state unchanged."
  exit 0
fi

# 7. Lint + index + log + state.
"${PROJECT_DIR}/scripts/memory-lint.sh"
(cd "$PROJECT_DIR" && $QMD_CMD update)

FILES_WRITTEN="$(RESULT="$RESULT" MEMORY_DIR="$MEMORY_DIR" bun -e '
const r = JSON.parse(process.env.RESULT);
const paths = [...(r.written.decisions || []), ...(r.written.mistakes || [])];
if (r.written.build) paths.push(r.written.build);
console.log(paths.map((p) => p.replace(process.env.MEMORY_DIR + "/", "")).join(", "));
')"
LOG_LINE="- ${DATE} — distilled session ${SESSION_ID} — ${FILES_WRITTEN:-no files}"
awk -v entry="$LOG_LINE" '
  !done && /^- / { print entry; done = 1 }
  { print }
  END { if (!done) print entry }
' "${MEMORY_DIR}/log.md" > "${TMP_DIR}/log.md.new"
mv "${TMP_DIR}/log.md.new" "${MEMORY_DIR}/log.md"

# 8. Optional git note binding.
if [[ "$NOTE" -eq 1 ]]; then
  if git -C "$PROJECT_DIR" rev-parse --verify HEAD >/dev/null 2>&1; then
    BUILD_REL="$(RESULT="$RESULT" MEMORY_DIR="$MEMORY_DIR" bun -e '
const r = JSON.parse(process.env.RESULT);
const p = r.written.build || "";
console.log(p.replace(process.env.MEMORY_DIR + "/", ""));
')"
    git -C "$PROJECT_DIR" notes --ref=ai-sessions add -f \
      -m "distilled: memory/${BUILD_REL} (session ${SESSION_ID})" HEAD
    echo "git note attached (refs/notes/ai-sessions) on $(git -C "$PROJECT_DIR" rev-parse --short HEAD)"
  else
    echo "warning: no HEAD commit; skipping git note" >&2
  fi
fi

echo "done: ${FILES_WRITTEN:-no files}"
