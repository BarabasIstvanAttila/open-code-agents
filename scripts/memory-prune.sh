#!/usr/bin/env bash
# File-based retention for memory/: move stale or archived notes out of the qmd
# collections, then let qmd drop the tombstones.
#
# qmd has no TTL. A document disappears only when its file leaves a collection
# path and `qmd update` marks it inactive; `qmd cleanup` then deletes it.
# Files in memory/.archive/ are outside every collection glob (dot-directory).
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MEMORY_DIR="${PROJECT_DIR}/memory"
ARCHIVE_DIR="${MEMORY_DIR}/.archive"
QMD_CMD="${QMD_CMD:-bunx @tobilu/qmd}"
DAYS=180
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: scripts/memory-prune.sh [--days N] [--dry-run]

Moves memory markdown files to memory/.archive/<collection>/ when either:
  - frontmatter has status: archived, or
  - timestamp is older than N days (default 180) and tags do not include "keep".

Then runs: qmd update && qmd cleanup   (skipped with --dry-run)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days)    DAYS="${2:?--days needs a number}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$DAYS" =~ ^[0-9]+$ ]] || { echo "--days must be a positive integer" >&2; exit 2; }

field() {
  awk -v key="$1" '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    NR > 1 && index($0, key ":") == 1 {
      sub("^" key ":[ ]*", "")
      gsub(/^"|"$/, "")
      print
      exit
    }
  ' "$2"
}

to_epoch() {
  date -j -f "%Y-%m-%d" "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null || echo ""
}

cutoff=$(( $(date +%s) - DAYS * 86400 ))
moved=0
kept=0

echo "=== memory prune === (days=${DAYS}, dry-run=${DRY_RUN})"

while IFS= read -r -d '' file; do
  rel="${file#"${PROJECT_DIR}/"}"
  base="$(basename "$file")"
  [[ "$base" == "index.md" || "$base" == "log.md" ]] && continue
  case "$rel" in memory/.archive/*|memory/ghost/*) continue ;; esac

  status="$(field status "$file")"
  ts="$(field timestamp "$file")"
  tags="$(field tags "$file")"

  reason=""
  if [[ "$status" == "archived" ]]; then
    reason="status: archived"
  elif [[ "$tags" == *keep* ]]; then
    kept=$((kept + 1)); continue
  elif [[ -n "$ts" ]]; then
    epoch="$(to_epoch "$ts")"
    if [[ -n "$epoch" && "$epoch" -lt "$cutoff" ]]; then
      reason="older than ${DAYS} days (${ts})"
    fi
  fi

  [[ -z "$reason" ]] && continue

  collection="$(basename "$(dirname "$file")")"
  dest="${ARCHIVE_DIR}/${collection}/${base}"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  would archive ${rel} — ${reason}"
  else
    mkdir -p "${ARCHIVE_DIR}/${collection}"
    mv "$file" "$dest"
    echo "  archived ${rel} -> ${dest#"${PROJECT_DIR}/"} — ${reason}"
  fi
  moved=$((moved + 1))
done < <(find "${MEMORY_DIR}" -type f -name '*.md' -print0 | sort -z)

echo ""
echo "Archived: ${moved}, kept (tag keep): ${kept}"

if [[ "$DRY_RUN" -eq 0 && "$moved" -gt 0 ]]; then
  echo ""
  echo "--- qmd update ---"
  (cd "$PROJECT_DIR" && $QMD_CMD update)
  echo "--- qmd cleanup ---"
  (cd "$PROJECT_DIR" && $QMD_CMD cleanup)
elif [[ "$DRY_RUN" -eq 0 ]]; then
  echo "Nothing to archive; skipping qmd update/cleanup."
fi
