---
description: Archive stale/archived memory notes (default 180 days) and clean the qmd index
agent: build
---

Run memory retention.

Optional arguments: $ARGUMENTS — e.g. `--days 90`. Default is 180 days.

Steps:
1. Run `bash scripts/memory-prune.sh --dry-run $ARGUMENTS` through
   `ctx_execute("shell", ...)` and show the candidate list.
2. If nothing would be archived, report "nothing to prune" and stop.
3. Otherwise ask the user to confirm with the question tool: list which files
   move and where (`memory/.archive/<collection>/`).
4. On confirmation, run `bash scripts/memory-prune.sh $ARGUMENTS`; report the
   moved count and that `qmd update` + `qmd cleanup` ran.
