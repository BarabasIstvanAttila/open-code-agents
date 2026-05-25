#!/usr/bin/env bash
set -euo pipefail

echo "=== qmd Collection Setup ==="
echo ""

QMD_DIR="${HOME}/.config/qmd/memory"

mkdir -p "${QMD_DIR}/tasks"
mkdir -p "${QMD_DIR}/patterns"
mkdir -p "${QMD_DIR}/plans"
mkdir -p "${QMD_DIR}/research"

echo "Created directories:"
echo "  ${QMD_DIR}/tasks/"
echo "  ${QMD_DIR}/patterns/"
echo "  ${QMD_DIR}/plans/"
echo "  ${QMD_DIR}/research/"
echo ""

echo "Creating qmd collections..."

qmd collection create tasks "${QMD_DIR}/tasks" 2>/dev/null || echo "  Collection 'tasks' may already exist — skipping"
qmd collection create patterns "${QMD_DIR}/patterns" 2>/dev/null || echo "  Collection 'patterns' may already exist — skipping"
qmd collection create plans "${QMD_DIR}/plans" 2>/dev/null || echo "  Collection 'plans' may already exist — skipping"
qmd collection create research "${QMD_DIR}/research" 2>/dev/null || echo "  Collection 'research' may already exist — skipping"

echo ""
echo "Generating initial embeddings (may take 1-2 min on first run)..."
qmd embed

echo ""
echo "=== qmd Status ==="
qmd status

echo ""
echo "=== Setup Complete ==="