#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
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

echo "Created memory directories:"
echo "  ${MEMORY_DIR}/tasks/"
echo "  ${MEMORY_DIR}/patterns/"
echo "  ${MEMORY_DIR}/plans/"
echo "  ${MEMORY_DIR}/research/"
echo ""

mkdir -p "${PROJECT_DIR}/.agent"
echo "Created .agent/ directory"
echo ""

echo "Creating qmd collections..."

${QMD_CMD} collection add "${MEMORY_DIR}/tasks" --name tasks 2>/dev/null || echo "  Collection 'tasks' may already exist — skipping"
${QMD_CMD} collection add "${MEMORY_DIR}/patterns" --name patterns 2>/dev/null || echo "  Collection 'patterns' may already exist — skipping"
${QMD_CMD} collection add "${MEMORY_DIR}/plans" --name plans 2>/dev/null || echo "  Collection 'plans' may already exist — skipping"
${QMD_CMD} collection add "${MEMORY_DIR}/research" --name research 2>/dev/null || echo "  Collection 'research' may already exist — skipping"

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
echo "  .agent/            — agent working files"
