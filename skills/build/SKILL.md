---
name: build
description: "Structured workflow for complex tasks. Adaptive understand → plan → implement loop with quality enforcement and delegation."
---

Invoked as `/flow:build <task description>`.

## 1. Understand the Big Picture

- Read all referenced files, tickets, pasted context
- Read related code broadly — not just the files mentioned
- Ask clarifying questions — open-ended, not formulaic
- Restate understanding: business context, who is affected, assumptions about business logic
- Do NOT proceed until the user signals readiness

## 2. High-Level Plan

- Search existing codebase for patterns, utilities, similar logic FIRST
- Invoke the `flow:rule-evaluator` agent to evaluate which optional rules apply
- Present the plan:
  - **Domain understanding** — business context, assumptions
  - **Major areas/phases** — NOT detailed task lists yet. Just the big picture breakdown.
- Discuss trade-offs, let user adjust
- Create/update `.flow/TASKS.md` with the high-level plan as a checklist
- User picks which area to work on first

## 3. Deep Dive (per selected area)

This is the adaptive core. Before creating a detailed task list, the orchestrator MUST judge:
"Do I have everything I need to implement this confidently, respecting all loaded rules?"

- If NOT confident: research more, explore code in detail, ask the user questions. Use `flow:dev` agents for targeted exploration if needed. This is not a failure — it's thoroughness.
- If confident: create a detailed task list for THIS AREA ONLY in `.flow/TASKS.md` (nested under the high-level item)
- The user can override this judgment: "good enough, implement" or "go deeper"

## 4. Implement (per detailed task)

- Delegate to `flow:dev` agents (subagent for single tasks, agentteam for parallel work)
- Delegation instructions per work mode:
  - **Foreground subagent**: "When encountering ambiguity that cannot be resolved by reading the codebase, use AskUserQuestion to raise it."
  - **Agentteam workers**: "When encountering ambiguity that cannot be resolved by reading the codebase, communicate it back to the orchestrator and wait for a response."
- After each task: verify work, run tests, update `.flow/TASKS.md`

## 5. Progress & Next

- After completing an area: update `.flow/TASKS.md`, mark items done
- Present: "Here's what's done, here's what's next"
- User picks next area → back to step 3
- User may `/rewind` to any checkpoint
- User may `/clear` when done

## Rules

Quality rules are active via hooks (always-on rules injected at session start, optional rules evaluated by flow:rule-evaluator). Follow them. If a rule conflicts with the user's explicit instruction, mention it and follow the user.

## Key Principles

- NEVER plan all details upfront — plan the big picture, then deep dive per area
- NEVER implement when not confident — research more, ask questions
- NEVER create detailed task lists for areas not being worked on yet
- The `.flow/TASKS.md` file is the living progress tracker — always keep it updated
- The orchestrator's job is reasoning, planning, and verification — delegate implementation
