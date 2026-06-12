# Architecture Decision: Skills vs Agent vs Multi-Agent for ESP32

---

## The Core Question

> Should ESP32/Espressif support be a dedicated agent, a skill, or a multi-agent system?

**Answer: Two focused skills, no new agent.**

Your five existing agents already form a multi-agent system.
The skills make them domain-capable without changing their behavioral profiles.

---

## Why Not a Dedicated ESP32 Agent

An agent in OpenCode encapsulates a **behavioral mode** — it controls *how* the AI
acts: what permissions it has, what tools it can use, how it approaches work.

A skill encapsulates **domain knowledge** — the *what* the AI knows about a topic.

ESP32 development is a **knowledge domain**, not a new behavioral mode. The work still
needs all the same behaviors you already have:

| Work | Behavior | Already handled by |
|---|---|---|
| Explore IDF API | Read-only exploration | `scout` |
| Design a driver | Planning without edits | `plan` |
| Implement code | Full edit access | `build` (or your `dev`) |
| Verify it builds | Run commands | `build` + `qa` |
| Store patterns | Memory accumulation | `mem` |

Adding an `esp32` agent creates a **behavioral overlap problem**: when do you use
`dev` vs `esp32`? You'd end up duplicating logic across two agents and maintaining
both as IDF APIs change. That's the opposite of compounding value.

---

## Why Not a Single Big Agent

The tempting alternative: one `esp32` subagent that knows everything about the platform
and can be spawned by `build` for ESP32 tasks.

Problems:
- **Always-on token cost.** An agent's prompt is always in context. A skill is loaded
  on-demand only when the agent recognizes it needs it.
- **No composability.** Your `plan` agent needs FreeRTOS patterns. Your `scout` needs
  LSP interpretation rules. Your `qa` needs build error patterns. A single agent can't
  be in multiple behavioral roles at once.
- **Behavioral vs knowledge conflation.** "Implement using FreeRTOS" is knowledge.
  "Don't make file edits" is behavior. Mixing them creates a fragile, overloaded agent.

---

## The Right Model: Skills as Domain Modules

```
                         ┌─────────────┐
                         │ opencode-   │
                         │   shared    │
                         │  submodule  │
                         └──────┬──────┘
                                │ symlinked to .opencode/skills/
                    ┌───────────┼───────────┐
                    │                       │
              ┌─────▼──────┐        ┌───────▼──────────┐
              │ esp32-idf  │        │  esp32-patterns  │
              │  SKILL.md  │        │    SKILL.md      │
              └─────┬──────┘        └───────┬──────────┘
                    │                       │
    Loaded on-demand by any agent that needs it
                    │                       │
        ┌───────────┼───────────────────────┤
        │           │           │           │
     scout        build        plan        mem
  (LSP hints)  (build cmds) (FreeRTOS   (what to
               (error msgs)  patterns)    store)
```

Each skill is:
- **Lazy-loaded** — zero cost until an agent calls `skill({ name: "..." })`
- **Composable** — multiple agents can use the same skill independently
- **Maintainable** — update the skill once, all agents benefit
- **Versioned** — lives in `opencode-shared`, compounding value over time

---

## When a Dedicated Subagent Would Make Sense

A subagent is justified when you need a distinct set of **bash permissions** that would
be wrong to give the main agent, or a **hidden orchestration step** the user shouldn't
see in the main flow.

For ESP32, one optional candidate: an `esp32-flash` hidden subagent.

**Case for it:**
- Flash/debug requires specific serial port access — you might want `ask` permission on
  `idf.py flash` but `allow` on `idf.py build`
- Hardware operations are a distinct, dangerous phase (flashing wrong firmware = brick)
- Could be hidden (`hidden: true`) and invoked programmatically only after QA passes

**Case against it (for now):**
- Your `build` agent already has full bash access
- The risk of accidental flash is managed by making `idf.py flash` require a port arg
  (`-p /dev/cu.usbserial-*`) — you'd never accidentally flash without a connected device
- Adds an agent to maintain for marginal safety benefit

**Recommendation:** start with skills only. Add the `esp32-flash` hidden subagent
if you find yourself wanting per-command permission control.

---

## Mapping Skills to Agent Modes

No agent files need to change. The skills are discoverable automatically via the
`skill` tool. Each agent will see them in `<available_skills>` and load them when
the task context triggers it.

You can accelerate discovery by mentioning the skills in `AGENTS.md`:

```markdown
## Available Skills

When working on ESP-IDF projects, load the relevant skills:

- `esp32-idf`     → idf.py commands, LSP interpretation, flash/monitor/debug
- `esp32-patterns` → FreeRTOS, component structure, GPIO/SPI/I2C/NVS, C++ idioms
```

This is a hint, not an instruction — agents decide when to load skills based on task
context. The `AGENTS.md` entry just removes ambiguity.

---

## init.sh Addition for opencode-shared

```bash
# Detect ESP-IDF project and symlink skills
if [ -f "sdkconfig" ] || grep -q "idf_component_register" CMakeLists.txt 2>/dev/null; then
    echo "[init] ESP-IDF project detected — linking ESP32 skills"
    mkdir -p .opencode/skills
    SHARED="$(cd "$(dirname "$0")" && pwd)"   # opencode-shared dir

    for skill in esp32-idf esp32-patterns; do
        if [ ! -L ".opencode/skills/$skill" ]; then
            ln -sf "$SHARED/skills/$skill" ".opencode/skills/$skill"
            echo "[init]   linked $skill"
        fi
    done
fi
```

---

## File Layout in opencode-shared

```
opencode-shared/
├── skills/
│   ├── esp32-idf/
│   │   └── SKILL.md          ← toolchain ops, LSP, build/flash/debug
│   └── esp32-patterns/
│       └── SKILL.md          ← FreeRTOS, components, GPIO/SPI/I2C, C++ idioms
├── agent/
│   ├── dev.md                ← unchanged (skills loaded on-demand)
│   ├── qa.md                 ← unchanged
│   ├── scout.md              ← unchanged
│   ├── plan.md               ← unchanged
│   └── mem.md                ← unchanged
└── init.sh                   ← add ESP-IDF detection block
```

---

## Summary

| Approach | Verdict | Reason |
|---|---|---|
| Dedicated `esp32` primary agent | ✗ Avoid | Behavioral overlap with existing agents; hard to maintain |
| Dedicated `esp32` subagent | ○ Optional later | Only justified if you need per-command bash permissions |
| Multi-agent system | ✓ Already exists | Your 5 agents ARE the multi-agent system |
| Two focused skills | ✓ Correct | Domain knowledge composable across all agents, lazy-loaded |

The guiding principle: agents own **how**, skills own **what**.
ESP32 is a "what" problem. Two skills is the answer.
