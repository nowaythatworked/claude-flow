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

Flow uses Claude Code's native `/rewind` and `/fork` as first-class workflow tools — not just error recovery, but the primary execution model.

### How /rewind Works in Claude Code

Every message you send creates a checkpoint. `/rewind` (or `Esc Esc`) opens a scrollable list of all your messages. You pick one, and Claude Code restores conversation and code to that point. Your original message is placed back in the input field so you can edit and re-send it. Git commits persist through rewinds — code that was committed is not lost.

### Rewind-to-Plan: The Execution Model

For multi-part tasks, the conversation builds understanding and produces a plan. You then tell the orchestrator which area to implement first — **this message is the checkpoint**:

```
Understand → Discuss → Plan agreed
  → "Start implementing area 1" (this is the checkpoint)
  → orchestrator delegates, agents implement, tests pass, commit
  → /rewind (returns to "Start implementing area 1")
  → edit message to "Start implementing area 2"
  → orchestrator checks TASKS.md + git log, sees area 1 is done
  → delegates area 2 implementation
  → /rewind → "Start implementing area 3" → ...
```

Everything before the checkpoint — the discussion, domain knowledge, nuances, the plan — stays in context. Each implementation area gets a clean context while inheriting the full understanding. The orchestrator reads `.flow/TASKS.md` and recent git history after each rewind to understand what was already completed.

### Fork for Checkpointing & Exploration

`/fork` (or `/branch`) creates a named branch of the conversation at the current point. Two use cases:

**Fine-grained checkpointing:** Before a risky implementation, fork to save the current state. If it goes wrong, you have a clean restore point.

```
Plan agreed → /fork before-refactor → implement risky refactor
→ went wrong? resume the fork. went well? continue.
```

**Exploration:** Try alternative approaches without losing work.

```
Plan A agreed → implement → /fork explore-plan-b
→ /rewind → try Plan B instead → compare results
```

**Session resumption:** Named forks make it easy to return to a specific point in future sessions via `/resume`.

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

### 5. After /rewind — Next Area
After the user rewinds to the plan checkpoint and edits their message for the next area:

- Orchestrator reads `.flow/TASKS.md` to see what's been completed
- Checks `git log` for recent commits to understand what was implemented
- Does NOT re-research or re-plan completed areas
- Picks up from where the checklist shows incomplete work
- Deep dives into the new area (back to step 3)

Use `/fork` before risky implementations or to create resume points for future sessions.

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

## Coming from GSD/VBW?

If you've been using GSD or VBW, here's what's different and why.

### What GSD/VBW get right

The core ideas are solid: discuss before implementing, delegate to specialized agents, verify work, track progress, surface assumptions. Flow keeps all of these — they're encoded in the always-on rules and the `/flow:build` workflow.

### Where they break down on real projects

**The .planning/ directory becomes noise.** GSD creates PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md, CONTEXT.md, SUMMARY.md, and RESEARCH.md per phase. In practice, agents skim or ignore these files. Important decisions written to CONTEXT.md get lost because the executing agent starts fresh and doesn't internalize the nuance. You end up re-explaining things that were already discussed.

**The phase lifecycle is too rigid.** `map-codebase → new-project → discuss-phase → list-assumptions → plan-phase → execute-phase → verify-work` — this pipeline makes sense for a greenfield feature. On a production monorepo, you're often fixing a bug that spans 3 packages, responding to a PR review, refactoring a pipeline, or implementing a ticket that's already half-specified. The lifecycle doesn't flex to these shapes.

**Wave-based execution loses human oversight.** GSD's executor groups tasks into waves and runs them in parallel with minimal intervention. This works for independent tasks but falls apart when tasks interact — agents overwrite each other's changes, make conflicting architectural decisions, or silently diverge from the plan. You discover the mess after the wave completes.

**Agent teams get stuck.** VBW's managed agent teams caused "inherit" model errors, cross-session interference, stuck agents requiring force-kill, and config management headaches. The framework spent more time managing agents than doing work.

**Init ceremony wastes time.** Before doing any work: `/gsd:new-project` (questioning, research agents, requirements derivation, roadmap creation), then `/gsd:discuss-phase`, then `/gsd:list-phase-assumptions`, then `/gsd:plan-phase`, then finally `/gsd:execute-phase`. For a focused 2-hour task, this ceremony can take longer than the actual work.

### How flow handles the same needs

| GSD/VBW | Flow | Why |
|---------|------|-----|
| `map-codebase` → project.md | No mapping. Codebase is truth. | Monorepos can't be summarized. Agents explore on-demand. |
| `discuss-phase` (formulaic) | Open-ended discussion until clear | User decides when understanding is sufficient, not a step count. |
| `list-phase-assumptions` | Domain understanding in plans | Each plan states business context assumptions. Task-scoped, not project-scoped. |
| `plan-phase` → PLAN.md file | In-context plan, `.flow/TASKS.md` checklist | Plan lives in conversation context (preserved through /rewind). TASKS.md is just a progress tracker. |
| `execute-phase` (waves) | Delegate to `flow:dev` agents | User controls pacing. One area at a time. Parallel when appropriate, not forced. |
| `verify-work` (UAT agent) | TDD + `/coderabbit` + `/score-pr` | Composable quality tools, not a monolithic verify step. |
| `.planning/` state directory | `.flow/TASKS.md` + conversation context | One file for progress tracking. Understanding stays in context, not files. |
| Framework-managed agent teams | Natural delegation (subagents/agentteam) | User says "use subagents" or "use agentteam." Claude picks. No framework lifecycle management. |

### The key insight

GSD/VBW optimize for **completeness** — making sure every step is documented, every phase has artifacts, every agent has state files. Flow optimizes for **effectiveness** — making sure the agent understands the task, writes quality code, and doesn't repeat your corrections. The documentation is the code. The state is the conversation. The artifacts are the commits.

## Why Not Just Claude Code Rules?

Claude Code has a native `.claude/rules/` system. Flow uses it for always-on rules but adds capabilities that native rules can't provide:

### What native rules can do
- Auto-load `.md` files at session start
- Conditionally load rules based on file path patterns (`paths:` frontmatter)
- Survive context compaction (re-read from disk)

### What native rules can't do
- **Inject into subagents.** Subagents don't inherit `.claude/rules/`. When you delegate to a subagent, it starts blind — no type safety rules, no DRY enforcement, no TDD. This is the biggest gap. Flow's `SubagentStart` hook fixes this by injecting rules into every subagent's context.
- **Evaluate semantically.** Native `paths:` matching is hardcoded to file glob patterns. It can't reason about *what you're working on* — only *which files you opened*. Flow uses Sonnet to evaluate optional rules based on the actual prompt and conversation context.
- **Re-evaluate as context evolves.** Native rules load once (or when a matching file is opened). Flow re-evaluates every 15 tool uses by reading the conversation transcript, catching when your work shifts to a different domain mid-session.
- **Scan for quality violations.** Native rules are passive — they provide guidance but can't enforce it. Flow's `PostToolUse` hook actively scans every file write for `any` types, unsafe assertions, and unexplained `@ts-ignore` directives.
- **Learn across sessions.** Native rules are static files. Flow's `flow:dev` agent has persistent project memory that accumulates codebase knowledge across sessions — patterns, conventions, gotchas discovered during work.

Flow and native rules are complementary. Use `.claude/rules/` for project-wide conventions (coding style, architecture decisions, domain glossary). Use `.flow/rules/` for quality enforcement that needs hooks, evaluation, and subagent injection.
