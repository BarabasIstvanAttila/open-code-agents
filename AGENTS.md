# OpenCode Agent Configuration — Rules & Learnings

**oMLX · qmd · context-mode · OpenCode**  
*Four agents: built-in `build` plus custom `plan`, `researcher`, and `orchestrator`. Free cloud models via opencode-go (deepseek-v4-flash + kimi-k3); oMLX retained for manual use.*

---

## Agents

```
/mode researcher → read-only research → .agent/research-report.md
/mode plan    → file-specific implementation plan from research (3-round cap)
/mode build   → implement the plan (OpenCode default agent, default_agent in opencode.json)
/mode orchestrator → autonomous container loop (local Docker, one container at a time)
```

| Agent | Source | Mode | Model | Role |
|-------|--------|------|-------|------|
| **researcher** | `.opencode/agent/researcher.md` (custom) | primary | opencode-go/deepseek-v4-flash (cloud-free) | Research — read-only codebase mapping + doc fetches, writes only `.agent/research-report.md` |
| **plan** | `.opencode/agent/plan.md` (custom) | primary | opencode-go/kimi-k3 (cloud) | Plan — 3-round cap, produce file-specific plan |
| **build** | OpenCode built-in | primary | opencode/glm-5.1 | Implement — follow the plan step by step, edit files, run commands |
| **orchestrator** | `.opencode/agent/orchestrator.md` (custom) | primary | opencode-go/deepseek-v4-flash (cloud-free) | Container loop — goal→plan→implement→verify locally (one container at a time, curl + Playwright browser), findings-driven iterations (uses `docker-loop` skill) |

Built-in subagents (`explore`, `general`) handle delegated research and parallel work; no project-local subagents are defined.

### Working files (per project, git-ignored)

```
.agent/
├── research-report.md   ← researcher output (only file it may write)
├── plan.md              ← plan agent output
└── orchestrator/        ← orchestrator loop state (goal.md, plan-N.md, findings-N.md, report.md, verify/)
```

### Persistent memory (indexed by qmd, OKF frontmatter)

```
memory/                    ← project-local (versioned with repo)
├── index.md             ← map (not indexed)
├── log.md               ← append-only change log (not indexed)
├── tasks/               ← task summaries          type: task
├── patterns/            ← code patterns           type: pattern
├── plans/               ← archived plans          type: plan
├── research/            ← archived research       type: research
├── builds/              ← build records           type: build
├── decisions/           ← decision log            type: decision
├── mistakes/            ← mistake ledger          type: mistake
├── ghost/               ← ghost reference area    (not linted/pruned)
└── .archive/            ← pruned files (not indexed)
```

Every concept file starts with OKF frontmatter (`type`, `title`, `description`,
`tags`, `timestamp`); `type` is the singular collection name (`tasks/`→`task`).
Template:
`templates/memory-frontmatter.md`. Validate with `scripts/memory-lint.sh`.
Retention: `scripts/memory-prune.sh [--days N] [--dry-run]` moves stale or
`status: archived` files to `.archive/` and runs `qmd update && qmd cleanup`
(qmd has no TTL of its own). Session capture: `scripts/session-distill.sh
[--session ses_…] [--dry-run] [--note]` turns a session into
decisions/mistakes/build records (or use `/distill`); `/prune` runs retention
with a dry-run confirmation gate.

---

## Architecture

```
  User
   │
   │  /mode researcher  /mode plan  /mode build  /mode orchestrator
   ▼  ────────────────  ──────────  ───────────  ──────────────────
  OpenCode (terminal)
   │
   ├─ researcher ─► OpenCode (deepseek-v4-flash, cloud-free) — read-only; writes only .agent/research-report.md
   ├─ plan  ──► OpenCode (kimi-k3, cloud) — writes .agent/plan.md, edit denied elsewhere
   ├─ build ──► OpenCode (glm-5.1, default) — implements the plan
   ├─ orchestrator ─► OpenCode (deepseek-v4-flash, cloud-free) — autonomous container loop
   │
   ├─ context-mode MCP ─── sandboxed execution (MANDATORY — all agents route I/O through this)
   ├─ qmd MCP ──────────── local semantic search (query, get, multi_get, status)
   ├─ context7 MCP ─────── library documentation lookup
   ├─ duckduckgo MCP ──── web search
   ├─ playwright MCP ──── browser verification (orchestrator loop; headless chromium via bunx)
   └─ sequentialthinking ─ structured reasoning chains
```

---

## context-mode — MANDATORY routing rules

One unrouted command dumps 56 KB into context. All I/O goes through the context-mode MCP server.

> **Transport:** local MCP server — `mcp.context-mode` in `opencode.json`
> (`bun /Users/atti/node_modules/context-mode/cli.bundle.mjs`,
> `CONTEXT_MODE_PLATFORM=opencode`, v1.0.151). Routing is **prompt-level only** —
> no plugin hook enforces the BLOCKED list. `ctx_doctor` warnings about plugin /
> legacy-MCP registration are expected. Restore the plugin only when upstream
> ships an OpenCode v2 `setup()` export. History: `memory/research/context-mode-incidents.md`.

### Route by intent

| Intent | Tool |
|--------|------|
| Read a web page | `ctx_fetch_and_index(url, source)` → `ctx_search(queries)` |
| HTTP call / API probe | `ctx_execute("javascript", "await fetch(...)")` |
| Shell, >20 lines of output | `ctx_execute("shell", code)` or `ctx_batch_execute(commands, queries)` |
| Analyze a file | `ctx_execute_file(path, language, code)` |
| Edit a file | `read` then `edit` (exact bytes) — never the sandbox |
| grep / search large trees | `ctx_execute("shell", "rg ...")` |
| Count / parse / compare / transform | `ctx_execute(language, code)` — print only the answer |
| Store for later recall | `ctx_index(content, source)` |
| Recall | `ctx_search(queries, source?, sort?)` |

### BLOCKED

- **curl / wget** and direct page reads → `ctx_fetch_and_index`
- **Inline HTTP** → `ctx_execute`
- **Raw file dumps for analysis** → `ctx_execute_file`

### Loop safety

- **Scratch scripts**: >5 lines or nested quotes → write to `.agent/tmp/*.sh`, run by path.
- **Tool error** → fix the *original* call from its schema; one schema-driven retry, max 2 per tool, then stop and report.
- **No probes**: never `cd`/test invented paths, never `bash <<< $'true'`. Uncertain state → ask the user.
- **Paths**: absolute and known-existing, or deliberate new files under the workspace.

### Think in Code — MANDATORY

Analyze/count/filter/compare/parse/transform in `ctx_execute(language, code)`; only `console.log()` output enters context. One script replaces ten tool calls.

### Session continuity

On resume, search BEFORE asking the user:

| Need | Command |
|------|---------|
| What did we decide? | `ctx_search(queries: ["decision"], source: "decision", sort: "timeline")` |
| What did research find? | `ctx_search(queries: ["research"], source: "research", sort: "timeline")` |
| What was the plan? | `ctx_search(queries: ["plan"], source: "plan", sort: "timeline")` |
| What happened last loop iteration? | `ctx_search(queries: ["orchestrator"], source: "orchestrator-iteration", sort: "timeline")` |

---

## qmd — Persistent Knowledge Base

Local semantic search with BM25 + vector + LLM reranking. Collections: `tasks`, `patterns`, `plans`, `research`, `builds`, `decisions`, `mistakes`, `ghost` in `memory/`.

Pipeline: query expansion (2 alternates, original ×2) → BM25 + vector per query → RRF (k=60) + top-rank bonus → top 30 → `Qwen3-Reranker-0.6B` LLM rerank → position-aware blend. Frontmatter is indexed as text, not as metadata — there is no `type:` filter. Search the literal token without a colon (`qmd query "type pattern context-mode"`): FTS5 treats `type:pattern` as a column filter and returns nothing.

| Tool | When to use |
|------|-------------|
| `qmd query` | Search for past work at startup (hybrid + rerank) |
| `qmd search` | BM25 only, no models — fast and deterministic |
| `qmd get` | Retrieve a specific document by path or docid |
| `qmd multi_get` | Retrieve multiple documents by glob |
| `qmd status` | Check index health |
| `qmd update` | Re-index after writing memory files |
| `qmd embed` | Rebuild vectors after model/chunk changes |
| `qmd cleanup` | Delete inactive docs (tombstones), orphans, caches; vacuum |
| `scripts/memory-lint.sh` | Validate frontmatter + links before indexing |
| `scripts/memory-prune.sh` | Archive stale notes; then update + cleanup |

---

## Key Decisions & Learnings

- **oMLX port**: 8005 (matches actual running instance)
- **Agent set (2026-10-21)**: built-in `build` + `plan` plus custom `researcher` and `orchestrator`. Removed `scout`, `dev`, `coder`, `deploy`, `qa`, `mem`, `oracle`, `builder`. `researcher` replaces `scout` with a read-only permission model — reads everything in the project, runs only read-only commands, and may write exactly one file (`.agent/research-report.md`). `opencode.json` `default_agent` is `build`.
- **Models (2026-10-21)**: default model → `opencode/glm-5.1`; small model → `opencode-go/deepseek-v4-flash`; plan agent → `opencode-go/kimi-k3`; orchestrator → `opencode-go/deepseek-v4-flash`. oMLX/Qwen3.5-9B retained for manual use only.
- **Context limits**: deepseek-v4-flash free tier ~32768 context / 8192 output — context-mode routing is load-bearing, not optional (one raw dump > budget). compaction reserved 4000.
- **oMLX (manual)**: Qwen3.5-9B-OptiQ-4bit, 9B params, 32k context — available via `omlx/` provider for local-only runs when needed.
- **oMLX context scaling**: Must be enabled in admin dashboard (http://127.0.0.1:8005/admin) — Claude Code Optimization
- **context-mode**: MCP server (2026-10-19; was a V1 plugin) — all I/O goes through sandbox. V1 plugin contract is dead in OpenCode v2; upstream has no V2 `setup()` export yet
- **qmd**: Bun-based MCP server (`bunx @tobilu/qmd mcp`) for persistent semantic memory
- **Agent permissions**: `plan.md` grants `read/glob/grep/list/skill/question/webfetch/websearch` explicitly and restricts `edit` to `.agent/*` — it plans but never implements. MCP tools (context-mode, qmd, duckduckgo) need no per-agent keys; they are enabled globally via the `tools` block in `opencode.json`.

---

## oMLX Integration Notes

- **Context scaling**: Enable in oMLX admin dashboard → Claude Code Optimization. This makes oMLX report a larger context to OpenCode so compaction triggers before the real limit is hit.
- **Memory limit**: Set Memory Limit (Models Only) to ~20GB in oMLX admin dashboard.
- **Prefill behavior**: MLX performs full prefill before emitting tokens. Time-to-first-token rises linearly with input length. Keep system prompt small.
- **KV cache**: Memory scales linearly with configured context limit. 9B model at 32k context uses ~4-6 GB KV cache (fits in 32GB Mac).
