#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

check() {
  local label="$1"
  local cmd="$2"
  local expected="$3"

  result=$(eval "$cmd" 2>&1) || result=""
  if echo "$result" | grep -q "$expected"; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label — expected '$expected' in output"
    echo "    Got: $(echo "$result" | head -3)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Service Health Check ==="
echo ""

echo "--- oMLX ---"
check "oMLX server" "curl -sf http://127.0.0.1:8005/v1/models" "object"

echo ""
echo "--- qmd ---"
if command -v qmd &>/dev/null; then
  check "qmd binary" "which qmd" "qmd"
  check "qmd status" "qmd status" "ok"
else
  echo "  ✗ qmd not found — install with: npm install -g @tobilu/qmd"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- context-mode ---"
if command -v context-mode-mcp &>/dev/null; then
  check "context-mode binary" "which context-mode-mcp" "context-mode"
else
  echo "  ✗ context-mode-mcp not found — verify npm/install path"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- bun ---"
if command -v bun &>/dev/null; then
  check "bun binary" "which bun" "bun"
else
  echo "  ✗ bun not found — install from https://bun.sh"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- opencode ---"
if command -v opencode &>/dev/null; then
  check "opencode binary" "which opencode" "opencode"
else
  echo "  ✗ opencode not found — install with: npm install -g opencode-ai"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi