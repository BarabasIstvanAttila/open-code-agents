# OpenCode Agent Pipeline — Configuration & Rules

**oMLX · qmd · context-mode · OpenCode**  
*Four primary agents, three subagents. All local-first. No proxy layer.*

---

## Agent Pipeline

**Automated flow (recommended — 3 user commands):**
```
/mode scout → /mode plan → [auto: mem] → /mode builder → [auto: coders → qa → mem]
```

**Standalone dev flow (for simple tasks — 5 user commands):**
```
/mode scout → /mode plan → [auto: mem] → /mode dev → /mode qa → /mode mem
```

| Agent | Mode | Model | Role |
|-------|------|-------|------|
| **scout** | primary | opencode-go/glm-5.1 (cloud) | Research — gather context, map codebase, fetch docs |
| **plan** | primary | opencode-go/qwen3.7-plus (cloud) | Plan — 3-round cap, produce plan, auto-spawn mem |
| **builder** | primary | opencode-go/deepseek-v4-flash (cloud) | Orchestrate — decompose plan, spawn coders, auto-spawn qa + mem |
| **dev** | primary | omlx/gemma-4-e4b-it-4bit (local) | Standalone implementation — for simple tasks that skip the builder |
| **coder** | subagent | omlx/gemma-4-e4b-it-4bit (local) | Focused implementation — spawned by builder, no MCPs, context-isolated |
| **qa** | subagent | omlx/gemma-4-e4b-it-4bit (local) | Validate — tests, lint, typecheck (auto-spawned by builder) |
| **mem** | subagent | omlx/gemma-4-e4b-it-4bit (local) | Memory — commit artifacts (auto-spawned by plan and builder) |

### Working files (per project, git-ignored)

```
.agent/
├── research-report.md      ← scout output
├── plan.md                 ← plan agent output
├── builder-progress.md     ← builder runtime progress tracking
├── builder-report.md       ← builder final report
├── dev-report.md           ← dev agent output (standalone mode)
├── qa-report.md            ← qa agent output
└── memory-log.md           ← mem agent output
```

### Persistent memory (written by mem, indexed by qmd)

```
memory/                    ← project-local (versioned with repo)
├── tasks/                 ← task summaries
├── patterns/              ← code patterns
├── plans/                 ← archived plans
├── research/              ← archived research
└── builds/                ← per-task build records (created by builder)
    └── <date>-<slug>/
        ├── plan.md        ← copy of plan used
        ├── research.md    ← copy of research used
        ├── steps/         ← per-step implementation records
        │   ├── 01-step-name.md
        │   └── ...
        └── summary.md     ← build results summary
```

---

## Architecture

```
  User
   │
   │  /mode scout  /mode plan       /mode builder
   ▼  ──────────  ──────────       ─────────────
  OpenCode (terminal)
   │
   ├─ scout   ──► OpenCode    (glm-5.1, cloud)
   ├─ plan    ──► OpenCode    (qwen3.7-plus, cloud)
   │   └─► mem (auto) ──► oMLX :8005  ← saves research + plan
   ├─ builder ──► OpenCode    (deepseek-v4-flash, cloud)
   │   ├─ coder ──► oMLX :8005  (gemma-4-e4b-it-4bit, local, no MCPs)
   │   ├─ coder ──► oMLX :8005  (gemma-4-e4b-it-4bit, local, no MCPs)
   │   └─ coder ──► oMLX :8005  (gemma-4-e4b-it-4bit, local, no MCPs)
   │   └─► qa (auto)  ──► oMLX :8005  ← validates build
   │   └─► mem (auto) ──► oMLX :8005  ← saves build + QA result (always)
   │
   ├─ dev     ──► oMLX :8005  (gemma-4-e4b-it-4bit, standalone mode)
   │
   ├─ context-mode MCP ─── sandboxed execution (MANDATORY — all agents route I/O through this)
   ├─ qmd MCP ──────────── local semantic search (query, get, multi_get, status)
   ├─ context7 MCP ─────── library documentation lookup
   ├─ duckduckgo MCP ──── web search
   └─ sequentialthinking ─ structured reasoning chains
```

### Auto-Spawn Chain

```
plan ──► mem (post-plan: saves research + plan)
builder ──► coders (parallel) ──► qa ──► mem (post-build: saves build + QA result, always)
```

- **Plan** always spawns mem after writing the plan
- **Builder** always spawns QA after coders complete
- **Builder** always spawns mem after QA — pass AND fail — failures are logged for future learning
- **QA failures** are recorded in memory so future plan runs can search for them and create fixes

### Builder → Coder Flow

The builder agent decomposes the plan into discrete work items and spawns coder subagents:

1. **Parse** plan into steps with dependencies
2. **Create** build folder: `memory/builds/<date>-<slug>/`
3. **Batch** independent steps (no file overlaps) for parallel execution
4. **Compose** focused prompts with all context inline (coder has NO MCPs)
5. **Spawn** coder subagents via `task(subagent_type: "coder", prompt: ...)`
6. **Collect** results and record per-step in `memory/builds/<slug>/steps/`
7. **Track** progress in `.agent/builder-progress.md`
8. **Finalize** with `memory/builds/<slug>/summary.md`
9. **Spawn QA** to validate the build
10. **Spawn mem** to commit all artifacts (including QA failures)

### Context Isolation

Coder subagents have **no MCP tools** (no context7, duckduckgo, sequentialthinking, qmd, context-mode). All context is provided inline by the builder in the task prompt. This prevents context pollution and keeps coder prompts focused.

---

## context-mode — MANDATORY routing rules

One unrouted command dumps 56 KB into context. All I/O goes through context-mode tools.

### BLOCKED

- **curl / wget** → Use `ctx_fetch_and_index` or `ctx_execute("javascript", "await fetch(...)")`
- **Inline HTTP** → Use `ctx_execute(language, code)` — only stdout enters context
- **Direct web fetching** → Use `ctx_fetch_and_index(url, source)` then `ctx_search(queries)`

### REDIRECTED — use sandbox

- **Shell (>20 lines output)** → `ctx_batch_execute(commands, queries)` or `ctx_execute("shell", code)`
- **File reading (for analysis)** → `ctx_execute_file(path, language, code)` — only `console.log()` output enters context
- **File reading (for editing)** → Read tool (need exact bytes for Edit)
- **grep / search (large results)** → `ctx_execute("shell", "rg ...")` in sandbox

### Think in Code — MANDATORY

Analyze/count/filter/compare/search/parse/transform data: **write code** via `ctx_execute(language, code)`. Only `console.log()` output enters context. One script replaces ten tool calls.

### Session Continuity

On resume, search BEFORE asking the user:

| Need | Command |
|------|---------|
| What did we decide? | `ctx_search(queries: ["decision"], source: "decision", sort: "timeline")` |
| What was the plan? | `ctx_search(queries: ["plan"], source: "plan", sort: "timeline")` |
| What did dev implement? | `ctx_search(queries: ["dev-progress"], source: "dev-progress", sort: "timeline")` |

---

## qmd — Persistent Knowledge Base

Local semantic search with BM25 + vector + LLM reranking. Collections: `tasks`, `patterns`, `plans`, `research`, `builds` in `memory/`.

| Tool | When to use |
|------|-------------|
| `qmd query` | Search for past work at startup |
| `qmd get` | Retrieve a specific document by path or docid |
| `qmd multi_get` | Retrieve multiple documents by glob |
| `qmd status` | Check index health |

---

## Key Decisions & Learnings

- **oMLX port**: 8005 (matches actual running instance)
- **Local model**: gemma-4-e4b-it-4bit for all local agents (via oMLX, fits 32GB Mac at 32k context)
- **Cloud models**: opencode-go/qwen3.7-plus for plan, opencode-go/deepseek-v4-flash for builder (cost-controlled)
- **Context limits**: 32768 context / 4096 output for local model, compaction reserved 4000
- **oMLX context scaling**: Must be enabled in admin dashboard (http://127.0.0.1:8005/admin) — Claude Code Optimization
- **context-mode**: Plugin + MCP tool routing — all I/O goes through sandbox
- **qmd**: Bun-based MCP server (`bunx @tobilu/qmd mcp`) for persistent semantic memory

---

## oMLX Integration Notes

- **Context scaling**: Enable in oMLX admin dashboard → Claude Code Optimization. This makes oMLX report a larger context to OpenCode so compaction triggers before the real limit is hit.
- **Memory limit**: Set Memory Limit (Models Only) to ~20GB in oMLX admin dashboard.
- **Prefill behavior**: MLX performs full prefill before emitting tokens. Time-to-first-token rises linearly with input length. Keep system prompt small.
- **KV cache**: Memory scales linearly with configured context limit. gemma-4-e4b-it-4bit at 32k context uses ~4-6 GB KV cache (fits in 32GB Mac).