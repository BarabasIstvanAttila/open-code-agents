# OpenCode Agent Pipeline — Configuration & Rules

**oMLX · qmd · context-mode · OpenCode**  
*Five primary agents, two subagents. Free cloud models via opencode-go (deepseek-v4-flash + kimi-k3); oMLX retained for manual use.*

---

## Agent Pipeline

```
/mode scout → /mode plan → /mode dev → /mode deploy → /mode qa → /mode mem
```

Container-development goals take the autonomous loop instead:

```
/mode orchestrator    (plan → implement → deploy one-by-one → curl+browser verify → findings → re-plan, until DoD green)
```

| Agent | Mode | Model | Role |
|-------|------|-------|------|
| **scout** | primary | opencode-go/deepseek-v4-flash (cloud-free) | Research — gather context, map codebase, fetch docs |
| **plan** | primary | opencode-go/kimi-k3 (cloud) | Plan — 3-round cap, produce file-specific plan |
| **dev** | primary | opencode-go/deepseek-v4-flash (cloud-free) | Implement — ReAct loop, follow plan step by step |
| **deploy** | primary | opencode-go/deepseek-v4-flash (cloud-free) | Deploy — compose stacks over SSH, deterministic smoke, deploy verdict (uses `homelab-deploy` skill) |
| **orchestrator** | primary | opencode-go/deepseek-v4-flash (cloud-free) | Container loop — goal→plan→implement→verify locally (one container at a time, curl + Playwright browser), findings-driven iterations (uses `docker-loop` skill) |
| **qa** - @qa| subagent | opencode-go/deepseek-v4-flash (cloud-free) | Validate — tests, lint, typecheck, plan compliance |
| **mem** - @mem| subagent | opencode-go/deepseek-v4-flash (cloud-free) | Memory — commit task summaries, patterns, rebuild qmd index |

### Working files (per project, git-ignored)

```
.agent/
├── research-report.md   ← scout output
├── plan.md              ← plan agent output
├── dev-report.md        ← dev agent output
├── deploy-report.md     ← deploy agent output
├── qa-report.md         ← qa agent output
├── memory-log.md        ← mem agent output
└── orchestrator/        ← orchestrator loop state (goal.md, plan-N.md, findings-N.md, verify/)
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
   │  /mode scout  /mode plan  /mode dev  /mode deploy  /mode qa  /mode mem
   ▼  ──────────  ──────────  ─────────  ───────────  ────────  ─────────
  OpenCode (terminal)
   │
   ├─ scout ──► OpenCode (deepseek-v4-flash, cloud-free)
   ├─ plan  ──► OpenCode (kimi-k3, cloud)
   ├─ dev   ──► OpenCode (deepseek-v4-flash, cloud-free)
   ├─ deploy ─► OpenCode (deepseek-v4-flash, cloud-free)
   ├─ orchestrator ─► OpenCode (deepseek-v4-flash, cloud-free) — autonomous container loop
   ├─ qa    ──► OpenCode (deepseek-v4-flash, cloud-free)
   └─ mem   ──► OpenCode (deepseek-v4-flash, cloud-free)
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

### Loop-safety — shell quoting & tool-error recovery

**Why this exists:** On 2026-07-07 a `ctx_execute("shell", code)` multi-line verification script had an unmatched `"` inside a heredoc. The cloud model then emitted six malformed tool calls in one turn — empty tool name, truncated paths, a `cd /a/bash && bash <<< $'true'` no-op "probe" against a nonexistent path — before opencode's `doom_loop` + `external_directory` guards aborted the turn and compaction pruned it. No damage, but the verification step was skipped.

| Risk | Rule |
|------|------|
| **Multi-line shell & nested quotes** | If a `ctx_execute("shell", code)` script is **>5 lines OR contains any `"` inside already-quoted strings**, write it as a temp `.sh` file in the workspace (via the `write` tool — file lives on host, sandbox can read it) and execute with `ctx_execute("shell", "bash /Users/atti/Projects/HomeLab/.agent/tmp/verify-NNN.sh")`. Removes the nested-quoting class of bugs. Single-purpose, ≤5-line scripts can stay inline. |
| **On tool error → STOP, don't mutate** | If a tool returns `invalid arguments`, `unmatched "`, or `Exit code 1`, fix the **original** call by re-reading its schema. Do NOT retry with: a different tool name, an empty tool name, a truncated/invented path, or a no-op probe. One schema-driven retry, then surface to the user. |
| **Retry cap** | Max **2 retries** for the SAME tool after a hard error. On the 3rd failure → tell the user and stop. No doom loops. |
| **Path hygiene** | Every path passed to a tool must be a known-existing absolute path (or a deliberate new file under the workspace). Never invent a path like `/a/bash` to "test" state — opencode's `external_directory` guard flags it and aborts the turn. |
| **No sanity probes** | Never send `bash <<< $'true'`, `cd <invented-path>`, `[a/a]`, or similar probes to recover from an error. If model state is uncertain, ask the user — don't try to "wake" the shell. |

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
- **Pipeline models (2026-08-25)**: scout/dev/deploy/qa/mem → `opencode-go/deepseek-v4-flash` (cloud-free); plan → `opencode-go/kimi-k3`. oMLX/Qwen3.5-9B retained for manual use, no longer a pipeline default.
- **Context limits**: deepseek-v4-flash free tier ~32768 context / 8192 output — context-mode routing is load-bearing, not optional (one raw dump > budget). compaction reserved 4000.
- **oMLX (manual)**: Qwen3.5-9B-OptiQ-4bit, 9B params, 32k context — available via `omlx/` provider for local-only runs when needed.
- **oMLX context scaling**: Must be enabled in admin dashboard (http://127.0.0.1:8005/admin) — Claude Code Optimization
- **context-mode**: Plugin + MCP tool routing — all I/O goes through sandbox
- **qmd**: Bun-based MCP server (`bunx @tobilu/qmd mcp`) for persistent semantic memory

---

## oMLX Integration Notes

- **Context scaling**: Enable in oMLX admin dashboard → Claude Code Optimization. This makes oMLX report a larger context to OpenCode so compaction triggers before the real limit is hit.
- **Memory limit**: Set Memory Limit (Models Only) to ~20GB in oMLX admin dashboard.
- **Prefill behavior**: MLX performs full prefill before emitting tokens. Time-to-first-token rises linearly with input length. Keep system prompt small.
- **KV cache**: Memory scales linearly with configured context limit. 9B model at 32k context uses ~4-6 GB KV cache (fits in 32GB Mac).