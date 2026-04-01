# flow

Quality enforcement and adaptive workflow framework for Claude Code. Designed for production monorepos, not greenfield projects.

## Background

Flow was born from frustration with existing frameworks (VBW, GSD) on production-grade work. Those frameworks assume greenfield projects — single developer, clean slate, entire codebase fits in a summary file. When applied to a large production monorepo with multiple developers, CI/CD, code review workflows, and complex domain logic, they fell apart:

- **File-based state passing loses context.** GSD writes discussion results to files, then resets context for the next phase. The agent in the next phase ignores half of what was written. Nuance is lost.
- **Project.md doesn't scale.** A monorepo can't be summarized in one file. The summaries are always incomplete, stale, and agents ignore them anyway.
- **Formulaic questioning misses the point.** "List 4 gray areas" doesn't surface real misunderstandings. Open-ended discussion does.
- **Framework ceremony creates friction.** Init scaffolding, lifecycle commands, config management, stuck agents, model errors. The overhead exceeds the value.
- **Codebase mapping is redundant.** The codebase IS the truth. CLAUDE.md has conventions, tests have patterns, docs exist. Generated architecture summaries add noise.

The concepts behind these frameworks are sound — discuss before implementing, delegate to agents, verify work, track progress. Flow keeps the concepts and drops the ceremony.

## The Core Workflow: Rewind & Fork

Flow's execution model uses Claude Code's native `/rewind` and `/fork` as first-class workflow tools, not just error recovery.

### Rewind-to-Plan

For multi-part tasks, the conversation builds up understanding and produces a plan. This plan is the **checkpoint**. Implementation happens one area at a time:

```
Understand → Discuss → Plan (checkpoint)
  → /rewind to plan → Implement area 1 → commit
  → /rewind to plan → Implement area 2 → commit
  → /rewind to plan → Implement area 3 → commit
  → /clear → next thing
```

Everything before the rewind point — the discussion, domain knowledge, nuances, the plan itself — stays in context. Each implementation gets a clean context window while inheriting the full understanding. Git commits persist through rewinds. You lose nothing.

### Fork for Exploration

When you want to explore an alternative approach without losing current state:

```
Plan A agreed → implement → /fork explore-plan-b
→ /rewind → try Plan B instead
→ compare results → pick the winner
```

### Clear for Phase Transitions

`/clear` resets context between major work units. It's the primary tool for moving between tasks, not `/rewind`.

## Analysis-Driven Design

Flow's rules come from analyzing **222 sessions**, **1365 prompts**, and classifying **321 corrections**. The 10.5% correction rate broke down into preventable categories:

| Mistake | Count | Prevention |
|---------|-------|------------|
| Premature implementation | 38 | Auto-injected "discuss first" guardrail |
| Dirty/hacky fixes (any types, hardcoded values) | 35 | Hooks + type safety rules |
| Ignoring existing code (DRY violations) | 28 | "Search before writing" rule |
| Scope misunderstanding | 27 | Domain understanding in plans |
| Scope creep | 22 | "Minimum viable change" rule |
| Wrong technical approach | 20 | Confidence-gated implementation |
| Insufficient research | 19 | Understanding phase enforcement |
| Not following explicit instructions | 18 | Re-read user message rule |
| Not testing work | 16 | TDD always rule + hooks |

76% of corrections are preventable through auto-injected rules and hooks. Flow encodes these lessons so you don't repeat them.

## Quick Start

```bash
# Test it
cd your-project
claude --plugin-dir ~/path/to/claude-flow

# Initialize (scaffolds .flow/ with rules)
/flow:init

# Start working
/flow:build I want to work on <ticket/task description>
```

## How It Works

### Always-On Quality Rules

Copied to `.flow/rules/always/` by `/flow:init`. Injected into every session via SessionStart hook and into every subagent via SubagentStart hook. ~600-800 tokens total:

- **Understand first** — no premature implementation
- **Reuse existing code** — search before writing, extend don't duplicate
- **Type safety** — no `any`, no assertions, fix at root cause
- **TDD always** — tests first, run after every change
- **Minimal changes** — only what was asked
- **No silent divergence** — surface unexpected findings, don't auto-decide
- **Delegation** — how to use subagents/agentteam effectively
- **Verify work** — read before asserting, run before claiming

### Optional Rules (LLM-Evaluated)

Live in `.flow/rules/optional/`. Each has a `description:` frontmatter explaining when it applies. Sonnet evaluates relevance on each substantial prompt and periodically during work (every 15 tool uses, reading the conversation transcript). Only loaded when relevant — keeps context lean.

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
| `flow:dev` | Implementation agent with persistent project memory. Learns codebase patterns across sessions. TDD-first, follows quality rules. |
| `flow:rule-evaluator` | Evaluates which optional rules are relevant. Used by hooks and orchestrator. Sonnet, read-only. |

## The Workflow: `/flow:build`

Not a rigid pipeline. An adaptive loop where the orchestrator continuously judges: *"Do I understand enough to implement this confidently?"*

### 1. Understand the Big Picture
Read context, ask questions, discuss. Restate understanding including business context and domain assumptions. The user decides when understanding is sufficient — not a hardcoded step count.

### 2. High-Level Plan
Search existing codebase first. Evaluate optional rules. Present major areas — NOT detailed task lists yet. Discuss trade-offs. Create `.flow/TASKS.md` with the high-level checklist. User picks which area to work on.

### 3. Deep Dive (per area)
Before making a detailed plan, the orchestrator asks itself: *"Do I have everything I need to implement this confidently, respecting all loaded rules?"*

- **Not confident?** Research more, explore code, ask the user. This is thoroughness, not failure.
- **Confident?** Create a detailed task list for THIS area only in `.flow/TASKS.md`.
- The user can override: *"good enough, implement"* or *"go deeper."*

### 4. Implement
Delegate to `flow:dev` agents. Single tasks → foreground subagent. Parallel tasks → agentteam.

Agents raise ambiguity through the appropriate channel:
- **Foreground subagent**: AskUserQuestion (passes through to user)
- **Agentteam worker**: communicates back to orchestrator, who discusses with user

After each task: verify, test, update `.flow/TASKS.md`.

### 5. Next
Mark area done. Present progress. User picks next area → back to step 3.

- `/rewind` to return to plan checkpoint for next area (clean implementation context)
- `/fork` to checkpoint before exploring alternatives
- `/clear` when all areas are done

## Commands

| Command | What |
|---------|------|
| `/flow:build <task>` | Adaptive workflow for complex tasks |
| `/flow:init` | Initialize flow in current project (scaffold .flow/) |
| `/flow:add-rule` | Add a new rule from a pattern you discovered |
| `/flow:rules` | Show all active rules and their status |

## Project Structure (after /flow:init)

```
your-project/
├── .claude/
│   └── rules/              # Team's native Claude Code rules (untouched)
└── .flow/
    ├── TASKS.md             # Living progress tracker
    └── rules/
        ├── always/          # Flow's always-on quality rules (8 files)
        │   ├── 01-understand-first.md
        │   ├── 02-reuse-existing.md
        │   ├── 03-type-safety.md
        │   ├── 04-testing.md
        │   ├── 05-minimal-changes.md
        │   ├── 06-no-divergence.md
        │   ├── 07-delegation.md
        │   └── 08-verify-work.md
        └── optional/        # Project-specific domain rules (starts empty)
```

Commit `.flow/` to git. Teammates get the rules by cloning.

## Adding Rules

When you discover a recurring pattern mid-session:

```
/flow:add-rule LLMs keep using raw DB queries instead of ElectroDB entities
```

Flow creates a focused rule file in the right directory. Immediately active for this project. Committed to git for the team.

## Design Philosophy

- **In-context over files** — discussion, understanding, and domain knowledge stay in the context window. No writing to intermediate files that agents ignore. This is the #1 lesson from VBW/GSD failure.
- **Rewind as a workflow tool** — not just error recovery. The plan is a checkpoint. Each implementation area gets a clean context while inheriting all understanding.
- **No codebase mapping** — the codebase is the truth. CLAUDE.md has conventions. Generated summaries are noise.
- **No project.md** — a monorepo can't be summarized in one file. Domain context is task-scoped: each plan surfaces only what's relevant.
- **No lifecycle enforcement** — the workflow adapts to the task. Small tasks skip straight to implementation. Complex tasks get deep discussion. The orchestrator judges what's needed.
- **Confidence-gated implementation** — the orchestrator won't implement when uncertain. It researches more or asks. This prevents the #1 correction category (premature implementation).
- **Rules grow organically** — start with the defaults, add rules as you discover patterns. Every shipped rule traces to a real correction from real sessions.
- **Hooks for enforcement, not prompts** — prompt instructions get forgotten mid-session. Hooks fire every time. Quality rules are injected mechanically, not relied upon from memory.
- **Agents learn** — `flow:dev` has persistent project memory. After 10 sessions it knows your codebase conventions, patterns, and gotchas.
