---
name: reload-rules
description: "Re-read all quality rules and evaluate dynamic rules. Use when rules have been lost to context compression or you can't find them."
---

Invoked as `/flow:reload-rules`. Can also be triggered by the agent itself when it detects rule blocks are missing from context.

## When to use

- You can't find `--- Rule [...] ---` or `--- Dynamic Rule [...] ---` blocks in your context
- The conversation has been running long and you suspect rules have been compressed away
- You want to make sure you're working with the latest rules

## Instructions

### 1. Always-on rules

Read **every** file in `.flow/rules/always/`:
```bash
ls .flow/rules/always/*.md
```
Then read each file fully. Do NOT summarize — the act of reading them into context is the point.

### 2. Dynamic rules

Invoke the `flow:rule-evaluator` agent to evaluate which dynamic rules are relevant to your current work. It will read all dynamic rules from `.flow/rules/dynamic/`, assess relevance, and return the ones that apply with their full content.

Read the returned rule content fully so it's in your context.

### 3. Confirm

Report: "Rules reloaded: [count] always-on, [count] dynamic rules active." List the names of active dynamic rules so the user can see what was selected.
