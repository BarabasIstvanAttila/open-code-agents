---
description: Recall prior decisions, research and plans from context-mode memory
---

Answer using context-mode memory first; ask the user only if memory is empty.

1. ctx_search(queries: ["$ARGUMENTS"], sort: "timeline", limit: 5)
2. ctx_search(queries: ["$ARGUMENTS"], source: "decision", sort: "timeline", limit: 3)
3. ctx_search(queries: ["$ARGUMENTS"], source: "research", sort: "timeline", limit: 3)
4. ctx_search(queries: ["$ARGUMENTS"], source: "plan", sort: "timeline", limit: 3)

Summarize findings with dates and source labels, then answer. If nothing matches, say so and retry ctx_search without a source filter.
