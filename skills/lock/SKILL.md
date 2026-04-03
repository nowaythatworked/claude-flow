---
name: lock
description: "Return to planning mode. Re-engages the implementation gate to prevent code changes until the plan is re-approved."
---

Invoked as `/flow:lock`.

## What this does

Transitions the workflow back to **planning** mode for this session. Use when:
- Starting a new area that needs discussion first
- The plan needs revision after discoveries during implementation
- You want to pause implementation and rethink

## Instructions

1. Run: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --set-phase planning`
2. Confirm: "Planning mode re-engaged. No code changes until `/flow:approve` is run again."
