---
name: rules-status
description: "Show current dynamic rule selection, watermark, recent eval activity, and lock state for debugging."
---

Invoked as `/flow:rules-status`. Read-only debugging view of the rule evaluator's state for the current session.

## Instructions

### 1. Get task and focus from session (if any)

```bash
TASK=$("${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "$CURRENT_SESSION_ID" --get-task)
FOCUS=$("${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "$CURRENT_SESSION_ID" --get-focus)
```

If this is a vanilla (non-flow) session, `$TASK` will be empty. The binary
auto-derives a `session__<session-id>` cache key when `--task-file` and
`--focus` are omitted; pass only `--session-id` in that case.

### 2. Run status

```bash
if [ -z "$TASK" ]; then
  "${CLAUDE_PLUGIN_ROOT}/bin/flow-rules" state status \
    --cwd . \
    --session-id "$CURRENT_SESSION_ID"
else
  "${CLAUDE_PLUGIN_ROOT}/bin/flow-rules" state status \
    --cwd . \
    --task-file "$TASK" \
    --focus "$FOCUS" \
    --session-id "$CURRENT_SESSION_ID"
fi
```

Present the output to the user verbatim. The report covers:

- which cache state file is in use
- whether the lock is currently held (and by whom)
- last eval timestamp, age, and duration
- inferred task type
- the three selection arrays (pattern / keyword / llm) with rule ids
- last 5 entries from `eval-log.jsonl`
- how many rules have already been injected to this session's conversation history

### 3. Follow-ups

- If the user wants to inspect the contents of a selected rule: list `.flow/rules/dynamic/` and Read each file by id.
- If the binary is unavailable or returns non-zero, fall back to `flow-rules state show` (raw JSON dump) or list `.flow/rule-cache/` directly with `ls`.

### 4. What this is not

This skill does not refresh the cache. To force a fresh evaluation, use `/flow:reload-rules`.
