# Phase 2 (TODO) — automatic capture plugin

Status: **parked**. Phase 1 runs manually via `scripts/session-distill.sh`.

## Goal

Capture every OpenCode session automatically, with zero user action, then distill
in the background so the terminal is never blocked — ghost's core behavior.

## Reference implementation in ghost

- `src/hooks.ts` — hook entrypoints, payload parsing.
- `src/session.ts` — session file lifecycle (create, append prompts/writes,
  finalize), concurrency via one file per session id.
- `src/background.ts` — forked distill process, PID/state handling.
- `src/redact.ts` — secret redaction before anything is written.

## OpenCode mapping

Claude Code hooks have no direct OpenCode v2 equivalent. Use a **v2 plugin**
(`{ id, setup }` contract, see `opencode.ai/v2/docs/build/plugins`) subscribing
to events:

| Ghost hook | OpenCode event (verify names in V2 docs) | Action |
|---|---|---|
| SessionStart | session start event | create `.agent/sessions/active/<id>.md`, inject warm-resume brief |
| UserPromptSubmit | message part (user) | append prompt block |
| PostToolUse Write/Edit | file edited event | append modified path |
| Stop | session idle | append turn-completed timestamp |
| SessionEnd | session end/close | move to `completed/`, fork distill |

## Tasks

- [ ] Verify exact event names and payload shapes in the V2 plugin docs; write a
      spike plugin that only logs events to `.agent/sessions/spike.log`.
- [ ] Implement capture: one markdown file per session under `.agent/sessions/`,
      mirroring ghost's `session-example.md` format.
- [ ] Concurrency: session map keyed by session id; never share a file between
      concurrent sessions.
- [ ] Redaction: run the same secret guard as `scripts/distill-write.js` before
      writing; consider `opencode session export` (raw) + in-plugin redaction.
- [ ] Background distill: fork `scripts/session-distill.sh --session <id>` after
      session end; write PID/state under `.agent/sessions/.state/`.
- [ ] Register qmd collection `ghost-sessions` over `.agent/sessions/completed/`.
- [ ] Worktree rule: resolve `git rev-parse --git-common-dir` and store sessions
      under the main repo root (ghost does this).
- [ ] Config switch: `{env:GHOST_CAPTURE}` so capture can be disabled per shell.
- [ ] Tests: two concurrent sessions land in separate files; no capture when
      disabled; distill failure leaves raw session intact.

## Risks

- Plugin contract churn (context-mode's V1→V2 breakage is the cautionary tale).
- Event payloads may not include full prompt text; fall back to
  `opencode session export` on session end.
- Background forks must not outlive/duplicate on restarts — PID file + lock.
