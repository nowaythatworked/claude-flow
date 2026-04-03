# flow

Quality enforcement and adaptive workflow framework for Claude Code. Designed for production monorepos, not greenfield projects.

> **Note:** Flow is heavily opinionated — it encodes my workflow patterns and quality standards from real production work. Currently, rules are the main customization layer. Remove or add rules to fit your project. Everything else follows the opinions baked in.

## Quick Start

```bash
# Install plugin (project-scoped — shared with team via .claude/settings.json)
claude plugin marketplace add nowaythatworked/claude-flow --scope project
claude plugin install flow@claude-flow --scope project

# Initialize project (copies rules, agents, scripts — run inside Claude Code)
/flow:init

# Start working
/flow:build I want to work on <ticket/task description>
```

`/flow:init` scaffolds `.flow/` with rules and scripts, and installs the `flow-dev` agent to `.claude/agents/`. This two-part setup is intentional — the plugin provides hooks and skills (always active via marketplace), while agents live in your project where they have full hook support and are customizable per project.

For development/testing, use `claude --plugin-dir ~/path/to/claude-flow` instead.

## What Flow Does

Flow has two layers that work independently:

**1. Quality enforcement (always active).** Rules are injected into every session and every subagent via hooks. You don't invoke a command — it's always there. This is the primary value. Every session benefits from type safety rules, DRY enforcement, TDD requirements, and whatever project-specific rules you add over time.

**2. Structured workflow (optional).** `/flow:build` provides an understand → plan → approve → deep-dive → implement loop for complex tasks. Use it when you need structure. Skip it for quick fixes.

Most of the value comes from layer 1. You can use flow for months and never run `/flow:build` — the hooks and rules still improve every session.

## Quality Enforcement

### Always-On Rules

Injected into every session via `SessionStart` hook and into every subagent via `SubagentStart` hook. ~600-800 tokens total. Shipped defaults:

- **Understand first** — no premature implementation, discuss when asked to explore
- **Reuse existing code** — search before writing, extend don't duplicate
- **Type safety** — no `any`, no assertions, fix at root cause
- **TDD always** — tests first, run after every change
- **Minimal changes** — only what was asked, propose don't just do
- **No silent divergence** — surface unexpected findings, don't auto-decide
- **Delegation** — use subagents/agentteam, keep orchestrator clean
- **Verify work** — read before asserting, run before claiming

These are starting points. Delete rules you disagree with, rewrite them to match your team's standards, or add new ones. Each project maintains its own copy in `.flow/rules/always/`.

### Dynamic Rules (LLM-Evaluated)

Live in `.flow/rules/dynamic/`. Each has a `description:` frontmatter. Sonnet evaluates relevance on each substantial prompt and periodically during work (every 15 tool uses, reading the conversation transcript). Only loaded when relevant — a project with 30 dynamic rules still keeps context lean because only 2-3 matching the current task are loaded.

### Rules Grow With Your Project

When you discover a mistake pattern:

```
/flow:add-rule LLMs keep using raw DB queries instead of ElectroDB entities
```

A focused rule file is created, committed to git, immediately active for the team. Over time, `.flow/rules/` becomes a living knowledge base. The more rules you maintain, the fewer corrections you make.

### Rule Persistence

Rules are injected at session start and re-evaluated throughout the conversation. In long sessions, rules can drift out of the agent's attention due to context compression. A persistent reminder on every message nudges the agent to follow its rules, and `/flow:reload-rules` re-reads all rules and re-evaluates dynamic rules when they've been lost. This works in any session — not just `/flow:build`.

## The `/flow:build` Workflow

A structured loop with explicit user gates — plan in conversation, approve to commit, deep-dive before implementing.

```
/flow:build → planning ──(/flow:approve)──→ planned ──(deep-dive)──→ /flow:implement ──→ implementing
                 ↑                            ↑    /flow:next or                             │
                 └────(/flow:lock)────────────┴────natural language───(/flow:lock)────────────┘
```

### Phase 1: Planning (conversation only)

Everything happens in conversation. No files, no task lists, no artifacts.

1. **Understand** — Read context broadly, ask questions, restate understanding including business context and assumptions. The user decides when understanding is sufficient.
2. **Plan** — Search codebase for existing patterns first. Develop a mid-level plan in conversation — major areas, approach per area, trade-offs. Not a detailed task list, not a vague summary.
3. **Reflect on scope** — Is this small (one area) or large (multiple areas)? Suggest splitting into separate sessions if warranted.
4. **Present & wait** — Present the plan clearly. Don't write anything, don't implement. Suggest the user runs `/flow:approve`.

Code writes outside `.flow/` are blocked during this phase.

### Gate: `/flow:approve`

The user runs `/flow:approve` to lock in the plan. The plan gets written to a task file (`.flow/<meaningful-name>.md`) as a checklist with section headings. Phase transitions to **planned**.

### Phase 2: Planned (deep-dive + task selection)

The plan exists in the task file. Now pick tasks and deep-dive before implementing.

Use `/flow:next` for a structured approach — it analyzes progress, checks what other sessions are working on, assesses task sizes, suggests parallelization, and guides the deep-dive. Or just tell the agent what to work on directly ("let's do task 1 and 2") — the agent will set focus and deep-dive into it.

Either way, the agent should deep-dive before implementing: research the relevant code, think through edge cases, pre-plan important structures (types, schemas, interfaces), and present findings before suggesting `/flow:implement`.

Code writes are still blocked — deep-dive is analysis, not implementation.

### Gate: `/flow:implement`

The user runs `/flow:implement`. Granular tasks are created in context (via TaskCreate, not written to file). Phase transitions to **implementing**.

### Phase 3: Implementing

Code writes unlocked. Delegate substantial work to `flow:dev` agents.

1. **Execute** — Delegate multi-file changes, complex logic, anything benefiting from focused context. Orchestrator handles coordination, verification, quick operations.
2. **Verify** — Run tests, check output after each task.
3. **Document** — Write what was done + commit hashes to the task file. The file becomes a log of execution, not planning.
4. **Next** — Suggest `/flow:next` for the next task, or `/flow:reset` if everything is done.

### Parallel Work with Branching

When `/flow:next` identifies tasks that can be worked on independently:

1. Main session identifies parallelizable tasks via `/flow:next`
2. User opens new terminals, runs `claude --resume <session-id>` to create branches
3. Each branch gets its own session with its own focus — hook enforcement is per-session
4. Deep-dive and implement in parallel across sessions
5. Sessions track which tasks are claimed via focus fields, preventing collisions

Branch detection is automatic — the `SessionStart` hook detects branched sessions and inherits the parent's task file and phase. The `SESSIONS.json` tracks parent relationships.

### Scaling

- **Small task** (one function, a few files): Planning phase covers everything. Brief deep-dive. Single agent implements.
- **Medium task** (feature across a few files): Full loop, all areas in one session.
- **Large task** (multi-area ticket, redesign): High-level plan, branch into parallel sessions for independent areas, deep-dive per area.

## Technical Details

### Hooks

| Hook | When | What |
|------|------|------|
| `SessionStart` | Start + compaction | Injects always-on rules, survives context compression |
| `SessionStart` | Resume (branch) | Auto-detects branched `/flow:build` sessions, registers with parent tracking |
| `SubagentStart` | Every agent spawn | Injects quality rules directly into subagent context |
| `UserPromptSubmit` | Every prompt | Rule reminder: follow injected rules, `/flow:reload-rules` if lost |
| `UserPromptSubmit` | Every prompt | Phase-aware reminder with focus context (only for registered sessions) |
| `UserPromptSubmit` | Substantial prompts | Sonnet evaluates which dynamic rules apply |
| `PostToolUse` | After Write/Edit | Phase guard: blocks code writes during planning and planned phases |
| `PostToolUse` | After Write/Edit | Scans for `any` types, unsafe assertions, `@ts-ignore` |
| `PostToolUse` | Every 15 tool uses | Re-evaluates dynamic rules based on transcript |

### Custom Agents

| Agent | Where | Purpose |
|-------|-------|---------|
| `flow-dev` | `.claude/agents/` (project) | Implementation agent with persistent memory, TDD-first, Stop hook for rule compliance. Customizable per project. |
| `flow:rule-evaluator` | Plugin | Evaluates which dynamic rules are relevant. Used by hooks and orchestrator. Sonnet, read-only. |

`flow-dev` is installed to your project by `/flow:init`, not kept in the plugin. This is intentional:
- **Full hook support** — project-level agents can have hooks (plugin agents can't). The Stop hook blocks the agent from finishing until it verifies compliance with all loaded rules.
- **Customizable** — each project can adjust the agent's system prompt, add hooks, change the model. It's a template you own, not a black box.
- **Shared via git** — teammates get the agent by cloning. No per-developer setup.

## Commands

| Command | What |
|---------|------|
| `/flow:build <task>` | Start structured workflow — enter planning phase |
| `/flow:approve` | Approve plan → write to task file (planning→planned) |
| `/flow:next` | Analyze what's next, pick tasks, deep-dive |
| `/flow:implement` | Unlock code writes, start implementing (planned→implementing) |
| `/flow:lock` | Go back one phase (implementing→planned, planned→planning) |
| `/flow:phase` | Show current phase, focus, and available commands |
| `/flow:reset` | Archive task file and reset phase |
| `/flow:init` | Initialize flow in current project (scaffold .flow/) |
| `/flow:add-rule` | Add a new rule from a pattern you discovered |
| `/flow:rules` | Show all active rules and their status |
| `/flow:reload-rules` | Re-read all rules into context (use when rules get lost) |

## Project Structure

After running `/flow:init`:

```
your-project/
├── .claude/
│   ├── agents/
│   │   └── flow-dev.md      # Implementation agent (with Stop hook)
│   └── rules/               # Team's native Claude Code rules (untouched)
└── .flow/
    ├── SESSIONS.json         # Active session state (phase, focus, parent per session)
    ├── <task-name>.md        # Task file (named by context, e.g. fix-auth-bug.md)
    ├── archive/              # Archived task files from completed work
    └── rules/
        ├── always/           # Always-on quality rules (8 files)
        └── dynamic/          # Project-specific domain rules (starts empty)
```

Commit `.flow/` and `.claude/agents/` to git. Teammates get everything by cloning.

## Design Philosophy

- **Plan in conversation, not files** — understanding stays in context. The task file is an artifact of approval, not a planning scratchpad.
- **Explicit user gates** — no phase transitions without user commands. The agent suggests, the user decides.
- **Deep-dive before implementing** — research and reason before writing code. Confidence is earned, not assumed.
- **Session-scoped enforcement** — hooks are per-session. A quick side-task in another session is unaffected by an active `/flow:build`.
- **No codebase mapping** — the codebase is the truth. CLAUDE.md has conventions. Generated summaries are noise.
- **Rules grow organically** — every shipped rule traces to a real correction from real sessions.
- **Hooks for enforcement, not prompts** — prompt instructions get forgotten mid-session. Hooks fire every time.
- **Agents learn** — `flow:dev` has persistent project memory via Claude Code's native memory system.

---

## Appendix: Coming from GSD/VBW?

If you've been using GSD or VBW, here's what's different and why.

### What they get right

Discuss before implementing, delegate to agents, verify work, track progress, surface assumptions. Flow keeps all of these — encoded in rules and the `/flow:build` workflow.

### Where they break down on production work

- **The .planning/ directory becomes noise.** Agents skim or ignore PROJECT.md, CONTEXT.md, SUMMARY.md. You re-explain things already discussed.
- **The phase lifecycle is too rigid.** `map → discuss → plan → execute → verify` doesn't flex to bug fixes, PR reviews, or half-specified tickets.
- **Wave-based execution loses oversight.** Agents overwrite each other, make conflicting decisions, silently diverge. You discover the mess after.
- **Agent teams get stuck.** Model errors, cross-session interference, stuck agents, config headaches.
- **Workflows are black boxes.** Can't inject project-specific checks between steps without forking.

### Comparison

| GSD/VBW | Flow | Why |
|---------|------|-----|
| `map-codebase` → project.md | No mapping | Monorepos can't be summarized |
| `discuss-phase` (formulaic) | Open-ended discussion | User decides when sufficient |
| `plan-phase` → PLAN.md | In-context plan → task file on approve | Plan lives in conversation until committed |
| `execute-phase` (waves) | Delegated with user in the loop | No silent divergence |
| `.planning/` (6+ files/phase) | `SESSIONS.json` + task file + conversation | Minimal state, not a state machine |
| Framework-managed agents | Natural delegation | No lifecycle management overhead |

### The key insight

GSD/VBW optimize for **completeness** — documenting every step. Flow optimizes for **effectiveness** — making sure the agent understands the task and writes quality code. The documentation is the code. The state is the conversation. The artifacts are the commits.

## Appendix: Why Not Just Claude Code Rules?

Claude Code's native `.claude/rules/` system is good but has gaps that flow fills:

- **Subagents don't inherit rules.** Flow's `SubagentStart` hook injects rules into every subagent.
- **No semantic evaluation.** Native `paths:` matching is file-glob only. Flow uses Sonnet to evaluate based on prompt and conversation context.
- **No re-evaluation.** Native rules load once. Flow re-evaluates every 15 tool uses as your work evolves.
- **No enforcement.** Native rules are passive guidance. Flow actively scans file writes for violations.
- **No learning.** Native rules are static. Flow's `flow:dev` agent accumulates knowledge across sessions.

Use `.claude/rules/` for project conventions. Use `.flow/rules/` for quality enforcement that needs hooks, evaluation, and subagent injection. They're complementary.
