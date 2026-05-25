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
| **scout** | primary | omlx/Qwen3.5-27B (local) | Research — gather context, map codebase, fetch docs |
| **plan** | primary | opencode-go/glm-5.1 (cloud) | Plan — 3-round cap, produce file-specific plan |
| **dev** | primary | omlx/Qwen3.5-27B (local) | Implement — ReAct loop, follow plan step by step |
| **qa** - @qa| subagent | omlx/Qwen3.5-27B (local) | Validate — tests, lint, typecheck, plan compliance |
| **mem** - @mem| subagent | omlx/Qwen3.5-27B (local) | Memory — commit task summaries, patterns, rebuild qmd index |

Agent definitions live in `.opencode/agent/<name>.md` with frontmatter for model, temperature, mode, and permission overrides.

### How to run a task

```bash
opencode

/mode scout
Add rate limiting to POST /api/auth/login — 5 req per IP per 15 min, Redis-backed

# After scout completes:
/mode plan

# After plan completes:
/mode dev

# After dev completes:
/mode qa

# After qa passes:
/mode mem
```

QA and mem can also be invoked as subagents by the dev agent when configured.

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
~/.config/qmd/memory/
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
   │  /mode scout      /mode plan       /mode dev         /mode qa          /mode mem
   ▼  ──────────────  ───────────────  ────────────────  ────────────────  ────────────
  OpenCode (terminal)
   │
   │  All model calls go directly to oMLX or OpenCode cloud.
   │  No LiteLLM proxy. No intermediate routing layer.
   │
   ├─ scout ──► oMLX :8005  (Qwen3.5-27B, local)
   ├─ plan  ──► OpenCode    (glm-5.1, cloud)
   ├─ dev   ──► oMLX :8005  (Qwen3.5-27B, local)
   ├─ qa    ──► oMLX :8005  (Qwen3.5-27B, local)
   └─ mem   ──► oMLX :8005  (Qwen3.5-27B, local)
   │
   │  Four MCP servers run as subprocesses:
   │
   ├─ context-mode MCP ─── sandboxed execution (ctx_execute, ctx_batch_execute,
   │                        ctx_fetch_and_index, ctx_search, ctx_index ...)
   │                        MANDATORY — all agents route I/O through this
   │
   ├─ qmd MCP ──────────── local semantic search (query, get, multi_get, status)
   │                        ~/.config/qmd/memory/  ← persistent knowledge base
   │                        qmd-collections: tasks, patterns, plans, research
   │
   ├─ context7 MCP ─────── library documentation lookup
   │
   ├─ duckduckgo MCP ──── web search
   │
   └─ sequentialthinking ─ structured reasoning chains
```

---

## context-mode — MANDATORY routing rules

context-mode MCP tools available. Rules protect context window from flooding. One unrouted command dumps 56 KB into context.

### Think in Code — MANDATORY

Analyze/count/filter/compare/search/parse/transform data: **write code** via `context-mode_ctx_execute(language, code)`, `console.log()` only the answer. Do NOT read raw data into context. PROGRAM the analysis, not COMPUTE it. Pure JavaScript — Node.js built-ins only (`fs`, `path`, `child_process`). `try/catch`, handle `null`/`undefined`. One script replaces ten tool calls.

### BLOCKED — do NOT attempt

#### curl / wget — BLOCKED
Shell `curl`/`wget` intercepted and blocked. Do NOT retry.
Use: `context-mode_ctx_fetch_and_index(url, source)` or `context-mode_ctx_execute(language: "javascript", code: "const r = await fetch(...)")`

#### Inline HTTP — BLOCKED
`fetch('http`, `requests.get(`, `requests.post(`, `http.get(`, `http.request(` — intercepted. Do NOT retry.
Use: `context-mode_ctx_execute(language, code)` — only stdout enters context

#### Direct web fetching — BLOCKED
Use: `context-mode_ctx_fetch_and_index(url, source)` then `context-mode_ctx_search(queries)`

### REDIRECTED — use sandbox

#### Shell (>20 lines output)
Shell ONLY for: `git`, `mkdir`, `rm`, `mv`, `cd`, `ls`, `npm install`, `pip install`.
Otherwise: `context-mode_ctx_batch_execute(commands, queries)` or `context-mode_ctx_execute(language: "shell", code: "...")`

#### File reading (for analysis)
Reading to **edit** → reading correct. Reading to **analyze/explore/summarize** → `context-mode_ctx_execute_file(path, language, code)`.

#### grep / search (large results)
Use `context-mode_ctx_execute(language: "shell", code: "grep ...")` in sandbox.

### Tool selection

0. **MEMORY**: `context-mode_ctx_search(sort: "timeline")` — after resume, check prior context before asking user.
1. **GATHER**: `context-mode_ctx_batch_execute(commands, queries)` — runs all commands, auto-indexes, returns search. ONE call replaces 30+. Each command: `{label: "header", command: "..."}`.
2. **FOLLOW-UP**: `context-mode_ctx_search(queries: ["q1", "q2", ...])` — all questions as array, ONE call (default relevance mode).
3. **PROCESSING**: `context-mode_ctx_execute(language, code)` | `context-mode_ctx_execute_file(path, language, code)` — sandbox, only stdout enters context.
4. **WEB**: `context-mode_ctx_fetch_and_index(url, source)` then `context-mode_ctx_search(queries)` — raw HTML never enters context.
5. **INDEX**: `context-mode_ctx_index(content, source)` — store in FTS5 for later search.

### Parallel I/O batches

For multi-URL fetches or multi-API calls, **always** include `concurrency: N` (1-8):

- `context-mode_ctx_batch_execute(commands: [3+ network commands], concurrency: 5)` — gh, curl, dig, docker inspect, multi-region cloud queries
- `context-mode_ctx_fetch_and_index(requests: [{url, source}, ...], concurrency: 5)` — multi-URL batch fetch

**Use concurrency 4-8** for I/O-bound work (network calls, API queries). **Keep concurrency 1** for CPU-bound (npm test, build, lint) or commands sharing state (ports, lock files, same-repo writes).

GitHub API rate-limit: cap at 4 for `gh` calls.

### Output

Write artifacts to FILES — never inline. Return: file path + 1-line description.
Descriptive source labels for `search(source: "label")`.

### Session Continuity

Skills, roles, and decisions persist for the entire session. Do not abandon them as the conversation grows.

### Memory

Session history is persistent and searchable. On resume, search BEFORE asking the user:

| Need | Command |
|------|---------|
| What did we decide? | `context-mode_ctx_search(queries: ["decision"], source: "decision", sort: "timeline")` |
| What constraints exist? | `context-mode_ctx_search(queries: ["constraint"], source: "constraint")` |
| What did scout find? | `context-mode_ctx_search(queries: ["research"], source: "scout-research", sort: "timeline")` |
| What was the plan? | `context-mode_ctx_search(queries: ["plan"], source: "plan", sort: "timeline")` |
| What did dev implement? | `context-mode_ctx_search(queries: ["dev-progress"], source: "dev-progress", sort: "timeline")` |
| What did QA verdict? | `context-mode_ctx_search(queries: ["qa verdict"], sort: "timeline")` |

DO NOT ask "what were we working on?" — SEARCH FIRST.
If search returns 0 results, proceed as a fresh session.

### ctx commands

| Command | Action |
|---------|--------|
| `ctx stats` | Call `stats` MCP tool, display full output verbatim |
| `ctx doctor` | Call `doctor` MCP tool, run returned shell command, display as checklist |
| `ctx upgrade` | Call `upgrade` MCP tool, run returned shell command, display as checklist |
| `ctx purge` | Call `purge` MCP tool with confirm: true. Warns before wiping knowledge base. |

After /clear or /compact: knowledge base preserved. Use `ctx purge` to start fresh.

---

## qmd — Persistent Knowledge Base

qmd is a local semantic search engine with BM25 + vector + LLM reranking. It accumulates every research report, plan, implementation note, and code pattern across sessions.

### MCP tools (available to all agents)

| Tool | When to use |
|------|-------------|
| `qmd query` | Scout and plan agents search for past work at startup |
| `qmd get` | Retrieve a specific past document by path or docid |
| `qmd multi_get` | Retrieve multiple documents matching a glob |
| `qmd status` | Check index health |

### CLI commands (used via ctx_execute in sandbox)

| Command | Purpose |
|---------|---------|
| `qmd search "term"` | BM25 keyword search |
| `qmd vsearch "phrase"` | Vector semantic search |
| `qmd query "question"` | Hybrid + reranking (best quality) |
| `qmd embed --changed` | Rebuild embeddings for changed files |
| `qmd index add path` | Add a file to a collection |

### Collections (created by `scripts/qmd-setup.sh`)

| Collection | Path | Contains |
|------------|------|----------|
| `tasks` | `~/.config/qmd/memory/tasks/` | Task summaries (written by mem) |
| `patterns` | `~/.config/qmd/memory/patterns/` | Code patterns (written by mem) |
| `plans` | `~/.config/qmd/memory/plans/` | Archived plans (written by mem) |
| `research` | `~/.config/qmd/memory/research/` | Archived research (written by mem) |

### How qmd grows smarter

After 5 tasks: scout finds relevant past patterns in under 10 seconds.  
After 20 tasks: plan agent often completes in round 1 alone.  
After 50 tasks: project-specific AI memory that knows every pattern, decision, and lesson.

---

## All Local Tools

### context-mode MCP
Sandboxed execution layer. ALL agent I/O routes through this. See routing rules above.

| Tool | Purpose |
|------|---------|
| `ctx_execute` | Run code in sandbox (JS/TS/Python/Shell). Only console.log enters context. |
| `ctx_execute_file` | Read file into sandbox, process it, only print the answer. |
| `ctx_batch_execute` | Run multiple commands in parallel, auto-index, return search. |
| `ctx_fetch_and_index` | Fetch URL, index content, never fetch raw HTML into context. |
| `ctx_search` | Search the knowledge base (BM25 + trigram + proximity reranking). |
| `ctx_index` | Store content in FTS5 for later search. |
| `ctx_stats` | Check context consumption statistics. |
| `ctx_doctor` | Diagnose context-mode installation. |

### qmd MCP
Local semantic search. Persistent knowledge base across sessions.

| Tool | Purpose |
|------|---------|
| `qmd query` | Hybrid search (BM25 + vector + reranking) |
| `qmd get` | Get document by path or docid |
| `qmd multi_get` | Get multiple documents by glob |
| `qmd status` | Index health check |

### context7 MCP
Library documentation lookup. Use for API references, framework docs, code examples.

| Tool | Purpose |
|------|---------|
| `context7_resolve-library-id` | Find the Context7-compatible library ID |
| `context7_query-docs` | Query up-to-date documentation for a library |

### duckduckgo MCP
Web search and content fetching.

| Tool | Purpose |
|------|---------|
| `duckduckgo_search` | Search the web for current information |
| `duckduckgo_fetch_content` | Fetch and extract clean text from a webpage |

### sequentialthinking MCP
Structured reasoning chains for complex problem-solving.

| Tool | Purpose |
|------|---------|
| `sequentialthinking_sequentialthinking` | Step-by-step reasoning with revision support |

### OpenCode built-in tools
Always available regardless of MCP servers.

| Tool | Purpose |
|------|---------|
| `read` | Read file contents (use before Edit to get exact bytes) |
| `write` | Write new file or overwrite existing file |
| `edit` | Make precise string replacements in files |
| `bash` | Run shell commands (use for git, mkdir, rm, mv, npm install) |
| `glob` | Find files by pattern |
| `grep` | Search file contents by regex |
| `task` | Launch a subagent for multi-step work |
| `todowrite` | Track task progress |
| `webfetch` | Fetch URL content |
| `websearch` | Search the web |

---

## Setup

### Prerequisites

| Software | Version | How to get |
|----------|---------|------------|
| oMLX | latest | macOS menu bar app — serves models on port 8005 |
| Node.js | 20+ | `brew install node` |
| bun | latest | `curl -fsSL https://bun.sh/install \| bash` |
| OpenCode | latest | `npm install -g opencode-ai` |
| qmd | latest | `npm install -g @tobilu/qmd` |
| context-mode MCP | — | follow context-mode MCP server setup |

### Environment variables

Copy `.env.example` to `.env` and fill in keys:

```bash
cp .env.example .env
# Edit .env: set OMLX_API_KEY, ANTHROPIC_API_KEY, GEMINI_API_KEY, CONTEXT7API
```

Add to shell profile for persistence:

```bash
echo 'export OMLX_API_KEY="your-key-here"' >> ~/.zshrc
echo 'export ANTHROPIC_API_KEY="sk-ant-..."' >> ~/.zshrc
echo 'export GEMINI_API_KEY="AIza..."' >> ~/.zshrc
echo 'export CONTEXT7API="your-key-here"' >> ~/.zshrc
```

### Initial setup

```bash
# 1. Install qmd and create collections
npm install -g @tobilu/qmd
chmod +x scripts/qmd-setup.sh
./scripts/qmd-setup.sh

# 2. Verify all services
chmod +x scripts/check-services.sh
./scripts/check-services.sh

# 3. Start opencode
./start.sh
```

### Expected service check output

```
✓ oMLX              localhost:8005  (Qwen3.5-27B-Claude-4.6-Opus-Distilled-MLX-4bit)
✓ qmd               status ok       (4 collections)
✓ context-mode      binary found
✓ bun               binary found
✓ opencode          binary found
```

---

## Configuration Files

| File | Purpose |
|------|---------|
| `opencode.json` | Main config — providers, agents, MCP servers, permissions |
| `AGENTS.md` | This file — routing rules, pipeline docs, tool reference |
| `.opencode/agent/scout.md` | Scout agent definition (research) |
| `.opencode/agent/plan.md` | Plan agent definition (cloud, 3-round cap) |
| `.opencode/agent/dev.md` | Dev agent definition (implementation, ReAct loop) |
| `.opencode/agent/qa.md` | QA subagent definition (validation) |
| `.opencode/agent/mem.md` | Mem subagent definition (memory commit) |
| `.env.example` | Environment variable template |
| `scripts/qmd-setup.sh` | Create qmd collections and initial config |
| `scripts/check-services.sh` | Verify all services are healthy |
| `start.sh` | Start opencode with EXA enabled |

---

## Key Decisions & Learnings

- **oMLX port**: 8005 (not 8080 as Plan.md suggested — matches actual running instance)
- **Local model**: Qwen3.5-27B-Claude-4.6-Opus-Distilled-MLX-4bit for all local agents (single model, no 7B/14B split)
- **Cloud model**: opencode-go/glm-5.1 for plan agent (cost-controlled, 3-round cap)
- **Agent modes**: scout/plan/dev = primary (user-switchable via /mode), qa/mem = subagent (invoked automatically)
- **context-mode**: Plugin + MCP tool routing — all I/O goes through sandbox
- **qmd**: Bun-based MCP server (`bun @tobilu/qmd mcp`) for persistent semantic memory