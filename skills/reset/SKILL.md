---
name: reset
description: "Reset the workflow — archive or delete the task file and reset the phase. Use when starting fresh or switching to a new task."
---

Invoked as `/flow:reset [flags]`.

## Flags

- `--archive` — move task file to `.flow/archive/` keeping its name (default)
- `--delete` — delete task file without archiving
- `--phase-only` — only reset this session's phase, keep task file as-is
- `-y` — skip confirmation

## Instructions

1. Get state: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --get`
   - If empty, tell the user there's nothing to reset.
   - Otherwise read the task file for a summary.

2. Unless `-y` was passed, use `AskUserQuestion` to confirm:
   - Show the current phase, the task file name, and a summary (how many items, how many completed)
   - Ask: "This will [archive/delete] the task file and reset the phase. Continue?"
   - If denied, abort.

3. Run the reset script:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/reset.sh" [--archive|--delete|--phase-only] --session "${CLAUDE_SESSION_ID}" .
   ```

4. Report what was done.
