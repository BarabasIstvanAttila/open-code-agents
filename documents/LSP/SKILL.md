---
name: esp32-idf
description: ESP-IDF toolchain for ESP32 C/C++ development. Load when running idf.py commands, interpreting clangd/LSP diagnostics in cross-compiled code, diagnosing build/linker errors, flashing firmware, reading monitor output, or setting up OpenOCD/GDB hardware debugging.
compatibility: opencode
metadata:
  domain: embedded
  framework: esp-idf
  targets: esp32,esp32s2,esp32s3,esp32c3,esp32c6,esp32h2
---

## When to load this skill

Load when:
- Editing `.c`, `.cpp`, `.h` files in a project with an `sdkconfig` or `CMakeLists.txt` calling `idf_component_register`
- Interpreting LSP diagnostics that might be cross-compiler false positives
- Running or debugging `idf.py` commands
- Hitting build errors, linker errors, or undefined references
- Flashing firmware or reading serial monitor output

---

## Environment

Always source IDF before any `idf.py` command (once per shell session):
```bash
. $IDF_PATH/export.sh
echo $IDF_PATH      # e.g. ~/esp/esp-idf
echo $IDF_TARGET    # e.g. esp32, esp32c3
```

Set/change target:
```bash
idf.py set-target esp32      # also accepts esp32s3, esp32c3, esp32c6, esp32h2
# Target change requires fullclean:
idf.py fullclean && idf.py set-target esp32c3
```

---

## Core idf.py Commands

| Command | Purpose | When |
|---|---|---|
| `idf.py reconfigure` | Re-run CMake only, refreshes `compile_commands.json` | After adding files, components, or changing includes |
| `idf.py build 2>&1 \| tee build.log` | Full build, capture output | Before marking any task done |
| `idf.py fullclean` | Delete entire build dir | After target change or mysterious CMake errors |
| `idf.py flash` | Flash connected device | Needs `-p /dev/cu.usbserial-*` on Mac |
| `idf.py monitor` | Serial monitor (115200 baud by default) | Ctrl+] to exit |
| `idf.py flash monitor` | Flash then immediately monitor | Most common combined workflow |
| `idf.py menuconfig` | Interactive Kconfig UI | Change sdkconfig options |
| `idf.py size` | Binary size report | Verify binary fits partition |
| `idf.py size-components` | Per-component size breakdown | Find what's bloating firmware |

Find the USB serial port:
```bash
ls /dev/cu.usbserial-* /dev/cu.SLAB_USBtoUART /dev/cu.wchusbserial* 2>/dev/null
```

---

## compile_commands.json Lifecycle

The file lives at `./build/compile_commands.json` and is clangd's source of truth
for include paths, compiler flags, and target architecture. Without it, the LSP is
essentially blind.

```bash
idf.py reconfigure   # fast — CMake only, no compilation
```

**Refresh after:**
- Adding new `.c`/`.cpp` files anywhere in the project
- Adding a new component (`REQUIRES`, `PRIV_REQUIRES`)
- Changing `IDF_TARGET`
- Adding include directories to `CMakeLists.txt`

A stale `compile_commands.json` produces false LSP errors (missing headers, unknown
types) even when `idf.py build` succeeds. Always run reconfigure before blaming the code.

---

## LSP Diagnostic Triage

**Real errors — fix these:**
- `use of undeclared identifier 'foo'` — missing `#include` or typo
- `no member named 'bar' in 'esp_wifi_config_t'` — API changed or wrong type
- `implicit conversion loses integer precision` — sign or width mismatch

**False positives — investigate before acting:**
- `'esp_log.h' file not found` → stale `compile_commands.json` → `idf.py reconfigure`
- Any error path inside `esp-idf/components/**` that you didn't touch → IDF internals, ignore
- Errors in `build/` generated files → always ignore

**Trust hierarchy:**
`idf.py build` result > LSP diagnostics

If LSP shows errors but build succeeds: reconfigure, restart clangd.
If build fails but LSP is clean: linker or CMake issue — LSP can't catch those.

---

## Build Error Patterns

**Include not found:**
```
fatal error: 'my_component.h' file not found
```
The including component hasn't declared the dependency. In its `CMakeLists.txt`:
```cmake
idf_component_register(... REQUIRES my_component)
# or PRIV_REQUIRES if only the .c file needs it, not public headers
```

**Undefined reference (linker):**
```
undefined reference to `esp_wifi_init`
```
Missing component dependency. Add `esp_wifi` to `REQUIRES`:
```cmake
idf_component_register(SRCS "main.c" REQUIRES esp_wifi nvs_flash)
```

**Multiple definition:**
```
multiple definition of `some_config`
```
A variable is *defined* (not just declared) in a header included by multiple `.c`
files. Move definition to one `.c` file; put `extern some_config_t some_config;` in
the header.

**GCC-flag errors in clangd (not a real error):**
```
unknown argument: '-mlongcalls'
```
This is clangd rejecting a GCC-only flag. Fix in `.clangd` project file:
```yaml
CompileFlags:
  Remove: [-mlongcalls, -mtext-section-literals, -fstrict-volatile-bitfields]
```

---

## Monitor Output Interpretation

```
I (1234) WIFI: connected to AP          ← ESP_LOGI — informational
W (1234) HEAP: low memory warning       ← ESP_LOGW — warning
E (1234) MQTT: connection failed        ← ESP_LOGE — error
Guru Meditation Error: Core 0 panic'ed  ← crash, backtrace follows
Backtrace: 0x400d1a2c:0x3ffb2e20 ...   ← decode with addr2line
```

Decode a crash backtrace:
```bash
# Xtensa (ESP32/S2/S3):
xtensa-esp32-elf-addr2line -pfiaC -e build/my_project.elf 0x400d1a2c

# RISC-V (C3/C6/H2):
riscv32-esp-elf-addr2line -pfiaC -e build/my_project.elf 0x42001234

# Or let idf.py monitor decode automatically — it does this when IDF_MONITOR_DECODE=1
```

Common crash causes by symptom:

| Monitor output | Likely cause |
|---|---|
| `LoadProhibited` at high address | Null pointer dereference |
| `StoreProhibited` | Writing to read-only flash region |
| `Unhandled debug exception` | Stack overflow |
| Watchdog reset, `Task watchdog got triggered` | Task blocking without yield |
| Random crashes after NVS write | NVS partition full or corrupted |

---

## Hardware Debug: OpenOCD + GDB

**Requires:** ESP-PROG, ESP32-S3 built-in USB-JTAG, or other JTAG adapter.

```bash
# Terminal 1 — start OpenOCD
openocd -f interface/ftdi/esp32_devkitj_v1.cfg -f target/esp32.cfg
# For ESP32-C3/H2 built-in JTAG:
openocd -f board/esp32c3-builtin.cfg

# Terminal 2 — connect GDB
xtensa-esp32-elf-gdb build/my_project.elf
# At GDB prompt:
(gdb) target remote :3333
(gdb) monitor reset halt
(gdb) b app_main
(gdb) continue
(gdb) bt           # backtrace on crash
(gdb) info locals  # local variables
```

---

## Signal Trust Order for Agent Decisions

```
1. idf.py build output   — ground truth for compilation and linking
2. idf.py monitor output — ground truth for runtime behavior
3. LSP diagnostics       — fast edit-time signal, may have false positives
4. OpenOCD/GDB           — ground truth for hardware state and crashes
```

Never mark an implementation task done without a clean `idf.py build`.
Never mark a runtime task done without checking monitor output.
