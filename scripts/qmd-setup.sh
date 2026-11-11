#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${LOCALAI_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
QMD_CMD="bunx @tobilu/qmd"

echo "=== qmd Project-Local Setup ==="
echo "Project: ${PROJECT_DIR}"
echo ""

echo "Initializing project-local qmd index..."
cd "${PROJECT_DIR}"
${QMD_CMD} init

MEMORY_DIR="${PROJECT_DIR}/memory"

mkdir -p "${MEMORY_DIR}/tasks"
mkdir -p "${MEMORY_DIR}/patterns"
mkdir -p "${MEMORY_DIR}/plans"
mkdir -p "${MEMORY_DIR}/research"
mkdir -p "${MEMORY_DIR}/builds"
mkdir -p "${MEMORY_DIR}/decisions"
mkdir -p "${MEMORY_DIR}/mistakes"
mkdir -p "${MEMORY_DIR}/ghost"

echo "Created memory directories:"
echo "  ${MEMORY_DIR}/tasks/"
echo "  ${MEMORY_DIR}/patterns/"
echo "  ${MEMORY_DIR}/plans/"
echo "  ${MEMORY_DIR}/research/"
echo "  ${MEMORY_DIR}/builds/"
echo "  ${MEMORY_DIR}/decisions/"
echo "  ${MEMORY_DIR}/mistakes/"
echo "  ${MEMORY_DIR}/ghost/  (reference area, excluded from lint/prune)"
echo ""

mkdir -p "${PROJECT_DIR}/.agent"
echo "Created .agent/ directory"
echo ""

echo "Creating qmd collections..."

${QMD_CMD} collection add "${MEMORY_DIR}/tasks" --name tasks 2>/dev/null || echo "  Collection 'tasks' may already exist — skipping"
${QMD_CMD} collection add "${MEMORY_DIR}/patterns" --name patterns 2>/dev/null || echo "  Collection 'patterns' may already exist — skipping"
${QMD_CMD} collection add "${MEMORY_DIR}/plans" --name plans 2>/dev/null || echo "  Collection 'plans' may already exist — skipping"
${QMD_CMD} collection add "${MEMORY_DIR}/research" --name research 2>/dev/null || echo "  Collection 'research' may already exist — skipping"
${QMD_CMD} collection add "${MEMORY_DIR}/builds" --name builds 2>/dev/null || echo "  Collection 'builds' may already exist — skipping"
${QMD_CMD} collection add "${MEMORY_DIR}/decisions" --name decisions 2>/dev/null || echo "  Collection 'decisions' may already exist — skipping"
${QMD_CMD} collection add "${MEMORY_DIR}/mistakes" --name mistakes 2>/dev/null || echo "  Collection 'mistakes' may already exist — skipping"
${QMD_CMD} collection add "${MEMORY_DIR}/ghost" --name ghost 2>/dev/null || echo "  Collection 'ghost' may already exist — skipping"

echo ""
echo "Generating initial embeddings (may take 1-2 min on first run)..."
${QMD_CMD} embed

echo ""
echo "=== qmd Status ==="
${QMD_CMD} status

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Project-local layout:"
echo "  .qmd/index.yaml    — qmd config"
echo "  .qmd/index.sqlite  — search index"
echo "  memory/tasks/      — task summaries"
echo "  memory/patterns/   — code patterns"
echo "  memory/plans/      — archived plans"
echo "  memory/research/   — archived research"
echo "  memory/builds/     — per-task build records"
echo "  memory/decisions/  — decision log (type: decision)"
echo "  memory/mistakes/   — mistake ledger (type: mistake)"
echo "  memory/ghost/      — ghost reference area (not linted/pruned)"
echo "  .agent/            — agent working files"
