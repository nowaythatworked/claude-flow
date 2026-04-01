---
description: "Show all active quality rules for this project — both always-on and dynamic flow rules."
---

# /rules — List Active Quality Rules

When invoked, give the user a clear overview of all quality rules in the project.

---

## What to do

### 1. Read always-on rules

Read all files in `.claude/rules/` (the native Claude Code rules directory). These are loaded automatically at session start and injected into every subagent.

### 2. Read dynamic rules

Read all files in `.flow/rules/dynamic/`. These are evaluated per-task and loaded only when relevant.

### 3. Present the summary

For each rule, show:
- **Filename** and category (always-on / dynamic)
- **Brief summary** — the heading and first 2-3 meaningful lines, enough to identify the concern

Group by category. Example format:

```
## Always-on rules (loaded every session)

1. **01-understand-first** — Understand before implementing. Restate understanding, ask when ambiguous.
2. **02-reuse-existing** — Search for existing patterns before writing new code.
...

## Dynamic rules (loaded per-task)

1. **git-workflow** — Git operation safety: verify branch, separate commits, describe WHY.
2. **ui-quality** — UI accessibility and visual consistency patterns.
...
```

### 4. Show totals

At the end, report:
- Count of always-on rules
- Count of dynamic rules
- Approximate total token cost (rough estimate based on file sizes — about 1 token per 4 characters)

### 5. Context relevance

If the user is in the middle of a task, note which dynamic rules would be relevant to their current work and why. If there's no active task context, skip this section.
