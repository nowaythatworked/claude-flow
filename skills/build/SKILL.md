---
name: build
description: "Structured workflow for complex tasks. Understand → plan → approve → deep-dive → implement with quality enforcement and delegation."
argument-hint: "<task description>"
---

Invoked as `/flow:build <task description>`.

## How rules reach you

Three mechanisms work together to keep quality rules active:

1. **Injection**: the hook system loads rule content into your context.
   - Static rules from `.flow/rules/always/` are injected at session start by `inject-session-rules.sh`. They survive context compaction (re-injected on compact).
   - Dynamic rules from `.flow/rules/dynamic/` are injected on every user message by the `flow-rules` evaluator binary, based on the current selection. Selection can grow or narrow as the task evolves.
2. **Reminder**: a phase-aware reminder at every user message tells you to follow ALL injected rules with equal weight: static and dynamic, prior and newly-added. The reminder doesn't add rules, it just reinforces adherence.
3. **Cross-check**: at checkpoints (before `/flow:approve` and `/flow:implement`) you enumerate every loaded rule and verify the plan against each in the audit shape below. This makes adherence observable and catches drift.

When new dynamic rules get injected mid-conversation, all previously-loaded rules still apply. The latest selection adds; it doesn't replace what's already loaded.

## 0. Initialize

1. Pick a meaningful task filename (see naming below)
2. Register session: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --set planning <task-filename>.md`

### Task file naming

Derive a short, descriptive, kebab-case filename from context:
- Ticket ID if available: `PROJ-123-auth-refactor.md`
- Branch name or task summary otherwise: `ariadne-pr-cleanup.md`, `fix-stryker-pipeline.md`

Note: the task file is NOT created yet: it will be created when the user runs `/flow:approve`.

## Planning phase

During planning, everything happens in conversation. No files, no task lists, no artifacts. The hook system reminds you to stay in this phase. No code changes until the workflow progresses.

### 1. Understand

- Read referenced files, tickets, context, and related code broadly
- Ask clarifying questions, don't assume
- Restate understanding: business context, who is affected, assumptions
- Do NOT move to planning until the user signals readiness

### 2. Plan in conversation

- Search codebase for existing patterns and utilities FIRST
- Run `"${CLAUDE_PLUGIN_ROOT}/bin/flow-rules" eval --sync --reason=planning-start --cwd . --session-id "$CURRENT_SESSION_ID"` to refresh dynamic rule selection for this task
- Develop the plan in conversation: major areas, approach per area, trade-offs
- This is a mid-level plan, not a detailed task list, not a vague summary
- Discuss with the user, let them adjust

### 3. Explore impact

Search the codebase for ripple effects of the planned changes:

- **Side-effects**: what else touches or depends on the code you're changing? Callers, consumers, tests, configs.
- **Affected areas**: what could break or behave differently as a result?
- **New possibilities**: does this change open up simplifications, cleanups, or improvements elsewhere worth mentioning?

Surface anything relevant to the user. This is not optional, a plan without impact analysis is incomplete.

### 4. Self-check & iterate

Keep questioning yourself throughout planning, not just once at the end:

- **"Do I understand enough?"** Are there areas I haven't explored? Assumptions I haven't validated?
- **"Have I found all affected areas?"** Did I search broadly enough for side-effects and dependencies?
- **"Is this plan solid enough to approve?"** Would I be comfortable if the user approved this right now?

If the answer to any is no, go back: research more, search the codebase, ask questions, refine. Iterate until you're genuinely confident. The user may also push back and ask you to go deeper, follow their lead.

### 5. Checkpoint before /flow:approve

This checkpoint runs **every single time** you are about to suggest `/flow:approve`, even if you already ran it earlier in this conversation. The plan may have evolved through user feedback. Re-running is required, not optional.

#### Step 1. Refresh dynamic rule selection

```bash
TASK=$("${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "$CURRENT_SESSION_ID" --get-task)
FOCUS=$("${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "$CURRENT_SESSION_ID" --get-focus)
"${CLAUDE_PLUGIN_ROOT}/bin/flow-rules" eval --sync \
  --reason=pre-approve-checkpoint \
  --cwd . \
  --session-id "$CURRENT_SESSION_ID" \
  --task-file "$TASK" \
  --focus "$FOCUS"
```

If the eval exits non-zero, surface the error to the user and proceed with cross-check against rules currently in your context. Don't block on eval failure.

#### Step 2. Read state

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/flow-rules" state show --cwd . --task-file "$TASK" --focus "$FOCUS"
```

The `selected_via_pattern`, `selected_via_keyword`, `selected_via_llm` arrays form the union of currently-selected dynamic rules.

#### Step 3. Enumerate every loaded rule

- Static rules: every file in `.flow/rules/always/` (run `ls .flow/rules/always/*.md`).
- Dynamic rules: union from step 2. If you see additional `--- Dynamic Rule [...] ---` blocks in your context that aren't in the union (e.g. selected earlier in the session), include those too.

If a static rule's `--- Rule [...] ---` block is missing from your context (compaction may have evicted it), Read the file directly.

#### Step 4. Cross-check the plan against every loaded rule

Static and dynamic rules carry **equal weight**. Don't pick a subset.

For each rule, decide:
- ✓: the plan satisfies the rule
- ⚠: partial fit, edge case, or ambiguity worth noting
- ✗: the plan violates or contradicts the rule

#### Step 5. Output the audit shape

Produce this output verbatim (no abbreviation, no skipping rules):

```markdown
## Rule-coherence checkpoint (pre-approve)

Refreshed selection: ran `flow-rules eval --sync --reason=pre-approve-checkpoint`.
Read state: task_type=<x>, <N> dynamic rules selected.

### Rules currently loaded (full set, equal weight)

**Static (.flow/rules/always/):**
- 01-understand-first.md: <symbol> <one-line justification>
- 02-reuse-existing.md: <symbol> <…>
- 03-type-safety.md: <symbol> <…>
- 04-testing.md: <symbol> <…>
- 05-minimal-changes.md: <symbol> <…>
- 06-no-divergence.md: <symbol> <…>
- 07-delegation.md: <symbol> <…>
- 08-verify-work.md: <symbol> <…>

**Dynamic (.flow/rules/dynamic/):**
- <rule-id>.md: <symbol> <one-line justification>
- (or "none currently selected")

If any rule that should be loaded isn't appearing here, run /flow:reload-rules.

### Conflicts / gaps
- <issue>
- (or "none: plan is rule-coherent")

### Decision
- If conflicts: raise to user; do NOT suggest /flow:approve
- If clean: suggest /flow:approve
```

#### Step 6. Act on the decision

If conflicts or gaps exist, raise them to the user before suggesting `/flow:approve`. Don't paper over them. Once resolved, the checkpoint runs again on next attempt to suggest.

If the cross-check is clean, proceed to step 6 of the planning phase below.

### 6. Present & wait

- Present the finalized plan clearly
- **Do NOT write anything to files. Do NOT implement.**
- Suggest to the user: "When you're happy with this plan, run `/flow:approve` to lock it in."

## What happens after planning

When you suggest `/flow:approve` and the user runs it, the plan is written to the task file. From there:

- `/flow:next` analyzes progress, picks tasks, deep-dives. It runs its own rule-coherence checkpoint before suggesting `/flow:implement`.
- `/flow:implement` unlocks code writes for the focused tasks.

Both are separate skills with their own instructions. Read them when invoked, don't try to do their work inside `/flow:build`.

## What NOT to do during planning

- Don't write code or create files. Reading and exploring only.
- Don't deep-dive into implementation specifics, that's `/flow:next` territory.
- Don't pre-create the task file, `/flow:approve` does that.
- Don't keep iterating after the user has signaled the plan is solid.
- Don't skip the rule-coherence checkpoint, even if you ran it earlier in this conversation.

## Commands

| Command | Effect |
|---------|--------|
| `/flow:approve` | Approve plan → write to file (planning→planned) |
| `/flow:next` | Analyze what's next, deep-dive, set focus |
| `/flow:implement` | Unlock code writes for focused tasks (planned→implementing) |
| `/flow:lock` | Go back one step |
| `/flow:phase` | Show current phase and focus |
| `/flow:reset` | Archive task file and reset |

## Principles

- Plan in conversation, not in files. The task file is the artifact of approval.
- Never implement without explicit user command. User feedback is NOT approval.
- Deep-dive before implementing. Research, reason, think through edge cases.
- Delegate substantial work. The orchestrator coordinates, agents implement.
- Document what was done, not what to do. The task file becomes a log of execution.
