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

### Persistent memory (indexed by qmd)

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

One unrouted command dumps 56 KB into context. All I/O goes through context-mode tools.

> **Transport: MCP server (not plugin) — 2026-10-19.** OpenCode v2 replaced the V1 plugin contract
> (`export default { id, server }`) with `{ id, setup }` / `{ id, effect }`. context-mode still ships the
> V1 shape in every published version (1.0.151 → 1.0.169) and on `main`, so `plugin: ["context-mode"]`
> fails to load: *"Plugin must export a default definition with an id and an effect or setup function."*
> context-mode therefore runs as a **local MCP server** (`mcp.context-mode` in `opencode.json`, command
> `bun /Users/atti/node_modules/context-mode/cli.bundle.mjs`, `CONTEXT_MODE_PLATFORM=opencode`).
> All 11 `ctx_*` tools work; **routing is prompt-level only** — the plugin's `tool.execute.before`
> hook that programmatically blocked `curl`/`wget` is gone, so the BLOCKED list below is now a rule
> the model follows, not one the host enforces. Do not rely on it to stop a stray `curl`.
> `ctx_doctor` reporting `Plugin registration: No plugin array found` and
> `Legacy MCP registration: mcp.context-mode is redundant` is **expected** in this mode — both checks
> assume the V1 plugin path. Restore the plugin only when upstream ships a V2 `setup()` export.

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
| **Multi-line shell & nested quotes** | If a `ctx_execute("shell", code)` script is **>5 lines OR contains any `"` inside already-quoted strings**, write it as a temp `.sh` file in the workspace (via the `write` tool — file lives on host, sandbox can read it) and execute with `ctx_execute("shell", "bash <project>/.agent/tmp/verify-NNN.sh")`. Removes the nested-quoting class of bugs. Single-purpose, ≤5-line scripts can stay inline. |
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
| What did research find? | `ctx_search(queries: ["research"], source: "research", sort: "timeline")` |
| What was the plan? | `ctx_search(queries: ["plan"], source: "plan", sort: "timeline")` |
| What happened last loop iteration? | `ctx_search(queries: ["orchestrator"], source: "orchestrator-iteration", sort: "timeline")` |

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
