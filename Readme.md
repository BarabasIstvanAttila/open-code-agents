# LocalAI Development Environment

<div align="center">

**A local-first AI-powered development workflow using OpenCode, oMLX, and semantic memory.**

[![Platform](https://img.shields.io/badge/Platform-macOS-121212.svg)](https://www.apple.com/macos/) [![oMLX](https://img.shields.io/badge/oMLX-27B-0066CC.svg)](https://github.com/ml-explore/mlx) [![OpenCode](https://img.shields.io/badge/OpenCode-AI-FF6B6B.svg)](https://opencode.ai)

</div>

---

## 📖 Overview

**LocalAI** is a sophisticated local-first development environment that combines multiple AI models, MCP servers, and semantic search to create an intelligent coding assistant pipeline. By keeping AI processing local while optionally leveraging cloud models for specific tasks, it provides privacy, speed, and cumulative learning across development sessions.

### 🎯 Scope

This project provides:

- **Multi-agent AI pipeline** for research, planning, implementation, and QA
- **Local-first architecture** with optional cloud model integration
- **Persistent semantic memory** that accumulates knowledge across sessions
- **Context-aware tool routing** that protects against context window bloat
- **Sandboxed execution** for safe code analysis and transformation
- **Framework documentation lookup** via Context7 integration
- **Web search capabilities** through DuckDuckGo MCP

The system is designed for macOS development environments and leverages the MLX framework for efficient local model inference.

---

## 🏗️ Architecture

```
                    User
                      │
    ┌─────────────────┼─────────────────┐
    │ /mode scout    │ /mode plan      │ /mode dev
    │ /mode qa       │ /mode mem       │
    ▼─────────────────┴─────────────────▼
         OpenCode Terminal
                   │
    ┌──────────────┴──────────────┐
    │                             │
    ▼                             ▼
┌─────────┐               ┌─────────────┐
│ oMLX    │◄── Local Models (27B)      │
│:8005    │    Qwen3.5-27B             │
└─────────┘               └─────────────┘
    │
    │ MCP Servers (Tool Routing)
    │
    ├──► context-mode    ── Sandboxed execution
    ├──► qmd             ── Semantic memory
    ├──► context7        ── Framework docs
    ├──► duckduckgo      ── Web search
    └──► sequentialthink ── Reasoning chains
```

### Agent Pipeline

| Agent | Model | Role |
|-------|-------|------|
| **scout** | Qwen3.5-27B (local) | Research — gather context, map codebase, fetch docs |
| **plan** | glm-5.1 (cloud) | Planning — produce file-specific implementation plans |
| **dev** | Qwen3.5-27B (local) | Implement — ReAct loop, follow plan step by step |
| **qa** | Qwen3.5-27B (local) | Validate — tests, lint, typecheck, plan compliance |
| **mem** | Qwen3.5-27B (local) | Memory — commit task summaries, patterns to qmd |

---

## 🚀 Quick Start

### Prerequisites

| Tool | Installation Command |
|------|---------------------|
| **oMLX** | Download macOS menu bar app from [MLX](https://github.com/ml-explore/mlx) |
| **Node.js** | `brew install node` (v20+) |
| **Bun** | `curl -fsSL https://bun.sh/install \\| bash` |
| **OpenCode** | `npm install -g opencode-ai` |
| **qmd** | `npm install -g @tobilu/qmd` |
| **Docker** | [Install Docker Desktop](https://www.docker.com/products/docker-desktop/) |

### Installation

```bash
# 1. Clone this repository
git clone <your-repo-url>
cd LocalAi

# 2. Set up environment variables
cp .env.example .env  # Edit and fill in API keys

# Add to ~/.zshrc for persistence:
echo 'export OMLX_API_KEY="your-key-here"' >> ~/.zshrc
echo 'export ANTHROPIC_API_KEY="sk-ant-..."' >> ~/.zshrc
echo 'export GEMINI_API_KEY="AIza..."' >> ~/.zshrc
echo 'export CONTEXT7API="your-key-here"' >> ~/.zshrc
source ~/.zshrc

# 3. Install qmd and create collections
npm install -g @tobilu/qmd
chmod +x scripts/qmd-setup.sh
./scripts/qmd-setup.sh

# 4. Verify all services
chmod +x scripts/check-services.sh
./scripts/check-services.sh
```

### Expected Service Check Output

```
✓ oMLX              localhost:8005  (Qwen3.5-27B-Claude-4.6-Opus-Distilled-MLX-4bit)
✓ qmd               status ok       (4 collections)
✓ context-mode      binary found
✓ bun               binary found
✓ opencode          binary found
```

---

## 🔧 Tools & Technologies

### AI/ML Frameworks

| Tool | Purpose | Type |
|------|---------|------|
| **oMLX** | Local model inference (27B parameter model) | Inference Engine |
| **Qwen3.5-27B** | Main local model for all agents | Language Model |
| **OpenCode** | Terminal interface, session management | Platform |
| **glm-5.1** | Cloud model for planning (cost-controlled) | Language Model |

### MCP Servers

| MCP Server | Purpose | Source |
|------------|---------|--------|
| **context-mode** | Sandboxed execution, tool routing | Local (Plugin) |
| **qmd** | Persistent semantic memory | Local (Bun) |
| **context7** | Framework documentation lookup | Remote (API) |
| **duckduckgo** | Web search and content fetching | Docker (mcp/duckduckgo) |
| **sequentialthinking** | Structured reasoning chains | Docker (mcp/sequentialthinking) |

### Development Tools

| Tool | Purpose |
|------|---------|
| **OpenCode** | Agent orchestration, terminal interface |
| **Bun** | Fast JavaScript runtime, package manager |
| **Node.js** | Runtime for context-mode plugin |
| **SQLite FTS5** | Full-text search for knowledge base |
| **BM25** | Ranking algorithm for semantic search |

---

## 📚 How to Use

### Running a Task

```bash
# Start the environment
./start.sh

# Enter the agent pipeline
opencode

# Step 1: Research phase
/mode scout
Add rate limiting to POST /api/auth/login — 5 req per IP per 15 min, Redis-backed

# Step 2: Planning phase
/mode plan

# Step 3: Implementation phase
/mode dev

# Step 4: Validation phase
/mode qa

# Step 5: Memory commit phase
/mode mem
```

### Project Structure

```
LocalAi/
├── .opencode/
│   ├── agent/
│   │   ├── scout.md    # Scout agent definition
│   │   ├── plan.md     # Plan agent definition
│   │   ├── dev.md      # Dev agent definition
│   │   ├── qa.md       # QA subagent definition
│   │   └── mem.md      # Memory subagent definition
│   └── skills/
│       └── skill-builder/
├── .agent/
│   ├── research-report.md
│   ├── plan.md
│   ├── dev-report.md
│   ├── qa-report.md
│   └── memory-log.md
├── scripts/
│   ├── qmd-setup.sh
│   ├── check-services.sh
│   └── start.sh
├── opencode.json       # Main configuration
├── AGENTS.md           # Agent pipeline documentation
└── Readme.md          # This file
```

---

## 🧠 Persistent Memory

The `qmd` system accumulates knowledge across sessions in `~/.config/qmd/memory/`:

```
~/.config/qmd/memory/
├── tasks/      # Task summaries (written by mem)
├── patterns/   # Code patterns (written by mem)
├── plans/      # Archived plans (written by mem)
└── research/   # Archived research (written by mem)
```

**How qmd grows smarter:**

- After 5 tasks: Scout finds relevant past patterns in under 10 seconds
- After 20 tasks: Plan agent often completes in round 1 alone
- After 50 tasks: Project-specific AI memory that knows every pattern, decision, and lesson

---

## ⚙️ Configuration

### Environment Variables

| Variable | Description |
|----------|-------------|
| `OMLX_API_KEY` | API key for oMLX service |
| `ANTHROPIC_API_KEY` | Anthropic API key (optional) |
| `GEMINI_API_KEY` | Google Gemini API key (optional) |
| `CONTEXT7API` | Context7 API key for documentation lookup |

### opencode.json

The main configuration file controls:

- Model providers and endpoints
- MCP server configuration
- Permission rules for tools
- Agent definitions and routing
- LSP and watcher settings

See [opencode.json](./opencode.json) for the complete configuration.

---

## 📦 Using as a Git Submodule

LocalAi is designed to be shared across multiple projects as a **git submodule**. This lets you maintain a single source of truth for agent definitions, MCP server config, and tool routing rules while allowing each project to override settings as needed.

### How It Works

```
your-project/
├── .localai/                  ← git submodule (this repo)
│   ├── opencode.json          ← base config (shared)
│   ├── AGENTS.md              ← agent pipeline rules (shared)
│   ├── .opencode/             ← agent & skill definitions (shared)
│   ├── scripts/               ← setup scripts (shared)
│   └── ...
├── opencode.json              ← project-specific overrides (yours)
├── AGENTS.md                  ← project-specific instructions (yours, optional)
└── src/                       ← your actual project code
```

OpenCode loads config in priority order — **later sources override earlier ones**:

```
Remote config → Global config → OPENCODE_CONFIG env → Project opencode.json → .opencode/ dirs → Inline env
```

This means your project's `opencode.json` can selectively override provider settings, add project-specific agents, or change permissions while inheriting everything else from the submodule.

### Step 1: Add the Submodule

```bash
# From your project root
git submodule add https://github.com/<your-username>/LocalAi.git .localai
git commit -m "Add LocalAi as submodule"
```

### Step 2: Create a Project-Level opencode.json

Create an `opencode.json` in your project root that **extends** the submodule's base config:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": [".localai/AGENTS.md", "AGENTS.md"],
  "provider": {
    "omlx": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "oMLX",
      "options": {
        "baseURL": "http://127.0.0.1:8005/v1",
        "apiKey": "{env:OMLX_API_KEY}"
      },
      "models": {
        "Qwen3.5-27B-Claude-4.6-Opus-Distilled-MLX-4bit": {
          "name": "Qwen3.5-27B-Claude-4.6-Opus-Distilled-MLX-4bit",
          "limit": { "context": 262144, "output": 131072 }
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
      "command": ["bun", "@tobilu/qmd", "mcp"],
      "enabled": true
    }
  },
  "tools": {
    "sequentialthinking*": true,
    "context7*": true,
    "duckduckgo*": true,
    "context-mode*": true,
    "qmd*": true
  },
  "plugin": ["context-mode"]
}
```

### Step 3: Link Agent Definitions

OpenCode discovers agents from `.opencode/agent/` relative to the working directory. Symlink the submodule's agents into your project:

```bash
# Create the agent directory in your project
mkdir -p .opencode/agent

# Symlink all agent definitions from the submodule
ln -sf ../../.localai/.opencode/agent/scout.md .opencode/agent/scout.md
ln -sf ../../.localai/.opencode/agent/plan.md  .opencode/agent/plan.md
ln -sf ../../.localai/.opencode/agent/dev.md   .opencode/agent/dev.md
ln -sf ../../.localai/.opencode/agent/qa.md    .opencode/agent/qa.md
ln -sf ../../.localai/.opencode/agent/mem.md   .opencode/agent/mem.md

# Symlink shared skills
ln -sf ../.localai/.opencode/skills .opencode/skills
```

### Step 4: Create Project-Specific AGENTS.md (Optional)

Add a project-level `AGENTS.md` in your project root with project-specific instructions:

```markdown
# My Project — Agent Instructions

## Project Context
This is a Node.js REST API using Express + PostgreSQL.

## Conventions
- Use TypeScript strict mode
- Follow existing file naming: kebab-case
- Tests go in `__tests__/` alongside source files
- Run `npm test` before committing

## Architecture
- `src/routes/` — Express route handlers
- `src/services/` — Business logic
- `src/models/` — Database models
- `src/middleware/` — Express middleware
```

OpenCode reads both `.localai/AGENTS.md` (shared pipeline rules) and your project's `AGENTS.md` (project context).

### Step 5: Environment Setup

```bash
# Run the submodule's setup scripts
chmod +x .localai/scripts/qmd-setup.sh
.localai/scripts/qmd-setup.sh

chmod +x .localai/scripts/check-services.sh
.localai/scripts/check-services.sh
```

### Integration Strategies Compared

| Strategy | Pros | Cons | Best For |
|----------|------|------|----------|
| **Submodule + Symlinks** | Auto-updates from upstream, single source of truth | Symlinks can break on Windows | Mac/Linux teams sharing config |
| **Submodule + `OPENCODE_CONFIG`** | No symlinks needed, explicit config path | Must set env var per project | Simpler setups, CI environments |
| **Copy files** | Full control, no git coupling | No auto-updates, drift risk | One-off projects, custom setups |

### Strategy B: Using `OPENCODE_CONFIG` Env Var

If you prefer not to use symlinks, point OpenCode directly at the submodule's config:

```bash
# Add to your project's .envrc (direnv) or .zshrc
export OPENCODE_CONFIG="./.localai/opencode.json"
export OPENCODE_CONFIG_CONTENT='{"instructions":[".localai/AGENTS.md","AGENTS.md"]}'
```

Then start OpenCode normally:

```bash
opencode
```

### Cloning a Project That Uses This Submodule

```bash
# Clone with submodules
git clone --recurse-submodules <your-project-url>

# Or if already cloned
git submodule init
git submodule update
```

### Updating the Submodule

When LocalAi receives updates and you want to pull them:

```bash
# Update to latest on the default branch
git submodule update --remote .localai

# Or update to a specific tag/branch
cd .localai
git checkout v2.0.0
cd ..
git add .localai
git commit -m "Update LocalAi submodule to v2.0.0"
```

### Removing the Submodule

```bash
git submodule deinit -f .localai
rm -rf .git/modules/.localai
git rm -f .localai
git commit -m "Remove LocalAi submodule"
```

---

## 🔐 Security & Privacy

- **Local inference**: All agent reasoning runs locally via oMLX
- **Optional cloud**: Only the plan agent uses a cloud model (glm-5.1)
- **Context protection**: Sandboxed execution prevents context flooding
- **No telemetry**: OpenCode runs with `autoshare: false`
- **Permission control**: Fine-grained tool permissions in `opencode.json`

---

## 📝 License

MIT — Feel free to use, modify, and distribute.

---

## 🔗 Resources

- **OpenCode**: https://opencode.ai
- **oMLX**: https://github.com/ml-explore/mlx
- **qmd**: https://github.com/tobilu/qmd
- **context-mode**: https://github.com/mksglu/context-mode
- **Context7**: https://context7.com
- **Docker Hub MCP Servers**: https://hub.docker.com/mcp

---

<div align="center">

**Built with ❤️ using local-first AI principles**

</div>
