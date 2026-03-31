# flow

Lightweight workflow framework for Claude Code. Quality enforcement via auto-injected rules and structured workflows, designed for production monorepos.

## Why

Born from analyzing **222 sessions**, **1365 prompts**, and **321 corrections**. The 10.5% correction rate revealed recurring patterns: skipped understanding, duplicated code, silent scope changes, untested implementations. Flow reduces corrections by auto-injecting quality rules into every session and enforcing them via hooks — so you stop repeating the same feedback.

## Installation

**Development/testing:**

```bash
claude --plugin-dir ./path/to/claude-flow
```

**Project-level (permanent):**

Add to the Claude Code marketplace, then install with project scope so all contributors get the same rules.

## How It Works

Two layers:

1. **Always-on rules** — copied to your project's `.claude/rules/`. Claude Code loads these natively every session. No hooks needed, no token overhead beyond the rules themselves (~600-800 tokens total).

2. **Optional rules** — live in `.flow/rules/optional/`. Evaluated per prompt by a hook. Only loaded when the prompt is relevant to that rule's domain.

**Hooks:**

| Hook | Trigger | Purpose |
|------|---------|---------|
| `SubagentStart` | Subagent spawns | Injects quality rules into subagent context |
| `UserPromptSubmit` | Every prompt | Evaluates which optional rules are relevant |
| `PostToolUse` | After Write/Edit | Scans output for quality violations |
| `SessionStart` | Session start/resume/compact | Injects rules into session context |

## Commands

| Command | What it does |
|---------|-------------|
| `/flow:flow` | Structured workflow: understand → plan → implement with /rewind checkpoints |
| `/flow:add-rule` | Create a new rule from a lesson learned, place it in the right directory |
| `/flow:rules` | List active rules (always-on + optional) and their status |

## Project Setup

1. **Copy always-on rules** to your project:

   ```bash
   cp rules/always/*.md your-project/.claude/rules/
   ```

2. **Copy optional rules** you want:

   ```bash
   mkdir -p your-project/.flow/rules/optional
   cp rules/optional/decode-pipeline.md your-project/.flow/rules/optional/
   ```

3. **Add rules organically** — when you catch a recurring mistake, run `/flow:add-rule` to capture it as a rule.

That's it. No init command. No config files. No ceremony.

## Rules System

```
rules/
  always/          # Universal rules — copy to project's .claude/rules/
    01-understand-first.md
    02-reuse-existing.md
    03-type-safety.md
    04-testing.md
    05-minimal-changes.md
    06-no-divergence.md
    07-delegation.md
    08-verify-work.md
  optional/         # Domain rules — copy to project's .flow/rules/optional/
    decode-pipeline.md
    git-workflow.md
    review-response.md
    ui-quality.md
```

**Always-on rules** (~600-800 tokens total): loaded every session via native `.claude/rules/`. These are the universal lessons — understand before implementing, reuse existing code, type safety, TDD, minimal changes, no silent divergence, delegation patterns, verify before claiming done.

**Optional rules**: evaluated per prompt by the `UserPromptSubmit` hook. Only injected when the prompt matches the rule's domain. This keeps context lean — you can have 20 optional rules and only pay tokens for the 1-2 that matter for the current task.

**Rule format**: small focused `.md` files. One concern per file. Title as H1, then actionable instructions. Keep each rule under 150 tokens for always-on, under 300 tokens for optional.

## Workflow

The `/flow:flow` command drives a structured workflow:

1. **Understand** — restate the task, surface assumptions, ask clarifying questions
2. **Plan** — propose an approach, list files to change, identify risks
3. **`/rewind`** — checkpoint. If the plan looks wrong, rewind here cheaply
4. **Implement** — execute the plan, delegating to subagents where appropriate
5. **`/rewind`** — checkpoint. If implementation went sideways, rewind to pre-implementation
6. **Implement again** — with lessons from the failed attempt still in context

The `/rewind` pattern is key: it's cheaper to rewind and retry than to untangle a bad implementation. The plan stays in context after rewinding, so the second attempt is better informed.

## Design Philosophy

- **No init ceremony** — copy rules, install plugin, go
- **No lifecycle enforcement** — use the workflow when it helps, skip it when it doesn't
- **No codebase mapping** — rules are project-agnostic quality patterns, not codebase-specific indexes
- **In-context over files** — rules are injected into context, not written to temp files or databases
- **Small and composable** — each rule is independent, add/remove without side effects
- **Lessons, not opinions** — every rule traces back to a real correction from real sessions
