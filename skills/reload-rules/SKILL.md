---
name: reload-rules
description: "Re-read all quality rules and evaluate dynamic rules. Use when rules have been lost to context compression or you can't find them."
---

Invoked as `/flow:reload-rules`. Can also be triggered by the agent itself when it detects rule blocks are missing from context.

For the rule-injection model (static + dynamic, equal weight, re-injected per turn), see `/flow:build` § "How rules reach you".

## When to use

- You can't find `--- Rule [...] ---` or `--- Dynamic Rule [...] ---` blocks in your context
- The conversation has been running long and you suspect rules have been compressed away
- You want to make sure you're working with the latest rules

## Instructions

### 1. Always-on rules

Read **every** file in `.flow/rules/always/`:
```bash
ls .flow/rules/always/*.md
```
Then read each file fully. Do NOT summarize, the act of reading them into context is the point.

### 2. Dynamic rules

Force a fresh evaluation of which dynamic rules apply, then read the selected rule files:

```bash
TASK=$("${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "$CURRENT_SESSION_ID" --get-task)
FOCUS=$("${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "$CURRENT_SESSION_ID" --get-focus)

"${CLAUDE_PLUGIN_ROOT}/bin/flow-rules" eval --sync \
  --reason=user-reload \
  --cwd . \
  --session-id "$CURRENT_SESSION_ID" \
  --task-file "$TASK" \
  --focus "$FOCUS"

"${CLAUDE_PLUGIN_ROOT}/bin/flow-rules" state show --cwd . --task-file "$TASK" --focus "$FOCUS"
```

The `state show` output contains `selected_via_pattern`, `selected_via_keyword`, `selected_via_llm`. The union is the current dynamic rule selection.

For each selected rule id, Read the file at `.flow/rules/dynamic/<id>` fully so the body lands in your context.

If `flow-rules` is unavailable (binary missing, eval fails): fall back to reading every file in `.flow/rules/dynamic/` directly, and tell the user the eval couldn't run so the selection wasn't refreshed.

### 3. Confirm

Report: "Rules reloaded: [count] always-on, [count] dynamic rules active." List the names of active dynamic rules so the user can see what was selected.
