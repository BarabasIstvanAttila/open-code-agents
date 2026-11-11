# open-code-agents

Local-first AI agent infrastructure for OpenCode. Four agents (`researcher`, `plan`, `build`, `orchestrator`) share a curated, qmd-indexed knowledge base, a session-distillation pipeline, and one-command wiring for consuming repositories — all running locally through OpenCode.

**Use case**: Add this repository as a Git submodule to any project to give it the full agent pipeline, persistent memory, and MCP tooling.

---

## Architecture

```
  Your Project
   │
   ├── .harness/                 ← This submodule
   │   ├── opencode.json         ← Providers, MCP servers, tools
   │   ├── AGENTS.md             ← Agent routing rules and working conventions
   │   ├── .opencode/
   │   │   ├── agent/            ← researcher, plan, orchestrator (build is built-in)
   │   │   ├── commands/         ← /ctx, /distill, /prune
   │   │   └── skills/           ← OpenCode skills
   │   ├── scripts/              ← Setup, memory, distill, maintenance
   │   ├── templates/            ← OKF frontmatter + distill prompt templates
   │   └── documents/ghost/      ← Ghost adoption notes (Phase 2/3 parked)
   │
   ├── .opencode/
   │   ├── agent    → .harness/.opencode/agent      (symlink)
   │   └── commands → .harness/.opencode/commands   (symlink)
   ├── scripts/                  ← LOCALAI_ROOT wrappers (distill, lint, prune)
   ├── .agent/                   ← Agent working files (gitignored)
   ├── .qmd/                     ← qmd index (gitignored)
   └── memory/                   ← Persistent knowledge base (versioned)
       ├── tasks/ patterns/ plans/ research/ builds/
       └── decisions/ mistakes/ ghost/
```

### Agent Pipeline

| Agent | Source | Mode | Model | Role |
|-------|--------|------|-------|------|
| **researcher** | `.opencode/agent/researcher.md` | primary | opencode-go/deepseek-v4-flash | Read-only research — maps the codebase, fetches docs, writes only `.agent/research-report.md` |
| **plan** | `.opencode/agent/plan.md` | primary | opencode-go/kimi-k3 | File-specific implementation plan, 3-round cap, writes only `.agent/plan.md` |
| **build** | OpenCode built-in | primary | opencode/glm-5.1 | Implements the plan step by step, edits files, runs commands |
| **orchestrator** | `.opencode/agent/orchestrator.md` | primary | opencode-go/deepseek-v4-flash | Autonomous container loop — goal → plan → implement → verify (local Docker, one container at a time, curl + Playwright) |

Typical flows:

```
Manual:         /mode researcher → /mode plan → /mode build
Container loop: /mode orchestrator   (iterates plan → implement → verify until DoD green)
```

Built-in `explore` and `general` subagents handle delegated and parallel research.

### Model routing

- **Cloud (opencode-go)** — default for the pipeline: `deepseek-v4-flash` for researcher/orchestrator, `kimi-k3` for plan, `glm-5.1` for build.
- **Local (oMLX)** — retained for manual local-only runs via the `omlx/` provider on port 8005 (`Qwen3.5-9B-OptiQ-4bit`, 32K context). Not a pipeline default.

---

## Memory System

Two layers, kept separate:

| Layer | Where | Trigger | Contents |
|-------|-------|---------|----------|
| **Curation** | `memory/` (versioned) | explicit, lint-gated writes | OKF concepts, one per file |
| **Capture** | `.agent/` (gitignored) | manual distill today; plugin events in Phase 2 | raw transcripts and summaries |

### Collections

| Directory | `type` | Holds |
|-----------|--------|-------|
| `memory/tasks/` | `task` | Task summaries — what was asked, what shipped |
| `memory/patterns/` | `pattern` | Reusable code and configuration patterns |
| `memory/plans/` | `plan` | Archived implementation plans |
| `memory/research/` | `research` | Research findings and source digests |
| `memory/builds/` | `build` | Per-session build records, session id + commit binding |
| `memory/decisions/` | `decision` | Technical decisions with context and reasoning |
| `memory/mistakes/` | `mistake` | Pitfalls and the rule that prevents a repeat |
| `memory/ghost/` | — | Ghost reference area (non-OKF; excluded from lint/prune, indexed for search) |

`memory/index.md` is the human map; `memory/log.md` is the append-only change log.
Both are excluded from lint and indexing.

### OKF frontmatter

Every concept file starts with:

```yaml
---
type: decision          # required; equals the singular collection name
title: Short human title (must match the H1)
description: Two sentences max — lands in the reranker's first chunk.
tags: [memory, qmd]
timestamp: 2026-10-22   # YYYY-MM-DD; used by retention
status: active          # optional: active | archived | superseded
superseded_by: memory/decisions/newer.md  # only with status: superseded
---
```

Rules: one concept per file, slug filename, plain relative links between
concepts. Full template: `templates/memory-frontmatter.md`.

Write path: create the file → `scripts/memory-lint.sh` → `bunx @tobilu/qmd update`
(+ `embed` for new content) → one line in `memory/log.md`.

### Session distillation

Turn a finished OpenCode session into durable memory:

```bash
scripts/session-distill.sh                 # newest non-distill session
scripts/session-distill.sh --session ses_… # specific session
scripts/session-distill.sh --dry-run       # summarize + show planned files, write nothing
scripts/session-distill.sh --force         # re-distill an already-processed session
scripts/session-distill.sh --note          # also attach a git note to HEAD
scripts/session-distill.sh --model <id>    # override the summarizer model
```

Pipeline:

```
opencode session export (raw, local only)
  → transcript compaction (~12 KB: prompts, assistant text, touched files)
  → free model summary (six sections: Intent / Changes / Decisions / Mistakes / Open Items / Tags)
  → scripts/distill-write.js  (deterministic writer: frontmatter, slugs, secret gate)
  → memory/decisions/ + memory/mistakes/ + memory/builds/
  → memory-lint.sh → qmd update → memory/log.md
  → optional: git notes --ref=ai-sessions on HEAD
```

Guarantees:

- **The model writes prose only** — frontmatter, filenames, and paths are script-owned.
- **Secret gate** — `sk-…`, `ghp_…`, `AKIA…`, and private-key blocks abort the write (exit 3).
- **Idempotent** — the script greps the versioned memory records for the session id; no bookkeeping file.
- **Dry run** — full summary, zero writes.

### Commands

| Command | Arguments | What it does |
|---------|-----------|--------------|
| `/distill` | `[ses_…] [--dry-run] [--force] [--note]` | Runs the session distiller |
| `/prune` | `[--days N]` | Dry-run list → confirmation → archive + qmd cleanup |
| `/ctx` | `<task>` | Runs a task strictly through context-mode tools |

Commands require an OpenCode restart after installation to appear.

### Retention

qmd has **no TTL** — documents expire only when files leave a collection path.

```bash
scripts/memory-prune.sh --dry-run     # preview
scripts/memory-prune.sh --days 90     # archive older than 90 days
scripts/memory-prune.sh               # default 180 days
```

Files are moved to `memory/.archive/<collection>/` when `status: archived` or
older than N days (unless tagged `keep`), then `qmd update` marks them inactive
and `qmd cleanup` hard-deletes rows, orphans, caches, and vacuums.
`memory/ghost/` is never pruned. Pruning archives; it never destroys.

### Retrieval

```bash
bunx @tobilu/qmd query "type decision session-distill"   # hybrid + rerank
bunx @tobilu/qmd search "qmd frontmatter"                 # BM25 only
bunx @tobilu/qmd get memory/decisions/<file>.md
```

Frontmatter is indexed as text, not metadata. Avoid `type:decision` (FTS5 reads
the colon as a column filter); search the literal token without a colon.

### Ghost adoption

`memory/ghost/` holds the reference notes on
[notkurt/ghost](https://github.com/notkurt/ghost): the capture-vs-curation
design, session/ledger formats, and the source map. Phase 1 (ledgers + manual
distill) is shipped; Phase 2 (automatic capture plugin) and Phase 3 (warm
resume, analytics, AGENTS.md slimming) are parked in `documents/ghost/`.

---

## Quick Start (Standalone)

```bash
git clone <this-repo>
cd open-code-agents

# Prerequisites
brew install bun                      # or: curl -fsSL https://bun.sh/install | bash
npm install -g opencode-ai
npm install -g @tobilu/qmd            # or use: bunx @tobilu/qmd

# Optional environment
export OMLX_API_KEY="your-key"        # only for local oMLX runs
export CONTEXT7API="your-key"         # Context7 docs lookup

# Initialize memory + search index
./scripts/qmd-setup.sh

# Verify services
./scripts/check-services.sh

# Start OpenCode
OPENCODE_ENABLE_EXA=1 opencode
```

---

## Using as a Git Submodule

This is the primary use case. The harness pins the agent definitions while the
consuming repo owns its `memory/` and `.qmd/` index.

### Add the submodule

```bash
# From your project root
git submodule add <this-repo-url> .harness
git submodule update --init

# Wire the host repo
bash .harness/scripts/bootstrap-host.sh
```

`bootstrap-host.sh` (idempotent, non-destructive):

0. **Migration** — removes legacy root symlinks (`AGENTS.md`, `opencode.json`)
   that point into the harness (old `init-submodule.sh` wiring).
1. **Global MCP** — merges the 6 shared servers + tool enables into
   `~/.config/opencode/opencode.json`, keeping existing entries. They then apply
   to every project on the machine.
2. **Symlinks** — `.opencode/agent` and `.opencode/commands` → harness.
3. **Wrappers** — `scripts/{session-distill,memory-lint,memory-prune}.sh` with
   `LOCALAI_ROOT` set to the host root.
4. **Instructions** — merges `.harness/AGENTS.md` into the host `opencode.json`.
5. **Host memory** — creates the host's own `memory/` (8 collections) and a
   project-local `.qmd` index.

Flags: `--harness <path>`, `--skip-global-mcp`, `--context-mode-path <path>`,
`--dry-run`.

Old setups — root `AGENTS.md` / `opencode.json` symlinks into the harness, created
by the retired `init-submodule.sh` — are migrated automatically: bootstrap
removes those symlinks, replaces `opencode.json` with a real host-owned file, and
wires the new layout. Re-add any host-specific providers/permissions afterwards.

### Fresh clone of a project that already uses the submodule

```bash
git clone <your-project-url>
cd <your-project>
git submodule update --init
bash .harness/scripts/bootstrap-host.sh
```

### Update the harness

```bash
git submodule update --remote .harness
bash .harness/scripts/bootstrap-host.sh    # refresh links/wrappers
git add .harness && git commit -m "chore: update harness submodule"
```

### Remove the submodule

```bash
rm -rf .opencode/agent .opencode/commands scripts/session-distill.sh \
       scripts/memory-lint.sh scripts/memory-prune.sh
git submodule deinit -f .harness
git rm -f .harness
rm -rf .git/modules/.harness
git commit -m "chore: remove harness submodule"
```

---

## Submodule Operations

| Operation | Command |
|-----------|---------|
| Initialize (first time) | `git submodule add <url> .harness && git submodule update --init && bash .harness/scripts/bootstrap-host.sh` |
| Initialize (fresh clone) | `git submodule update --init && bash .harness/scripts/bootstrap-host.sh` |
| Update | `git submodule update --remote .harness && bash .harness/scripts/bootstrap-host.sh` |
| Status | `git submodule status .harness` |
| Re-link after git operations | `bash .harness/scripts/bootstrap-host.sh --skip-global-mcp` |

---

## Configuration

### Global MCP config

`~/.config/opencode/opencode.json` holds the shared servers and applies to every
project:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": { /* context-mode, context7, duckduckgo, sequentialthinking, qmd, playwright */ },
  "tools": { "context-mode*": true, "qmd*": true, /* … */ }
}
```

Project configs override global per server name.

### Host `opencode.json`

`bootstrap-host.sh` merges the only required key:

```jsonc
{
  "instructions": [".harness/AGENTS.md"]
}
```

Add host-specific providers, permissions, or agents normally.

### Environment variables

| Variable | Required | Description |
|----------|----------|-------------|
| `OMLX_API_KEY` | Optional | Local oMLX server key (manual local runs only) |
| `CONTEXT7API` | Yes for Context7 | Documentation lookup key |
| `OPENCODE_ENABLE_EXA` | Optional | Set to `1` to enable Exa search |

### MCP servers

| Server | Type | Purpose |
|--------|------|---------|
| **context-mode** | Local (`bun …/cli.bundle.mjs`) | Sandboxed I/O, context protection |
| **context7** | Remote | Library documentation lookup |
| **duckduckgo** | Docker | Web search |
| **sequentialthinking** | Docker | Structured reasoning chains |
| **qmd** | Local (`bunx @tobilu/qmd mcp`) | Persistent semantic memory |
| **playwright** | Local (`bunx @playwright/mcp`) | Browser verification |

> **Note:** context-mode runs as an **MCP server**, not a V1 plugin — OpenCode v2
> removed the plugin contract it used. Routing rules are prompt-level. Expected
> `ctx_doctor` warnings about plugin/legacy-MCP registration are documented in
> `memory/research/context-mode-incidents.md`.

---

## Working Files

Gitignored (per-host, disposable):

```
.agent/
├── research-report.md      ← researcher output
├── plan.md                 ← plan agent output
├── orchestrator/           ← loop state (goal, plan-N, findings-N, verify/)
├── sessions/               ← Phase 2 capture (parked)
└── tmp/                    ← raw exports, distill logs

.qmd/                       ← project-local qmd index
```

Versioned with the host repo:

```
memory/                     ← 8 OKF collections + index.md + log.md
```

---

## Prerequisites

| Software | Version | Install |
|----------|---------|---------|
| **bun** | latest | `curl -fsSL https://bun.sh/install \| bash` |
| **OpenCode** | v2 | `npm install -g opencode-ai` |
| **qmd** | latest | `npm install -g @tobilu/qmd` or `bunx @tobilu/qmd` |
| **Docker** | latest | For duckduckgo + sequentialthinking MCP servers |
| **oMLX** | latest | Optional — local models on port 8005 |
| **sqlite** (macOS) | — | `brew install sqlite` (qmd dependency) |

---

## Project Structure

```
open-code-agents/
├── AGENTS.md                    ← Agent routing rules, context-mode contract, memory conventions
├── opencode.json                ← OpenCode config (providers, MCP, tools)
├── opencode.json.tui-migration.bak
├── tui.json                     ← Terminal UI settings
├── start.sh                     ← Start OpenCode with EXA enabled
├── README.md / SETUP.md / Install.md
├── .opencode/
│   ├── agent/{researcher,plan,orchestrator}.md
│   ├── commands/{ctx,distill,prune}.md
│   ├── skills/{skill-builder,esp32-idf,esp32-patterns,docker-loop,homelab-deploy,…}
│   └── package.json
├── scripts/
│   ├── bootstrap-host.sh        ← Wire a consuming repo (Strategy A)
│   ├── bootstrap-merge.js       ← Non-destructive config merges
│   ├── session-distill.sh       ← Session → memory pipeline
│   ├── distill-write.js         ← Deterministic OKF writer
│   ├── memory-lint.sh           ← Frontmatter + link validation
│   ├── memory-prune.sh          ← Retention + qmd cleanup
│   ├── qmd-setup.sh             ← Collections + index init (honors LOCALAI_ROOT)
│   ├── init-esp32.sh / check-esp32.sh
│   └── check-services.sh
├── templates/
│   ├── memory-frontmatter.md
│   └── session-distill-prompt.md
├── documents/ghost/             ← Phase 2/3 TODOs + setup README
├── memory/                      ← 8 OKF collections (versioned)
└── .agent/                      ← Agent working files (gitignored)
```

---

## How It Works

1. **OpenCode discovery** — the host's `opencode.json` points at
   `.harness/AGENTS.md`; agents and commands are symlinked into `.opencode/`.
2. **Memory root** — `LOCALAI_ROOT` makes the harness scripts read/write the
   host's `memory/` and `.qmd/`, not the submodule's.
3. **Curation** — agents write OKF concepts; lint gates structure; qmd indexes
   for hybrid retrieval (BM25 + vectors + reranker).
4. **Capture** — `session-distill.sh` summarizes a session with a free model and
   writes decision/mistake/build records. Raw transcripts never enter versioned
   memory.
5. **Retention** — `memory-prune.sh` archives stale notes and cleans the index;
   `memory/ghost/` and `keep`-tagged files are exempt.

---

## Quick Reference

### Scripts

| Script | Purpose |
|--------|---------|
| `bootstrap-host.sh` | Wire a consuming repo: global MCP, symlinks, wrappers, memory |
| `bootstrap-merge.js` | Internal merge helper for `bootstrap-host.sh` |
| `session-distill.sh` | Distill a session into decisions/mistakes/build records |
| `distill-write.js` | Internal deterministic writer + secret gate |
| `memory-lint.sh` | Validate OKF frontmatter and relative links |
| `memory-prune.sh` | Archive stale notes; run `qmd update` + `cleanup` |
| `qmd-setup.sh` | Create collections and index (8 collections) |
| `init-esp32.sh` / `check-esp32.sh` | ESP-IDF LSP setup / verification |
| `check-services.sh` | Verify oMLX, qmd, context-mode, bun, opencode |

### Commands

| Command | Purpose |
|---------|---------|
| `/ctx <task>` | Execute strictly through context-mode tools |
| `/distill [args]` | Distill a session into memory |
| `/prune [--days N]` | Dry-run → confirm → archive + cleanup |
| `/esp-build`, `/esp-check`, `/esp-flash`, … | ESP-IDF helpers (after `init-esp32.sh`) |

---

## ESP32/ESP-IDF Development

This system supports ESP32 development with full LSP integration through
`esp-clangd`.

### Quick Start

```bash
# In your ESP-IDF project directory:
. $IDF_PATH/export.sh
bash path/to/.harness/scripts/init-esp32.sh
opencode
```

### Features

- **LSP via esp-clangd** — cross-compiler-aware (Xtensa + RISC-V), diagnostics without a full build
- **Two domain skills**: `esp32-idf` (toolchain) and `esp32-patterns` (FreeRTOS, drivers, NVS, C++ idioms)
- **Auto-generated `compile_commands.json`** — refresh with `idf.py reconfigure`
- **IDF-aware shell wrapper** — every agent bash command has the ESP-IDF environment pre-sourced
- **Custom slash commands** — `/esp-build`, `/esp-check`, `/esp-flash`, `/esp-size`, `/esp-new-component`

### Available Skills

| Skill | Description | When to load |
|-------|-------------|--------------|
| `esp32-idf` | Toolchain: idf.py, LSP triage, build/flash/debug | Running build commands, interpreting errors |
| `esp32-patterns` | Domain patterns: FreeRTOS, GPIO, SPI/I2C, NVS, C++ | Designing components, writing drivers |

### Signal Trust Order

1. `idf.py build` output → ground truth
2. `idf.py monitor` output → runtime truth
3. LSP diagnostics → fast edit-time signal (may be stale)

### Safety Rules

- Never mark a task done without a clean `idf.py build`
- Never edit files in `build/` or `managed_components/`
- `idf.py flash` and `idf.py erase_flash` require user confirmation

---

## Troubleshooting

### `ctx_workflow` / unknown context-mode tool

The context-mode tool set is closed: `ctx_execute`, `ctx_execute_file`,
`ctx_batch_execute`, `ctx_fetch_and_index`, `ctx_index`, `ctx_search`,
`ctx_purge`, `ctx_insight`, `ctx_doctor`, `ctx_stats`, `ctx_upgrade`.
Any other name is a hallucination; OpenCode's validator will suggest the correct
tool. If an agent loops, tell it to call `search(namespace: "context-mode")`
first.

### oMLX not responding

```bash
curl -s http://127.0.0.1:8005/v1/models | head -5
# If empty or error, start oMLX:
open -a oMLX
```

### oMLX lags before the first token

The configured model (`Qwen3.5-9B-OptiQ-4bit`) is tuned for
`32K context / 4K output`. Do not raise context to 256K — local models hang.
Enable **context scaling** in the oMLX admin dashboard
(http://127.0.0.1:8005/admin) so compaction triggers earlier.

### Docker MCP servers failing

```bash
docker ps
docker pull mcp/duckduckgo
docker pull mcp/sequentialthinking
```

### qmd errors

```bash
which qmd            # or: bunx @tobilu/qmd --version
bunx @tobilu/qmd status
bunx @tobilu/qmd init   # re-initialize if the project index is missing
```

### Broken symlinks after git operations

```bash
bash .harness/scripts/bootstrap-host.sh --skip-global-mcp
```

### Distill issues

```bash
ls .agent/tmp/                      # raw export, summary, stderr from the last run
scripts/session-distill.sh --dry-run --session ses_…
scripts/session-distill.sh --force --session ses_…   # already distilled
```

If lint fails after a distill, the files are still written; fix the reported
frontmatter rather than forcing green.

### Prune safety

Always start with `--dry-run`. Prune moves files to `memory/.archive/` and then
runs `qmd update && cleanup`; `rm` is never used.

### context-mode not found

context-mode is an MCP server, not a plugin. Verify the entry in
`~/.config/opencode/opencode.json` and that
`/Users/atti/node_modules/context-mode/cli.bundle.mjs` exists. Re-run
`bootstrap-host.sh` to re-seed the global block.

---

## Articles

- https://github.com/criterium/opencode-lab/tree/main/research/memory-system
- https://mariozechner.at/posts/2026-03-25-thoughts-on-slowing-the-fuck-down/
- https://walkinglabs.github.io/learn-harness-engineering/en/
- https://mcpmarket.com/
- https://grokkingthesystemdesign.com/guides/agentic-system-design/#multi-agent-system-design-and-coordination-patterns
- https://datasciencedojo.com/blog/agentic-loops-explained-from-react-to-loop-engineering-2026-guide/
- https://pi.dev/packages/pi-knowledge
- https://annycedavis.com/2026/09/tokens-rule-everything-around-me.html
- https://cloud.google.com/blog/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing
- https://aaif.io/projects/goose
- https://github.com/jellydn/my-ai-tools

## License

This project is designed to be used as a submodule. See the repository for license details.
