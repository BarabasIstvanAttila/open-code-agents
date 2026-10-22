# memory log — append-only

Newest first. One line per change: `YYYY-MM-DD — what changed — why`.

- 2026-10-22 — Distill idempotency now derives from versioned memory records (grep builds/decisions/mistakes); dropped .agent/distilled-sessions.txt — state travels with the repo, nothing to recover after .agent/ is wiped
- 2026-10-22 — Ghost Phase 1 adopted — added memory/decisions/ + memory/mistakes/ collections, memory/ghost/ reference area, session-distill pipeline (+ /distill, /prune) — Phase 2/3 parked in documents/ghost/
- 2026-10-22 — distilled session ses_e9b4af32dffenfJE48t0RCT8M6 — 10 decisions, 2 mistakes, 1 build record (memory/decisions/, memory/mistakes/, memory/builds/)
- 2026-10-22 — Rewrote the context-mode section in `AGENTS.md` to a route-by-intent table and moved the incident history to `research/context-mode-incidents.md`; added `/ctx` and `/ctx/recall` commands — keeps the always-loaded contract short while making routing callable.
- 2026-10-22 — Baseline measured and recorded at `research/qmd-okf-baseline.md`; documented that FTS5 rejects `type:pattern` (column-filter syntax) and that `type pattern` works — prevents a class of empty-result queries.
- 2026-10-22 — Adopted OKF frontmatter across `memory/`; added `scripts/memory-lint.sh`, `scripts/memory-prune.sh`, and seeded one concept per collection — gives qmd, humans, and agents one structure, with file-based retention to replace the missing TTL.
- 2026-10-22 — Research digest added at `research/okf-frontmatter-qmd.md` — captures the qmd rerank pipeline and cleanup lifecycle verified against `@tobilu/qmd` 2.5.2.
