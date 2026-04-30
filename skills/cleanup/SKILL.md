---
name: cleanup
description: "Sweep orphaned rule-cache files (subagent caches, injected ledgers) and truncate eval logs. Safe; dry-run by default."
---

Invoked as `/flow:cleanup`. Sweeps `.flow/rule-cache/` for files that no longer correspond to a live session in `.flow/SESSIONS.json`, reaps stale lock directories with dead PIDs, and truncates `eval-log.jsonl` and `pending-signals.jsonl` if they grew past their line limits.

## Instructions

### 1. Preview

Always start with a dry run:

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/flow-rules" cleanup --cwd . --dry-run
```

Present the output to the user. If everything reads "0 deleted / 0 reaped / under limit", tell the user there's nothing to clean and stop.

### 2. Confirm

Use `AskUserQuestion` to confirm the user wants to proceed with the deletions shown.

### 3. Apply

If the user confirms, run without `--dry-run`:

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/flow-rules" cleanup --cwd .
```

Present the final report.

### Notes

- Cleanup never touches files belonging to sessions that ARE in `SESSIONS.json`.
- If `SESSIONS.json` is missing or unreadable, cleanup refuses to identify orphans (everything is treated as live). Truncation still applies.
- Default thresholds are 1000 lines for `eval-log.jsonl` and 100 lines for `pending-signals.jsonl`. Override with `--max-eval-log <N>` / `--max-pending-signals <N>`.
