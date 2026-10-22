---
description: Do a task using only context-mode tools for I/O
---

Complete the following task strictly through the context-mode MCP server (AGENTS.md §context-mode):

$ARGUMENTS

Contract:
1. Route every shell run, file analysis, and web read through ctx_* tools — never curl/wget/webfetch, never raw dumps.
2. Scratch scripts >5 lines or with nested quotes: write to .agent/tmp/*.sh, execute by path.
3. On tool error: fix the original call from its schema, one retry, then stop and report. No probes, no invented paths.
4. If the task yields reusable knowledge, ctx_index it with a precise source label before finishing.
5. End with ctx_stats() and quote the context-savings ratio.
