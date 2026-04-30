---
name: add-rule
description: "Add a new quality rule based on a pattern discovered during work. Grows the project's rule set organically."
argument-hint: "<pattern description>"
---

# /add-rule: Capture a Quality Rule

When the user invokes this, they've spotted a pattern or mistake worth codifying. Help them turn it into a rule.

---

## Step 1: Identify the pattern

Ask the user what pattern or mistake they want to capture. If the conversation already contains a clear correction or pattern (e.g., the user just corrected you), infer it and confirm:

> "It sounds like the rule is: [description]. Is that right, or do you want to adjust it?"

Get the core principle in one sentence.

## Step 2: Classify the rule

Determine the right category:

- **Always-on**: universal rules that apply to every task regardless of context (e.g., "never commit .env files", "restate understanding before implementing"). These go in `.flow/rules/always/` as native Claude Code rules.
- **Optional**: domain-specific or situational rules that only matter for certain types of work (e.g., "decode pipeline conventions", "UI accessibility patterns"). These go in `.flow/rules/dynamic/`.

If unclear, ask the user. Default to dynamic: it's easier to promote a rule than to demote one.

## Step 3: Draft the rule

Write a rule file that follows these conventions:

- **One concern per file.** Don't combine unrelated guidance.
- **~50-150 tokens.** Rules are injected into context, so brevity matters.
- **Start with a heading** that names the concern clearly.
- **Include concrete examples** from the actual correction when possible. "Do X" / "Don't do Y" pairs work well.
- **Use the naming convention** of existing rules in the target directory.

Check existing rules in the target directory first to avoid duplicates or overlaps.

### Frontmatter (dynamic rules only)

Always-on rules don't need frontmatter. They're loaded by `inject-session-rules.sh` for every session.

Dynamic rules need frontmatter so the `flow-rules` evaluator knows when to select them. The shape is **presence-inferred**: include any subset of the three signal fields below. Selection is the union of whichever fields are present.

```yaml
---
relevance: "<one-line description of when this rule applies>"
patterns:
  - "**/*.tsx"
  - "src/components/**"
keywords:
  - "useEffect"
  - "component"
  - "JSX"
---
```

- **`relevance`** (string): one-line description used by the LLM evaluator to decide whether the rule applies to the current task. Make it specific. The LLM never sees the rule body, only this field. Triggers the LLM selection path.
- **`patterns`** (string array): glob patterns matched against file paths the agent reads, edits, globs, or greps. Triggers the pattern selection path. Sync, no LLM call.
- **`keywords`** (string array): case-insensitive substrings matched against recent user text + tool args. Triggers the keyword selection path. Sync, no LLM call.

A rule with no signal fields will be skipped with a warning, the author opted out of selection.

Worked example for a React component rule:

```markdown
---
relevance: "When working on React components, JSX, or files in src/components/"
patterns:
  - "**/*.tsx"
  - "src/components/**"
keywords:
  - "react"
  - "component"
  - "useeffect"
  - "jsx"
---

# React Component Conventions

- Prefer named exports over default exports.
- Use Mantine for UI primitives, see mantine-conventions.md.
- ...
```

Pattern matches usually win for file-shape signals (cheap, deterministic). Keywords help when shape isn't enough (user discusses geocoding without touching geocoding files yet). `relevance` is the fallback for purely semantic rules.

## Step 4: Confirm and write

Show the user the full rule content and the target path. Wait for their confirmation before writing the file.

If the user wants changes, revise and re-confirm. Only write once they approve.
