---
description: "Add a new quality rule based on a pattern discovered during work. Grows the project's rule set organically."
---

# /add-rule — Capture a Quality Rule

When the user invokes this, they've spotted a pattern or mistake worth codifying. Help them turn it into a rule.

---

## Step 1 — Identify the pattern

Ask the user what pattern or mistake they want to capture. If the conversation already contains a clear correction or pattern (e.g., the user just corrected you), infer it and confirm:

> "It sounds like the rule is: [description]. Is that right, or do you want to adjust it?"

Get the core principle in one sentence.

## Step 2 — Classify: always-on or optional

Determine the right category:

- **Always-on** — universal rules that apply to every task regardless of context (e.g., "never commit .env files", "restate understanding before implementing"). These go in `.claude/rules/` as native Claude Code rules.
- **Optional** — domain-specific or situational rules that only matter for certain types of work (e.g., "decode pipeline conventions", "UI accessibility patterns"). These go in `.flow/rules/optional/`.

If unclear, ask the user. Default to optional — it's easier to promote a rule than to demote one.

## Step 3 — Draft the rule

Write a rule file that follows these conventions:

- **One concern per file.** Don't combine unrelated guidance.
- **~50-150 tokens.** Rules are injected into context, so brevity matters.
- **Start with a heading** that names the concern clearly.
- **Include concrete examples** from the actual correction when possible — "Do X" / "Don't do Y" pairs work well.
- **Use the naming convention** of existing rules in the target directory.

Check existing rules in the target directory first to avoid duplicates or overlaps.

## Step 4 — Confirm and write

Show the user the full rule content and the target path. Wait for their confirmation before writing the file.

If the user wants changes, revise and re-confirm. Only write once they approve.
