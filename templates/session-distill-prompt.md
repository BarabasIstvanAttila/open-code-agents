# Session distill prompt

You are distilling an OpenCode session into durable project memory.
The transcript is appended below under `--- SESSION TRANSCRIPT ---`.

Rules:
- Do not use tools. Do not ask questions. Do not add preamble or closing remarks.
- Output ONLY the six markdown sections below, in this exact order, using level-3 headings (`###`).
- No code fences around the output.
- Be specific: file paths, commands, and reasons. Do not invent facts that are not in the transcript.
- If the session corrects or reverses an earlier proposal, record the final state only — never record a superseded approach as a current decision.
- Use `_None this session._` when a section has no content.

### Intent

One or two sentences: what the user set out to do.

### Changes

One bullet per file or area changed, in the form `- <path>: <what changed>`.
Use `_None this session._` if nothing was changed.

### Decisions

One bullet per significant technical decision, in exactly this form:
`- **<short decision title>** — <context and why, one or two sentences>.`
Use `_None this session._` if there were none.

### Mistakes

One bullet per thing that went wrong, had to be retried, or should be avoided
next time, in exactly this form:
`- **<short mistake title>** — <what happened and the rule to follow next time>.`
Use `_None this session._` if there were none.

### Open Items

One bullet per unfinished item or follow-up. Use `_None this session._` if none.

### Tags

Comma-separated lowercase tags, at most five, e.g. `memory, qmd, scripts`.

--- SESSION TRANSCRIPT ---
