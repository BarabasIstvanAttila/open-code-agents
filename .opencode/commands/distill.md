---
description: Distill an OpenCode session into memory/ (decisions, mistakes, build record)
agent: build
---

Run the session distiller for this project.

Optional arguments: $ARGUMENTS — a session id (`ses_…`) and/or flags:
`--dry-run`, `--force`, `--note`, `--model <id>`. Empty means the newest
non-distill session.

Steps:
1. Run `bash scripts/session-distill.sh $ARGUMENTS` through
   `ctx_execute("shell", ...)`.
2. On failure: read the error, fix the invocation once (loop-safety rules), then
   stop and report.
3. Report which memory files were written (decisions / mistakes / build record),
   the `memory/log.md` line, and the git note when `--note` was passed.
4. Never hand-edit memory files to force lint green.
