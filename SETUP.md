# Setup Guide — LocalAi Project

## Prerequisites

| Software | Version | How to get |
|----------|---------|------------|
| oMLX | latest | macOS menu bar app — serves models on port 8005 |
| ESP-IDF | v5.3+ | `git clone --recursive https://github.com/espressif/esp-idf.git ~/esp/esp-idf` |
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

## ESP-IDF / ESP32 Setup

For ESP32 development with LSP support:

```bash
# 1. Install ESP-IDF prerequisites
python3 -m pip install --user -r ~/esp/esp-idf/requirements.txt
~/esp/esp-idf/install.sh  # installs toolchains (esp-clang, Xtensa/RISC-V gcc)

# 2. Navigate to your ESP-IDF project and initialize
cd my-esp32-project
. $IDF_PATH/export.sh
bash path/to/local-ai/scripts/init-esp32.sh

# 3. Start opencode
opencode
```

The init script will:
1. Detect `esp-clangd` binary and cross-compiler paths
2. Generate `.opencode/esp-shell.sh` (IDF-aware shell wrapper)
3. Generate `.clangd` project config (filters GCC-only flags)
4. Merge LSP config into `opencode.json`
5. Run `idf.py reconfigure` to create `compile_commands.json`
6. Symlink ESP32 skills into `.opencode/skills/`

### Verify ESP32 setup

```bash
bash path/to/local-ai/scripts/check-esp32.sh
```

## Expected service check output

```
✓ oMLX              localhost:8005  (gemma-4-e4b-it-4bit)
✓ qmd               status ok       (5 collections: tasks, patterns, plans, research, builds)
✓ context-mode      binary found
✓ bun               binary found
✓ opencode          binary found
```

## oMLX Configuration (Manual Steps)

**Important**: These must be configured in the oMLX admin dashboard, not in opencode.json.

1. Open oMLX admin dashboard: http://127.0.0.1:8005/admin
2. Enable **Context Scaling** (Claude Code Optimization) — this makes oMLX report a larger context to OpenCode so compaction triggers before the real limit is hit
3. Set **Memory Limit (Models Only)** to ~20GB — leaves headroom for macOS and other processes
4. Download the **gemma-4-e4b-it-4bit** model if not already available

## Configuration Files

| File | Purpose |
|------|---------|
| `opencode.json` | Main config — providers, agents, MCP servers, permissions |
| `AGENTS.md` | Agent pipeline rules, context-mode routing, tool reference |
| `.opencode/agent/scout.md` | Scout agent definition (research) |
| `.opencode/agent/plan.md` | Plan agent definition (cloud, 3-round cap) |
| `.opencode/agent/builder.md` | Builder agent definition (orchestration) |
| `.opencode/agent/dev.md` | Dev agent definition (implementation, ReAct loop) |
| `.opencode/agent/coder.md` | Coder subagent definition (focused implementation) |
| `.opencode/agent/qa.md` | QA subagent definition (validation) |
| `.opencode/agent/mem.md` | Mem subagent definition (memory commit) |
| `.opencode/skills/esp32-idf/` | ESP-IDF toolchain skill |
| `.opencode/skills/esp32-patterns/` | ESP32 patterns skill |
| `.env.example` | Environment variable template |
| `scripts/qmd-setup.sh` | Create qmd project-local index and collections |
| `scripts/check-services.sh` | Verify all services are healthy |
| `scripts/init-esp32.sh` | Initialize ESP-IDF project with LSP support |
| `scripts/check-esp32.sh` | Verify ESP-IDF + LSP environment |
| `templates/AGENTS-esp32.md` | AGENTS.md template for ESP32 projects |
| `start.sh` | Start opencode with EXA enabled |

---

## Key Decisions & Learnings

- **oMLX port**: 8005 (matches actual running instance)
- **Local model**: gemma-4-e4b-it-4bit for all local agents (via oMLX, fits 32GB Mac at 32k context)
- **Cloud models**: opencode-go/qwen3.7-plus for plan, opencode-go/deepseek-v4-flash for builder (cost-controlled)
- **Context limits**: 32768 context / 8192 output for local model, compaction reserved 4000
- **oMLX context scaling**: Must be enabled in admin dashboard (http://127.0.0.1:8005/admin) — Claude Code Optimization
- **context-mode**: Plugin + MCP tool routing — all I/O goes through sandbox
- **qmd**: Bun-based MCP server (`bunx @tobilu/qmd mcp`) for persistent semantic memory
- **ESP32 support**: Two domain skills (`esp32-idf`, `esp32-patterns`) for ESP-IDF development with LSP via `esp-clangd`

---

## oMLX Integration Notes

- **Context scaling**: Enable in oMLX admin dashboard → Claude Code Optimization. This makes oMLX report a larger context to OpenCode so compaction triggers before the real limit is hit.
- **Memory limit**: Set Memory Limit (Models Only) to ~20GB in oMLX admin dashboard.
- **Prefill behavior**: MLX performs full prefill before emitting tokens. Time-to-first-token rises linearly with input length. Keep system prompt small.
- **KV cache**: Memory scales linearly with configured context limit. gemma-4-e4b-it-4bit at 32k context uses ~4-6 GB KV cache (fits in 32GB Mac).