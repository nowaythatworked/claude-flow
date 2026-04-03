---
name: next
description: "Analyze what's next, pick tasks, and deep-dive before implementation. The hub between planning and implementing."
---

Invoked as `/flow:next [--no-lock]`.

## What this does

Checkpoint and navigation skill. Analyzes the current state of the task, helps pick what to focus on next, and deep-dives into selected tasks before implementation.

## Instructions

### 1. Orient & lock

- Get state: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --get`
  - If empty: no active workflow. Suggest `/flow:build`.
  - If phase is `planning`: tell the user to finish planning first. Suggest `/flow:approve` when the plan is ready.

- **If phase is `implementing`** and `--no-lock` was NOT passed: transition back to `planned` — you're picking new tasks now.
  - Clear focus: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --clear-focus`
  - Set phase: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --set-phase planned`
  - This also handles `/rewind` scenarios where the conversation context no longer matches the on-disk state.
- **If `--no-lock` was passed**: skip the phase transition. Useful for checking progress mid-implementation without leaving implementing phase.

- Read the task file: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --get-task` → read `.flow/<filename>`
- Read recent commits: `git log --oneline -20`
- Check what other sessions are working on: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . --dump` — look at focus fields to see what's claimed

### 2. Analyze

- What's been completed? (check marks in task file, commits)
- What's remaining?
- Are any tasks claimed by other sessions? (check focus fields in SESSIONS.json)
- What's the right next step?

### 3. Suggest

Present analysis to the user:
- Summary of progress so far
- Available tasks (not claimed by other sessions)
- For each available task, assess:
  - **Size**: small (can be done quickly by orchestrator), medium (one focused agent), large (needs delegation/parallelization)
  - **Dependencies**: does this need to be done before/after something else?
  - **Parallelization potential**: can this be worked on in a separate session alongside other tasks?
- If multiple tasks could be parallelized: suggest the user could branch into separate sessions
- Recommend what to focus on next and why

**Wait for the user to confirm** what they want to work on. Do NOT set focus until the user decides.

### 4. Set focus

Once the user confirms task selection:
- Set focus: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --set-focus "<task-1>" "<task-2>"`
- Tasks are identified by their heading or description from the plan

### 5. Deep-dive

This is a **pseudo implementation** — read the actual code, trace the actual paths, form the actual plan. You stop short of writing code, but the important decisions should be made.

- **Read the code**: Open the relevant files. Understand existing structures, interfaces, types, schemas. Don't skim — you need to know what's there.
- **Think about reusability**: Can existing code be refactored to serve this need? Prefer reshaping over adding.
- **Trace the impact**: Follow the call chain. What depends on what you're changing? What tests cover this? What could break?
- **Pre-plan the important structures**: Types, schemas, interfaces, function signatures that affect multiple files or consumers — these should be decided now. If a transport schema changes, plan the shape. If a new type is needed, draft it.
- **Pre-decide the hard parts**: Architecture choices, refactoring strategies, edge case handling, order of operations.
- **Leave the mechanical work**: The dev agent writes function bodies, test implementations, wiring, imports. It's Opus — it handles the how. But it shouldn't be inventing the what.

The bar: could you brief a junior engineer and trust they'd implement this correctly? They should know what to build, which files to touch, what types/schemas to use. They figure out the code, not the design.

If you already have enough information from earlier discussions (e.g., the planning phase already covered this in depth): acknowledge that and present what you know. Don't force unnecessary ceremony.

### 6. Self-check & iterate

Before presenting findings, ask yourself: **"Could I brief a junior engineer and trust they'd implement this correctly?"**

- Do you know which files need to change?
- Are the types, schemas, and interfaces decided?
- Have you identified existing code that should be refactored rather than duplicated?
- Are the hard decisions made — architecture, refactoring strategy, edge case handling?
- Do you know what to tell the dev agent to escalate back?

If not — go back: research more, delegate exploration to subagents, or ask the user. Iterate until you're genuinely confident. The user may also push you to go deeper — follow their lead.

### 7. Present findings

- Present the deep-dive analysis to the user
- Include: approach, key decisions, risks, things the dev agent should escalate
- Suggest: "When you're satisfied with this analysis, run `/flow:implement` to start implementation."
- If the analysis revealed issues with the overall plan: suggest `/flow:lock` to go back to planning

### Coming from implementing phase

When called after completing implementation tasks:
- Update the task file: mark completed items, add what was done + commit hashes
- Then follow steps 1-7 above for the next set of tasks
- If all tasks are complete: congratulate and suggest `/flow:reset`

## Rules

- Never set focus without user confirmation
- Never skip the deep-dive — even for "obvious" tasks, at minimum state your approach and assumptions
- Never suggest `/flow:implement` without presenting your analysis first
- If other sessions have claimed tasks, respect their focus — don't suggest claiming the same tasks
- The deep-dive is analysis, not implementation — no code changes
