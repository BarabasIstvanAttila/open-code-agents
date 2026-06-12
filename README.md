# open-code-agents

Local-first AI agent infrastructure for OpenCode. Provides a complete 7-agent pipeline (scout → plan → builder → coder subagents → qa → mem) powered by local models via oMLX, with persistent semantic memory through qmd.

**Use case**: Add this as a Git submodule to any project to get full AI-powered development support running locally through OpenCode.

---

## Architecture

```
  Your Project
   │
   ├── local-ai/                  ← This submodule
   │   ├── opencode.json          ← Agent configuration (providers, MCP servers, tools)
   │   ├── AGENTS.md              ← Agent routing rules and pipeline docs
   │   ├── .opencode/agent/       ← Agent definitions (scout, plan, builder, dev, coder, qa, mem)
   │   ├── .opencode/skills/      ← OpenCode skills
   │   └── scripts/               ← Setup and maintenance scripts
   │
   ├── AGENTS.md                  ← symlink → local-ai/AGENTS.md
   ├── opencode.json              ← symlink → local-ai/opencode.json (or merged)
   ├── .opencode/agent/           ← symlink → local-ai/.opencode/agent/
   ├── .opencode/skills/          ← symlink → local-ai/.opencode/skills/
   ├── .agent/                    ← Agent working files (gitignored)
   ├── .qmd/                      ← qmd search index (gitignored)
   └── memory/                    ← Persistent AI memory (versioned with repo)
       ├── tasks/
       ├── patterns/
       ├── plans/
       ├── research/
       └── builds/
```

### Agent Pipeline

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

### Model routing

- **Local (oMLX)**: Runs on your Mac via oMLX on port 8005. Handles scout, dev, coder, qa, and mem agents. Zero data leaves your machine.
  - `gemma-4-e4b-it-4bit` — local model (32K context, 8K output)
- **Cloud (OpenCode)**: Used for plan and builder agents.
  - `qwen3.7-plus` — plan agent (200K context)
  - `deepseek-v4-flash` — builder agent (32K context, cost-controlled)

---

## Quick Start (Standalone)

If you want to use this project on its own (not as a submodule):

```bash
git clone git@github.com:BarabasIstvanAttila/open-code-agents.git
cd open-code-agents

# Install prerequisites
brew install bun          # or: curl -fsSL https://bun.sh/install | bash
npm install -g opencode-ai
npm install -g @tobilu/qmd

# Set environment variables
export OMLX_API_KEY="your-key"
export CONTEXT7API="your-key"

# Set up qmd collections and index
./scripts/qmd-setup.sh

# Verify all services
./scripts/check-services.sh

# Start OpenCode
OPENCODE_ENABLE_EXA=1 opencode
```

---

## Using as a Git Submodule

This is the primary use case. Add this project as a submodule to give any repository local AI support via OpenCode.

### Adding the submodule

From your project root:

```bash
# Add this repository as a submodule
git submodule add git@github.com:BarabasIstvanAttila/open-code-agents.git local-ai
git submodule update --init --recursive

# Run the initialization script
bash local-ai/scripts/init-submodule.sh local-ai
```

The init script will:

1. **Validate prerequisites** — Check for git, bun, opencode CLI, oMLX, qmd
2. **Create symlinks** — Link config files from the submodule into your project root so OpenCode can find them:
   - `AGENTS.md` → `local-ai/AGENTS.md`
   - `.opencode/agent/` → `local-ai/.opencode/agent/`
   - `.opencode/skills/` → `local-ai/.opencode/skills/`
   - `.opencode/package.json` → `local-ai/.opencode/package.json`
3. **Handle opencode.json** — If your project doesn't have one, it symlinks the submodule's config. If it does, it prints merge instructions.
4. **Create working directories** — `.agent/`, `memory/` (with tasks, patterns, plans, research, builds subdirs)
5. **Initialize qmd** — Set up project-local index and collections
6. **Update .gitignore** — Add entries for `.agent/`, `.qmd/`, `*.secrets/`, `.env`, `memory/`

### Setting environment variables

Add to your shell profile (`~/.zshrc` or `~/.bashrc`):

```bash
export OMLX_API_KEY="your-omlx-key"
export CONTEXT7API="your-context7-key"
```

Or create a `.env` file in your project root (add `.env` to `.gitignore`):

```bash
OMLX_API_KEY=your-omlx-key
CONTEXT7API=your-context7-key
```

### Starting oMLX

oMLX serves local models on port 8005. Start it before using OpenCode:

```bash
# macOS menu bar app — recommended
open -a oMLX

# Or via Homebrew service
brew services start jundot/omlx/omlx
```

### Starting Docker (for MCP servers)

Some MCP servers (duckduckgo, sequentialthinking) run as Docker containers:

```bash
open -a Docker    # macOS
# Or: sudo systemctl start docker    # Linux
```

### Verifying the setup

```bash
bash local-ai/scripts/check-services.sh
```

Expected output:

```
✓ oMLX              localhost:8005
✓ qmd               status ok
✓ context-mode      binary found
✓ bun               binary found
✓ opencode          binary found
```

### Starting OpenCode

```bash
OPENCODE_ENABLE_EXA=1 opencode
```

Then use the agent pipeline:

**Automated flow (recommended — 3 commands):**
```
/mode scout    →  Research the task
/mode plan     →  Create plan + auto-save to memory
/mode builder  →  Orchestrate coders + auto-run QA + auto-save to memory
```

**Standalone dev flow (for simple tasks — 5 commands):**
```
/mode scout    →  Research the task
/mode plan     →  Create plan + auto-save to memory
/mode dev      →  Implement the plan (standalone, full context)
/mode qa       →  Validate the implementation
/mode mem      →  Commit to persistent memory
```

---

## Submodule Operations

| Operation | Command |
|-----------|---------|
| **Initialize** (fresh clone) | `git submodule update --init --recursive` |
| **Initialize** (first time) | `bash local-ai/scripts/init-submodule.sh local-ai` |
| **Update** (pull latest) | `bash local-ai/scripts/update-submodule.sh local-ai` |
| **Update** (manual) | `cd local-ai && git pull origin main && cd ..` |
| **Check status** | `git submodule status local-ai` |
| **Remove** | See [Removing the submodule](#removing-the-submodule) below |

### Cloning a project that already uses this submodule

```bash
git clone <your-project-url>
cd <your-project>
git submodule update --init --recursive
bash local-ai/scripts/init-submodule.sh local-ai
```

### Updating to the latest version

```bash
bash local-ai/scripts/update-submodule.sh local-ai

# Then commit the updated reference
git add local-ai
git commit -m "chore: update local-ai submodule"
```

### Removing the submodule

```bash
# Remove symlinks (adjust if you used a different submodule path)
rm AGENTS.md
rm opencode.json
rm -rf .opencode/agent
rm -rf .opencode/skills
rm .opencode/package.json

# Remove the submodule
git submodule deinit -f local-ai
git rm -f local-ai
rm -rf .git/modules/local-ai

# Commit the removal
git commit -m "chore: remove local-ai submodule"
```

---

## Configuration

### opencode.json

If your project already has its own `opencode.json`, the init script will not overwrite it. Instead, you need to manually merge the required sections:

**Required sections to add:**

```json
{
  "instructions": ["AGENTS.md"],
  "provider": {
    "omlx": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "oMLX",
      "options": {
        "baseURL": "http://127.0.0.1:8005/v1",
        "apiKey": "{env:OMLX_API_KEY}"
      },
      "models": {
        "gemma-4-e4b-it-4bit": {
          "name": "gemma-4-e4b-it-4bit",
          "limit": { "context": 32768, "output": 8192 }
        }
      }
    }
  },
  "mcp": {
    "context7": {
      "type": "remote",
      "url": "https://mcp.context7.com/mcp",
      "headers": { "CONTEXT7_API_KEY": "{env:CONTEXT7API}" },
      "enabled": true
    },
    "duckduckgo": {
      "type": "local",
      "command": ["docker", "run", "-i", "--rm", "mcp/duckduckgo"],
      "enabled": true
    },
    "sequentialthinking": {
      "type": "local",
      "command": ["docker", "run", "-i", "--rm", "mcp/sequentialthinking"],
      "enabled": true
    },
    "qmd": {
      "type": "local",
      "command": ["bunx", "@tobilu/qmd", "mcp"],
      "enabled": true
    }
  },
  "plugin": ["context-mode"]
}
```

**Or replace your opencode.json entirely:**

```bash
rm opencode.json
ln -s local-ai/opencode.json opencode.json
```

### Environment variables

| Variable | Required | Description |
|----------|----------|-------------|
| `OMLX_API_KEY` | Yes | API key for local oMLX server |
| `CONTEXT7API` | Yes | API key for Context7 documentation lookup |
| `OPENCODE_ENABLE_EXA` | Optional | Set to `1` to enable Exa search |

### MCP Servers

| Server | Type | Purpose |
|--------|------|---------|
| **context7** | Remote | Library documentation lookup |
| **duckduckgo** | Docker | Web search |
| **sequentialthinking** | Docker | Structured reasoning chains |
| **qmd** | Local (bunx) | Persistent semantic memory |
| **context-mode** | Plugin | Sandboxed execution, I/O routing |

---

## Working Files

These directories are created by init and should be in `.gitignore`:

```
.agent/                  ← Agent working files (gitignored)
├── research-report.md   ← scout output
├── plan.md              ← plan agent output
├── builder-progress.md  ← builder runtime progress tracking
├── builder-report.md    ← builder final report
├── dev-report.md        ← dev agent output (standalone mode)
├── qa-report.md         ← qa agent output
└── memory-log.md        ← mem agent output

.qmd/                    ← qmd search index (gitignored)
```

This directory is **versioned with your repo**:

```
memory/                  ← Persistent AI memory
├── tasks/               ← Task summaries
├── patterns/            ← Code patterns
├── plans/               ← Archived plans
├── research/            ← Archived research
└── builds/              ← Per-task build records (created by builder)
    └── <date>-<slug>/
        ├── plan.md      ← Copy of plan used
        ├── research.md  ← Copy of research used
        ├── steps/       ← Per-step implementation records
        └── summary.md   ← Build results summary
```

---

## Prerequisites

| Software | Version | Install |
|----------|---------|---------|
| **oMLX** | latest | macOS menu bar app — serves models on port 8005 |
| **Node.js** | 20+ | `brew install node` |
| **bun** | latest | `curl -fsSL https://bun.sh/install \| bash` |
| **OpenCode** | latest | `npm install -g opencode-ai` |
| **qmd** | latest | `npm install -g @tobilu/qmd` |
| **Docker** | latest | For MCP servers (duckduckgo, sequentialthinking) |
| **context-mode** | — | Installed as OpenCode plugin automatically |

---

## Project Structure

```
open-code-agents/
├── AGENTS.md                    ← Agent pipeline documentation & routing rules
├── opencode.json                ← OpenCode configuration (providers, MCP, tools)
├── start.sh                     ← Start OpenCode with EXA enabled
├── Install.md                   ← Installation notes
├── README.md                    ← This file
├── .opencode/
│   ├── agent/
│   │   ├── scout.md             ← Research agent definition
│   │   ├── plan.md              ← Planning agent definition
│   │   ├── builder.md           ← Orchestration agent definition
│   │   ├── dev.md               ← Standalone implementation agent definition
│   │   ├── coder.md             ← Focused subagent definition (spawned by builder)
│   │   ├── qa.md                ← QA validation agent definition
│   │   └── mem.md               ← Memory agent definition
│   ├── skills/
│   │   └── skill-builder/       ← Skill creation skill
│   ├── .gitignore               ← Ignore node_modules in .opencode
│   └── package.json             ← Plugin dependencies (context-mode)
├── scripts/
│   ├── init-submodule.sh        ← Initialize as submodule in a parent project
│   ├── update-submodule.sh      ← Update submodule to latest version
│   ├── check-services.sh        ← Verify all services are running
│   └── qmd-setup.sh             ← Initialize qmd collections and index
├── .secrets/                    ← Secret files (gitignored)
├── memory/                      ← Persistent AI memory collections
└── .agent/                      ← Agent working files (gitignored)
```

---

## How It Works

When you add this project as a submodule and run `init-submodule.sh`:

1. **Symlinks** connect the parent project root to the submodule's config files. OpenCode expects `opencode.json`, `AGENTS.md`, and `.opencode/` in the project root — symlinks make this work transparently.

2. **Agent definitions** in `.opencode/agent/` tell OpenCode which agents are available, their models, temperatures, and permissions.

3. **MCP servers** (context7, duckduckgo, sequentialthinking, qmd) provide tools for web search, documentation lookup, structured reasoning, and persistent memory.

4. **context-mode plugin** enforces I/O routing rules — all large reads go through a sandbox to prevent context window flooding.

5. **qmd** builds a persistent semantic search index in `.qmd/` that grows smarter over sessions. After 5+ tasks, the scout agent finds relevant past patterns in under 10 seconds.

---

## Troubleshooting

### oMLX not responding

```bash
curl -s http://127.0.0.1:8005/v1/models | head -5
# If empty or error, start oMLX:
open -a oMLX
```

### oMLX works in browser but lags in OpenCode

This is almost always caused by the **context window limit** being set too high for a local model. The project config uses `32768` for context and `8192` for output — these are tuned for the gemma-4-e4b-it-4bit model running locally on Mac hardware.

If you experience long delays before the first token appears:

1. Check your `opencode.json` — the oMLX model limits should be:
   ```json
   "limit": { "context": 32768, "output": 4096 }
   ```
2. Do NOT set context to 262144 (256K) — the local model cannot process that much context efficiently and will hang for minutes before responding.
3. Verify the model is responding at all:
   ```bash
    curl -s -H "Authorization: Bearer $OMLX_API_KEY" \
      -H "Content-Type: application/json" \
      -d '{"model":"gemma-4-e4b-it-4bit","messages":[{"role":"user","content":"hello"}],"max_tokens":50}' \
      http://127.0.0.1:8005/v1/chat/completions
   ```
4. If the curl test works but OpenCode still lags, the issue is context size — OpenCode sends the full system prompt (AGENTS.md + agent definitions + conversation history) which can be very large.
5. **Enable oMLX context scaling** in the admin dashboard (http://127.0.0.1:8005/admin) — this makes oMLX report a larger context to OpenCode so compaction triggers earlier.

### Docker MCP servers failing

```bash
docker ps                        # Check Docker is running
docker pull mcp/duckduckgo       # Pull the image manually
docker pull mcp/sequentialthinking
```

### qmd errors

```bash
which qmd                        # Verify qmd is installed
qmd status                       # Check index health
bunx @tobilu/qmd init            # Re-initialize if needed
```

### Symlinks broken after git operations

```bash
bash local-ai/scripts/init-submodule.sh local-ai    # Re-create symlinks (idempotent)
```

### Submodule not updating

```bash
cd local-ai && git fetch origin && git checkout main && git pull origin main
cd ..
git add local-ai
git commit -m "chore: update local-ai submodule"
```

### context-mode not found

context-mode is installed as an OpenCode plugin. If missing:

```bash
cd .opencode && bun install    # Installs @opencode-ai/plugin
```

---

## License

This project is designed to be used as a submodule. See the repository for license details.