# Setup Guide — LocalAi Project

## Prerequisites

| Software | Version | How to get |
|----------|---------|------------|
| oMLX | latest | macOS menu bar app — serves models on port 8005 |
| Node.js | 20+ | `brew install node` |
| bun | latest | `curl -fsSL https://bun.sh/install \| bash` |
| OpenCode | latest | `npm install -g opencode-ai` |
| qmd | latest | `npm install -g @tobilu/qmd` or `bun install -g @tobilu/qmd` |
| context-mode MCP | — | follow context-mode MCP server setup |

## Environment variables

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

## Initial setup

```bash
# 1. Install qmd and create project-local collections
bun install -g @tobilu/qmd
chmod +x scripts/qmd-setup.sh
./scripts/qmd-setup.sh

# 2. Verify all services
chmod +x scripts/check-services.sh
./scripts/check-services.sh

# 3. Start opencode
./start.sh
```

## Expected service check output

```
✓ oMLX              localhost:8005  (Qwen3.5-9B-OptiQ-4bit)
✓ qmd               status ok       (4 collections)
✓ context-mode      binary found
✓ bun               binary found
✓ opencode          binary found
```

## oMLX Configuration (Manual Steps)

**Important**: These must be configured in the oMLX admin dashboard, not in opencode.json.

1. Open oMLX admin dashboard: http://127.0.0.1:8005/admin
2. Enable **Context Scaling** (Claude Code Optimization) — this makes oMLX report a larger context to OpenCode so compaction triggers before the real limit is hit
3. Set **Memory Limit (Models Only)** to ~20GB — leaves headroom for macOS and other processes
4. Download the **Qwen3.5-9B-OptiQ-4bit** model if not already available

## Configuration Files

| File | Purpose |
|------|---------|
| `opencode.json` | Main config — providers, agents, MCP servers, permissions |
| `AGENTS.md` | Agent pipeline rules, context-mode routing, tool reference |
| `.opencode/agent/scout.md` | Scout agent definition (research) |
| `.opencode/agent/plan.md` | Plan agent definition (cloud, 3-round cap) |
| `.opencode/agent/dev.md` | Dev agent definition (implementation, ReAct loop) |
| `.opencode/agent/qa.md` | QA subagent definition (validation) |
| `.opencode/agent/mem.md` | Mem subagent definition (memory commit) |
| `.env.example` | Environment variable template |
| `scripts/qmd-setup.sh` | Create qmd project-local index and collections |
| `scripts/check-services.sh` | Verify all services are healthy |
| `start.sh` | Start opencode with EXA enabled |