---
name: implement
description: "Start implementation of focused tasks. Unlocks code writes, creates granular task list, delegates to agents."
---

Invoked as `/flow:implement`.

## What this does

Transitions from **planned** to **implementing** for the focused tasks. Unlocks code writes and begins execution.

The rule-coherence checkpoint already ran in `/flow:next` before you got here. `/flow:implement` is purely the unlock + execute phase: everything is figured out, you just do the work. For the rule-injection model (static + dynamic, equal weight, re-injected per turn), see `/flow:build` § "How rules reach you".

## Implementation rules

These rules apply throughout every step below. The phase-aware reminder during the `implementing` phase points here.

- **Follow ALL injected rules, equal weight.** Static rules from `.flow/rules/always/` and dynamic rules from `.flow/rules/dynamic/` are both authoritative. Newly-injected rules don't override previously-loaded ones; the set is cumulative within a session.
- **Delegate substantial work.** Use `flow:dev` agents when work involves multiple files, complex logic, or anything that benefits from a focused context. The orchestrator coordinates, agents implement.
- **Brief the dev agent fully.** Pass: what to implement and why, what risks or edge cases to watch for, what decisions should be escalated back, and any context the agent wouldn't discover on its own.
- **Take agent escalations seriously.** The dev agent (Opus) will raise concerns, ambiguities, and significant decisions back to you. Relay to the user when needed. Don't silently resolve them.
- **Verify each piece of work.** Run tests, check output, manually verify UI changes. Never claim "tests pass" without actually running them.
- **Document what was actually done.** Note divergences from the plan, commit hashes inline with the work they describe, edge cases discovered.
- **Don't skip the granular task list.** TaskCreate before working. Plan the work, then work the plan.

### Subagent ambiguity handling

- **Foreground subagent** (single focused task): "When encountering ambiguity that cannot be resolved by reading the codebase, use AskUserQuestion to raise it."
- **Agentteam** (parallel independent tasks): "When encountering ambiguity, communicate it back to the orchestrator and wait."

## Steps

### 1. Validate

- Get state: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "$CURRENT_SESSION_ID" --get`
  - If empty: no active workflow. Suggest `/flow:build`.
  - If phase is `planning`: tell the user to approve the plan first (`/flow:approve`).
  - If phase is `implementing`: already implementing. Show current focus and continue.

- Get focus: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "$CURRENT_SESSION_ID" --get-focus`
  - If empty: tell the user to run `/flow:next` first to pick tasks and deep-dive.

### 2. Transition

- Set phase: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "$CURRENT_SESSION_ID" --set-phase implementing`
- Confirm: "Implementation unlocked for: [focused tasks]. Code writes are now allowed."

### 3. Create granular tasks

Based on the deep-dive analysis from `/flow:next`, break the focused tasks into granular implementation steps using `TaskCreate`. These are in-context tasks, NOT written to the task file.

Each task should be specific and actionable:
- "Refactor `AuthMiddleware.validate()` to use token service"
- "Add rate limiting to `/api/users` endpoint"
- "Write tests for new token validation flow"

### 4. Execute

Apply the Implementation rules above throughout. After each task: verify work, run tests, mark task complete.

### 5. Document

When focused tasks are complete:
- Write what was done to the task file. Mark items as complete, add brief notes with commit hashes inline:
  ```markdown
  - [x] Auth middleware refactor
    Refactored to use token service (abc1234)
    Added rate limiting with per-user config (def5678)
    Fixed edge case for expired tokens (901abcd)
  ```
- Commits go next to the work they describe, not the task heading. One task typically has multiple commits.
- This documents execution, not planning. The task file becomes a log of what happened.

### 6. Suggest next

- "Implementation complete for [focused tasks]. Run `/flow:next` to pick the next work."
- If all plan items are done: "All tasks complete! Run `/flow:reset` to archive and clean up."

## What happens after implementation

When you suggest `/flow:next` and the user runs it, the session relocks to `planned` phase. The user can branch, switch focus, or continue with remaining plan items. The deep-dive process and rule-coherence checkpoint will run again before the next implementation cycle.

## What NOT to do during implementation

- Don't reopen planning-level discussion mid-execution. If the plan is wrong, suggest `/flow:lock`.
- Don't expand scope mid-execution. Surface side-effects to the user. Don't silently add work.
- Don't skip verification or test runs.
- Don't claim success without measurable evidence (test output, type-check pass, manual verification for UI).
- Don't start implementing without focus set. `/flow:next` must come first.
