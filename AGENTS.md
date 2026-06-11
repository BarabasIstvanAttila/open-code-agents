# OpenCode Agent Pipeline — Configuration & Rules

**oMLX · qmd · context-mode · OpenCode**  
*Three primary agents, two subagents. All local-first. No proxy layer.*

---

## Agent Pipeline

```
/mode scout → /mode plan → /mode dev → /mode qa → /mode mem
```

| Agent | Mode | Model | Role |
|-------|------|-------|------|
| **scout** | primary | omlx/Qwen3.5-9B (local) | Research — gather context, map codebase, fetch docs |
| **plan** | primary | opencode-go/glm-5.1 (cloud) | Plan — 3-round cap, produce file-specific plan |
| **dev** | primary | opencode-go/glm-5.1 (cloud) | Implement — ReAct loop, follow plan step by step |
| **qa** - @qa| subagent | omlx/Qwen3.5-9B (local) | Validate — tests, lint, typecheck, plan compliance |
| **mem** - @mem| subagent | omlx/Qwen3.5-9B (local) | Memory — commit task summaries, patterns, rebuild qmd index |

### Working files (per project, git-ignored)

```
.agent/
├── research-report.md   ← scout output
├── plan.md              ← plan agent output
├── dev-report.md        ← dev agent output
├── qa-report.md         ← qa agent output
└── memory-log.md        ← mem agent output
```

### Persistent memory (written by mem, indexed by qmd)

```
memory/                    ← project-local (versioned with repo)
├── tasks/               ← task summaries
├── patterns/            ← code patterns
├── plans/               ← archived plans
└── research/            ← archived research
```

---

## Architecture

```
  User
   │
   │  /mode scout  /mode plan  /mode dev  /mode qa  /mode mem
   ▼  ──────────  ──────────  ─────────  ────────  ─────────
  OpenCode (terminal)
   │
   ├─ scout ──► oMLX :8005  (Qwen3.5-9B, local)
   ├─ plan  ──► OpenCode    (glm-5.1, cloud)
   ├─ dev   ──► oMLX :8005  (Qwen3.5-9B, local)
   ├─ qa    ──► oMLX :8005  (Qwen3.5-9B, local)
   └─ mem   ──► oMLX :8005  (Qwen3.5-9B, local)
   │
   ├─ context-mode MCP ─── sandboxed execution (MANDATORY — all agents route I/O through this)
   ├─ qmd MCP ──────────── local semantic search (query, get, multi_get, status)
   ├─ context7 MCP ─────── library documentation lookup
   ├─ duckduckgo MCP ──── web search
   └─ sequentialthinking ─ structured reasoning chains
```

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

Local semantic search with BM25 + vector + LLM reranking. Collections: `tasks`, `patterns`, `plans`, `research` in `memory/`.

| Tool | When to use |
|------|-------------|
| `qmd query` | Search for past work at startup |
| `qmd get` | Retrieve a specific document by path or docid |
| `qmd multi_get` | Retrieve multiple documents by glob |
| `qmd status` | Check index health |

---

## Key Decisions & Learnings

- **oMLX port**: 8005 (matches actual running instance)
- **Local model**: Qwen3.5-9B-OptiQ-4bit for all local agents (9B params, fits 32GB Mac at 32k context)
- **Cloud model**: opencode-go/glm-5.1 for plan/dev agents (cost-controlled)
- **Context limits**: 32768 context / 4096 output for local model, compaction reserved 4000
- **oMLX context scaling**: Must be enabled in admin dashboard (http://127.0.0.1:8005/admin) — Claude Code Optimization
- **context-mode**: Plugin + MCP tool routing — all I/O goes through sandbox
- **qmd**: Bun-based MCP server (`bunx @tobilu/qmd mcp`) for persistent semantic memory

---

## oMLX Integration Notes

- **Context scaling**: Enable in oMLX admin dashboard → Claude Code Optimization. This makes oMLX report a larger context to OpenCode so compaction triggers before the real limit is hit.
- **Memory limit**: Set Memory Limit (Models Only) to ~20GB in oMLX admin dashboard.
- **Prefill behavior**: MLX performs full prefill before emitting tokens. Time-to-first-token rises linearly with input length. Keep system prompt small.
- **KV cache**: Memory scales linearly with configured context limit. 9B model at 32k context uses ~4-6 GB KV cache (fits in 32GB Mac).