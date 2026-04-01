# flow

Quality enforcement and adaptive workflow framework for Claude Code. Designed for production monorepos, not greenfield projects.

> **Note:** Flow is heavily opinionated — it encodes my workflow patterns and quality standards from real production work. Currently, rules are the main customization layer. Remove or add rules to fit your project. Everything else follows the opinions baked in.

## Quick Start

```bash
# Install (project-scoped recommended — shared with team via .claude/settings.json)
/plugin marketplace add nowaythatworked/claude-flow
/plugin install flow@claude-flow --scope project

# Initialize (scaffolds .flow/ with rules)
/flow:init

# Start working
/flow:build I want to work on <ticket/task description>
```

For development/testing, use `claude --plugin-dir ~/path/to/claude-flow` instead.

## What Flow Does

Flow has two layers that work independently:

**1. Quality enforcement (always active).** Rules are injected into every session and every subagent via hooks. You don't invoke a command — it's always there. This is the primary value. Every session benefits from type safety rules, DRY enforcement, TDD requirements, and whatever project-specific rules you add over time.

**2. Structured workflow (optional).** `/flow:build` provides an adaptive understand → plan → implement loop for complex tasks. Use it when you need structure. Skip it for quick fixes.

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

### Optional Rules (LLM-Evaluated)

Live in `.flow/rules/optional/`. Each has a `description:` frontmatter. Sonnet evaluates relevance on each substantial prompt and periodically during work (every 15 tool uses, reading the conversation transcript). Only loaded when relevant — a project with 30 optional rules still keeps context lean because only 2-3 matching the current task are loaded.

### Rules Grow With Your Project

When you discover a mistake pattern:

```
/flow:add-rule LLMs keep using raw DB queries instead of ElectroDB entities
```

A focused rule file is created, committed to git, immediately active for the team. Over time, `.flow/rules/` becomes a living knowledge base. The more rules you maintain, the fewer corrections you make.

## The `/flow:build` Workflow

An adaptive loop — not a rigid pipeline. The orchestrator continuously judges: *"Do I understand enough to implement this confidently?"*

### 1. Understand the Big Picture
Read context, ask questions, discuss. Restate understanding including business context and domain assumptions. The user decides when understanding is sufficient.

### 2. High-Level Plan
Search existing codebase for patterns first. Evaluate optional rules. Present major areas — NOT detailed task lists yet. Discuss trade-offs. Create `.flow/TASKS.md` as a scratchpad/checklist. User picks which area to work on.

### 3. Deep Dive (per area)

**Orient:** Read `.flow/TASKS.md` and `git log` to understand current state — what's done, what's in progress, any notes from previous areas.

**Judge confidence:** *"Do I have everything I need to implement this confidently, respecting all loaded rules?"*

- **Not confident?** Research more (delegate to subagents), explore code, ask the user.
- **Confident?** Create a detailed task list for THIS area only.
- The user can override: *"good enough, implement"* or *"go deeper."*

Note important discoveries in `.flow/TASKS.md` that could affect other areas.

### 4. Implement
Delegate to `flow:dev` agents. Single tasks → foreground subagent. Parallel tasks → agentteam. Ensure implementation complies with loaded rules. After each task: verify, test, update `.flow/TASKS.md`.

### 5. Next Area

**Continue in the same context** if it's not bloated — orchestrator presents progress, user picks next area, back to step 3.

**Rewind for a clean context** on larger tasks — run `/rewind`, select the message where you chose the first area, edit it to the next area. The orchestrator gets a clean context with the full discussion and plan intact, orients via TASKS.md + git log, and deep dives the new area.

**Fork before risky changes** — `/fork before-refactor` saves the current state. Resume the fork if things go wrong. Also useful for exploring alternative approaches or creating resume points for future sessions.

### Scaling

- **Small task** (one function, a few files): Steps 1-2 in one exchange. Already confident. Single agent implements everything. No TASKS.md, no rewind.
- **Medium task** (feature across a few files): Full loop, all areas in one session without rewinds.
- **Large task** (multi-area ticket, redesign): High-level plan, rewind between areas, TASKS.md as scratchpad, deep dives per area.

## Technical Details

### Hooks

| Hook | When | What |
|------|------|------|
| `SessionStart` | Start + compaction | Injects always-on rules, survives context compression |
| `SubagentStart` | Every agent spawn | Injects quality rules directly into subagent context |
| `UserPromptSubmit` | Substantial prompts | Sonnet evaluates which optional rules apply |
| `PostToolUse` | Every 15 tool uses | Re-evaluates optional rules based on transcript |
| `PostToolUse` | After Write/Edit | Scans for `any` types, unsafe assertions, `@ts-ignore` |

### Custom Agents

| Agent | Purpose |
|-------|---------|
| `flow:dev` | Implementation agent with persistent project memory. Learns codebase patterns across sessions. TDD-first. |
| `flow:rule-evaluator` | Evaluates which optional rules are relevant. Used by hooks and orchestrator. Sonnet, read-only. |

The `flow:dev` agent accumulates project knowledge across sessions — conventions, patterns, gotchas. This persists via git and is shared with the team.

## Commands

| Command | What |
|---------|------|
| `/flow:build <task>` | Adaptive workflow for complex tasks |
| `/flow:init` | Initialize flow in current project (scaffold .flow/) |
| `/flow:add-rule` | Add a new rule from a pattern you discovered |
| `/flow:rules` | Show all active rules and their status |

## Project Structure

After running `/flow:init`:

```
your-project/
├── .claude/
│   └── rules/              # Team's native Claude Code rules (untouched)
└── .flow/
    ├── TASKS.md             # Scratchpad / progress tracker
    └── rules/
        ├── always/          # Always-on quality rules (8 files)
        └── optional/        # Project-specific domain rules (starts empty)
```

Commit `.flow/` to git. Teammates get the rules by cloning.

## Design Philosophy

- **In-context over files** — understanding stays in the context window, not intermediate files that agents ignore. Learnings get stored as rules which are enforced via hooks.
- **No codebase mapping** — the codebase is the truth. CLAUDE.md has conventions. Generated summaries are noise.
- **No project.md** — a monorepo can't be summarized in one file. Domain context is task-scoped.
- **No lifecycle enforcement** — the workflow adapts to the task. The orchestrator judges what's needed.
- **Confidence-gated implementation** — the orchestrator won't implement when uncertain. It researches more or asks.
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
| `plan-phase` → PLAN.md | In-context plan + TASKS.md scratchpad | Plan preserved through /rewind |
| `execute-phase` (waves) | Delegated with user in the loop | No silent divergence |
| `.planning/` (6+ files/phase) | `.flow/TASKS.md` + conversation | One scratchpad, not a state machine |
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
