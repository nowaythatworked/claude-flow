# Rules

Rules are small focused `.md` files — one concern per file, actionable instructions, no fluff.

## Directory Structure

```
rules/
  always/       Shipped defaults. Copy to your project's .claude/rules/
  optional/     Domain-specific. Copy to your project's .flow/rules/optional/
```

### always/

Universal quality rules that apply to every session. These get copied into the project's `.claude/rules/` directory, where Claude Code loads them natively on every session start. No hooks involved — this is built-in Claude Code behavior.

Keep the total budget under ~800 tokens across all always-on rules. Every token here is paid on every prompt.

Current rules:
- `01-understand-first.md` — analyze before implementing, ask before assuming
- `02-reuse-existing.md` — search for existing code before writing new
- `03-type-safety.md` — no `any`, no type assertions, trace root causes
- `04-testing.md` — TDD, run tests, never claim without verifying
- `05-minimal-changes.md` — only change what was requested
- `06-no-divergence.md` — surface surprises, don't silently change plans
- `07-delegation.md` — use subagents for implementation, keep orchestrator clean
- `08-verify-work.md` — read before answering, run before claiming

### optional/

Domain-specific rules that only apply to certain types of work. These get copied into the project's `.flow/rules/optional/` directory. The `UserPromptSubmit` hook evaluates each prompt and only injects rules whose domain matches the current task.

Optional rules can be longer (up to ~300 tokens each) since they're only loaded when relevant.

Current rules:
- `decode-pipeline.md` — logistics email extraction pipeline patterns
- `git-workflow.md` — branch verification, commit practices
- `review-response.md` — triaging PR review comments
- `ui-quality.md` — component patterns, design system adherence

## Adding a New Rule

1. Decide: is this always relevant, or domain-specific?
2. Create a `.md` file in the appropriate directory
3. Format: H1 title, then bullet points or short paragraphs
4. Keep it actionable — what to do, what not to do, why

For always-on rules, use the numbered prefix convention (`09-rule-name.md`) to control load order. For optional rules, use a descriptive name.

Or just run `/flow:add-rule` during a session — it will ask what you learned and place the rule in the right directory.

## How Rules Are Loaded

**Always-on** (`rules/always/` -> `.claude/rules/`):
- Loaded by Claude Code natively at session start
- No hook overhead — this is a built-in feature
- Present in every prompt's context

**Optional** (`rules/optional/` -> `.flow/rules/optional/`):
- Evaluated by the `UserPromptSubmit` hook on every prompt
- Hook reads the prompt, checks against each optional rule's domain
- Only matching rules are injected into context
- Also injected into subagents via the `SubagentStart` hook
