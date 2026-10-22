# Phase 3 (TODO) — warm resume, analytics, AGENTS.md slimming

Status: **parked**. Depends on Phase 2 capture data.

## 1. Warm resume

Ghost injects context at session start when the same branch had a session in the
last 24 h: what you were working on, open items, decisions, and pitfalls —
scored by file overlap with current changes.

Implementation sketch:

- [ ] On session start, find the most recent completed session for the current
      branch (`git rev-parse --abbrev-ref HEAD`).
- [ ] If within 24 h, query qmd for that session's build record + decisions.
- [ ] Score mistakes/decisions by overlap with `git diff --name-only`
      (ghost's relevance rule).
- [ ] Inject a short brief (≤ ~40 lines) into the session start context.
- [ ] Never inject twice for the same session id.

Reference: ghost `src/session.ts` (resume logic), `knowledge.ts` (briefing).

## 2. Scope briefing

`ghost brief "<description>"` generates a pre-work context pack. Port as:

- [ ] `scripts/memory-brief.sh "<description>"` → qmd query + recent builds +
      open items + known pitfalls, printed as markdown.

## 3. Heatmap and stats

- [ ] `scripts/memory-heatmap.sh` — file-modification frequency across
      `memory/builds/` records and `.agent/sessions/`; supports `--tag`.
- [ ] `memory-stats.sh` — sessions distilled, decisions/mistakes per week,
      collection counts (qmd status + log.md).

Reference: ghost `heatmap`, `stats`, `validate` commands.

## 4. AGENTS.md slimming (`absorb`)

Ghost's `absorb` extracts verbose CLAUDE.md content into structured ledgers and
leaves a slim rules file.

- [ ] `scripts/agents-absorb.sh --dry-run` — propose sections to move from
      `AGENTS.md` into `memory/patterns/` + `memory/research/` concepts.
- [ ] Write-back only after human confirmation; keep `AGENTS.md.pre-absorb` copy.
- [ ] Target: AGENTS.md ≤ ~150 lines, every moved concept linked.

Reference: ghost `src/knowledge.ts` (`absorb`).

## 5. Git-notes convention

- [ ] Push notes explicitly: `git push origin refs/notes/ai-sessions`.
- [ ] Document in AGENTS.md that notes are local-only until pushed.
- [ ] Optional: `scripts/notes-log.sh` wrapper for
      `git log --show-notes=ai-sessions`.

## Exit criteria

- New session on an active branch shows a relevant brief without being asked.
- Heatmap identifies the most-edited files from session history.
- AGENTS.md shrinks without losing rules; moved content is qmd-searchable.
