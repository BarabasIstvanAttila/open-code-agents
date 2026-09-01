# AGENTS.md
# Loaded by OpenCode as always-on context for every agent session.
# Keep this short — detailed knowledge lives in the skills.

## Project type
ESP-IDF project. Target: see sdkconfig → CONFIG_IDF_TARGET.
Language: C17 / C++17 with ESP-IDF constraints (no exceptions, no RTTI by default).

## Key paths
| Path | Purpose |
|---|---|
| `build/compile_commands.json` | LSP index — refresh with `idf.py reconfigure` |
| `sdkconfig` | Kconfig build configuration |
| `components/` | Project components |
| `main/` | Main application component |
| `build/` | Build output — never edit files here |

## Skills to load
Always check if the task is ESP32-related. If so:
- `esp32-idf` — when running build/flash/monitor/debug commands or interpreting LSP errors
- `esp32-patterns` — when designing or implementing components, FreeRTOS tasks, drivers

## Build signal trust order
1. `idf.py build` output → ground truth for compilation and linking
2. `idf.py monitor` output → ground truth for runtime behavior
3. LSP diagnostics → fast edit-time signal (may have false positives if index is stale)

## Agent roles (reminder)
| Agent | Role | Can edit |
|---|---|---|
| dev | Implement and debug | ✅ |
| qa | Verify and test | ❌ |
| scout | Explore code and docs | ❌ |
| plan | Design and architecture | ❌ |
| mem | Persist patterns to memory | ✅ |

## Never do
- Mark a task done without a clean `idf.py build`
- Edit files in `build/` or `managed_components/`
- Run `idf.py flash` or `idf.py erase_flash` without user confirmation
- Run `idf.py fullclean` without user confirmation
