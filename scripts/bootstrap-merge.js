#!/usr/bin/env bun
// Non-destructive OpenCode config merges for bootstrap-host.sh.
//
// MODE=global → merge the shared MCP servers + tool enables into
//               $GLOBAL_CONFIG (default ~/.config/opencode/opencode.json)
// MODE=host   → merge instructions into $HOST_ROOT/opencode.json
//
// Existing keys are never overwritten. DRY_RUN=1 prints the plan only.

import {
  readFileSync,
  writeFileSync,
  existsSync,
  mkdirSync,
  renameSync,
} from "node:fs";
import { dirname, join } from "node:path";
import { homedir } from "node:os";

const MODE = process.env.MODE;
const DRY = process.env.DRY_RUN === "1";

if (!["global", "host"].includes(MODE)) {
  console.error("bootstrap-merge: MODE must be 'global' or 'host'");
  process.exit(2);
}

const CONTEXT_MODE_PATH =
  process.env.CONTEXT_MODE_PATH ||
  "/Users/atti/node_modules/context-mode/cli.bundle.mjs";

const MCP = {
  "context-mode": {
    type: "local",
    command: ["bun", CONTEXT_MODE_PATH],
    environment: { CONTEXT_MODE_PLATFORM: "opencode" },
    timeout: 300000,
    enabled: true,
  },
  context7: {
    type: "remote",
    url: "https://mcp.context7.com/mcp",
    headers: { CONTEXT7_API_KEY: "{env:CONTEXT7API}" },
    enabled: true,
  },
  duckduckgo: {
    type: "local",
    command: ["docker", "run", "-i", "--rm", "mcp/duckduckgo"],
    enabled: true,
  },
  sequentialthinking: {
    type: "local",
    command: ["docker", "run", "-i", "--rm", "mcp/sequentialthinking"],
    enabled: true,
  },
  qmd: {
    type: "local",
    command: ["bunx", "@tobilu/qmd", "mcp"],
    enabled: true,
  },
  playwright: {
    type: "local",
    command: ["bunx", "@playwright/mcp@latest", "--headless"],
    enabled: true,
  },
};

const TOOLS = [
  "context-mode*",
  "context7*",
  "duckduckgo*",
  "sequentialthinking*",
  "qmd*",
  "playwright*",
];

// Remove // and /* */ comments plus trailing commas, without touching strings.
function stripJsonc(text) {
  let out = "";
  let inStr = false;
  let esc = false;
  let inLine = false;
  let inBlock = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    const n = text[i + 1];
    if (inLine) {
      if (c === "\n") {
        inLine = false;
        out += c;
      }
      continue;
    }
    if (inBlock) {
      if (c === "*" && n === "/") {
        inBlock = false;
        i += 1;
      }
      continue;
    }
    if (inStr) {
      out += c;
      if (esc) esc = false;
      else if (c === "\\") esc = true;
      else if (c === '"') inStr = false;
      continue;
    }
    if (c === '"') {
      inStr = true;
      out += c;
      continue;
    }
    if (c === "/" && n === "/") {
      inLine = true;
      i += 1;
      continue;
    }
    if (c === "/" && n === "*") {
      inBlock = true;
      i += 1;
      continue;
    }
    out += c;
  }
  return out.replace(/,\s*([}\]])/g, "$1");
}

function pickTarget(baseDir) {
  const json = join(baseDir, "opencode.json");
  const jsonc = join(baseDir, "opencode.jsonc");
  if (existsSync(json)) return json;
  if (existsSync(jsonc)) return jsonc;
  return json;
}

function load(target) {
  if (!existsSync(target)) return {};
  const raw = readFileSync(target, "utf8");
  let text = stripJsonc(raw);
  try {
    return JSON.parse(text);
  } catch {
    text = text.replace(/,\s*([}\]])/g, "$1");
    try {
      return JSON.parse(text);
    } catch (err) {
      console.error(`bootstrap-merge: cannot parse ${target}: ${err.message}`);
      process.exit(2);
    }
  }
}

function save(target, cfg) {
  const body = JSON.stringify(cfg, null, 2) + "\n";
  if (DRY) return;
  mkdirSync(dirname(target), { recursive: true });
  const tmp = `${target}.tmp-${process.pid}`;
  writeFileSync(tmp, body);
  renameSync(tmp, target);
}

const result = { mode: MODE, dry_run: DRY, target: "", added: [], kept: [] };

if (MODE === "global") {
  const target =
    process.env.GLOBAL_CONFIG || join(homedir(), ".config", "opencode", "opencode.json");
  const cfg = load(target);
  cfg.$schema ||= "https://opencode.ai/config.json";
  cfg.mcp = cfg.mcp || {};
  cfg.tools = cfg.tools || {};

  for (const [name, def] of Object.entries(MCP)) {
    if (cfg.mcp[name]) {
      result.kept.push(`mcp.${name}`);
    } else {
      cfg.mcp[name] = def;
      result.added.push(`mcp.${name}`);
    }
  }
  for (const key of TOOLS) {
    if (key in cfg.tools) {
      result.kept.push(`tools.${key}`);
    } else {
      cfg.tools[key] = true;
      result.added.push(`tools.${key}`);
    }
  }

  save(target, cfg);
  result.target = target;
} else {
  const hostRoot = process.env.HOST_ROOT;
  if (!hostRoot) {
    console.error("bootstrap-merge: HOST_ROOT is required for host mode");
    process.exit(2);
  }
  const harnessRel = process.env.HARNESS_REL || ".harness";
  const target = pickTarget(hostRoot);
  const cfg = load(target);
  cfg.$schema ||= "https://opencode.ai/config.json";

  const want = [];
  if (existsSync(join(hostRoot, "AGENTS.md"))) want.push("AGENTS.md");
  want.push(`${harnessRel}/AGENTS.md`);

  const current = Array.isArray(cfg.instructions)
    ? cfg.instructions
    : typeof cfg.instructions === "string"
      ? [cfg.instructions]
      : [];
  for (const entry of want) {
    if (current.includes(entry)) {
      result.kept.push(`instructions.${entry}`);
    } else {
      current.push(entry);
      result.added.push(`instructions.${entry}`);
    }
  }
  cfg.instructions = current;

  save(target, cfg);
  result.target = target;
}

console.log(JSON.stringify(result, null, 2));
