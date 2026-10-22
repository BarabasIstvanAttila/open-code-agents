# Memory frontmatter — Open Knowledge Format (OKF) template

Every file under `memory/` is **one concept**: a single file, a path that identifies it,
and an OKF frontmatter block at the top. qmd indexes the body as plain text, so these
fields are searchable by BM25 and embeddings — there is no metadata filter, hence
`type` is also written as a literal token in the body when it matters.

## Template

```markdown
---
type: research
title: Short human title (matches the H1)
description: Two sentences max. Appears in search snippets and reranker context.
tags: [qmd, memory, okf]
resource: https://example.com/source   # optional: URL or repo path
timestamp: 2026-10-22                  # ISO date (UTC), date the concept was written
status: active                         # optional: active | archived | superseded
superseded_by: memory/research/newer.md # optional, only with status: superseded
---

# Short human title (matches `title`)

Body. Plain relative links to related concepts:

See [context-mode routing](../patterns/context-mode-routing.md).
```

## Rules

| Rule | Why |
|------|-----|
| `type` is required and must be the singular collection name | `tasks/`→`task`, `patterns/`→`pattern`, `plans/`→`plan`, `research/`→`research`, `builds/`→`build`, `decisions/`→`decision`, `mistakes/`→`mistake` |
| `title` required, and the H1 must match it | qmd extracts the first H1 as the document title; drift confuses snippets |
| `description` required, <= 2 sentences | lands in the first ~900-token chunk, which is what the reranker scores |
| `timestamp` required, `YYYY-MM-DD` | age is used by `scripts/memory-prune.sh`; qmd itself does not expire anything |
| `tags` is an inline YAML array | tags are BM25 anchors, not filters; `keep` exempts a file from pruning |
| One concept per file, slug filename | OKF: the path is the identity; qmd docids are path-based |
| Use plain relative links | build the concept graph; qmd indexes the link text too |
| No dates/versions in prose, only in fields | avoids "fossils" (see research report, source A1) |

## Write path

1. Create the file under the matching collection with the frontmatter above.
2. `scripts/memory-lint.sh` must pass.
3. `bunx @tobilu/qmd update` to index, then `bunx @tobilu/qmd embed` if new content.
4. Append one line to `memory/log.md`.

## Lifecycle

- `status: active` (default) — searchable and current.
- `status: archived` — eligible for `scripts/memory-prune.sh`.
- `status: superseded` + `superseded_by` — kept for history, points at the replacement.

Retention is **file-based**: pruning moves files to `memory/.archive/` (outside every
qmd collection glob), then runs `qmd update` (tombstones) and `qmd cleanup`
(hard-deletes inactive rows, orphans, caches, then vacuums).
