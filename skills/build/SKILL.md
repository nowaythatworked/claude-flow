---
name: build
description: "Structured workflow for complex tasks. Guides through understand → plan → implement cycle with quality enforcement."
---

# Structured Workflow

Run this workflow for any non-trivial task. Invoked as `/flow:build <task description>`.

---

## Phase 1 — Understand

Fully understand the task before doing anything.

- Read all referenced files, tickets, links, and pasted context.
- Read related code in the codebase — look broadly.
- Ask clarifying questions. Open-ended, specific to the task, not formulaic checklists.
- Restate your understanding: who is affected, user-facing implications, business logic assumptions.

**Do NOT proceed to Phase 2 until the user signals readiness.**

---

## Phase 2 — Plan

### 2a. Research the codebase first

Before proposing anything:
- Search for existing patterns, utilities, and similar logic.
- Identify code to extend or reuse. Do not reinvent what already exists.

### 2b. Evaluate optional rules

Read `.flow/rules/optional/`. Determine which are relevant to this task. Load them. Note which you loaded and why.

### 2c. Present the plan in two parts

**Domain understanding:**
- Business context — what problem this solves, who benefits, what changes for users
- Assumptions about business logic — state them explicitly

**Technical plan:**
- Numbered sub-tasks, each focused and independently implementable
- For each: what existing code to extend/reuse, what to create, approach
- Testing strategy per sub-task

### 2d. Discuss trade-offs

Present alternatives considered and why you chose this approach. Let the user adjust.

### 2e. Checkpoint

Once approved, this is the **/rewind checkpoint**. `/rewind` returns here for the next sub-task.

---

## Phase 3 — Implement

User confirms plan and says which sub-task to start.

### Delegation

Choose the right delegation model based on the work:

**Single sub-task (no parallelism) → foreground subagent:**
- Instruct the subagent: "When encountering ambiguity that cannot be resolved by reading the codebase, use AskUserQuestion to raise it."

**Parallel sub-tasks → agentteam:**
- Instruct workers: "When encountering ambiguity that cannot be resolved by reading the codebase, communicate it back to the orchestrator and wait for a response."
- As orchestrator: consolidate questions from workers, discuss with the user, relay answers back.

For all delegated agents:
- Pass relevant context and the current sub-task scope.
- Quality rules are injected automatically via hooks — no need to repeat them.
- Verify their work after completion.

### TDD approach
- Write tests first when possible.
- After each sub-task: run tests, verify compilation, report results.

### Sub-task cycle
1. User says which sub-task to work on.
2. Implement via delegation.
3. Run tests and verify.
4. Report results — what was done, what was tested, any issues.
5. User may `/rewind` to plan checkpoint for next sub-task.
6. User may `/clear` when all sub-tasks are done.

---

## Quality rules

Quality rules are active via hooks:
- **Always-on rules** injected at session start and into every subagent automatically.
- **Optional rules** evaluated in Phase 2 and loaded when relevant.
- **Post-write scanning** after every file edit.

Follow them. If a rule conflicts with the user's explicit instruction, mention it and follow the user.
