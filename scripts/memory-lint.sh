#!/usr/bin/env bash
# Validate OKF frontmatter and link integrity for memory/ before qmd indexes it.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MEMORY_DIR="${PROJECT_DIR}/memory"
STRICT=0
[[ "${1:-}" == "--strict" ]] && STRICT=1

VALID_TYPES="task pattern plan research build decision mistake"
errors=0
warnings=0

err()  { echo "  ✗ $1"; errors=$((errors + 1)); }
warn() { echo "  ! $1"; warnings=$((warnings + 1)); }

# field <key> <file> — first value inside the leading frontmatter block
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

has_frontmatter() {
  [[ "$(head -n 1 "$1")" == "---" ]] && tail -n +2 "$1" | grep -q '^---$'
}

echo "=== memory lint ==="

while IFS= read -r -d '' file; do
  rel="${file#"${PROJECT_DIR}/"}"
  base="$(basename "$file")"

  # Reserved OKF files, the archive, and the ghost reference area are out of scope
  [[ "$rel" == "memory/index.md" || "$rel" == "memory/log.md" ]] && continue
  case "$rel" in memory/.archive/*|memory/ghost/*) continue ;; esac

  if ! has_frontmatter "$file"; then
    warn "${rel} — missing frontmatter"
    continue
  fi

  type="$(field type "$file")"
  title="$(field title "$file")"
  desc="$(field description "$file")"
  ts="$(field timestamp "$file")"

  [[ -n "$type" ]]  || err "${rel} — missing 'type'"
  [[ -n "$title" ]] || err "${rel} — missing 'title'"
  [[ -n "$desc" ]]  || err "${rel} — missing 'description'"
  [[ -n "$ts" ]]    || err "${rel} — missing 'timestamp'"

  if [[ -n "$type" ]] && ! echo " ${VALID_TYPES} " | grep -q " ${type} "; then
    err "${rel} — invalid type '${type}' (allowed: ${VALID_TYPES})"
  fi

  if [[ -n "$type" ]]; then
    parent="$(basename "$(dirname "$file")")"
    case "$parent" in
      tasks)    expected="task" ;;
      patterns) expected="pattern" ;;
      plans)    expected="plan" ;;
      research) expected="research" ;;
      builds)   expected="build" ;;
      decisions) expected="decision" ;;
      mistakes)  expected="mistake" ;;
      *)        expected="$parent" ;;
    esac
    [[ "$expected" == "$type" ]] || err "${rel} — type '${type}' does not match collection '${parent}' (expected '${expected}')"
  fi

  if [[ -n "$ts" ]] && ! [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    err "${rel} — timestamp '${ts}' is not YYYY-MM-DD"
  fi

  if [[ -n "$ts" ]]; then
    epoch="$(date -j -f "%Y-%m-%d" "$ts" +%s 2>/dev/null || date -d "$ts" +%s 2>/dev/null || echo "")"
    [[ -n "$epoch" ]] || err "${rel} — timestamp '${ts}' is not a real date"
  fi

  # Link integrity for relative markdown links
  while IFS= read -r link; do
    target="${link%%#*}"
    [[ -z "$target" ]] && continue
    case "$target" in http://*|https://*|mailto:*|/*) continue ;; esac
    resolved="$(cd "$(dirname "$file")" && cd "$(dirname "$target")" 2>/dev/null && pwd)/$(basename "$target")" || {
      err "${rel} — broken link '${target}'"; continue; }
    [[ -e "$resolved" ]] || err "${rel} — broken link '${target}'"
  done < <(grep -oE '\]\([^)]+\)' "$file" | sed -E 's/^\]\((.*)\)$/\1/' || true)
done < <(find "${MEMORY_DIR}" -type f -name '*.md' -print0 | sort -z)

if [[ "${STRICT}" -eq 1 && "${warnings}" -gt 0 ]]; then
  echo ""
  echo "--strict: treating ${warnings} warning(s) as errors"
  errors=$((errors + warnings))
fi

echo ""
echo "Results: ${errors} error(s), ${warnings} warning(s)"
[[ "${errors}" -eq 0 ]]
