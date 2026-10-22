#!/usr/bin/env bun
// Parse a session-distill summary and write OKF memory records.
// Deterministic: the model supplies section text only; this helper owns
// frontmatter, slugs, filenames, and the secret gate.
//
// Env: SUMMARY, DATE, SESSION_ID, SESSION_TITLE, BRANCH, COMMIT, MEMORY_DIR, DRY_RUN

import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";

const env = process.env;
const summaryPath = env.SUMMARY;
const date = env.DATE;
const sessionId = env.SESSION_ID;
const sessionTitle = (env.SESSION_TITLE || sessionId || "session").trim();
const branch = env.BRANCH || "unknown";
const commit = env.COMMIT || "none";
const memoryDir = env.MEMORY_DIR;
const dryRun = env.DRY_RUN === "1";

if (!summaryPath || !date || !sessionId || !memoryDir) {
  console.error("distill-write: missing SUMMARY, DATE, SESSION_ID, or MEMORY_DIR");
  process.exit(2);
}

let raw = readFileSync(summaryPath, "utf8");
// Strip ANSI escapes and code-fence lines the model may add.
raw = raw.replace(/\x1b\[[0-9;?]*[a-zA-Z]/g, "");
raw = raw.split(/\r?\n/).filter((l) => !/^\s*```/.test(l)).join("\n");

const KEYS = ["intent", "changes", "decisions", "mistakes", "open items", "tags"];
const sections = {};
let current = null;
for (const line of raw.split(/\r?\n/)) {
  const heading = line.match(/^#{1,4}\s+(.+?)\s*$/);
  if (heading) {
    const key = heading[1].trim().toLowerCase();
    if (KEYS.includes(key)) {
      current = key;
      sections[current] = [];
      continue;
    }
    if (current) current = null;
  }
  if (current) sections[current].push(line);
}
const section = (k) => (sections[k] || []).join("\n").trim();

const intent = section("intent");
const changes = section("changes");
const openItems = section("open items");
if (!intent) {
  console.error("distill-write: summary has no 'Intent' section");
  process.exit(2);
}

// Secret gate: refuse to write anything that looks like a credential.
const SECRET =
  /(sk-[A-Za-z0-9_-]{8,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----)/;
const allText = Object.values(sections).flat().join("\n");
if (SECRET.test(allText)) {
  console.error("distill-write: secret pattern detected — refusing to write memory");
  process.exit(3);
}

const NONE_RE = /^_?none\b/i;
const isNone = (text) =>
  !text || text.split(/\r?\n/).every((l) => !l.trim() || NONE_RE.test(l.trim()));

function bullets(text) {
  const items = [];
  let cur = null;
  for (const line of text.split(/\r?\n/)) {
    const bold = line.match(/^\s*[-*]\s+\*\*(.+?)\*\*\s*(?:[—:–-]+)?\s*(.*)$/);
    if (bold) {
      if (NONE_RE.test(bold[1].trim())) continue;
      cur = { title: bold[1].trim(), body: bold[2].trim() };
      items.push(cur);
    } else if (cur && line.trim()) {
      cur.body = (cur.body ? cur.body + " " : "") + line.trim();
    }
  }
  return items.filter((i) => i.title);
}

function sentences(text, max = 2, limit = 240) {
  const flat = text.replace(/\s+/g, " ").trim();
  const parts = flat.split(/(?<=[.!?])\s+/).filter(Boolean);
  let out = parts.slice(0, max).join(" ").trim();
  if (out.length > limit) out = out.slice(0, limit - 1).trimEnd() + "…";
  return out || flat.slice(0, limit);
}

const slugify = (s) =>
  s
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 50) || "entry";

function yaml(s) {
  return JSON.stringify(String(s).replace(/\s+/g, " ").trim());
}

function tagsFrom(text) {
  const base = ["session-distill"];
  for (const tag of text.split(/[,\n]/)) {
    const t = tag.trim().toLowerCase().replace(/[^a-z0-9-]+/g, "-").replace(/^-+|-+$/g, "");
    if (t && !base.includes(t)) base.push(t);
    if (base.length >= 6) break;
  }
  return base;
}

const tags = tagsFrom(section("tags"));

const planned = [];
const written = { decisions: [], mistakes: [], build: null };

function uniquePath(dir, slug) {
  let candidate = join(dir, `${date}-${slug}.md`);
  let n = 2;
  while (existsSync(candidate)) {
    candidate = join(dir, `${date}-${slug}-${n}.md`);
    n += 1;
  }
  return candidate;
}

function writeConcept(type, dir, title, description, body, kind) {
  mkdirSync(dir, { recursive: true });
  const path = uniquePath(dir, slugify(title));
  const content = `---
type: ${type}
title: ${yaml(title)}
description: ${yaml(description)}
tags: [${tags.join(", ")}]
timestamp: ${date}
status: active
---

# ${title.replace(/\s+/g, " ").trim()}

${body.trim()}

_Source: session \`${sessionId}\` on branch \`${branch}\` (${date})._
`;
  planned.push(path);
  if (!dryRun) {
    writeFileSync(path, content);
    written[kind].push(path);
  }
  return path;
}

for (const item of bullets(section("decisions"))) {
  writeConcept(
    "decision",
    join(memoryDir, "decisions"),
    item.title,
    sentences(item.body || item.title),
    item.body || item.title,
    "decisions",
  );
}
for (const item of bullets(section("mistakes"))) {
  writeConcept(
    "mistake",
    join(memoryDir, "mistakes"),
    item.title,
    sentences(item.body || item.title),
    item.body || item.title,
    "mistakes",
  );
}

// Fallback: non-empty section without bold bullets becomes one entry.
if (!isNone(section("decisions")) && !planned.some((p) => p.includes("/decisions/"))) {
  const text = section("decisions");
  writeConcept("decision", join(memoryDir, "decisions"), `${sessionTitle} — decisions`,
    sentences(text), text, "decisions");
}
if (!isNone(section("mistakes")) && !planned.some((p) => p.includes("/mistakes/"))) {
  const text = section("mistakes");
  writeConcept("mistake", join(memoryDir, "mistakes"), `${sessionTitle} — mistakes`,
    sentences(text), text, "mistakes");
}

const buildDir = join(memoryDir, "builds");
const buildPath = uniquePath(buildDir, slugify(sessionTitle));
const rel = (p) => p.replace(memoryDir + "/", "").replace(memoryDir, "");
const links = [
  ...written.decisions.map((p) => `- decision: [${rel(p)}](../${rel(p)})`),
  ...written.mistakes.map((p) => `- mistake: [${rel(p)}](../${rel(p)})`),
];
if (dryRun) {
  links.length = 0;
  for (const p of planned) links.push(`- planned: ${rel(p)}`);
}

const buildBody = `# ${sessionTitle.replace(/\s+/g, " ").trim()}

## Session

- id: \`${sessionId}\`
- branch: \`${branch}\`
- commit: \`${commit}\`
- date: ${date}

## Intent

${intent || "_None._"}

## Changes

${changes || "_None._"}

## Open Items

${openItems || "_None._"}

## Memory written

${links.length ? links.join("\n") : "_None._"}
`;

const buildContent = `---
type: build
title: ${yaml(sessionTitle)}
description: ${yaml(sentences(intent))}
tags: [${tags.join(", ")}]
timestamp: ${date}
status: active
---

${buildBody}
`;

mkdirSync(buildDir, { recursive: true });
planned.push(buildPath);
if (!dryRun) {
  writeFileSync(buildPath, buildContent);
  written.build = buildPath;
}

console.log(
  JSON.stringify(
    {
      dry_run: dryRun,
      sections: {
        intent: intent.length,
        changes: changes.length,
        decisions: section("decisions").length,
        mistakes: section("mistakes").length,
        open_items: openItems.length,
      },
      written,
      planned: planned.map(rel),
    },
    null,
    2,
  ),
);
