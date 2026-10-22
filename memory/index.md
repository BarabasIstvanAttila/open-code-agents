# memory/ — the project knowledge base

One concept per file, Open Knowledge Format (OKF) frontmatter, indexed by qmd.
This file is the human/agent map; the retrieval-time map lives in qmd contexts
(`qmd context list`).

## Collections

| Directory | `type` | Holds |
|-----------|--------|-------|
| `memory/tasks/` | `task` | Task summaries — what was asked, what shipped |
| `memory/patterns/` | `pattern` | Reusable code/config patterns |
| `memory/plans/` | `plan` | Archived implementation plans |
| `memory/research/` | `research` | Research findings and source digests |
| `memory/builds/` | `build` | Per-task build records and verification evidence |
| `memory/decisions/` | `decision` | Technical decisions with context and reasoning |
| `memory/mistakes/` | `mistake` | Pitfalls and the rule that prevents a repeat |

`memory/ghost/` is a **non-OKF reference area** (ghost session-capture
learnings). It is excluded from lint and prune but indexed as the `ghost`
collection so it stays searchable.

## Reading

1. Start here, then open the one concept you need.
2. For search, use qmd: `bunx @tobilu/qmd query "..."` (hybrid + rerank) or
   `qmd search` (BM25 only), then `qmd get <path>`.
3. Collection and path summaries: `qmd context list`.

## Writing

Follow [the frontmatter template](../templates/memory-frontmatter.md). Minimum:

```yaml
---
type: research        # must equal the parent directory
title: ...
description: ...      # <= 2 sentences, shows up in snippets
tags: [...]
timestamp: 2026-10-22
---
```

Then `scripts/memory-lint.sh`, `bunx @tobilu/qmd update`, and append to
[log.md](log.md).

## Retention

qmd has **no TTL** — documents expire only when files leave a collection path.
Use `scripts/memory-prune.sh [--days N] [--dry-run]`; it moves stale or
`status: archived` files to `memory/.archive/` and runs `qmd update && qmd cleanup`.
Files tagged `keep` are never pruned.
