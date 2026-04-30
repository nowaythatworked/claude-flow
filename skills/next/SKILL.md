---
name: next
description: "Analyze what's next, pick tasks, and deep-dive before implementation. The hub between planning and implementing."
argument-hint: "[--no-lock]"
hooks:
  UserPromptSubmit:
    - hooks:
        - type: command
          command: "${CLAUDE_PLUGIN_ROOT}/scripts/flow-next-lock.sh"
          timeout: 5
---

Invoked as `/flow:next [--no-lock]`.

## What this does

Checkpoint and navigation skill. Analyzes the current state of the task, helps pick what to focus on next, and deep-dives into selected tasks before implementation.

For the rule-injection model (static + dynamic, equal weight, re-injected per turn), see `/flow:build` § "How rules reach you".

## Instructions

> **Follow every step on every invocation, in order, without skipping.** It does not matter if this skill was called earlier in the conversation, or if the user already told you what they want to work on. Start from step 1 every time.

### 1. Orient & lock

Run this command now:

```
"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "$CURRENT_SESSION_ID" --get
```

Handle the result:
- **Empty**: no active workflow. Tell the user and suggest `/flow:build`. Stop here.
- **`planning`**: tell the user to finish planning first and suggest `/flow:approve`. Stop here.
- **`implementing`** and `--no-lock` was NOT passed: **you must lock before doing anything else.**
  1. `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "$CURRENT_SESSION_ID" --clear-focus`
  2. `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "$CURRENT_SESSION_ID" --set-phase planned`
  3. Run `--get` again and confirm the output now starts with `planned`. If it does not, stop and tell the user the lock failed.
  4. Tell the user: "Phase locked: **implementing → planned**."
  - Note: a `flow-next-lock` hook may have already done this. If `--get` already returns `planned`, confirm that to the user and continue.
- **`planned`**: already unlocked, no phase change needed. Continue.
- **`--no-lock` was passed**: skip the lock. Tell the user: "Skipping lock (`--no-lock`). Phase remains: `implementing`." Continue.

- Read the task file: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "$CURRENT_SESSION_ID" --get-task` → read `.flow/<filename>`
- Read recent commits: `git log --oneline -20`
- Check other session entries: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . --dump`. Entries persist until the user runs `/flow:reset`; they are not "stale" or "orphaned" just because their work is done. Only use the focus fields to check for active task conflicts. Do not suggest cleaning up, removing, or commenting on other entries.

### 2. Analyze

- What's been completed? (check marks in task file, commits)
- What's remaining?
- Do any other sessions have overlapping focus? (check focus fields, ignore entries with empty focus)
- What's the right next step?

### 3. Suggest

Present analysis to the user:
- Summary of progress so far
- Available tasks (not claimed by other sessions)
- For each available task, assess:
  - **Size**: small (can be done quickly by orchestrator), medium (one focused agent), large (needs delegation/parallelization)
  - **Dependencies**: does this need to be done before/after something else?
  - **Parallelization potential**: can this be worked on in a separate session alongside other tasks?
- If multiple tasks could be parallelized: suggest the user could branch into separate sessions
- Recommend what to focus on next and why

**Wait for the user to confirm** what they want to work on. Do NOT set focus until the user decides.

### 4. Set focus

Once the user confirms task selection:
- Set focus: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "$CURRENT_SESSION_ID" --set-focus "<task-1>" "<task-2>"`
- Tasks are identified by their heading or description from the plan

### 5. Deep-dive process

This is a **pseudo implementation**: read the actual code, trace the actual paths, form the actual plan. You stop short of writing code, but the important decisions should be made.

- **Read the code**: open the relevant files. Understand existing structures, interfaces, types, schemas. Don't skim, you need to know what's there.
- **Think about reusability**: can existing code be refactored to serve this need? Prefer reshaping over adding.
- **Trace the impact**: follow the call chain. What depends on what you're changing? What tests cover this? What could break?
- **Pre-plan the important structures**: types, schemas, interfaces, function signatures that affect multiple files or consumers should be decided now. If a transport schema changes, plan the shape. If a new type is needed, draft it.
- **Pre-decide the hard parts**: architecture choices, refactoring strategies, edge case handling, order of operations.
- **Leave the mechanical work**: the dev agent writes function bodies, test implementations, wiring, imports. It's Opus, it handles the how. But it shouldn't be inventing the what.

The bar: could you brief a junior engineer and trust they'd implement this correctly? They should know what to build, which files to touch, what types/schemas to use. They figure out the code, not the design.

If you already have enough information from earlier discussions (e.g., the planning phase already covered this in depth): acknowledge that and present what you know. Don't force unnecessary ceremony.

### 6. Self-check & iterate

Before presenting findings, ask yourself: **"Could I brief a junior engineer and trust they'd implement this correctly?"**

- Do you know which files need to change?
- Are the types, schemas, and interfaces decided?
- Have you identified existing code that should be refactored rather than duplicated?
- Are the hard decisions made (architecture, refactoring strategy, edge case handling)?
- Do you know what to tell the dev agent to escalate back?

If not, go back: research more, delegate exploration to subagents, or ask the user. Iterate until you're genuinely confident. The user may also push you to go deeper, follow their lead.

### 7. Checkpoint before /flow:implement

This checkpoint runs **every single time** you are about to suggest `/flow:implement`, even if you already ran it earlier in this conversation. The deep-dive may have surfaced new context that changes how the plan applies. Re-running is required, not optional.

#### Step 1. Refresh dynamic rule selection

```bash
TASK=$("${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "$CURRENT_SESSION_ID" --get-task)
FOCUS=$("${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "$CURRENT_SESSION_ID" --get-focus)
"${CLAUDE_PLUGIN_ROOT}/bin/flow-rules" eval --sync \
  --reason=pre-implement-checkpoint \
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

If a static rule's `--- Rule [...] ---` block is missing from your context, Read the file directly.

#### Step 4. Cross-check the deep-dive plan against every loaded rule

Static and dynamic rules carry **equal weight**. Don't pick a subset.

For each rule, decide:
- ✓: the deep-dive plan satisfies the rule
- ⚠: partial fit, edge case, or ambiguity worth noting
- ✗: the deep-dive plan violates or contradicts the rule

#### Step 5. Output the audit shape

Produce this output verbatim (no abbreviation, no skipping rules):

```markdown
## Rule-coherence checkpoint (pre-implement)

Refreshed selection: ran `flow-rules eval --sync --reason=pre-implement-checkpoint`.
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
- (or "none: deep-dive plan is rule-coherent")

### Decision
- If conflicts: raise to user; do NOT suggest /flow:implement
- If clean: suggest /flow:implement
```

#### Step 6. Act on the decision

If conflicts or gaps exist, raise them to the user before suggesting `/flow:implement`. Don't paper over them. Once resolved, the checkpoint runs again on next attempt to suggest.

If the cross-check is clean, proceed to step 8 below.

### 8. Present findings

- Present the deep-dive analysis to the user
- Include: approach, key decisions, risks, things the dev agent should escalate
- Suggest: "When you're satisfied with this analysis, run `/flow:implement` to start implementation."
- If the analysis revealed issues with the overall plan: suggest `/flow:lock` to go back to planning

### Coming from implementing phase

When called after completing implementation tasks:
- Update the task file: mark completed items, add what was done + commit hashes
- Then follow steps 1-8 above for the next set of tasks
- If all tasks are complete: congratulate and suggest `/flow:reset`

## What happens after the deep-dive

When you suggest `/flow:implement` and the user runs it, code writes unlock and execution begins against the focused tasks. You'll switch from analysis to delegation/coordination mode.

## What NOT to do during the deep-dive

- Don't write code. Read, trace, design.
- Don't expand scope beyond the focused tasks.
- Don't skip the rule-coherence checkpoint before suggesting `/flow:implement`.
- Don't suggest `/flow:implement` without presenting the deep-dive analysis first.

## Rules

- Never set focus without user confirmation
- Never skip the deep-dive, even for "obvious" tasks (at minimum state your approach and assumptions)
- Never suggest `/flow:implement` without presenting your analysis first
- If other sessions have claimed tasks, respect their focus, don't suggest claiming the same tasks
- The deep-dive is analysis, not implementation, no code changes
