---
name: approve
description: "Approve the current plan and transition to implementation mode. Removes the planning lock."
---

Invoked as `/flow:approve`.

## What this does

Transitions the workflow from **planning** to **implementing** mode for this session.

## Instructions

1. Check current state: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --get`
   - If empty or phase isn't `planning`, tell the user there's nothing to approve.
2. Get task file: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --get-task`
   - Read it — if it has no plan, warn that there's no plan to approve yet.
3. Transition: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --set-phase implementing`
4. Confirm: "Plan approved. Implementation mode active. I'll delegate code changes to subagents."
