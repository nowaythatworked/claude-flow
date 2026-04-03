---
name: build
description: "Structured workflow for complex tasks. Adaptive understand → plan → implement loop with quality enforcement and delegation."
---

Invoked as `/flow:build <task description>`.

## 0. Initialize

1. Pick a meaningful task filename (see naming below)
2. Register session: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --set planning <task-filename>.md`

### Task file naming

Derive a short, descriptive, kebab-case filename from context:
- Ticket ID if available: `PROJ-123-auth-refactor.md`
- Branch name or task summary otherwise: `ariadne-pr-cleanup.md`, `fix-stryker-pipeline.md`

This file is referenced below as "the task file." Find it via: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --get-task`

## Planning phase (steps 1–4)

During planning, the hook system reminds you to stay in this phase. No code changes outside `.flow/` until the user runs `/flow:approve`.

### 1. Understand

- Read referenced files, tickets, context — and related code broadly
- Ask clarifying questions
- Restate understanding: business context, who is affected, assumptions
- Do NOT move to planning until the user signals readiness

### 2. High-Level Plan

- Search codebase for existing patterns and utilities FIRST
- Invoke the `flow:rule-evaluator` agent to evaluate which dynamic rules apply
- Present the plan: domain understanding + major areas (NOT detailed task lists)
- Discuss trade-offs, let user adjust
- Write the high-level plan to the task file as a checklist
- User picks which area to work on first

### 3. Deep Dive (per selected area)

**Orient** — read the task file + `git log --oneline -20` + notes from previous areas.

**Judge confidence** — "Do I have everything I need to implement this confidently?"
- Not confident → research more (delegate to subagents for verbose exploration), ask questions
- Confident → create detailed task list for THIS AREA ONLY in the task file

Note important discoveries in the task file — things that affect other areas and would be lost after a rewind.

### 4. Present & Wait

- Present the finalized plan for this area
- **Do NOT implement. Do NOT ask if the user wants to start.**
- The user will run `/flow:approve` when ready

## Implementation phase (steps 5–6)

After `/flow:approve`, implementation is unlocked. The user can run `/flow:lock` at any time to return to planning.

### 5. Implement

**Delegation guideline:** Delegate work to `flow:dev` agents when it involves substantial code changes — multiple files, complex logic, anything that benefits from a focused context. The orchestrator handles coordination, verification, and quick operations where spawning an agent would cost more overhead than doing it directly (a single shell command, a small config edit, a merge).

- **Foreground subagent** (single focused task): "When encountering ambiguity that cannot be resolved by reading the codebase, use AskUserQuestion to raise it."
- **Agentteam** (parallel independent tasks): "When encountering ambiguity, communicate it back to the orchestrator and wait."
- After each task: verify work, run tests, update the task file

### 6. Progress & Next

- Update the task file, mark items done
- Present: "Here's what's done, here's what's next"
- User picks next area → `/flow:lock` → back to step 3
- User may `/rewind` for a clean context, `/fork` for named checkpoints

## Commands

| Command | Effect |
|---------|--------|
| `/flow:approve` | Unlock implementation |
| `/flow:lock` | Return to planning |
| `/flow:phase` | Show current phase |
| `/flow:reset` | Archive task file and reset |

## Rules

Quality rules are loaded via hooks (always-on at session start, dynamic per-task). Follow them. If a rule conflicts with the user's explicit instruction, mention it and follow the user.

## Principles

- Plan the big picture first, then deep dive per area — never plan all details upfront
- Never implement without `/flow:approve` — user feedback on the plan is NOT approval
- Never create detailed task lists for areas not being worked on yet
- Research more or ask when not confident — thoroughness over speed
- Keep the task file updated — it's the living progress tracker
