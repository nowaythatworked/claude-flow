---
name: implement
description: "Start implementation of focused tasks. Unlocks code writes, creates granular task list, delegates to agents."
---

Invoked as `/flow:implement`.

## What this does

Transitions from **planned** to **implementing** for the focused tasks. Unlocks code writes and begins execution.

## Instructions

### 1. Validate

- Get state: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --get`
  - If empty: no active workflow. Suggest `/flow:build`.
  - If phase is `planning`: tell the user to approve the plan first (`/flow:approve`).
  - If phase is `implementing`: already implementing. Show current focus and continue.

- Get focus: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --get-focus`
  - If empty: tell the user to run `/flow:next` first to pick tasks and deep-dive.

### 2. Transition

- Set phase: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --set-phase implementing`
- Confirm: "Implementation unlocked for: [focused tasks]. Code writes are now allowed."

### 3. Create granular tasks

Based on the deep-dive analysis from `/flow:next`, break the focused tasks into granular implementation steps using `TaskCreate`. These are in-context tasks, NOT written to the task file.

Each task should be specific and actionable:
- "Refactor `AuthMiddleware.validate()` to use token service"
- "Add rate limiting to `/api/users` endpoint"
- "Write tests for new token validation flow"

### 4. Execute

**Delegation guideline:** Delegate work to `flow:dev` agents when it involves substantial code changes — multiple files, complex logic, anything that benefits from a focused context. The orchestrator handles coordination, verification, and quick operations where spawning an agent would cost more overhead than doing it directly.

When delegating, brief the dev agent on:
- What to implement and why (from the deep-dive)
- What risks or edge cases to watch for
- What decisions should be escalated back rather than made autonomously
- Relevant context the agent wouldn't discover on its own

The dev agent is Opus and will raise concerns, ambiguities, and significant decisions back to you. Take these seriously — relay to the user when needed, don't silently resolve them.

- **Foreground subagent** (single focused task): "When encountering ambiguity that cannot be resolved by reading the codebase, use AskUserQuestion to raise it."
- **Agentteam** (parallel independent tasks): "When encountering ambiguity, communicate it back to the orchestrator and wait."
- After each task: verify work, run tests, mark task complete

### 5. Document

When focused tasks are complete:
- Write what was done to the task file — mark items as complete, add brief notes with commit hashes inline:
  ```markdown
  - [x] Auth middleware refactor
    Refactored to use token service (abc1234)
    Added rate limiting with per-user config (def5678)
    Fixed edge case for expired tokens (901abcd)
  ```
- Commits go next to the work they describe, not the task heading — one task typically has multiple commits
- This documents execution, not planning — the task file becomes a log of what happened

### 6. Suggest next

- "Implementation complete for [focused tasks]. Run `/flow:next` to pick the next work."
- If all plan items are done: "All tasks complete! Run `/flow:reset` to archive and clean up."

## Rules

- Never start implementing without focus set — `/flow:next` must come first
- Always create granular tasks via TaskCreate before starting — plan the work, then work the plan
- Verify each piece of work (run tests, check output) before marking complete
- Document what was actually done, not what was planned — note any divergences
