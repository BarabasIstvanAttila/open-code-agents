#!/usr/bin/env bash
# opencode-shared/check.sh
# Health check for the OpenCode + ESP32 environment.
# Run any time something feels broken.
# Usage: ./opencode-shared/check.sh

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅  $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️   $*${NC}"; }
err()  { echo -e "${RED}❌  $*${NC}"; }

ERRORS=0

echo ""
echo -e "${BOLD}OpenCode / ESP32 Environment Check${NC}"
echo "════════════════════════════════════════════════"

# ── IDF Environment ───────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[ESP-IDF]${NC}"

if [ -n "${IDF_PATH:-}" ] && [ -f "$IDF_PATH/export.sh" ]; then
    ok "IDF_PATH = $IDF_PATH"
    IDF_VER=$(cat "$IDF_PATH/version.txt" 2>/dev/null || \
              git -C "$IDF_PATH" describe --tags 2>/dev/null || echo "unknown")
    ok "IDF version: $IDF_VER"
else
    err "IDF_PATH not set or invalid"
    echo "    Fix: . ~/esp/esp-idf/export.sh"
    ERRORS=$((ERRORS + 1))
fi

if [ -n "${IDF_TARGET:-}" ]; then
    ok "IDF_TARGET = $IDF_TARGET"
elif [ -f "sdkconfig" ]; then
    T=$(grep '^CONFIG_IDF_TARGET=' sdkconfig | sed 's/CONFIG_IDF_TARGET="\(.*\)"/\1/')
    [ -n "$T" ] && ok "IDF_TARGET (from sdkconfig) = $T" \
                || warn "IDF_TARGET not set and not readable from sdkconfig"
else
    warn "IDF_TARGET not set (will use default 'esp32' on next build)"
fi

# ── esp-clangd ────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[LSP / esp-clangd]${NC}"

ESP_CLANGD=$(ls ~/.espressif/tools/esp-clang/*/esp-clang/bin/clangd 2>/dev/null | tail -1)
if [ -n "$ESP_CLANGD" ]; then
    ok "esp-clangd: $ESP_CLANGD"
    VER=$("$ESP_CLANGD" --version 2>&1 | head -1)
    ok "Version: $VER"
else
    err "esp-clangd not found"
    echo "    Fix: idf_tools.py install all"
    ERRORS=$((ERRORS + 1))
fi

# Verify the path matches what's in opencode.json
if [ -f "opencode.json" ]; then
    JSON_CLANGD=$(python3 -c "
import json
try:
    c = json.load(open('opencode.json'))
    cmd = c.get('lsp', {}).get('clangd', {}).get('command', [])
    print(cmd[0] if cmd else '')
except: print('')
" 2>/dev/null)
    if [ -n "$JSON_CLANGD" ] && [ "$JSON_CLANGD" = "$ESP_CLANGD" ]; then
        ok "opencode.json clangd path matches installed version"
    elif [ -n "$JSON_CLANGD" ] && [ "$JSON_CLANGD" != "$ESP_CLANGD" ]; then
        warn "opencode.json clangd path is stale"
        echo "    Configured: $JSON_CLANGD"
        echo "    Current:    $ESP_CLANGD"
        echo "    Fix: ./opencode-shared/init.sh"
    fi
fi

# ── compile_commands.json ─────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[LSP Index]${NC}"

if [ -f "build/compile_commands.json" ]; then
    AGE=$(( ($(date +%s) - $(stat -f %m "build/compile_commands.json" 2>/dev/null || echo 0)) / 60 ))
    ENTRIES=$(python3 -c "import json; d=json.load(open('build/compile_commands.json')); print(len(d))" 2>/dev/null || echo "?")
    ok "compile_commands.json: $ENTRIES entries, ${AGE}m old"
    if [ "$AGE" -gt 120 ]; then
        warn "File is >2h old — run: idf.py reconfigure"
    fi
else
    err "build/compile_commands.json missing"
    echo "    Fix: idf.py reconfigure"
    ERRORS=$((ERRORS + 1))
fi

# ── .clangd ───────────────────────────────────────────────────────────────────
if [ -f ".clangd" ]; then
    ok ".clangd project config present"
else
    warn ".clangd missing — clangd will emit GCC-flag errors"
    echo "    Fix: ./opencode-shared/init.sh"
fi

# ── Shell wrapper ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[Shell / Agent Commands]${NC}"

if [ -x ".opencode/esp-shell.sh" ]; then
    ok ".opencode/esp-shell.sh present and executable"
else
    err ".opencode/esp-shell.sh missing or not executable"
    echo "    Fix: ./opencode-shared/init.sh"
    ERRORS=$((ERRORS + 1))
fi

# Check opencode.json shell setting
if [ -f "opencode.json" ]; then
    SHELL_CFG=$(python3 -c "
import json
try:
    c = json.load(open('opencode.json'))
    print(c.get('shell','NOT SET'))
except: print('ERROR')
" 2>/dev/null)
    if [ "$SHELL_CFG" = ".opencode/esp-shell.sh" ]; then
        ok "opencode.json shell = $SHELL_CFG"
    else
        warn "opencode.json shell = '$SHELL_CFG' (expected .opencode/esp-shell.sh)"
        echo "    Fix: ./opencode-shared/init.sh"
    fi
fi

# ── Skills ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[Skills]${NC}"

for skill in esp32-idf esp32-patterns; do
    if [ -f ".opencode/skills/$skill/SKILL.md" ]; then
        ok "Skill '$skill' available"
    else
        err "Skill '$skill' not found at .opencode/skills/$skill/SKILL.md"
        echo "    Fix: ./opencode-shared/init.sh"
        ERRORS=$((ERRORS + 1))
    fi
done

# ── opencode.json ────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[opencode.json]${NC}"

if [ -f "opencode.json" ]; then
    python3 -c "
import json, sys
try:
    c = json.load(open('opencode.json'))
    issues = []
    if '\$schema' not in c: issues.append('missing \$schema')
    if 'lsp' not in c: issues.append('lsp not configured')
    if 'permission' not in c: issues.append('permission not configured')
    if 'shell' not in c: issues.append('shell not configured')
    if issues:
        print('  [warn]  opencode.json issues: ' + ', '.join(issues))
    else:
        print('  [ok]    opencode.json looks complete')
except json.JSONDecodeError as e:
    print(f'  [err]   opencode.json parse error: {e}')
    sys.exit(1)
"
else
    err "opencode.json missing"
    echo "    Fix: ./opencode-shared/init.sh"
    ERRORS=$((ERRORS + 1))
fi

# ── Cross-compiler ────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[Cross-compiler]${NC}"

for PREFIX in xtensa-esp-elf riscv32-esp-elf; do
    GCC=$(ls ~/.espressif/tools/${PREFIX}/*/bin/${PREFIX}-gcc 2>/dev/null | tail -1)
    if [ -n "$GCC" ]; then
        VER=$("$GCC" --version 2>&1 | head -1 | awk '{print $NF}')
        ok "${PREFIX}-gcc: $VER"
    else
        warn "${PREFIX}-gcc not found (needed if targeting that architecture)"
    fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════"
if [ "$ERRORS" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}All checks passed.  Run: opencode${NC}"
else
    echo -e "${RED}${BOLD}$ERRORS error(s) found.  Run: ./opencode-shared/init.sh${NC}"
fi
echo ""
