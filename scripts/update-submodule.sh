#!/usr/bin/env bash
set -euo pipefail

SUBMODULE_PATH="${1:-local-ai}"
PARENT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SUBMODULE_FULL="${PARENT_DIR}/${SUBMODULE_PATH}"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
YELLOW='\033[0;33m'
NC='\033[0m'

banner() {
  echo ""
  echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}║        OpenCode Agent Infrastructure — Update        ║${NC}"
  echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

check_submodule() {
  if [ ! -d "${SUBMODULE_FULL}" ]; then
    echo -e "${RED}✗${NC} Submodule not found at: ${SUBMODULE_FULL}"
    echo "  Run: git submodule add git@github.com:BarabasIstvanAttila/open-code-agents.git ${SUBMODULE_PATH}"
    exit 1
  fi

  if ! git config --file .gitmodules --get "submodule.${SUBMODULE_PATH}.url" &>/dev/null 2>&1; then
    echo -e "${RED}✗${NC} Not a registered submodule: ${SUBMODULE_PATH}"
    echo "  Add it first: git submodule add git@github.com:BarabasIstvanAttila/open-code-agents.git ${SUBMODULE_PATH}"
    exit 1
  fi
}

update_submodule() {
  echo -e "${BOLD}Pulling latest changes${NC}"
  echo "──────────────────────────"

  local before_commit
  before_commit="$(cd "${SUBMODULE_FULL}" && git rev-parse HEAD 2>/dev/null || echo "unknown")"

  cd "${PARENT_DIR}"

  git submodule update --remote --merge "${SUBMODULE_PATH}" 2>/dev/null || \
    (cd "${SUBMODULE_FULL}" && git pull origin main 2>/dev/null || git pull origin master 2>/dev/null)

  local after_commit
  after_commit="$(cd "${SUBMODULE_FULL}" && git rev-parse HEAD 2>/dev/null || echo "unknown")"

  if [ "${before_commit}" = "${after_commit}" ]; then
    echo -e "${GREEN}  ✓${NC} Already up to date (${after_commit:0:8})"
  else
    echo -e "${GREEN}  ✓${NC} Updated: ${before_commit:0:8} → ${after_commit:0:8}"

    echo ""
    echo -e "${BOLD}Changes:${NC}"
    cd "${SUBMODULE_FULL}" && git log --oneline "${before_commit}..${after_commit}" 2>/dev/null | head -10
  fi

  echo ""
}

relink_symlinks() {
  echo -e "${BOLD}Re-linking symlinks${NC}"
  echo "───────────────────"

  cd "${PARENT_DIR}"

  local relink_count=0

  for link in AGENTS.md opencode.json .opencode/agent .opencode/skills .opencode/package.json; do
    if [ -L "${link}" ]; then
      local current_target
      current_target="$(readlink "${link}")"
      local expected
      case "${link}" in
        AGENTS.md)           expected="${SUBMODULE_PATH}/AGENTS.md" ;;
        opencode.json)       expected="${SUBMODULE_PATH}/opencode.json" ;;
        .opencode/agent)     expected="${SUBMODULE_PATH}/.opencode/agent" ;;
        .opencode/skills)    expected="${SUBMODULE_PATH}/.opencode/skills" ;;
        .opencode/package.json) expected="${SUBMODULE_PATH}/.opencode/package.json" ;;
      esac

      if [ "${current_target}" != "${expected}" ]; then
        rm "${link}" && ln -s "${expected}" "${link}"
        echo -e "${GREEN}  ✓${NC} Re-linked: ${link} → ${expected}"
        relink_count=$((relink_count + 1))
      else
        echo -e "${CYAN}  ℹ${NC} OK: ${link} → ${current_target}"
      fi
    fi
  done

  if [ "${relink_count}" -eq 0 ]; then
    echo "  No symlinks needed updating."
  fi

  echo ""
}

reinstall_deps() {
  echo -e "${BOLD}Re-installing dependencies${NC}"
  echo "─────────────────────────────"

  if [ -L ".opencode/package.json" ] && command -v bun &>/dev/null; then
    cd "${PARENT_DIR}/.opencode" && bun install 2>/dev/null
    echo -e "${GREEN}  ✓${NC} .opencode/node_modules updated"
  else
    echo -e "${CYAN}  ℹ${NC} Skipped (no symlinked package.json or bun not found)"
  fi

  echo ""
}

rebuild_qmd() {
  echo -e "${BOLD}Rebuilding qmd index${NC}"
  echo "─────────────────────────"

  cd "${PARENT_DIR}"

  if command -v qmd &>/dev/null || command -v bunx &>/dev/null; then
    bunx @tobilu/qmd embed --changed 2>/dev/null || qmd embed --changed 2>/dev/null || true
    echo -e "${GREEN}  ✓${NC} qmd embeddings updated"
  else
    echo -e "${YELLOW}  ⚠${NC} qmd not available — run manually: qmd embed --changed"
  fi

  echo ""
}

print_summary() {
  echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${GREEN}║                 Update Complete                      ║${NC}"
  echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${CYAN}Verify services:${NC}  bash ${SUBMODULE_PATH}/scripts/check-services.sh"
  echo -e "  ${CYAN}Start OpenCode:${NC}   OPENCODE_ENABLE_EXA=1 opencode"
  echo ""
  echo -e "  ${YELLOW}Don't forget to commit the updated submodule reference:${NC}"
  echo "     git add ${SUBMODULE_PATH}"
  echo "     git commit -m \"chore: update ${SUBMODULE_PATH} submodule\""
  echo ""
}

main() {
  banner
  check_submodule
  update_submodule
  relink_symlinks
  reinstall_deps
  rebuild_qmd
  print_summary
}

main "$@"