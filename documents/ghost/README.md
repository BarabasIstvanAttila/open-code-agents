# Ghost-inspired memory setup

This folder tracks the adoption of [notkurt/ghost](https://github.com/notkurt/ghost)
ideas into the local OpenCode memory system. Reference material lives in
[`memory/ghost/`](../../memory/ghost/README.md).

## Design

Two layers, kept separate:

| Layer | Where | Trigger | Contents |
|-------|-------|---------|----------|
| **Capture** | `.agent/sessions/` (Phase 2) | automatic plugin events | raw session markdown |
| **Curation** | `memory/` | explicit, lint-gated writes | OKF concepts, one per file |

Distillation converts capture into curation; qmd indexes the curation layer.
Nothing raw is versioned — only distilled concepts and build records.

## Phases

| Phase | Scope | Status |
|-------|-------|--------|
| **1** | `memory/decisions/` + `memory/mistakes/` collections, `scripts/session-distill.sh` (manual), `/distill` + `/prune` commands | **implemented** |
| **2** | OpenCode v2 plugin: automatic capture on session events, background distill, `.agent/sessions/`, qmd `ghost-sessions` collection | parked — [todo](phase-2-capture-plugin.todo.md) |
| **3** | Warm-resume injection, file-modification heatmap, `absorb`-style AGENTS.md slimming, git-notes push convention | parked — [todo](phase-3-warm-resume-analytics.todo.md) |

## Phase 1 usage

```sh
scripts/session-distill.sh                 # newest session
scripts/session-distill.sh --session ses_… # specific session
scripts/session-distill.sh --dry-run       # summary only, writes nothing
scripts/session-distill.sh --force         # re-distill
scripts/session-distill.sh --note          # also git-note HEAD
```

In the TUI: `/distill [args]` and `/prune [--days N]`.

Outputs per session: `memory/decisions/*.md`, `memory/mistakes/*.md`,
`memory/builds/*.md`, one `memory/log.md` line, qmd index update, optional git
note on `refs/notes/ai-sessions`.

Guardrails: idempotency derived from the versioned memory records themselves
(the session id is greppable in builds/decisions/mistakes), deterministic
frontmatter/slug writing, secret-pattern refusal, lint gate, dry-run mode.

## Rollback

Phase 1 adds files only; nothing existing changes behavior except the lint/prune
exclusions and three new qmd collections. To remove: delete
`scripts/session-distill.sh`, `scripts/distill-write.js`,
`templates/session-distill-prompt.md`, `memory/decisions/`,
`memory/mistakes/`, `.opencode/commands/{distill,prune}.md`, then revert the
collection registrations in `.qmd/index.yml` with
`bunx @tobilu/qmd collection remove <name>`.
