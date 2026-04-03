---
name: build
description: "Structured workflow for complex tasks. Understand → plan → approve → deep-dive → implement with quality enforcement and delegation."
---

Invoked as `/flow:build <task description>`.

## 0. Initialize

1. Pick a meaningful task filename (see naming below)
2. Register session: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --set planning <task-filename>.md`

### Task file naming

Derive a short, descriptive, kebab-case filename from context:
- Ticket ID if available: `PROJ-123-auth-refactor.md`
- Branch name or task summary otherwise: `ariadne-pr-cleanup.md`, `fix-stryker-pipeline.md`

Note: the task file is NOT created yet — it will be created when the user runs `/flow:approve`.

## Planning phase

During planning, everything happens in conversation. No files, no task lists, no artifacts. The hook system reminds you to stay in this phase. No code changes until the workflow progresses.

### 1. Understand

- Read referenced files, tickets, context — and related code broadly
- Ask clarifying questions — don't assume
- Restate understanding: business context, who is affected, assumptions
- Do NOT move to planning until the user signals readiness

### 2. Plan in conversation

- Search codebase for existing patterns and utilities FIRST
- Invoke the `flow:rule-evaluator` agent to evaluate which dynamic rules apply
- Develop the plan in conversation: major areas, approach per area, trade-offs
- This is a mid-level plan — not a detailed task list, not a vague summary
- Discuss with the user, let them adjust

### 3. Explore impact

Search the codebase for ripple effects of the planned changes:

- **Side-effects** — what else touches or depends on the code you're changing? Callers, consumers, tests, configs.
- **Affected areas** — what could break or behave differently as a result?
- **New possibilities** — does this change open up simplifications, cleanups, or improvements elsewhere worth mentioning?

Surface anything relevant to the user. This is not optional — a plan without impact analysis is incomplete.

### 4. Reflect on scope

- Is this a small task (one area, straightforward) or a large task (multiple areas, complex)?
- For large tasks: suggest the user whether to split into separate `/flow:build` sessions or handle in one
- For small tasks: note that deep-dive can be brief since the planning already covers it

### 5. Self-check & iterate

Keep questioning yourself throughout planning — not just once at the end:

- **"Do I understand enough?"** — Are there areas I haven't explored? Assumptions I haven't validated?
- **"Have I found all affected areas?"** — Did I search broadly enough for side-effects and dependencies?
- **"Is this plan solid enough to approve?"** — Would I be comfortable if the user approved this right now?

If the answer to any is no — go back: research more, search the codebase, ask questions, refine. Iterate until you're genuinely confident. The user may also push back and ask you to go deeper — follow their lead.

### 6. Present & wait

- Present the finalized plan clearly
- **Do NOT write anything to files. Do NOT implement.**
- Suggest to the user: "When you're happy with this plan, run `/flow:approve` to lock it in."

## Planned phase

After `/flow:approve`, the plan is written to the task file. Use `/flow:next` to pick tasks and deep-dive.

### Rules for planned phase

- The plan exists in the task file — refer to it, don't rewrite it
- Use `/flow:next` for structured task selection and deep-dive, or respond directly if the user tells you what to work on
- If the user picks tasks directly: set focus via `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --set-focus "<task>"` and deep-dive following the `/flow:next` deep-dive rules (pseudo-implementation, pre-plan types/schemas, trace impact)
- Still no code changes — deep-dive is analysis, not implementation
- Suggest to the user: "Run `/flow:next` to pick tasks, or just tell me what to focus on."

## Implementation phase

After `/flow:implement`, code writes are unlocked for the focused tasks.

### Rules for implementation

**Delegation guideline:** Delegate work to `flow:dev` agents when it involves substantial code changes — multiple files, complex logic, anything that benefits from a focused context. The orchestrator handles coordination, verification, and quick operations where spawning an agent would cost more overhead than doing it directly.

- **Foreground subagent** (single focused task): "When encountering ambiguity that cannot be resolved by reading the codebase, use AskUserQuestion to raise it."
- **Agentteam** (parallel independent tasks): "When encountering ambiguity, communicate it back to the orchestrator and wait."
- After each task: verify work, run tests
- When done: write what was done + commit hashes to the task file as documentation
- Suggest to the user: "Tasks complete. Run `/flow:next` to pick the next work."

## Commands

| Command | Effect |
|---------|--------|
| `/flow:approve` | Approve plan → write to file (planning→planned) |
| `/flow:next` | Analyze what's next, deep-dive, set focus |
| `/flow:implement` | Unlock code writes for focused tasks (planned→implementing) |
| `/flow:lock` | Go back one step |
| `/flow:phase` | Show current phase and focus |
| `/flow:reset` | Archive task file and reset |

## Principles

- Plan in conversation, not in files — the task file is the artifact of approval
- Never implement without explicit user command — user feedback is NOT approval
- Deep-dive before implementing — research, reason, think through edge cases
- Delegate substantial work — the orchestrator coordinates, agents implement
- Document what was done, not what to do — the task file becomes a log of execution
