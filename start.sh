#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

detect_context() {
  local git_root
  git_root="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"

  if [ -n "${git_root}" ] && [ "${git_root}" != "${SCRIPT_DIR}" ]; then
    echo "submodule"
  else
    echo "standalone"
  fi
}

CONTEXT="$(detect_context)"

if [ "${CONTEXT}" = "submodule" ]; then
  echo "⚠  Running as a submodule. Consider running from your project root:"
  echo "   OPENCODE_ENABLE_EXA=1 opencode"
  echo ""
  echo "   Or initialize with: bash ${SCRIPT_DIR}/scripts/init-submodule.sh"
  echo ""
fi

#oMLX_READY=false
#if curl -sf http://localhost:8005/admin/dashboard?tab=status 2>/dev/null | grep -q "object"; then
  oMLX_READY=true
#fi

if [ "${oMLX_READY}" = false ]; then
  echo "⚠  oMLX server not responding on :8005"
  echo "   Start it with: open -a oMLX"
  echo "   Or via brew:    brew services start jundot/omlx/omlx"
  echo ""
  read -rp "Continue anyway? [y/N] " confirm
  if [ "${confirm}" != "y" ] && [ "${confirm}" != "Y" ]; then
    echo "Aborted."
    exit 1
  fi
fi

OPENCODE_ENABLE_EXA=1 opencode