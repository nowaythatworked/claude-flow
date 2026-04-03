---
name: lock
description: "Go back one step in the workflow. implementing→planned, planned→planning. Re-engages write protection."
---

Invoked as `/flow:lock`.

## What this does

Steps the workflow back one phase. Use when:
- Discoveries during implementation require rethinking the approach
- The deep-dive revealed issues with the overall plan
- You want to pause and reassess

## Transitions

| From | To | Effect |
|------|----|--------|
| `implementing` | `planned` | Stops implementation, re-engages write lock. Focus is cleared. |
| `planned` | `planning` | Goes back to conversation-only mode. Task file is kept for reference but plan can be revised. |
| `planning` | — | Already in planning. Nothing to do. |

## Instructions

1. Get state: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --get`
   - If empty: no active workflow. Suggest `/flow:build`.

2. Determine transition based on current phase:

   **From `implementing`:**
   - Clear focus: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --clear-focus`
   - Set phase: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --set-phase planned`
   - Confirm: "Back to planned phase. Code writes locked. Run `/flow:next` to pick tasks and deep-dive again."

   **From `planned`:**
   - Clear focus: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --clear-focus`
   - Set phase: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --set-phase planning`
   - Confirm: "Back to planning phase. The task file is kept for reference. Discuss revisions in conversation, then `/flow:approve` when ready."

   **From `planning`:**
   - "Already in planning phase. Nothing to lock."
