# flow

Quality enforcement and adaptive workflow framework for Claude Code. Designed for production monorepos, not greenfield projects.

## Why

Born from analyzing **222 sessions**, **1365 prompts**, and **321 corrections** over 4 weeks of real work. The 10.5% correction rate revealed recurring patterns: premature implementation, duplicated code, silent scope changes, dirty type hacks, untested code. 76% of these are preventable.

Flow fixes this with two mechanisms:
1. **Quality rules** auto-injected into every session and every subagent — so you stop repeating the same feedback
2. **An adaptive workflow** that ensures understanding before implementation — so the agent doesn't jump to coding before it truly understands the task

## Quick Start

```bash
# Test it
cd your-project
claude --plugin-dir ~/path/to/claude-flow

# Initialize (copies rules, scaffolds .flow/)
/flow:init

# Start working
/flow:build I want to work on ORB-2274. <Ticket>...</Ticket>
```

## How It Works

### Always-On Quality Rules

Copied to your project's `.claude/rules/` by `/flow:init`. Claude Code loads these natively every session. ~600-800 tokens total. Covers:

- **Understand first** — no premature implementation
- **Reuse existing code** — search before writing, extend don't duplicate
- **Type safety** — no `any`, no assertions, fix at root cause
- **TDD always** — tests first, run after every change
- **Minimal changes** — only what was asked
- **No silent divergence** — surface unexpected findings, don't auto-decide
- **Delegation** — how to use subagents/agentteam effectively
- **Verify work** — read before asserting, run before claiming

### Optional Rules (LLM-Evaluated)

Live in `.flow/rules/optional/`. Evaluated by Sonnet on each substantial prompt and periodically during work. Only loaded when relevant. Domain-specific — decode pipeline conventions, UI quality standards, git workflow, review response patterns.

Each rule file has a `keywords:` line for fast matching. As the rule set grows, the LLM evaluator ensures agents only get what they need.

### Hooks

| Hook | When | What |
|------|------|------|
| `SubagentStart` | Every agent spawn | Injects quality rules directly into the subagent's context |
| `UserPromptSubmit` | Substantial prompts | Sonnet evaluates which optional rules apply |
| `PostToolUse` | Every 15 tool uses | Re-evaluates optional rules based on conversation transcript |
| `PostToolUse` | After Write/Edit | Scans for `any` types, unsafe assertions, ts-ignore |
| `SessionStart` | Start + compaction | Loads rules, survives context compression |

### Custom Agents

| Agent | Purpose |
|-------|---------|
| `flow:dev` | Implementation agent with persistent project memory. Learns codebase patterns across sessions. TDD-first, follows quality rules. |
| `flow:rule-evaluator` | Evaluates which optional rules are relevant. Used by hooks and by the orchestrator during planning. Sonnet, read-only. |

## The Workflow: `/flow:build`

Not a rigid pipeline. An adaptive loop where the orchestrator continuously judges: "Do I understand enough to implement this confidently?"

### 1. Understand the Big Picture
Read context, ask questions, discuss. Restate understanding including business context and domain assumptions. The user decides when understanding is sufficient.

### 2. High-Level Plan
Search existing codebase first. Evaluate optional rules. Present major areas — NOT detailed task lists. Discuss trade-offs. Create `.flow/TASKS.md` with the high-level checklist. User picks which area to work on.

### 3. Deep Dive (per area)
The adaptive core. Before making a detailed plan, the orchestrator asks itself: *"Do I have everything I need to implement this confidently?"*

- **Not confident?** Research more, explore code, ask the user. This is not a failure — it's thoroughness.
- **Confident?** Create a detailed task list for THIS area only.
- The user can override: *"good enough, implement"* or *"go deeper."*

### 4. Implement
Delegate to `flow:dev` agents. Single tasks → foreground subagent. Parallel tasks → agentteam. Dev agents raise ambiguity through the appropriate channel (AskUserQuestion for subagents, team messaging for agentteam). After each task: verify, test, update `.flow/TASKS.md`.

### 5. Next
Mark area done. Present progress. User picks next area → back to step 3. Use `/rewind` to return to checkpoints. Use `/clear` when done.

### Why This Works

- **No upfront over-planning.** Big picture first, details only for the area being worked on. Like real engineering.
- **Confidence-gated implementation.** The orchestrator won't implement if it's not sure. It'll research more or ask.
- **Persistent progress.** `.flow/TASKS.md` tracks what's done across the session. No "i completely forgot we didn't finish."
- **Rules that follow agents.** Subagents get quality rules injected via hooks. They can't "forget" about type safety or TDD.
- **Dev agent learns.** `flow:dev` has persistent project memory. After 10 sessions it knows your codebase patterns.

## Commands

| Command | What |
|---------|------|
| `/flow:build <task>` | Adaptive workflow for complex tasks |
| `/flow:init` | Initialize flow in current project (copy rules, scaffold .flow/) |
| `/flow:add-rule` | Add a new rule from a pattern you discovered |
| `/flow:rules` | Show all active rules and their status |

## Project Structure (after /flow:init)

```
your-project/
└── .flow/
    ├── TASKS.md                # Living progress tracker
│       ├── 01-understand-first.md
│       ├── 02-reuse-existing.md
│       └── ... (8 files)
└── .flow/
    ├── TASKS.md                # Living progress tracker
    └── rules/
        └── optional/           # LLM-evaluated domain rules
            ├── decode-pipeline.md
            └── ... (project-specific)
```

Commit both `.claude/rules/` and `.flow/` to git. Teammates get the rules by cloning.

## Adding Rules

When you discover a recurring pattern mid-session:

```
/flow:add-rule LLMs keep using raw DB queries instead of ElectroDB entities
```

Flow creates a focused rule file in the right directory. The rule is immediately active for this project and committed to git for the team.

## Design Philosophy

- **No init ceremony beyond `/flow:init`** — one command, done
- **No lifecycle enforcement** — the workflow adapts to the task, not the other way around
- **No codebase mapping** — the codebase is the truth, CLAUDE.md and rules have conventions
- **In-context over files** — discussion and understanding stay in the context window, not written to intermediate files that agents ignore
- **Monorepo-aware** — no single project.md trying to describe everything. Domain context is task-scoped.
- **Rules grow organically** — start with the defaults, add rules as you discover patterns
- **Every rule traces to a real correction** — not opinions, lessons from 321 actual mistakes
