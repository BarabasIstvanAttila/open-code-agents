#!/usr/bin/env bash
set -euo pipefail

SUBMODULE_PATH="${1:-local-ai}"
PARENT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SUBMODULE_FULL="${PARENT_DIR}/${SUBMODULE_PATH}"
WARNINGS=0
SKIPPED=0
CREATED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}  ℹ${NC} $1"; }
ok()      { echo -e "${GREEN}  ✓${NC} $1"; }
warn()   { echo -e "${YELLOW}  ⚠${NC} $1"; WARNINGS=$((WARNINGS + 1)); }
skip()    { echo -e "${YELLOW}  ↷${NC} $1"; SKIPPED=$((SKIPPED + 1)); }
created() { echo -e "${GREEN}  +${NC} $1"; CREATED=$((CREATED + 1)); }
fail()    { echo -e "${RED}  ✗${NC} $1"; }

banner() {
  echo ""
  echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}║        OpenCode Agent Infrastructure — Init          ║${NC}"
  echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

check_prereqs() {
  echo -e "${BOLD}Prerequisites${NC}"
  echo "─────────────"

  command -v git &>/dev/null && ok "git" || { fail "git — required"; WARNINGS=$((WARNINGS + 1)); }
  command -v bun &>/dev/null && ok "bun" || { fail "bun — install from https://bun.sh"; WARNINGS=$((WARNINGS + 1)); }
  command -v opencode &>/dev/null && ok "opencode CLI" || { fail "opencode CLI — install: npm i -g opencode-ai"; WARNINGS=$((WARNINGS + 1)); }

  if curl -sf http://127.0.0.1:8005/v1/models 2>/dev/null | grep -q "object"; then
    ok "oMLX server on :8005"
  else
    warn "oMLX server not responding on :8005 — start it before using local models"
  fi

  if command -v qmd &>/dev/null; then
    ok "qmd"
  else
    warn "qmd not found — install: npm i -g @tobilu/qmd"
  fi

  echo ""
}

validate_submodule() {
  if [ ! -d "${SUBMODULE_FULL}" ]; then
    fail "Submodule directory not found: ${SUBMODULE_FULL}"
    echo ""
    echo "Add the submodule first:"
    echo "  git submodule add git@github.com:BarabasIstvanAttila/open-code-agents.git ${SUBMODULE_PATH}"
    echo "  git submodule update --init --recursive"
    exit 1
  fi

  if [ ! -f "${SUBMODULE_FULL}/opencode.json" ]; then
    fail "Submodule does not contain expected files: ${SUBMODULE_FULL}"
    echo "  Expected opencode.json in ${SUBMODULE_FULL}"
    exit 1
  fi

  ok "Submodule found at ${SUBMODULE_PATH}"
}

ensure_symlink() {
  local target="$1"
  local link="$2"
  local desc="$3"

  if [ -L "${link}" ]; then
    local current_target
    current_target="$(readlink "${link}")"
    if [ "${current_target}" = "${target}" ]; then
      skip "${desc} — symlink already exists"
    else
      warn "${desc} — symlink points to ${current_target}, expected ${target}"
    fi
  elif [ -e "${link}" ]; then
    warn "${desc} — file exists (not a symlink), skipping to avoid overwriting"
  else
    ln -s "${target}" "${link}"
    created "${desc}"
  fi
}

ensure_dir() {
  local dir="$1"
  local desc="$2"

  if [ -d "${dir}" ]; then
    skip "${desc} — directory exists"
  else
    mkdir -p "${dir}"
    created "${desc}"
  fi
}

create_symlinks() {
  echo -e "${BOLD}Creating symlinks${NC}"
  echo "──────────────────"

  cd "${PARENT_DIR}"

  ensure_symlink "${SUBMODULE_PATH}/AGENTS.md" "AGENTS.md" "AGENTS.md → ${SUBMODULE_PATH}/AGENTS.md"

  ensure_dir ".opencode" ".opencode/"
  ensure_symlink "${SUBMODULE_PATH}/.opencode/agent" ".opencode/agent" ".opencode/agent → submodule agents"
  ensure_symlink "${SUBMODULE_PATH}/.opencode/skills" ".opencode/skills" ".opencode/skills → submodule skills"
  ensure_symlink "${SUBMODULE_PATH}/.opencode/package.json" ".opencode/package.json" ".opencode/package.json → submodule"

  if command -v bun &>/dev/null; then
    if [ ! -d ".opencode/node_modules" ]; then
      (cd .opencode && bun install 2>/dev/null) && ok ".opencode/node_modules installed" || warn "bun install in .opencode/ failed"
    else
      skip ".opencode/node_modules — already exists"
    fi
  fi

  echo ""
}

merge_opencode_config() {
  echo -e "${BOLD}OpenCode configuration${NC}"
  echo "─────────────────────"

  cd "${PARENT_DIR}"

  if [ -f "opencode.json" ]; then
    if [ -L "opencode.json" ]; then
      skip "opencode.json — already symlinked"
    else
      warn "opencode.json already exists in project root (not a symlink)"
      echo ""
      echo -e "${YELLOW}  You need to manually merge config from ${SUBMODULE_PATH}/opencode.json:${NC}"
      echo ""
      echo "  Required sections to merge:"
      echo "    1. Add providers:       .provider.omlx and .provider.opencode"
      echo "    2. Add MCP servers:     .mcp.context7, .mcp.duckduckgo, .mcp.sequentialthinking, .mcp.qmd"
      echo "    3. Add tools:           .tools (enable context7*, duckduckgo*, sequentialthinking*, context-mode*, qmd*)"
      echo "    4. Add plugin:          .plugin (\"context-mode\")"
      echo "    5. Add instructions:     .instructions (\"AGENTS.md\")"
      echo ""
      echo "  Or replace your opencode.json with the submodule version:"
      echo "    rm opencode.json && ln -s ${SUBMODULE_PATH}/opencode.json opencode.json"
      echo ""
    fi
  else
    ln -s "${SUBMODULE_PATH}/opencode.json" "opencode.json"
    created "opencode.json → ${SUBMODULE_PATH}/opencode.json"
  fi

  echo ""
}

create_directories() {
  echo -e "${BOLD}Creating working directories${NC}"
  echo "─────────────────────────────"

  cd "${PARENT_DIR}"

  local sub_path="${SUBMODULE_PATH}"
  if [ "$(basename "${SUBMODULE_PATH}")" = "${SUBMODULE_PATH}" ] && [ ! -d "${SUBMODULE_PATH}/memory" ]; then
    sub_path="${SUBMODULE_FULL}"
  fi

  ensure_dir ".agent" ".agent/"
  ensure_dir "memory" "memory/"
  ensure_dir "memory/tasks" "memory/tasks/"
  ensure_dir "memory/patterns" "memory/patterns/"
  ensure_dir "memory/plans" "memory/plans/"
  ensure_dir "memory/research" "memory/research/"

  echo ""
}

setup_qmd() {
  echo -e "${BOLD}qmd setup${NC}"
  echo "──────────"

  cd "${PARENT_DIR}"

  if command -v qmd &>/dev/null || command -v bunx &>/dev/null; then
    if [ ! -d ".qmd" ]; then
      echo "  Initializing qmd index..."
      bunx @tobilu/qmd init 2>/dev/null || qmd init 2>/dev/null || warn "qmd init failed"
      ok "qmd index initialized"
    else
      skip ".qmd/ — already initialized"
    fi

    for collection in tasks patterns plans research; do
      local dir="memory/${collection}"
      if [ -d "${dir}" ]; then
        bunx @tobilu/qmd collection add "${dir}" --name "${collection}" 2>/dev/null || \
          qmd collection add "${dir}" --name "${collection}" 2>/dev/null || true
      fi
    done
    ok "qmd collections configured"
  else
    warn "qmd/bunx not available — run '${SUBMODULE_PATH}/scripts/qmd-setup.sh' manually after installing qmd"
  fi

  echo ""
}

update_gitignore() {
  echo -e "${BOLD}Updating .gitignore${NC}"
  echo "────────────────────"

  cd "${PARENT_DIR}"

  local gitignore=".gitignore"
  local entries=(".agent/" ".qmd/" "*.secrets/" ".env" "memory/tasks/" "memory/patterns/" "memory/plans/" "memory/research/")

  for entry in "${entries[@]}"; do
    if grep -qF "${entry}" "${gitignore}" 2>/dev/null; then
      skip ".gitignore already has: ${entry}"
    else
      echo "${entry}" >> "${gitignore}"
      created ".gitignore entry: ${entry}"
    fi
  done

  echo ""
}

print_next_steps() {
  echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${GREEN}║              Initialization Complete                 ║${NC}"
  echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  Created: ${CREATED}   Skipped: ${SKIPPED}   Warnings: ${WARNINGS}"
  echo ""
  echo -e "${BOLD}Next steps:${NC}"
  echo ""
  echo "  1. Set environment variables:"
  echo "     export OMLX_API_KEY=\"your-omlx-key\""
  echo "     export CONTEXT7API=\"your-context7-key\""
  echo ""
  echo "  2. Start oMLX (if not already running):"
  echo "     brew services start jundot/omlx/omlx"
  echo "     # or: open -a oMLX"
  echo ""
  echo "  3. Start Docker (required for MCP servers):"
  echo "     open -a Docker"
  echo ""
  echo "  4. Verify services:"
  echo "     bash ${SUBMODULE_PATH}/scripts/check-services.sh"
  echo ""
  echo "  5. Start OpenCode:"
  echo "     OPENCODE_ENABLE_EXA=1 opencode"
  echo ""
  echo -e "  ${CYAN}Agent pipeline:${NC} /mode scout → /mode plan → /mode dev → /mode qa → /mode mem"
  echo ""
  echo -e "  ${YELLOW}To update the submodule later:${NC}"
  echo "     bash ${SUBMODULE_PATH}/scripts/update-submodule.sh ${SUBMODULE_PATH}"
  echo ""
}

main() {
  banner
  check_prereqs
  validate_submodule
  create_symlinks
  merge_opencode_config
  create_directories
  setup_qmd
  update_gitignore
  print_next_steps
}

main "$@"